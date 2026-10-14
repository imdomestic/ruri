import Foundation
import CryptoKit
import Darwin
import RuriLocalization

public struct ChorusModSync: Sendable {
    public struct Receipt: Codable, Sendable { public let buildID: String; public let files: [ChorusBuild.File] }
    public struct Result: Sendable { public let unmanaged: [String]; public let files: [String] }
    public let paths: LauncherPaths
    public let client: ChorusClient
    public init(paths: LauncherPaths, client: ChorusClient) { self.paths = paths; self.client = client }

    public static func clientFiles(_ manifest: ChorusBuild) throws -> [ChorusBuild.File] {
        guard manifest.status == .ready, manifest.minecraft != nil, manifest.loaderVersion != nil, manifest.java != nil else {
            throw RuriError.message(Messages.Chorus.buildUnavailable)
        }
        let files = manifest.files.filter(\.isClient)
        guard !files.isEmpty, Set(files.map(\.name)).count == files.count else { throw RuriError.message(Messages.Chorus.invalidResponse) }
        for file in files {
            guard file.name.hasSuffix(".jar"), file.name != ".jar", !file.name.hasPrefix("."),
                  !file.name.contains("/"), !file.name.contains("\\"), !file.name.contains("\0"),
                  file.sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
                  file.size > 0 else { throw RuriError.message(Messages.Chorus.invalidResponse) }
        }
        return files
    }
    public static func digest(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    static func verify(_ url: URL, file: ChorusBuild.File) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              Int64(values.fileSize ?? -1) == file.size, try digest(url) == file.sha256 else {
            throw RuriError.message(Messages.Chorus.checksumFailed(file.name))
        }
    }
    public func synchronize(_ build: ChorusBuild, instance: GameInstance) async throws -> Result {
        let files = try Self.clientFiles(build)
        let state = try StateStore.load(paths), configured = paths.configured(with: state)
        let lease = try GameRunLease.acquire(paths: configured, instanceID: instance.id)
        defer { withExtendedLifetime(lease) {} }
        let directory = configured.game(instance.id).appendingPathComponent("mods")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let receiptURL = directory.appendingPathComponent(".chorus-managed.json")
        let previous = FileManager.default.fileExists(atPath: receiptURL.path)
            ? try JSONDecoder().decode(Receipt.self, from: Data(contentsOf: receiptURL)).files : []
        let priorNames = Set(previous.map(\.name)), nextNames = Set(files.map(\.name))
        let existing = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        let unmanaged = existing.filter { $0.hasSuffix(".jar") && !priorNames.contains($0) }.sorted()
        guard Set(unmanaged).isDisjoint(with: nextNames) else { throw RuriError.message(Messages.Chorus.unmanagedConflict) }
        for file in previous {
            let target = try LauncherPaths.safePath(file.name, within: directory)
            if FileManager.default.fileExists(atPath: target.path) { try Self.verify(target, file: file) }
        }
        let cache = paths.cache.appendingPathComponent("chorus", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        var prepared: [(ChorusBuild.File, URL)] = []
        for file in files {
            try Task.checkCancellation()
            let cached = cache.appendingPathComponent(file.sha256 + ".jar")
            if FileManager.default.fileExists(atPath: cached.path) { try Self.verify(cached, file: file) }
            else {
                let bytes = try await client.data(file.url)
                let stage = cache.appendingPathComponent(UUID().uuidString + ".part")
                defer { try? FileManager.default.removeItem(at: stage) }
                try bytes.write(to: stage, options: .atomic)
                try Self.verify(stage, file: file)
                try FileManager.default.moveItem(at: stage, to: cached)
                let sha1 = Insecure.SHA1.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
                await DownloadCache(paths: paths).store(.init(url: nil, destination: cached, sha1: sha1, size: file.size, cacheable: true))
            }
            prepared.append((file, cached))
        }
        try Task.checkCancellation()
        // 在同一文件系统完成准备后原子交换目录，托管清单与模组一起发布。
        let stagedDirectory = directory.deletingLastPathComponent().appendingPathComponent(".chorus-mods-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: stagedDirectory) }
        try FileManager.default.copyItem(at: directory, to: stagedDirectory)
        for (file, source) in prepared {
            let target = try LauncherPaths.safePath(file.name, within: stagedDirectory)
            if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
            try FileManager.default.copyItem(at: source, to: target)
        }
        for file in previous where !nextNames.contains(file.name) {
            let target = try LauncherPaths.safePath(file.name, within: stagedDirectory)
            if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
        }
        try JSONEncoder().encode(Receipt(buildID: build.id, files: files)).write(to: stagedDirectory.appendingPathComponent(".chorus-managed.json"), options: .atomic)
        try Task.checkCancellation()
        guard renamex_np(stagedDirectory.path, directory.path, UInt32(RENAME_SWAP)) == 0 else { throw CocoaError(.fileWriteUnknown) }
        return Result(unmanaged: unmanaged, files: files.map(\.name))
    }
}
