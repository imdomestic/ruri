import Foundation
import RuriLocalization

public struct VexPreparedInstance: Sendable {
    public let instance: GameInstance
    public let java: JavaRuntime
    public let unmanagedMods: [String]
}

public struct VexInstanceManager: Sendable {
    public let paths: LauncherPaths
    public let client: VexClient
    private let synchronizer: any VexModSynchronizing
    public init(paths: LauncherPaths, client: VexClient, synchronizer: (any VexModSynchronizing)? = nil) {
        self.paths = paths
        self.client = client
        self.synchronizer = synchronizer ?? VexModSync(paths: paths, client: client)
    }
    public static func key(server: URL, project: String, minecraft: String, loader: String, version: String) -> String {
        [server.absoluteString, project, minecraft, loader, version].joined(separator: "/")
    }
    private func instanceKey(_ build: VexBuild) throws -> String {
        guard build.project == client.project, let minecraft = build.minecraft, let version = build.loaderVersion else {
            throw RuriError.message(Messages.Vex.invalidResponse)
        }
        return Self.key(server: client.baseURL, project: build.project, minecraft: minecraft, loader: build.loader, version: version)
    }
    public func installed(_ build: VexBuild) async throws -> VexPreparedInstance {
        let files = try VexModSync.clientFiles(build)
        guard let id = try VexSettings.load(paths: paths).instances[instanceKey(build)] else {
            throw RuriError.message(Messages.CLIInterface.instanceInstallRequiredBeforeLaunch)
        }
        let instance = try InstanceService(paths: paths).resolve(id: id)
        guard instance.installed else { throw RuriError.message(Messages.CLIInterface.instanceInstallRequiredBeforeLaunch) }
        guard instance.runDirectory == .isolated else { throw RuriError.message(Messages.Vex.invalidResponse) }
        let configured = paths.configured(with: try StateStore.load(paths))
        let marker = try JSONDecoder().decode(Marker.self, from: Data(contentsOf: configured.instance(id).appendingPathComponent("vex-instance.json")))
        guard marker.key == (try instanceKey(build)) else { throw RuriError.message(Messages.Vex.invalidResponse) }
        let manifest = try await GameInstaller(paths: configured).loadManifest(instance)
        let java = try await GameJavaRequirement(instance: instance, manifest: manifest).require(from: JavaDiscovery.scan(paths: configured, extra: [instance.javaPath].compactMap { $0 }))
        let mods = configured.game(id).appendingPathComponent("mods")
        let receipt = try JSONDecoder().decode(VexModSync.Receipt.self, from: Data(contentsOf: mods.appendingPathComponent(".vex-managed.json")))
        guard receipt.project == build.project, receipt.buildID == build.id, receipt.files == files else { throw RuriError.message(Messages.Vex.buildUnavailable) }
        for file in files { try VexModSync.verify(LauncherPaths.safePath(file.name, within: mods), file: file) }
        let managed = Set(files.map(\.name))
        let unmanaged = try FileManager.default.contentsOfDirectory(atPath: mods.path).filter { $0.hasSuffix(".jar") && !managed.contains($0) }.sorted()
        return .init(instance: instance, java: java, unmanagedMods: unmanaged)
    }
    public struct Marker: Codable, Sendable { public let key: String }
    public func prepare(_ build: VexBuild, progress: @escaping @Sendable (InstallProgress) async -> Void = { _ in }) async throws -> VexPreparedInstance {
        _ = try VexModSync.clientFiles(build)
        guard let minecraft = build.minecraft, let version = build.loaderVersion, let major = build.java,
              let loader = LoaderKind(rawValue: build.loader), loader != .vanilla else { throw RuriError.message(Messages.Vex.invalidResponse) }
        let key = try instanceKey(build)
        try paths.prepare()
        let preparation = try OperationLease.acquire(directory: paths.root, name: ".vex-prepare.lock")
        defer { withExtendedLifetime(preparation) {} }
        let settings = try VexSettings.load(paths: paths), state = try StateStore.load(paths)
        let instanceID: UUID
        if let id = settings.instances[key], state.instances.contains(where: { $0.id == id }) { instanceID = id }
        else {
            let name = ["Vex", build.project, build.loader, minecraft].joined(separator: " · ")
            let instance = try InstanceService(paths: paths).create(name: name, game: minecraft, selections: [.init(loader: loader, version: version)], directoryID: GameDirectory.defaultID)
            instanceID = instance.id
            try StateStore.updateIfChanged(paths) { state in
                guard let index = state.instances.firstIndex(where: { $0.id == instanceID }) else { throw RuriError.message(Messages.Vex.invalidResponse) }
                state.instances[index].runDirectory = .isolated
            }
            try VexSettings.update(paths: paths) { $0.instances[key] = instance.id }
        }
        var instance = try InstanceService(paths: paths).resolve(id: instanceID)
        guard instance.gameVersion == minecraft, instance.loader == loader, instance.loaderVersion == version,
              instance.runDirectory == .isolated else { throw RuriError.message(Messages.Vex.invalidResponse) }
        let downloader = DownloadManager(cache: DownloadCache(paths: paths))
        if !instance.installed { instance = try await InstanceService(paths: paths).install(instanceID, downloader: downloader, progress: progress) }
        try StateStore.updateIfChanged(paths) { state in
            guard let index = state.instances.firstIndex(where: { $0.id == instanceID }) else { throw RuriError.message(Messages.Vex.invalidResponse) }
            state.instances[index].javaMajor = major
            instance = state.instances[index]
        }
        let configured = paths.configured(with: try StateStore.load(paths))
        try FileManager.default.createDirectory(at: configured.instance(instanceID), withIntermediateDirectories: true)
        try JSONEncoder().encode(Marker(key: key)).write(to: configured.instance(instanceID).appendingPathComponent("vex-instance.json"), options: .atomic)
        let manifest = try await GameInstaller(paths: configured, downloader: downloader).loadManifest(instance)
        let requirement = try GameJavaRequirement(instance: instance, manifest: manifest)
        guard manifest.requiredJava <= major else { throw RuriError.message(Messages.CoreLaunch.javaVersionIncompatible) }
        let runtimes = await JavaDiscovery.scan(paths: configured, extra: [instance.javaPath].compactMap { $0 })
        let java: JavaRuntime
        if let installed = try requirement.select(from: runtimes) { java = installed }
        else {
            let installer = JavaInstaller(paths: configured)
            let available = try await installer.available()
            guard let remote = available.first(where: { $0.major == major && $0.architecture == requirement.architecture }) else {
                throw RuriError.message(Messages.CoreGameJavaRequirement.missingCompatibleJava(String(major), requirement.architecture))
            }
            java = try await installer.install(remote, downloader: downloader, progress: progress)
            try requirement.validate(java)
        }
        let result = try await synchronizer.synchronize(build, instance: instance)
        return VexPreparedInstance(instance: instance, java: java, unmanagedMods: result.unmanaged)
    }
}

