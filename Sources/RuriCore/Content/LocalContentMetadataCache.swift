import Foundation
import Darwin

/// A presentation cache only. Installation and removal still validate the real files.
/// File identity survives an enable/disable rename; changed or replaced archives miss the cache.
struct LocalContentStamp: Equatable, Sendable {
    let key: String
    let size: Int64
    var isDirectory = false

    static func read(_ url: URL, allowDirectory: Bool = false) -> Self? {
        var value = stat()
        guard url.withUnsafeFileSystemRepresentation({ pointer in
            pointer.map { lstat($0, &value) } ?? -1
        }) == 0 else { return nil }
        let directory = value.st_mode & S_IFMT == S_IFDIR
        guard value.st_mode & S_IFMT == S_IFREG || (allowDirectory && directory) else { return nil }
        var key = "\(value.st_dev):\(value.st_ino):\(value.st_birthtimespec.tv_sec):\(value.st_birthtimespec.tv_nsec):\(value.st_size):\(value.st_mtimespec.tv_sec):\(value.st_mtimespec.tv_nsec)"
        if directory {
            for path in ["pack.mcmeta", "pack.png", "shaders/shaders.properties"] {
                key += ":" + (read(url.appendingPathComponent(path))?.key ?? "-")
            }
        }
        return Self(key: key, size: directory ? 0 : value.st_size, isDirectory: directory)
    }
}

/// All mutable state is protected by `lock`; archive parsing runs outside it.
final class LocalContentMetadataCache: @unchecked Sendable {
    struct Record: Codable {
        let metadata: LocalModMetadata?
        var accessed: Date
        var pack: LocalPackMetadata? = nil
        var identities: [ContentIdentity]? = nil
        var parsed: Bool? = nil
        var isParsed: Bool { parsed != false }
        var cost: Int {
            let fields: [String?] = [metadata?.id, metadata?.name, metadata?.version, metadata?.summary, metadata?.homepage?.absoluteString, metadata?.iconPath, pack?.summary, pack?.iconPath]
            let local = fields.compactMap { $0 }.reduce(0) { $0 + $1.utf8.count } + (metadata?.authors.reduce(0) { $0 + $1.utf8.count } ?? 0)
            let online = identities?.reduce(0) { $0 + 1024 + $1.record.title.utf8.count + ($1.summary?.utf8.count ?? 0) } ?? 0
            return 512 + local + online
        }
    }
    private final class Registry: @unchecked Sendable {
        let lock = NSLock()
        let stores = NSCache<NSURL, LocalContentMetadataCache>()
        init() { stores.countLimit = 8 }
    }
    private static let registry = Registry()
    static func shared(in directory: URL) -> LocalContentMetadataCache {
        let key = directory.standardizedFileURL as NSURL
        registry.lock.lock(); defer { registry.lock.unlock() }
        if let existing = registry.stores.object(forKey: key) { return existing }
        let store = LocalContentMetadataCache(directory: directory)
        registry.stores.setObject(store, forKey: key)
        return store
    }

    private let lock = NSLock()
    private let url: URL
    private var records: [String: Record] = [:]
    private var cost = 0
    private var dirty = false
    private static let byteLimit = 16 * 1024 * 1024

    private init(directory: URL) {
        // Retain the existing path and mod keys so upgrading reuses the mod cache.
        // Bump the schema when the metadata parser's interpretation changes.
        url = directory.appendingPathComponent("local-mod-metadata-v1.json")
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= Self.byteLimit,
           let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode([String: Record].self, from: data) {
            records = saved
            cost = records.values.reduce(0) { $0 + $1.cost }
            trim()
        }
    }

    private func key(_ stamp: LocalContentStamp, _ kind: ContentKind) -> String { kind == .mod ? stamp.key : kind.rawValue + ":" + stamp.key }
    func cached(_ stamp: LocalContentStamp, kind: ContentKind = .mod) -> Record? {
        lock.lock(); defer { lock.unlock() }
        let key = key(stamp, kind)
        guard var record = records[key] else { return nil }
        record.accessed = Date()
        records[key] = record
        return record
    }

    func resolve(_ url: URL, stamp: LocalContentStamp, kind: ContentKind = .mod) -> Record? {
        guard !Task.isCancelled, LocalContentStamp.read(url, allowDirectory: stamp.isDirectory) == stamp else { return nil }
        if let hit = cached(stamp, kind: kind), hit.isParsed { return hit }
        let metadata = kind == .mod ? LocalModMetadata.read(url) : nil
        let pack = kind != .mod ? LocalPackMetadata.read(url, kind: kind, isDirectory: stamp.isDirectory) : nil
        // Do not save a partial/cancelled parse or metadata for a file replaced mid-read.
        guard !Task.isCancelled, LocalContentStamp.read(url, allowDirectory: stamp.isDirectory) == stamp else { return nil }
        lock.lock(); defer { lock.unlock() }
        let key = key(stamp, kind)
        let record = Record(metadata: metadata, accessed: Date(), pack: pack, identities: records[key]?.identities)
        cost -= records[key]?.cost ?? 0
        records[key] = record; cost += record.cost; dirty = true
        trim()
        return record
    }

    func remember(_ identities: [ContentIdentity], for file: LocalContentFile) {
        guard let stamp = file.stamp, !stamp.isDirectory, LocalContentStamp.read(file.url) == stamp else { return }
        lock.lock(); defer { lock.unlock() }
        let key = key(stamp, file.kind)
        var record = records[key] ?? Record(metadata: nil, accessed: Date(), parsed: false)
        let matches = identities.filter { $0.record.kind == file.kind }
        guard record.identities != matches else { return }
        cost -= records[key]?.cost ?? 0
        record.identities = matches; record.accessed = Date()
        records[key] = record; cost += record.cost; dirty = true
        trim()
    }

    func flush() {
        lock.lock(); defer { lock.unlock() }
        guard dirty else { return }
        do {
            let data = try JSONEncoder().encode(records)
            guard data.count <= Self.byteLimit else { return }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            dirty = false
        } catch { /* The list remains usable when the disposable cache cannot be saved. */ }
    }

    private func trim() {
        guard records.count > 4096 || cost > Self.byteLimit else { return }
        for (key, record) in records.sorted(by: { $0.value.accessed < $1.value.accessed }) {
            records.removeValue(forKey: key); cost -= record.cost; dirty = true
            if records.count <= 3072 && cost <= Self.byteLimit * 3 / 4 { break }
        }
    }
}
