import RuriLocalization
import Foundation

public enum InstanceExportFormat: String, CaseIterable, Sendable, Identifiable {
    case ruri, complete, multimc, mcbbs, mrpack
    public var id: String { rawValue }
    public var title: String { switch self { case .ruri: Messages.CoreInstanceTransfer.ruriInstance.localized; case .complete: Messages.CoreInstanceTransfer.ruriFullCopy.localized; case .multimc: "Prism / MultiMC"; case .mcbbs: "MCBBS / HMCL"; case .mrpack: "Modrinth" } }
}

public struct PreparedInstanceImport: Identifiable, Sendable {
    public let id: UUID
    public let format: String
    public private(set) var instance: GameInstance
    public let warnings: [String]
    public let author: String?
    public let summary: String?
    public var packVersion: String? { modpack.flatMap { $0.version.isEmpty ? nil : $0.version } }
    public let fileCount: Int
    public let byteCount: Int64
    /// Content files the pack carries itself, outside its download list.
    public let bundledContent: [BundledContentFile]
    public let curseForgeFiles: [CurseForgeReference]
    /// Selected pack files the archive does not already carry.
    public private(set) var remoteFiles: [PackFile]
    public var remoteFileCount: Int { remoteFiles.count }
    let packFiles: [PackFile]
    public private(set) var omittedOptionalPaths: Set<String> = []
    var selectedPackFiles: [PackFile] { packFiles.filter { !omittedOptionalPaths.contains($0.path) } }
    public var optionalFiles: [PackFile] { packFiles.filter(\.optional) }
    public func selectingOptionalFiles(excluding paths: Set<String>) -> Self {
        var result = self
        result.omittedOptionalPaths = paths.intersection(Set(optionalFiles.map(\.path)))
        result.remoteFiles = result.selectedPackFiles.filter { !FileManager.default.fileExists(atPath: game.appendingPathComponent($0.path).path) }
        return result
    }
    /// Drops the pack's values for these settings so the new instance follows
    /// the global ones instead.
    public func inheritingLaunchSettings(_ keys: Set<LaunchSettingKey>) -> Self {
        guard !keys.isEmpty, var overrides = instance.launchOverrides else { return self }
        for key in keys { overrides.setInheritance(true, for: key, defaults: .init()) }
        var result = self; result.instance.launchOverrides = overrides
        return result
    }
    /// Uses a catalog project's artwork when the imported instance has no icon of its own.
    public func usingIcon(_ png: Data) -> Self {
        guard instance.iconPNG == nil, instance.iconStyle == nil else { return self }
        var result = self
        result.instance.iconPNG = png
        return result
    }
    let sourceMetadata: Data?
    let workspace: URL
    let game: URL
    let records: Data?
    let modpack: ModpackDescriptor?
    let inheritedModpack: InstalledModpack?
    var installation: PreparedMinecraftInstallation? = nil
    public var includesInstallation: Bool { installation != nil }
}

struct InstanceImportDescription {
    let instance: GameInstance
    let game: URL
    let format: String
    var warnings: [String] = []
    var author: String?
    var summary: String?
    var records: Data?
    var curseForgeFiles: [CurseForgeReference] = []
    var packFiles: [PackFile] = []
    var excluded: Set<String> = []
    var sourceMetadata: Data?
    var overlays: [URL] = []
    var modpack: ModpackDescriptor?
    var inheritedModpack: InstalledModpack?
    var installation: URL?
}

public struct BundledContentFile: Identifiable, Sendable {
    public var id: String { path }
    public let path: String
    public let size: Int64
}

public struct PackFile: Identifiable, Sendable {
    public var id: String { path }
    public let path: String
    public let sha1: String
    public let url: URL?
    public var sha512: String?
    public var size: Int64?
    public var fallbackURLs: [URL] = []
    public var optional = false
    public var force = false
    func item(in root: URL, url override: URL? = nil) throws -> DownloadItem { DownloadItem(url: override ?? url, destination: try LauncherPaths.safePath(path, within: root), sha1: sha1, sha512: sha512, size: size, cacheable: true) }
}