public struct VexLaunchPlan: Codable, Sendable {
    public let project: String
    public let instanceID: UUID
    public let roomID: String
    public let generation: Int
    public let buildID: String
    public let javaPath: String
    public let javaMajor: Int
    public let mainClass: String
    public let gameDirectory: String
    public let destinationArguments: [String]
    public let authenticationRequired: Bool
    public let unmanagedMods: [String]

    public static func inspect(_ prepared: VexPreparedInstance, room: VexRoom, paths basePaths: LauncherPaths) async throws -> Self {
        let state = try StateStore.load(basePaths), paths = basePaths.configured(with: state)
        let instance = prepared.instance
        let manifest = try await GameInstaller(paths: paths).loadManifest(instance)
        try GameJavaRequirement(instance: instance, manifest: manifest).validate(prepared.java)
        guard let mainClass = manifest.mainClass, manifest.inheritsFrom == nil,
              GameQuickPlay.supports(instance: instance, manifest: manifest) else { throw RuriError.message(Messages.CoreLaunch.mainClassMissing) }
        let destination = try ServerAddress(room.host + ":" + String(room.port))
        let arguments = GameQuickPlay.applying(.server(destination), arguments: [], logging: paths.instance(instance.id).appendingPathComponent("quick-play/vex.json"), gameDirectory: paths.game(instance.id))
        return Self(project: room.project, instanceID: instance.id, roomID: room.id, generation: room.generation, buildID: room.buildId,
                    javaPath: prepared.java.path, javaMajor: prepared.java.major, mainClass: mainClass,
                    gameDirectory: paths.game(instance.id).path, destinationArguments: arguments,
                    authenticationRequired: state.accounts.isEmpty, unmanagedMods: prepared.unmanagedMods)
    }
}
