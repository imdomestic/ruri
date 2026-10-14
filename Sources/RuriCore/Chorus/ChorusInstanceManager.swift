import Foundation
import RuriLocalization

public struct ChorusPreparedInstance: Sendable {
    public let instance: GameInstance
    public let java: JavaRuntime
    public let unmanagedMods: [String]
}

public struct ChorusInstanceManager: Sendable {
    public let paths: LauncherPaths
    public let client: ChorusClient
    public init(paths: LauncherPaths, client: ChorusClient) { self.paths = paths; self.client = client }
    public static func key(minecraft: String, loader: String, version: String) -> String { [minecraft, loader, version].joined(separator: "/") }

    public func installed(_ build: ChorusBuild) async throws -> ChorusPreparedInstance {
        let files = try ChorusModSync.clientFiles(build)
        guard let minecraft = build.minecraft, let version = build.loaderVersion,
              let id = try ChorusSettings.load(paths: paths).instances[Self.key(minecraft: minecraft, loader: build.loader, version: version)] else {
            throw RuriError.message(Messages.CLIInterface.instanceInstallRequiredBeforeLaunch)
        }
        let instance = try InstanceService(paths: paths).resolve(id: id)
        guard instance.installed else { throw RuriError.message(Messages.CLIInterface.instanceInstallRequiredBeforeLaunch) }
        let configured = paths.configured(with: try StateStore.load(paths))
        let manifest = try await GameInstaller(paths: configured).loadManifest(instance)
        let java = try await GameJavaRequirement(instance: instance, manifest: manifest).require(from: JavaDiscovery.scan(paths: configured, extra: [instance.javaPath].compactMap { $0 }))
        let mods = configured.game(id).appendingPathComponent("mods")
        let receipt = try JSONDecoder().decode(ChorusModSync.Receipt.self, from: Data(contentsOf: mods.appendingPathComponent(".chorus-managed.json")))
        guard receipt.buildID == build.id, receipt.files == files else { throw RuriError.message(Messages.Chorus.buildUnavailable) }
        for file in files { try ChorusModSync.verify(LauncherPaths.safePath(file.name, within: mods), file: file) }
        let managed = Set(files.map(\.name))
        let unmanaged = try FileManager.default.contentsOfDirectory(atPath: mods.path).filter { $0.hasSuffix(".jar") && !managed.contains($0) }.sorted()
        return .init(instance: instance, java: java, unmanagedMods: unmanaged)
    }

    public func prepare(_ build: ChorusBuild, progress: @escaping @Sendable (InstallProgress) async -> Void = { _ in }) async throws -> ChorusPreparedInstance {
        _ = try ChorusModSync.clientFiles(build)
        guard let minecraft = build.minecraft, let version = build.loaderVersion, let major = build.java,
              let loader = LoaderKind(rawValue: build.loader), loader != .vanilla else { throw RuriError.message(Messages.Chorus.invalidResponse) }
        let key = Self.key(minecraft: minecraft, loader: build.loader, version: version)
        var instanceID: UUID?
        try ChorusSettings.update(paths: paths) { settings in
            if let id = settings.instances[key], try StateStore.load(paths).instances.contains(where: { $0.id == id }) { instanceID = id }
            else {
                let name = ["Chorus", build.loader, minecraft].joined(separator: " · ")
                let instance = try InstanceService(paths: paths).create(name: name, game: minecraft, selections: [.init(loader: loader, version: version)], directoryID: GameDirectory.defaultID)
                instanceID = instance.id; settings.instances[key] = instance.id
            }
        }
        guard let instanceID else { throw RuriError.message(Messages.Chorus.invalidResponse) }
        var instance = try InstanceService(paths: paths).resolve(id: instanceID)
        guard instance.gameVersion == minecraft, instance.loader == loader, instance.loaderVersion == version else { throw RuriError.message(Messages.Chorus.invalidResponse) }
        let downloader = DownloadManager(cache: DownloadCache(paths: paths))
        if !instance.installed { instance = try await InstanceService(paths: paths).install(instanceID, downloader: downloader, progress: progress) }
        try StateStore.updateIfChanged(paths) { state in
            guard let index = state.instances.firstIndex(where: { $0.id == instanceID }) else { throw RuriError.message(Messages.Chorus.invalidResponse) }
            state.instances[index].javaMajor = major
            instance = state.instances[index]
        }
        let configured = paths.configured(with: try StateStore.load(paths))
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
        let result = try await ChorusModSync(paths: paths, client: client).synchronize(build, instance: instance)
        return ChorusPreparedInstance(instance: instance, java: java, unmanagedMods: result.unmanaged)
    }
}

public struct ChorusLaunchPlan: Codable, Sendable {
    public let instanceID: UUID
    public let roomID: String
    public let generation: Int
    public let buildID: String
    public let javaPath: String
    public let javaMajor: Int
    public let mainClass: String
    public let gameDirectory: String
    public let classpath: [String]
    public let destinationArguments: [String]
    public let authenticationRequired: Bool
    public let unmanagedMods: [String]

    public static func inspect(_ prepared: ChorusPreparedInstance, room: ChorusRoom, paths basePaths: LauncherPaths) async throws -> Self {
        let state = try StateStore.load(basePaths), paths = basePaths.configured(with: state)
        let instance = prepared.instance
        let manifest = try await GameInstaller(paths: paths).loadManifest(instance)
        try GameJavaRequirement(instance: instance, manifest: manifest).validate(prepared.java)
        guard let mainClass = manifest.mainClass, manifest.inheritsFrom == nil,
              GameQuickPlay.supports(instance: instance, manifest: manifest) else { throw RuriError.message(Messages.CoreLaunch.mainClassMissing) }
        let resources = try paths.resources(for: instance), architecture = GameInstaller.architecture(for: manifest)
        var classpath: [String] = []
        for library in manifest.libraries where GameInstaller.allowed(library, architecture: architecture) {
            if let artifact = try library.artifact() {
                let file = try resources.libraryFile(artifact, fallback: Library.mavenPath(library.name))
                guard FileManager.default.fileExists(atPath: file.path) else { throw RuriError.message(Messages.CoreLaunch.gameFilesMissing(file.lastPathComponent)) }
                if library.includeInClasspath != false { classpath.append(file.path) }
            }
        }
        let jar = try LauncherPaths.safePath("\(manifest.jar ?? instance.gameVersion)/\(manifest.jar ?? instance.gameVersion).jar", within: resources.versions)
        guard FileManager.default.fileExists(atPath: jar.path) else { throw RuriError.message(Messages.CoreLaunch.gameFilesMissing(jar.lastPathComponent)) }
        classpath.append(jar.path)
        let destination = try ServerAddress(room.host + ":" + String(room.port))
        let arguments = GameQuickPlay.applying(.server(destination), arguments: [], logging: paths.instance(instance.id).appendingPathComponent("quick-play/chorus.json"), gameDirectory: paths.game(instance.id))
        return Self(instanceID: instance.id, roomID: room.id, generation: room.generation, buildID: room.buildId,
                    javaPath: prepared.java.path, javaMajor: prepared.java.major, mainClass: mainClass,
                    gameDirectory: paths.game(instance.id).path, classpath: classpath, destinationArguments: arguments,
                    authenticationRequired: state.accounts.isEmpty, unmanagedMods: prepared.unmanagedMods)
    }
}
