import Foundation
import RuriCore
import RuriLocalization

public struct VexPreparedInstance: Sendable {
    public let server: String
    public let instance: GameInstance
    public let java: JavaRuntime
    public let unmanagedMods: [String]
}

public struct VexInstanceManager: Sendable {
    public let paths: LauncherPaths
    public let client: VexClient
    public init(paths: LauncherPaths, client: VexClient) {
        self.paths = paths
        self.client = client
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
        let files = try VexMRPack.clientFiles(build)
        guard let id = try VexSettings.load(paths: paths).instances[instanceKey(build)] else {
            throw RuriError.message(Messages.CLIInterface.instanceInstallRequiredBeforeLaunch)
        }
        let capabilities = ExperimentalInstanceCapabilities(paths: paths)
        let instance = try capabilities.instance(id: id)
        guard instance.installed else { throw RuriError.message(Messages.CLIInterface.instanceInstallRequiredBeforeLaunch) }
        guard instance.runDirectory == .isolated else { throw RuriError.message(Messages.Vex.invalidResponse) }
        let configured = try capabilities.context().paths
        let marker = try JSONDecoder().decode(Marker.self, from: Data(contentsOf: configured.instance(id).appendingPathComponent("vex-instance.json")))
        guard marker.key == (try instanceKey(build)), marker.server == client.baseURL.absoluteString,
              marker.project == build.project, marker.buildID == build.id,
              marker.clientFingerprint == (try VexMRPack.fingerprint(build)) else { throw RuriError.message(Messages.Vex.invalidResponse) }
        let manifest = try await GameInstaller(paths: configured).loadManifest(instance)
        let java = try await GameJavaRequirement(instance: instance, manifest: manifest).require(from: JavaDiscovery.scan(paths: configured, extra: [instance.javaPath].compactMap { $0 }))
        let mods = configured.game(id).appendingPathComponent("mods")
        guard let pack = try ModpackRegistry.load(paths: configured, instanceID: id) else {
            throw RuriError.message(Messages.Vex.buildUnavailable)
        }
        let managedPaths = try ExperimentalInstanceCapabilities.verifyModContent(pack, game: configured.game(id), expected: files.map(VexMRPack.managed))
        let managed = Set(managedPaths.map { String($0.dropFirst("mods/".count)) })
        let unmanaged = try FileManager.default.contentsOfDirectory(atPath: mods.path).filter { $0.hasSuffix(".jar") && !managed.contains($0) }.sorted()
        return .init(server: client.baseURL.absoluteString, instance: instance, java: java, unmanagedMods: unmanaged)
    }
    public struct Marker: Codable, Sendable {
        public let key: String
        public let server: String
        public let project: String
        public let room: String
        public var buildID: String? = nil
        public var clientFingerprint: String? = nil
    }
    public func prepare(_ build: VexBuild, roomID: String, generation: Int, progress: @escaping @Sendable (InstallProgress) async -> Void = { _ in }) async throws -> VexPreparedInstance {
        _ = try VexMRPack.clientFiles(build)
        let fingerprint = try VexMRPack.fingerprint(build)
        guard let minecraft = build.minecraft, let version = build.loaderVersion, let major = build.java,
              let loader = LoaderKind(rawValue: build.loader), loader != .vanilla else { throw RuriError.message(Messages.Vex.invalidResponse) }
        let key = try instanceKey(build)
        try paths.prepare()
        let preparation = try OperationLease.acquire(directory: paths.root, name: ".vex-prepare.lock")
        defer { withExtendedLifetime(preparation) {} }
        let settings = try VexSettings.load(paths: paths)
        let capabilities = ExperimentalInstanceCapabilities(paths: paths)
        let context = try capabilities.context()
        if let id = settings.instances[key] {
            let current = context.paths
            let instance = try capabilities.instance(id: id)
            var marker = try ExperimentalInstanceCapabilities.readMetadata(current.instance(id).appendingPathComponent("vex-instance.json"), limit: 1_048_576) as Marker
            guard marker.key == key, marker.server == client.baseURL.absoluteString, marker.project == build.project,
                  instance.gameVersion == minecraft, instance.loader == loader, instance.loaderVersion == version,
                  instance.runDirectory == .isolated else { throw RuriError.message(Messages.Vex.invalidResponse) }
            if marker.clientFingerprint == fingerprint {
                let lease = try GameRunLease.acquire(paths: current, instanceID: id)
                defer { withExtendedLifetime(lease) {} }
                guard let pack = try ModpackRegistry.load(paths: current, instanceID: id) else { throw RuriError.message(Messages.Vex.buildUnavailable) }
                _ = try ExperimentalInstanceCapabilities.verifyModContent(pack, game: current.game(id), expected: VexMRPack.clientFiles(build).map(VexMRPack.managed))
                marker.buildID = build.id
                try JSONEncoder().encode(marker).write(to: current.instance(id).appendingPathComponent("vex-instance.json"), options: .atomic)
                return try await installed(build)
            }
        }
        let archive = paths.cache.appendingPathComponent("vex-" + UUID().uuidString + ".mrpack")
        defer { try? FileManager.default.removeItem(at: archive) }
        guard generation > 0 else { throw RuriError.message(Messages.Vex.invalidResponse) }
        try await client.data(client.projectPath("/rooms/" + VexClient.component(roomID) + "/pack.mrpack"),
                              query: [.init(name: "buildId", value: build.id), .init(name: "generation", value: String(generation))])
            .write(to: archive, options: .atomic)
        let downloader = DownloadManager(cache: DownloadCache(paths: paths))
        let prepared = try await capabilities.prepareImport(archive, excludingFiles: ["servers.dat"])
        let instanceID: UUID
        do {
            try VexMRPack.validate(prepared, build: build, roomID: roomID, generation: generation)
            var existing: GameInstance?
            if let id = settings.instances[key] {
                let current = context.paths
                let instance = try capabilities.instance(id: id)
                let marker = try ExperimentalInstanceCapabilities.readMetadata(current.instance(id).appendingPathComponent("vex-instance.json"), limit: 1_048_576) as Marker
                guard marker.key == key, marker.server == client.baseURL.absoluteString, marker.project == build.project,
                      instance.gameVersion == minecraft, instance.loader == loader, instance.loaderVersion == version,
                      instance.runDirectory == .isolated else { throw RuriError.message(Messages.Vex.invalidResponse) }
                try VexMRPack.adoptLegacy(instance: instance, paths: current, project: build.project)
                existing = instance
            }
            let name = ["Vex", build.project, build.loader, minecraft].joined(separator: " · ")
            let imported = try await ExperimentalInstanceCapabilities(paths: context.paths)
                .install(prepared, existing: existing, name: name, concurrency: context.concurrentDownloads, progress: progress)
            instanceID = imported.id
            if existing == nil { try VexSettings.update(paths: paths) { $0.instances[key] = imported.id } }
            await capabilities.discardImport(prepared)
        } catch {
            await capabilities.discardImport(prepared)
            throw error
        }
        let instance = try capabilities.setJavaMajor(major, instanceID: instanceID)
        let configured = try capabilities.context().paths
        try FileManager.default.createDirectory(at: configured.instance(instanceID), withIntermediateDirectories: true)
        try JSONEncoder().encode(Marker(key: key, server: client.baseURL.absoluteString, project: build.project, room: roomID,
                                       buildID: build.id, clientFingerprint: fingerprint))
            .write(to: configured.instance(instanceID).appendingPathComponent("vex-instance.json"), options: .atomic)
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
        for file in try VexMRPack.clientFiles(build) {
            try VexMRPack.verify(LauncherPaths.safePath(file.name, within: configured.game(instanceID).appendingPathComponent("mods")), file: file)
        }
        return try await installed(build)
    }
}

public struct VexLaunchPlan: Codable, Sendable {
    public let server: String
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
        let context = try ExperimentalInstanceCapabilities(paths: basePaths).context(), paths = context.paths
        let instance = prepared.instance
        let manifest = try await GameInstaller(paths: paths).loadManifest(instance)
        try GameJavaRequirement(instance: instance, manifest: manifest).validate(prepared.java)
        guard let mainClass = manifest.mainClass, manifest.inheritsFrom == nil else { throw RuriError.message(Messages.CoreLaunch.mainClassMissing) }
        let destination = try ServerAddress(room.host + ":" + String(room.port))
        let arguments = try ExperimentalInstanceCapabilities(paths: paths).quickPlayArguments(instance: instance, manifest: manifest, address: destination)
        return Self(server: prepared.server, project: room.project, instanceID: instance.id, roomID: room.id, generation: room.generation, buildID: room.buildId,
                    javaPath: prepared.java.path, javaMajor: prepared.java.major, mainClass: mainClass,
                    gameDirectory: paths.game(instance.id).path, destinationArguments: arguments,
                    authenticationRequired: !context.accountAvailable, unmanagedMods: prepared.unmanagedMods)
    }
}