/// Portable exports contain game data and preferences; shared downloads and
/// machine-specific Java paths are rebuilt for the destination Mac.
struct PortableInstance: Codable {
    var formatVersion = 1
    let name: String
    let gameVersion: String
    let loader: LoaderKind
    let loaderVersion: String?
    let components: [MinecraftDirectoryComponent]?
    let memoryMB: Int
    let extraJVMArguments: String
    let extraGameArguments: String?
    let supportedJavaMajors: [Int]?
    let javaMajor: Int?
    let packLibraries: [Library]?
    let width: Int
    let height: Int
    let fullscreen: Bool?
    let launchPresentation: LaunchPresentation?
    var macOSGameSettings: MacOSGameSettings?
    let launchCommands: LaunchCommands?
    let iconPNG: Data?
    let iconStyle: InstanceIconStyle?
    let installation: ImportedMinecraftInstallation?
    init(_ instance: GameInstance, installation: ImportedMinecraftInstallation? = nil) {
        name = instance.name; gameVersion = instance.gameVersion; loader = instance.loader; loaderVersion = instance.loaderVersion
        components = instance.repositoryComponents
        extraGameArguments = instance.extraGameArguments; supportedJavaMajors = instance.supportedJavaMajors; packLibraries = instance.packLibraries
        javaMajor = instance.javaMajor
        memoryMB = instance.memoryMB; extraJVMArguments = instance.extraJVMArguments; width = instance.width; height = instance.height
        fullscreen = instance.fullscreen; launchPresentation = instance.launchPresentation; macOSGameSettings = instance.macOSGameSettings
        launchCommands = instance.launchCommands?.isEmpty == false ? instance.launchCommands : nil
        iconPNG = instance.iconPNG; iconStyle = instance.iconStyle; self.installation = installation
        if installation != nil { formatVersion = 2 }
        if instance.loaderSelections.count > 1 { formatVersion = 3 }
    }
    func instance() throws -> GameInstance {
        guard (1...3).contains(formatVersion), formatVersion == 3 || (formatVersion == 2) == (installation != nil) else { throw RuriError.message(Messages.CoreInstanceTransfer.unsupportedInstanceVersion) }
        try installation?.validate()
        var result = GameInstance(name: name, gameVersion: gameVersion, loader: loader, loaderVersion: loaderVersion)
        result.repositoryComponents = components
        if installation == nil, let components {
            guard components.count == result.loaderSelections.count,
                  (result.loaderSelections.first?.loader ?? .vanilla) == loader,
                  result.loaderSelections.first?.version == loaderVersion else {
                throw RuriError.message(Messages.LoaderSelection.invalidSelection)
            }
        }
        result.extraGameArguments = extraGameArguments; result.supportedJavaMajors = supportedJavaMajors; result.packLibraries = packLibraries
        result.javaMajor = javaMajor
        result.memoryMB = memoryMB; result.extraJVMArguments = extraJVMArguments; result.width = width; result.height = height
        result.fullscreen = fullscreen; result.launchPresentation = launchPresentation; result.macOSGameSettings = macOSGameSettings
        result.launchCommands = launchCommands
        result.launchCommands?.enabled = false
        result.iconPNG = iconPNG; result.iconStyle = iconStyle; result.importedInstallation = installation
        return result
    }
}

struct MultiMCPack: Codable {
    struct Component: Codable { let uid: String; let version: String? }
    var formatVersion = 1
    let components: [Component]
}

