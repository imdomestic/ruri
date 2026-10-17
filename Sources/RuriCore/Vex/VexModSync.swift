import Foundation
import CryptoKit
import Darwin
import RuriLocalization

public protocol VexModSynchronizing: Sendable {
    func synchronize(_ build: VexBuild, instance: GameInstance) async throws -> VexModSync.Result
}

public struct VexModSync: VexModSynchronizing {
    public struct Receipt: Codable, Sendable {
        public let project: String
        public let buildID: String
        public let files: [VexBuild.File]
    }
    public struct Result: Sendable { public let unmanaged: [String]; public let files: [String] }
    public let paths: LauncherPaths
    public let client: VexClient
    public init(paths: LauncherPaths, client: VexClient) { self.paths = paths; self.client = client }

    public static func clientFiles(_ build: VexBuild) throws -> [VexBuild.File] {
        guard build.status == .ready, build.minecraft != nil, build.loaderVersion != nil, build.java != nil else {
            throw RuriError.message(Messages.Vex.buildUnavailable)
        }
        let files = build.files.filter(\.isClient)
        guard Set(files.map(\.name)).count == files.count else { throw RuriError.message(Messages.Vex.invalidResponse) }
        for file in files {
            guard file.name.hasSuffix(".jar"), file.name != ".jar", !file.name.hasPrefix("."),
                  !file.name.contains("/"), !file.name.contains("\\"), !file.name.contains("\0"),
                  file.sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
                  file.size > 0 else { throw RuriError.message(Messages.Vex.invalidResponse) }
        }
        return files
    }
    public static func digest(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    static func verify(_ url: URL, file: VexBuild.File) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              Int64(values.fileSize ?? -1) == file.size, try digest(url) == file.sha256 else {
            throw RuriError.message(Messages.Vex.checksumFailed(file.name))
        }
    }
    public func synchronize(_ build: VexBuild, instance: GameInstance) async throws -> Result {
        guard build.project == client.project else { throw RuriError.message(Messages.Vex.invalidResponse) }
        let files = try Self.clientFiles(build)
        let state = try StateStore.load(paths), configured = paths.configured(with: state)
        let settings = state.settings.experimental?.vex ?? VexSettings()
        let marker = try JSONDecoder().decode(VexInstanceManager.Marker.self, from: Data(contentsOf: configured.instance(instance.id).appendingPathComponent("vex-instance.json")))
        guard instance.runDirectory == .isolated, settings.instances[marker.key] == instance.id else {
            throw RuriError.message(Messages.Vex.invalidResponse)
        }
        let lease = try GameRunLease.acquire(paths: configured, instanceID: instance.id)
        defer { withExtendedLifetime(lease) {} }
        let directory = configured.game(instance.id).appendingPathComponent("mods")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let receiptURL = directory.appendingPathComponent(".vex-managed.json")
        let receipt = FileManager.default.fileExists(atPath: receiptURL.path)
            ? try JSONDecoder().decode(Receipt.self, from: Data(contentsOf: receiptURL)) : nil
        guard receipt == nil || receipt?.project == build.project else { throw RuriError.message(Messages.Vex.invalidResponse) }
        let previous = receipt?.files ?? []
        let priorNames = Set(previous.map(\.name)), nextNames = Set(files.map(\.name))
        let existing = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        let unmanaged = existing.filter { $0.hasSuffix(".jar") && !priorNames.contains($0) }.sorted()
        guard Set(unmanaged).isDisjoint(with: nextNames) else { throw RuriError.message(Messages.Vex.unmanagedConflict) }
        for file in previous {
            let target = try LauncherPaths.safePath(file.name, within: directory)
            if FileManager.default.fileExists(atPath: target.path) { try Self.verify(target, file: file) }
        }
        let cache = paths.cache.appendingPathComponent("vex", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        var prepared: [(VexBuild.File, URL)] = []
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
            }
            prepared.append((file, cached))
        }
        try Task.checkCancellation()
        let stage = directory.deletingLastPathComponent().appendingPathComponent(".vex-mods-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: stage) }
        try FileManager.default.copyItem(at: directory, to: stage)
        for (file, source) in prepared {
            let target = try LauncherPaths.safePath(file.name, within: stage)
            if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
            try FileManager.default.copyItem(at: source, to: target)
        }
        for file in previous where !nextNames.contains(file.name) {
            let target = try LauncherPaths.safePath(file.name, within: stage)
            if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
        }
        try JSONEncoder().encode(Receipt(project: build.project, buildID: build.id, files: files))
            .write(to: stage.appendingPathComponent(".vex-managed.json"), options: .atomic)
        try Task.checkCancellation()
        guard renamex_np(stage.path, directory.path, UInt32(RENAME_SWAP)) == 0 else { throw CocoaError(.fileWriteUnknown) }
        return Result(unmanaged: unmanaged, files: files.map(\.name))
    }
}
