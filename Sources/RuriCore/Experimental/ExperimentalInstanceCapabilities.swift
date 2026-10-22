import Foundation
import CryptoKit
import RuriLocalization

public struct ExperimentalManagedFile: Sendable {
    public let path: String
    public let sha1: String
    public let sha256: String
    public let sha512: String
    public let size: Int64
    public init(path: String, sha1: String, sha256: String, sha512: String, size: Int64) {
        self.path = path; self.sha1 = sha1; self.sha256 = sha256; self.sha512 = sha512; self.size = size
    }
}

/// Instances, Modrinth packs and their files, through the launcher's own services.
public struct ExperimentalInstanceCapabilities: Sendable {
    public let paths: LauncherPaths
    public init(paths: LauncherPaths) { self.paths = paths }
    public struct Context: Sendable {
        public let paths: LauncherPaths
        public let concurrentDownloads: Int
        public let accountAvailable: Bool
    }
    public func context() throws -> Context {
        let state = try StateStore.load(paths)
        return Context(paths: paths.configured(with: state), concurrentDownloads: state.settings.concurrentDownloads,
                       accountAvailable: !state.accounts.isEmpty)
    }
    public func instance(id: UUID) throws -> GameInstance { try InstanceService(paths: paths).resolve(id: id) }
    public func setJavaMajor(_ major: Int, instanceID: UUID) throws -> GameInstance {
        let state = try StateStore.updateIfChanged(paths) { state in
            guard let index = state.instances.firstIndex(where: { $0.id == instanceID }) else {
                throw OperationFailure("NOT_FOUND", Messages.CLIInterface.instanceNotFound.localized)
            }
            state.instances[index].javaMajor = major
        }
        return state.instances.first { $0.id == instanceID }!
    }
    public func prepareImport(_ archive: URL, excludingFiles: Set<String>) async throws -> PreparedInstanceImport {
        try await InstanceTransfer(paths: paths).prepare(archive, excludingFiles: excludingFiles)
    }
    public func discardImport(_ prepared: PreparedInstanceImport) async {
        await InstanceTransfer(paths: paths).discard(prepared)
    }
    public static func readMetadata<T: Decodable>(_ file: URL, limit: Int) throws -> T {
        try RunDirectoryCopyGuard.decode(file, limit: limit)
    }
    public func removeHiddenServers(instanceID: UUID, matching predicate: (ServerAddress) -> Bool) throws {
        let snapshot = try ServerListManager(paths: paths, instanceID: instanceID).snapshot()
        guard let original = snapshot.original else { return }
        var document = snapshot.document
        document.entries.removeAll { fields in
            guard fields.first(where: { $0.name == "hidden" })?.value.integer.map({ $0 != 0 }) == true,
                  let address = fields.first(where: { $0.name == "ip" })?.value.string,
                  let endpoint = try? ServerAddress(address) else { return false }
            return predicate(endpoint)
        }
        guard document.entries.count != snapshot.document.entries.count else { return }
        let file = try LauncherPaths.safePath("servers.dat", within: paths.game(instanceID))
        guard paths.game(instanceID).standardizedFileURL.resolvingSymlinksInPath() == snapshot.directory,
              try RunDirectoryCopyGuard.read(file, limit: 8 * 1024 * 1024) == original else {
            throw RuriError.message(Messages.Servers.listChanged)
        }
        let backup = try LauncherPaths.safePath("servers.dat.ruri-backup", within: paths.game(instanceID))
        try original.write(to: backup, options: .atomic)
        try document.encoded().write(to: file, options: .atomic)
    }
    public static func digest(_ file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var digest = SHA256()
        while let bytes = try handle.read(upToCount: 1_048_576), !bytes.isEmpty { try Task.checkCancellation(); digest.update(data: bytes) }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
    public static func verify(_ file: URL, expected: ExperimentalManagedFile) throws {
        let info = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard info.isRegularFile == true, info.isSymbolicLink != true, Int64(info.fileSize ?? -1) == expected.size,
              try digest(file) == expected.sha256,
              DownloadManager.valid(file, item: DownloadItem(url: nil, destination: file, sha1: expected.sha1, sha512: expected.sha512, size: expected.size)) else {
            throw RuriError.message(Messages.CoreInstanceTransfer.bundledFileChecksumFailed(expected.path))
        }
    }
    public static func validate(_ prepared: PreparedInstanceImport, version: String, minecraft: String, loader: LoaderKind,
                                loaderVersion: String, files: [ExperimentalManagedFile]) throws {
        guard prepared.format == "Modrinth", prepared.packVersion == version, !prepared.includesInstallation,
              prepared.instance.gameVersion == minecraft, prepared.instance.loader == loader,
              prepared.instance.loaderVersion == loaderVersion else { throw RuriError.message(Messages.CoreModpackUpdater.invalidPackSelection) }
        let bundled = try FileTree.entries(in: prepared.game).filter { !$0.directory && $0.path.hasPrefix("mods/") }
        let paths = Set(bundled.map(\.path)).union(prepared.packFiles.filter { $0.path.hasPrefix("mods/") }.map(\.path))
        guard paths == Set(files.map(\.path)) else { throw RuriError.message(Messages.CoreModpackUpdater.invalidPackSelection) }
        for file in files {
            let target = try LauncherPaths.safePath(file.path, within: prepared.game)
            if FileManager.default.fileExists(atPath: target.path) { try verify(target, expected: file) }
            else {
                guard let remote = prepared.packFiles.first(where: { $0.path == file.path }),
                      remote.sha1 == file.sha1, remote.sha512 == file.sha512, remote.size == file.size else {
                    throw RuriError.message(Messages.CoreInstanceTransfer.bundledFileChecksumFailed(file.path))
                }
            }
        }
    }
    public static func verifyTrackedFiles(_ pack: InstalledModpack, game: URL) throws {
        for file in pack.files {
            guard try ModpackUpdatePlanner.digest(LauncherPaths.safePath(file.path, within: game)) == file.sha1 else {
                throw RuriError.message(Messages.CoreModpackUpdater.filesChangedAfterPreview(file.path))
            }
        }
    }
    public static func verifyModContent(_ pack: InstalledModpack, game: URL, expected: [ExperimentalManagedFile]) throws -> Set<String> {
        try verifyTrackedFiles(pack, game: game)
        let managed = pack.files.filter { $0.path.hasPrefix("mods/") && $0.path.hasSuffix(".jar") }
        var seen = Set<String>()
        for file in managed {
            let url = try LauncherPaths.safePath(file.path, within: game)
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var digest = SHA512()
            while let bytes = try handle.read(upToCount: 1_048_576), !bytes.isEmpty {
                try Task.checkCancellation(); digest.update(data: bytes)
            }
            let sha512 = digest.finalize().map { String(format: "%02x", $0) }.joined()
            guard let target = expected.first(where: { $0.sha512 == sha512 }) else {
                throw RuriError.message(Messages.CoreModpackUpdater.filesChangedAfterPreview(file.path))
            }
            try verify(url, expected: target)
            seen.insert(sha512)
        }
        guard seen == Set(expected.map(\.sha512)) else { throw RuriError.message(Messages.CoreModpackUpdater.invalidPackSelection) }
        return Set(managed.map(\.path))
    }
    public func recordExistingPack(instance: GameInstance, version: String, files: [ExperimentalManagedFile]) throws {
        guard try ModpackRegistry.load(paths: paths, instanceID: instance.id) == nil else { return }
        let lease = try GameRunLease.acquire(paths: paths, instanceID: instance.id)
        defer { withExtendedLifetime(lease) {} }
        let entries = try files.map { file -> InstalledModpack.File in
            let target = try LauncherPaths.safePath(file.path, within: paths.game(instance.id))
            try Self.verify(target, expected: file)
            let identities = ContentManager.modInfo(target)?.id.map { ["mod:" + $0] } ?? []
            return .init(path: file.path, sha1: file.sha1, size: file.size, force: false, identities: identities)
        }
        try ModpackRegistry.save(.init(format: "Modrinth", name: instance.name, version: version, origin: nil, settings: instance, files: entries), paths: paths, instanceID: instance.id)
    }
    public func install(_ prepared: PreparedInstanceImport, existing: GameInstance?, name: String,
                        concurrency: Int, progress: @escaping @Sendable (InstallProgress) async -> Void) async throws -> GameInstance {
        let downloader = DownloadManager(cache: DownloadCache(paths: paths))
        if let existing {
            guard let previous = try ModpackRegistry.load(paths: paths, instanceID: existing.id) else { throw RuriError.message(Messages.CoreModpackUpdater.missingPackSource) }
            try Self.verifyTrackedFiles(previous, game: paths.game(existing.id))
            let updater = ModpackUpdater(paths: paths, downloader: downloader)
            let plan = try await updater.prepare(prepared, for: existing, concurrency: concurrency, progress: progress)
            do {
                guard !plan.changes.contains(where: \.conflict) else { throw RuriError.message(Messages.CoreModpackUpdater.previewConfigurationChanged) }
                let keeping = Set(plan.changes.filter { $0.action == .keep }.map(\.id))
                _ = try await updater.apply(plan, keepingLocal: keeping, concurrency: concurrency, progress: progress)
                await updater.discard(plan)
            } catch {
                await updater.discard(plan)
                throw error
            }
            return try InstanceService(paths: paths).resolve(id: existing.id)
        }
        let imported = try await InstanceTransfer(paths: paths).install(prepared, name: name,
            installer: GameInstaller(paths: paths, downloader: downloader), concurrency: concurrency, progress: progress)
        if imported.repositoryVersionID == nil { try StateStore.updateIfChanged(paths) { $0.instances.append(imported) } }
        return imported
    }
    public func quickPlayArguments(instance: GameInstance, manifest: VersionManifest, address: ServerAddress) throws -> [String] {
        guard GameQuickPlay.supports(instance: instance, manifest: manifest) else { throw RuriError.message(Messages.CoreLaunch.mainClassMissing) }
        return GameQuickPlay.applying(.server(address), arguments: [], logging: paths.instance(instance.id).appendingPathComponent("quick-play/extension.json"), gameDirectory: paths.game(instance.id))
    }
}