public actor InstanceTransfer {
    let paths: LauncherPaths
    static let loaderIDs: [String: LoaderKind] = ["net.fabricmc.fabric-loader": .fabric, "org.quiltmc.quilt-loader": .quilt, "net.minecraftforge": .forge, "net.neoforged": .neoforge, "com.mumfrey.liteloader": .liteloader]
    static let excluded: Set<String> = [".ruri", "logs", "crash-reports", "assets", "libraries", "versions", "natives", "webcache", "launcher_accounts.json", "launcher_profiles.json", "usercache.json", "usernamecache.json", "launcher_msa_credentials.bin", ".fabric", ".quilt", ".mixin.out", ".optifine", "downloads", "server-resource-packs", "mods/.connector", "CustomSkinLoader/caches", "local/crash_assistant"]
    public init(paths: LauncherPaths) { self.paths = paths }

    public func prepare(_ source: URL, origin: ModpackOrigin? = nil, excludingFiles: Set<String> = [], progress: @Sendable (InstallProgress) -> Void = { _ in }) throws -> PreparedInstanceImport {
        try paths.prepare()
        let workspace = paths.cache.appendingPathComponent("transfer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        do {
            progress(InstallProgress(Messages.CoreInstanceTransfer.identifyingInstance))
            let isDirectory = try source.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard isDirectory.isSymbolicLink != true else { throw RuriError.message(Messages.CoreInstanceTransfer.actualDirectoryRequired) }
            let unpacked: URL
            if isDirectory.isDirectory == true { unpacked = source }
            else {
                unpacked = workspace.appendingPathComponent("unpacked")
                try SafeArchive.extract(source, to: unpacked, maxBytes: 128 * 1024 * 1024 * 1024)
            }
            let root = try Self.findRoot(unpacked)
            var description = try Self.describe(root)
            for path in excludingFiles { _ = try LauncherPaths.safePath(path, within: description.game) }
            description.excluded.formUnion(excludingFiles)
            description.packFiles.removeAll { excludingFiles.contains($0.path) }
            if let origin { description.modpack?.origin = origin }
            let locks = try Self.lockWorlds(description.game); defer { locks.forEach { close($0) } }
            let snapshot = workspace.appendingPathComponent("minecraft")
            let declaredFolders = Set(description.packFiles.compactMap { $0.path.split(separator: "/").first.map(String.init) })
            var excluded = try Self.exclusions(description.game, includeWorlds: true).subtracting(declaredFolders).union(description.excluded)
            if description.installation != nil {
                // A complete export already selected its game files; retain
                // bundled folders even when light packs normally rebuild them.
                excluded = Set(excluded.filter { $0 == ".ruri" || ($0.hasPrefix("saves/") && $0.hasSuffix("/session.lock")) })
            }
            if FileManager.default.fileExists(atPath: description.game.path) {
                try FileTree.copy(from: description.game, to: snapshot, excluding: excluded) { done, total in progress(InstallProgress(Messages.CoreInstanceTransfer.copyingInstanceContents, completed: done, total: total)) }
            } else { try FileManager.default.createDirectory(at: snapshot, withIntermediateDirectories: true) }
            for overlay in description.overlays {
                if FileManager.default.fileExists(atPath: overlay.path) { try FileTree.overlay(from: overlay, to: snapshot, excluding: excluded) }
            }
            // In mrpack, archive overrides are applied after downloads and may
            // intentionally replace them. Keep the bundled file as authoritative.
            let packFiles = description.packFiles.filter { description.format != "Modrinth" || !FileManager.default.fileExists(atPath: snapshot.appendingPathComponent($0.path).path) }
            for file in packFiles {
                let item = try file.item(in: snapshot)
                if FileManager.default.fileExists(atPath: item.destination.path) {
                    guard DownloadManager.valid(item.destination, item: item) else { throw RuriError.message(Messages.CoreInstanceTransfer.bundledFileChecksumFailed(file.path)) }
                } else if file.url == nil { throw RuriError.message(Messages.CoreInstanceTransfer.missingBundledFileDownloadSource(file.path)) }
            }
            let installation = try description.installation.map {
                try PreparedMinecraftInstallation.capture($0, in: workspace, instance: description.instance, paths: paths)
            }
            let entries = try FileTree.entries(in: snapshot)
            let bundled = Self.bundledContent(entries)
            return PreparedInstanceImport(id: UUID(), format: description.format, instance: description.instance, warnings: description.warnings, author: description.author, summary: description.summary,
                                          fileCount: entries.filter { !$0.directory }.count + (installation?.fileCount ?? 0), byteCount: entries.reduce(0) { $0 + $1.size } + (installation?.byteCount ?? 0), bundledContent: bundled, curseForgeFiles: description.curseForgeFiles,
                                          remoteFiles: packFiles.filter { !FileManager.default.fileExists(atPath: snapshot.appendingPathComponent($0.path).path) },
                                          packFiles: packFiles, sourceMetadata: description.sourceMetadata, workspace: workspace, game: snapshot, records: description.records, modpack: description.modpack, inheritedModpack: description.inheritedModpack, installation: installation)
        } catch { try? FileManager.default.removeItem(at: workspace); throw error }
    }

    /// One item per mod archive or pack in a content folder; unpacked packs
    /// count once, and side files such as shader settings are not content.
    static func bundledContent(_ entries: [FileTree.Entry]) -> [BundledContentFile] {
        var sizes: [String: Int64] = [:]
        for entry in entries where !entry.directory {
            let parts = entry.path.split(separator: "/", maxSplits: 2).map(String.init)
            guard parts.count >= 2, let kind = ContentKind.allCases.first(where: { $0.folder == parts[0] }) else { continue }
            if parts.count == 2 {
                guard kind.fileExtensions.contains((parts[1] as NSString).pathExtension.lowercased()) else { continue }
            } else if kind == .mod { continue }
            sizes[parts[0] + "/" + parts[1], default: 0] += entry.size
        }
        return sizes.map { BundledContentFile(path: $0.key, size: $0.value) }.sorted { $0.path < $1.path }
    }

    public func discard(_ prepared: PreparedInstanceImport) { try? FileManager.default.removeItem(at: prepared.workspace) }

    /// `content` downloads provider files the pack references, such as CurseForge mods.
    public func install(_ prepared: PreparedInstanceImport, name: String, importJVMArguments: Bool = false, installer: GameInstaller, concurrency: Int = 8,
                        content: @Sendable () async throws -> [ContentInstallation] = { [] },
                        progress: @Sendable @escaping (InstallProgress) async -> Void) async throws -> GameInstance {
        let target = try destinationInstance(prepared, name: name, importJVMArguments: false)
        // Game assets download alongside the pack's own files on a parallel
        // track; the installer later finds them in place or joins the transfers.
        async let assets: Void = prefetchGame(target, prepared: prepared, downloader: installer.downloader, concurrency: concurrency, progress: progress)
        let files = try await content()
        try await completeFiles(prepared, downloader: installer.downloader, concurrency: concurrency, progress: progress)
        let instance = try await install(prepared, name: name, importJVMArguments: importJVMArguments, content: files, installing: { instance, location in
            try await GameInstaller(paths: location, downloader: installer.downloader).install(instance, concurrency: concurrency, progress: progress)
        })
        await assets
        return instance
    }

    private nonisolated func prefetchGame(_ target: GameInstance, prepared: PreparedInstanceImport, downloader: DownloadManager, concurrency: Int,
                                          progress: @Sendable @escaping (InstallProgress) async -> Void) async {
        guard !prepared.includesInstallation, target.importedInstallation == nil else { return }
        // Resolve resources exactly as the install will, including its repository guard.
        let location = target.repositoryVersionID == nil ? paths.including(target) : paths.stagingRepositoryImport(target)
        await GameInstaller(paths: location, downloader: downloader).prefetch(target, concurrency: concurrency, progress: progress)
    }

    public func validateDestination(_ prepared: PreparedInstanceImport, name: String) throws {
        _ = try destinationInstance(prepared, name: name, importJVMArguments: false)
    }

    private func destinationInstance(_ prepared: PreparedInstanceImport, name: String, importJVMArguments: Bool) throws -> GameInstance {
        var instance = prepared.instance
        instance.id = UUID(); instance.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        instance.directoryID = paths.newInstanceDirectoryID; instance.runDirectory = .isolated
        if instance.name.isEmpty { instance.name = prepared.instance.name }
        instance.javaPath = nil; instance.installed = false
        if !importJVMArguments { instance.extraJVMArguments = ""; instance.launchOverrides?.jvmArguments = nil }
        instance = try MinecraftFolderStore.preparingNewInstance(instance, paths: paths)
        if prepared.includesInstallation, instance.repositoryVersionID != nil {
            instance.repositoryComponents = instance.importedInstallation?.components; instance.importedInstallation = nil
        }
        try Self.validate(instance)
        return instance
    }
    public func completeFiles(_ prepared: PreparedInstanceImport, downloader: DownloadManager, concurrency: Int = 8,
                              progress: @Sendable @escaping (InstallProgress) async -> Void) async throws {
        let files = prepared.selectedPackFiles; let root = prepared.game
        try await forEachConcurrently(files, width: concurrency) { file in
            let urls = [file.url].compactMap { $0 } + file.fallbackURLs
            if urls.isEmpty { try await downloader.fetch(file.item(in: root)); return }
            var failure: (any Error)?
            for url in urls {
                do { try await downloader.fetch(file.item(in: root, url: url)); return }
                catch { if Task.isCancelled { throw CancellationError() }; failure = error }
            }
            throw failure ?? RuriError.message(Messages.CoreInstanceTransfer.missingDownloadSource)
        } completed: { _, done in
            await progress(InstallProgress(Messages.CoreInstanceTransfer.completingPackFiles, completed: done, total: files.count))
        }
    }
    // The closure makes filesystem rollback testable without contacting game services.
    func install(_ prepared: PreparedInstanceImport, name: String, importJVMArguments: Bool = false, content: [ContentInstallation] = [],
                 installGame: @Sendable (GameInstance) async throws -> GameInstance) async throws -> GameInstance {
        try await install(prepared, name: name, importJVMArguments: importJVMArguments, content: content, installing: { instance, _ in try await installGame(instance) })
    }

    func install(_ prepared: PreparedInstanceImport, name: String, importJVMArguments: Bool = false, content: [ContentInstallation] = [],
                 installing: @Sendable (GameInstance, LauncherPaths) async throws -> GameInstance) async throws -> GameInstance {
        var instance = try destinationInstance(prepared, name: name, importJVMArguments: importJVMArguments)
        for file in prepared.selectedPackFiles {
            let item = try file.item(in: prepared.game)
            guard DownloadManager.valid(item.destination, item: item) else { throw RuriError.message(Messages.CoreInstanceTransfer.modifiedBundledFile(file.path)) }
        }
        try Self.validatePackContent(content, references: prepared.curseForgeFiles)
        let transaction = try instance.repositoryVersionID == nil ? nil : RepositoryImportTransaction(instance: instance, paths: paths)
        let location = transaction?.staging ?? paths.including(instance)
        do {
            try location.prepareInstance(instance.id)
            // User files are copied first; official installer then supplies any
            // generated legacy resources without a destructive directory merge.
            try FileTree.copy(from: prepared.game, to: location.game(instance.id), excluding: prepared.omittedOptionalPaths)
            if let records = prepared.records {
                try records.write(to: location.gameDataState(instance.id).appendingPathComponent("content.json"), options: .atomic)
                _ = try await ContentManager(paths: location, instanceID: instance.id).records()
            }
            if let source = prepared.sourceMetadata { try source.write(to: location.instance(instance.id).appendingPathComponent("source-mcbbs.packmeta"), options: .atomic) }
            try Self.copyPackContent(content, to: location, instanceID: instance.id)
            let pack = try ModpackRegistry.capture(prepared, instance: instance, paths: location, content: content)
            if let installation = prepared.installation {
                try installation.validate(instance: prepared.instance, paths: paths)
                let plan = try MinecraftInstallationCopy.read(instance: prepared.instance, copy: instance, paths: paths, installationRoot: installation.root)
                try await plan.install(instance, at: location)
                try MinecraftInstallationCopy.retainOriginals(from: installation.root, to: location.instance(instance.id))
                try await GameInstaller(paths: location).prepareRunDirectory(instance, manifest: JSONDecoder().decode(VersionManifest.self, from: plan.manifest))
                instance.installed = true
            } else { instance = try await installing(instance, location) }
            if let pack { try ModpackRegistry.save(pack, paths: location, instanceID: instance.id) }
            try Task.checkCancellation()
            return try transaction?.publish(instance) ?? instance
        } catch {
            if let transaction {
                let reason = Task.isCancelled || error is CancellationError ? Messages.CoreInstanceTransfer.operationCancelled.localized : error.localizedDescription
                do {
                    let kept = try transaction.preserve()
                    throw RepositoryImportFailure(message: Messages.CoreInstanceTransfer.packImportIncomplete(String(describing: reason)).localized, preservedFiles: kept)
                } catch let failure as RepositoryImportFailure { throw failure }
                catch { throw RepositoryImportFailure(message: Messages.CoreInstanceTransfer.importNeedsRecovery(String(describing: reason), error.localizedDescription).localized, preservedFiles: transaction.workspace) }
            }
            try? FileManager.default.removeItem(at: location.instance(instance.id)); throw error
        }
    }

    public func export(_ instance: GameInstance, to destination: URL, format: InstanceExportFormat = .ruri, includeWorlds: Bool = true, details: ModpackExportDetails = .init(),
                       progress: @Sendable (InstallProgress) -> Void = { _ in }) async throws {
        let complete = format == .complete || (format == .ruri && (instance.repositoryVersionID != nil || instance.importedInstallation != nil))
        guard complete || (instance.repositoryVersionID == nil && instance.importedInstallation == nil) else { throw RuriError.message(Messages.CoreInstanceTransfer.localFilesRequireFullCopy) }
        if instance.loader == .legacyfabric && [.multimc, .mrpack].contains(format) {
            throw RuriError.message(Messages.CoreInstanceTransfer.legacyFabricUnsupported)
        }
        if instance.loaderSelections.contains(where: { $0.loader == .liteloader }) && [.multimc, .mrpack].contains(format) {
            throw RuriError.message(Messages.CoreInstanceTransfer.liteLoaderUnsupported)
        }
        if instance.loaderSelections.contains(where: { $0.loader == .optifine }) && [.multimc, .mrpack].contains(format) {
            throw RuriError.message(Messages.CoreInstanceTransfer.optifineUnsupported)
        }
        var instance = try instance.resolvingPersistedLaunchSettings(paths: paths)
        if instance.launchCommands?.isEmpty == false, ![.ruri, .complete].contains(format) {
            throw RuriError.message(Messages.CoreInstanceTransfer.disabledCommandsUnsupported)
        }
        // Portable formats already carry the maximum heap. Encode additional
        // structured limits as ordinary JVM arguments before user arguments,
        // preserving their original precedence in every supported format.
        if let memory = instance.frozenMemory, memory.minimumBytes != 512 * 1_048_576 || memory.initialBytes != memory.minimumBytes || memory.metaspaceBytes != nil {
            let limits = memory.arguments.filter { !$0.hasPrefix("-Xmx") }
            instance.extraJVMArguments = ArgumentTokenizer.join(limits + (try ArgumentTokenizer.split(instance.extraJVMArguments)))
        }
        try await ContentManager(paths: paths, instanceID: instance.id).recover()
        try await WorldManager(paths: paths, instanceID: instance.id).recover()
        let game = paths.game(instance.id)
        let locks = try Self.lockWorlds(game); defer { locks.forEach { close($0) } }
        if complete { try await exportComplete(instance, to: destination, includeWorlds: includeWorlds, progress: progress); return }
        if format == .mrpack { try await exportMRPack(instance, game: game, to: destination, includeWorlds: includeWorlds, details: details, progress: progress); return }
        if format == .mcbbs { try exportMCBBS(instance, game: game, to: destination, includeWorlds: includeWorlds, details: details, progress: progress); return }
        if format == .multimc, instance.extraGameArguments?.isEmpty == false || instance.packLibraries?.isEmpty == false || instance.supportedJavaMajors?.isEmpty == false { throw RuriError.message(Messages.CoreInstanceTransfer.extraLaunchSettings) }
        var extra: [String: Data] = [:]
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if format == .ruri {
            extra["ruri-instance.json"] = try encoder.encode(PortableInstance(instance))
            let records = try await ContentManager(paths: paths, instanceID: instance.id).records()
            extra["ruri-content.json"] = try encoder.encode(records)
            if let pack = try ModpackRegistry.load(paths: paths, instanceID: instance.id) { extra["ruri-modpack-state.json"] = try encoder.encode(pack) }
            let source = paths.instance(instance.id).appendingPathComponent("source-mcbbs.packmeta")
            if FileManager.default.fileExists(atPath: source.path) { extra["ruri-source-mcbbs.packmeta"] = try Self.read(source) }
        } else {
            var components = [MultiMCPack.Component(uid: "net.minecraft", version: instance.gameVersion)]
            if instance.loader != .vanilla, let uid = Self.loaderIDs.first(where: { $0.value == instance.loader })?.key {
                components.append(.init(uid: uid, version: instance.loaderVersion))
            }
            extra["mmc-pack.json"] = try encoder.encode(MultiMCPack(components: components))
            let cfg = ["InstanceType=OneSix", "name=\(Self.iniEncode(instance.name))", "OverrideMemory=true", "MaxMemAlloc=\(instance.memoryMB)",
                       "OverrideWindow=true", "LaunchMaximized=\(instance.fullscreen == true)", "MinecraftWinWidth=\(instance.width)", "MinecraftWinHeight=\(instance.height)",
                       "OverrideJavaArgs=\(!instance.extraJVMArguments.isEmpty)", "JvmArgs=\(Self.iniEncode(instance.extraJVMArguments))"].joined(separator: "\n") + "\n"
            extra["instance.cfg"] = Data(cfg.utf8)
        }
        progress(InstallProgress(Messages.CoreInstanceTransfer.exportingInstance))
        try SafeArchive.create(from: game, to: destination, prefix: format == .ruri ? "minecraft" : ".minecraft", additionalFiles: extra,
                               excluding: Self.exclusions(game, includeWorlds: includeWorlds)) { done, total in progress(InstallProgress(Messages.CoreInstanceTransfer.exportingInstance, completed: done, total: total)) }
    }

    private static func findRoot(_ source: URL) throws -> URL {
        func recognized(_ dir: URL) -> Bool { ["ruri-instance.json", "mmc-pack.json", "modrinth.index.json", "mcbbs.packmeta", "modpack.json", "manifest.json"].contains { FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path) } }
        if recognized(source) { return source }
        let candidates = try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]).filter {
            let info = try $0.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            return info.isDirectory == true && info.isSymbolicLink != true && recognized($0)
        }
        guard candidates.count == 1 else { throw RuriError.message(candidates.isEmpty ? Messages.CoreInstanceTransfer.unsupportedManifest : Messages.CoreInstanceTransfer.multipleInstanceDirectories) }
        return candidates[0]
    }
    static func read(_ url: URL) throws -> Data {
        let info = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard info.isRegularFile == true, info.isSymbolicLink != true, (info.fileSize ?? 0) <= 4 * 1024 * 1024 else { throw RuriError.message(Messages.CoreInstanceTransfer.invalidInstanceManifest(url.lastPathComponent)) }
        return try Data(contentsOf: url)
    }
    static func describe(_ root: URL) throws -> InstanceImportDescription {
        let fm = FileManager.default
        let portable = root.appendingPathComponent("ruri-instance.json")
        var instance: GameInstance; var warnings: [String] = []; let format: String; var records: Data?
        if fm.fileExists(atPath: portable.path) {
            instance = try JSONDecoder().decode(PortableInstance.self, from: read(portable)).instance(); format = "Ruri"
            let metadata = root.appendingPathComponent("ruri-content.json")
            if fm.fileExists(atPath: metadata.path) { records = try read(metadata) }
        } else if fm.fileExists(atPath: root.appendingPathComponent("modrinth.index.json").path) {
            return try describeMRPack(root)
        } else if fm.fileExists(atPath: root.appendingPathComponent("mcbbs.packmeta").path) {
            return try describeMCBBS(root)
        } else if fm.fileExists(atPath: root.appendingPathComponent("modpack.json").path) {
            return try describeHMCL(root)
        } else if fm.fileExists(atPath: root.appendingPathComponent("manifest.json").path), !fm.fileExists(atPath: root.appendingPathComponent("mmc-pack.json").path) {
            let data = try read(root.appendingPathComponent("manifest.json"))
            if let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], object["addons"] != nil { return try describeMCBBS(root, filename: "manifest.json") }
            return try describeCurseForge(root)
        } else {
            format = "Prism / MultiMC"
            let pack = try JSONDecoder().decode(MultiMCPack.self, from: read(root.appendingPathComponent("mmc-pack.json")))
            guard pack.formatVersion == 1, Set(pack.components.map(\.uid)).count == pack.components.count,
                  let game = pack.components.first(where: { $0.uid == "net.minecraft" })?.version else { throw RuriError.message(Messages.CoreInstanceTransfer.invalidMultiMCManifest) }
            let supported = Set(loaderIDs.keys).union(["net.minecraft", "org.lwjgl", "org.lwjgl3", "net.fabricmc.intermediary", "org.quiltmc.hashed"])
            let unknown = Set(pack.components.map(\.uid)).subtracting(supported)
            guard unknown.isEmpty else { throw RuriError.message(Messages.CoreInstanceTransfer.unsupportedComponents(String(describing: unknown.sorted().joined(separator: ", ")))) }
            let loaders = pack.components.filter { loaderIDs[$0.uid] != nil }
            guard loaders.count <= 1 else { throw RuriError.message(Messages.CoreInstanceTransfer.multipleLoadersUnsupported) }
            for folder in ["patches", "jarmods"] {
                let url = root.appendingPathComponent(folder)
                if fm.fileExists(atPath: url.path), !(try FileTree.entries(in: url)).isEmpty { throw RuriError.message(Messages.CoreInstanceTransfer.customPatchRequiresHandling(String(describing: folder))) }
            }
            let cfgURL = root.appendingPathComponent("instance.cfg")
            let cfg = fm.fileExists(atPath: cfgURL.path) ? try iniDecode(String(decoding: read(cfgURL), as: UTF8.self)) : [:]
            instance = GameInstance(name: cfg["name"] ?? root.lastPathComponent, gameVersion: game, loader: loaders.first.flatMap { loaderIDs[$0.uid] } ?? .vanilla, loaderVersion: loaders.first?.version)
            // Only what the instance explicitly overrides stays local; everything
            // else follows this Mac's global settings like a new instance.
            var overrides = InstanceLaunchOverrides()
            if cfg["OverrideMemory"]?.lowercased() == "true", let value = cfg["MaxMemAlloc"].flatMap(Int.init) { instance.memoryMB = value; overrides.memory = .init(maximumMB: value) }
            if cfg["OverrideWindow"]?.lowercased() == "true" {
                instance.width = cfg["MinecraftWinWidth"].flatMap(Int.init) ?? instance.width; instance.height = cfg["MinecraftWinHeight"].flatMap(Int.init) ?? instance.height
                instance.fullscreen = cfg["LaunchMaximized"]?.lowercased() == "true"
                overrides.window = .init(width: instance.width, height: instance.height, fullscreen: instance.fullscreen ?? false)
            }
            if cfg["OverrideJavaArgs"]?.lowercased() == "true" { instance.extraJVMArguments = cfg["JvmArgs"] ?? ""; overrides.jvmArguments = instance.extraJVMArguments }
            var commands = LaunchCommands()
            commands.before = cfg["PreLaunchCommand"] ?? ""; commands.after = cfg["PostExitCommand"] ?? ""; commands.wrapper = cfg["WrapperCommand"] ?? ""
            if !commands.isEmpty { instance.launchCommands = commands; overrides.commands = commands }
            instance.launchOverrides = overrides
        }
        try validate(instance)
        if instance.launchCommands?.isEmpty == false { warnings.append(Messages.CoreInstanceTransfer.retainedCommands.localized) }
        let games = ["minecraft", ".minecraft"].map { root.appendingPathComponent($0) }.filter { fm.fileExists(atPath: $0.path) }
        guard games.count == 1, try games[0].resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]).isDirectory == true,
              try games[0].resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw RuriError.message(Messages.CoreInstanceTransfer.uniqueGameDirectory) }
        let source = root.appendingPathComponent("ruri-source-mcbbs.packmeta")
        return InstanceImportDescription(instance: instance, game: games[0], format: format, warnings: warnings, records: records,
                                         sourceMetadata: format == "Ruri" && fm.fileExists(atPath: source.path) ? try read(source) : nil,
                                         inheritedModpack: format == "Ruri" && fm.fileExists(atPath: root.appendingPathComponent("ruri-modpack-state.json").path) ? try ModpackRegistry.read(root.appendingPathComponent("ruri-modpack-state.json"), game: games[0]) : nil,
                                         installation: instance.importedInstallation != nil ? try LauncherPaths.safePath("installation", within: root) : nil)
    }
    static func validate(_ instance: GameInstance) throws {
        if instance.importedInstallation == nil { try LoaderCompatibility.validate(instance.loaderSelections, game: instance.gameVersion) }
        try instance.launchCommands?.validate()
        if let icon = instance.iconPNG { try InstanceIconImage.validate(icon) }
        guard !instance.name.isEmpty, instance.name.count <= 256, !instance.gameVersion.isEmpty, instance.gameVersion.count <= 128,
              instance.loader == .vanilla || !(instance.loaderVersion ?? "").isEmpty,
              (512...131072).contains(instance.memoryMB), (320...16384).contains(instance.width), (240...16384).contains(instance.height),
              instance.extraJVMArguments.count <= 32768, (instance.extraGameArguments?.count ?? 0) <= 32768, (instance.supportedJavaMajors ?? []).allSatisfy({ (6...100).contains($0) }),
              instance.javaMajor == nil || (6...99).contains(instance.javaMajor!) else { throw RuriError.message(Messages.CoreInstanceTransfer.invalidIconSettings) }
        _ = try GameInstaller.applyingPackLibraries(instance.packLibraries ?? [], to: VersionManifest(id: "pack", libraries: []))
    }
    static func exclusions(_ game: URL, includeWorlds: Bool) throws -> Set<String> {
        var result = excluded
        if FileManager.default.fileExists(atPath: game.path) {
            for file in try FileManager.default.contentsOfDirectory(at: game, includingPropertiesForKeys: [.isRegularFileKey]) {
                if ["log", "hprof", "jfr"].contains(file.pathExtension.lowercased()), try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true { result.insert(file.lastPathComponent) }
            }
        }
        if !includeWorlds { result.insert("saves") }
        let saves = game.appendingPathComponent("saves")
        if FileManager.default.fileExists(atPath: saves.path) {
            for world in try FileManager.default.contentsOfDirectory(at: saves, includingPropertiesForKeys: nil) { result.insert("saves/\(world.lastPathComponent)/session.lock") }
        }
        return result
    }
    static func lockWorlds(_ game: URL) throws -> [Int32] {
        let saves = game.appendingPathComponent("saves")
        guard FileManager.default.fileExists(atPath: saves.path) else { return [] }
        guard try saves.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw RuriError.message(Messages.CoreInstanceTransfer.symlinkSaves) }
        var locks: [Int32] = []
        do {
            for world in try FileManager.default.contentsOfDirectory(at: saves, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) {
                let info = try world.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard info.isSymbolicLink != true else { throw RuriError.message(Messages.CoreInstanceTransfer.symlinkInSaves) }
                if info.isDirectory == true, let lock = try WorldManager.readLock(world) { locks.append(lock) }
            }
            return locks
        } catch { locks.forEach { close($0) }; throw error }
    }
    static func iniEncode(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r") + "\""
    }
    static func iniDecode(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), !trimmed.hasPrefix(";"), !trimmed.hasPrefix("["), let equals = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[..<equals].trimmingCharacters(in: .whitespaces)
            var value = String(trimmed[trimmed.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 { value.removeFirst(); value.removeLast() }
            var decoded = ""; var escape = false
            for char in value {
                if escape { decoded += char == "n" ? "\n" : char == "r" ? "\r" : char == "t" ? "\t" : String(char); escape = false }
                else if char == "\\" { escape = true } else { decoded.append(char) }
            }
            if escape { decoded.append("\\") }
            result[key] = decoded
        }
        return result
    }
}
