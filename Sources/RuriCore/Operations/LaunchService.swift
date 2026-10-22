import RuriLocalization
import Foundation

/// Shared orchestration for GUI and CLI. Presentation and interactive Java
/// selection are callbacks; ownership transfers to the existing game monitor.
@MainActor public struct LaunchService {
    public let paths: LauncherPaths
    private let downloader: DownloadManager
    private let accounts: AccountService
    public init(paths: LauncherPaths, downloader: DownloadManager = DownloadManager(), accounts: AccountService? = nil) {
        self.paths = paths; self.downloader = downloader; self.accounts = accounts ?? AccountService(paths: paths)
    }
    public func preflight(instanceID: UUID, accountID: UUID? = nil, worldFolder: String? = nil, destination: LaunchDestination = .normal) async throws -> OperationValue {
        let state = try StateStore.load(paths), paths = paths.configured(with: state), stored = try InstanceService(paths: paths).resolve(id: instanceID)
        guard stored.installed else { throw OperationFailure("INSTALLATION_REQUIRED", Messages.CLIInterface.instanceInstallRequiredBeforeLaunch.localized, nextActions: [.init(["instance", "install", instanceID.uuidString])]) }
        let instance = try stored.launchSnapshot(defaults: state.settings, workload: MemoryWorkload.scan(paths: paths, instance: stored))
        let manifest = try await GameInstaller(paths: paths, downloader: downloader).loadManifest(instance)
        let requirement = try GameJavaRequirement(instance: instance, manifest: manifest)
        let java = try await resolveJava(instance: instance, requirement: requirement, paths: paths)
        let selectedAccount = accountID ?? state.activeAccountID
        guard let selectedAccount, let account = state.accounts.first(where: { $0.id == selectedAccount }) else { throw OperationFailure("ACCOUNT_REQUIRED", Messages.CLIInterface.launchAccountRequired.localized, nextActions: [.init(["account", "list", "--json"])]) }
        guard worldFolder == nil || destination == .normal else { throw RuriError.message(Messages.Servers.destinationConflict) }
        let target = worldFolder.map { LaunchDestination.world(folder: $0) } ?? destination
        let selectedFolder: String? = { if case .world(let folder) = target { return folder }; return nil }()
        _ = try selectedFolder.map { folder in
            try WorldQuickPlay.requireSupport(instance: instance, manifest: manifest)
            return try WorldQuickPlay.selection(folder: folder, instanceID: instance.id, paths: paths)
        }
        let plan = try await LaunchBuilder.build(instance: instance, manifest: manifest, java: java, account: account, paths: paths, destination: target, capabilities: JavaCapabilities.load(for: java, cache: paths.cache))
        return .object(["instanceID": .string(instanceID.uuidString), "accountID": .string(account.id.uuidString), "accountKind": .string(account.kind.rawValue),
            "javaPath": .string(java.path), "javaMajor": .integer(java.major), "gameDirectory": .string(plan.directory.path),
            "command": .string(plan.redactedCommand), "jvmTuning": try plan.tuning.map { try .encode($0) } ?? .null, "authenticationChecked": .bool(account.kind == .offline), "environmentNames": .array((plan.customEnvironmentNames ?? []).map(OperationValue.string))])
    }
    public func start(instanceID: UUID, accountID: UUID? = nil, worldFolder: String? = nil, destination: LaunchDestination = .normal, recorder provided: GameSessionRecorder? = nil,
                      javaResolver: (@MainActor (GameInstance, VersionManifest) async throws -> JavaRuntime)? = nil,
                      progress: @Sendable @escaping (InstallProgress) async -> Void = { _ in },
                      updated: @MainActor (GameSession) -> Void = { _ in }) async throws -> GameSession {
        var state = try StateStore.load(paths)
        let initial = try InstanceService(paths: paths).resolve(id: instanceID)
        guard let selectedID = accountID ?? state.activeAccountID, let selected = state.accounts.first(where: { $0.id == selectedID }) else {
            throw OperationFailure("ACCOUNT_REQUIRED", Messages.CLIInterface.launchAccountRequired.localized, nextActions: [.init(["account", "list", "--json"])])
        }
        let configured = paths.configured(with: state)
        let recorder = try provided ?? GameSessionRecorder(paths: configured, instance: initial, accountMode: selected.kind.rawValue)
        func advance(_ stage: GameSession.Stage) throws { try recorder.transition(stage); updated(recorder.record) }
        do {
            var stored = initial
            if !stored.installed {
                try advance(.installation)
                let installed = try await GameInstaller(paths: configured, downloader: downloader).install(stored, concurrency: state.settings.concurrentDownloads, progress: progress)
                stored = try InstanceService(paths: configured).recordInstallation(installed, requested: stored)
                state = try StateStore.load(paths)
            }
            let paths = self.paths.configured(with: state)
            let instance = try stored.launchSnapshot(defaults: state.settings, workload: MemoryWorkload.scan(paths: paths, instance: stored))
            try Task.checkCancellation()
            try advance(.recovery)
            try await ContentManager(paths: paths, instanceID: instanceID).recover()
            try await WorldManager(paths: paths, instanceID: instanceID).recover()
            try advance(.account)
            let authenticated = try await accounts.authenticate(selectedID)
            defer { withExtendedLifetime(authenticated) {} }
            recorder.addSecrets(authenticated.secrets)
            let account = authenticated.account
            var token = authenticated.accessToken, externalAuth: ExternalAuthLaunch?, offlineSkin: OfflineSkinLaunch?
            if account.kind == .external, let server = account.externalLogin?.server {
                async let metadata = ExternalAuthentication().metadata(for: server)
                async let jar = AuthlibInjector().prepare(paths: paths)
                externalAuth = try await ExternalAuthLaunch(jar: jar, metadata: metadata, userProperties: authenticated.externalCredentials?.user?.propertiesJSON ?? "{}")
            }
            if account.kind == .offline {
                let skin = try SkinLibrary(paths: paths).preview(for: account.id), cape = try SkinLibrary(paths: paths).cape(for: account.id)
                if skin != nil || cape != nil {
                    offlineSkin = try await OfflineSkinLaunch(account: account, skin: skin, cape: cape, injector: AuthlibInjector().prepare(paths: paths))
                    token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
                }
            }
            try advance(.manifest)
            let installer = GameInstaller(paths: paths, downloader: downloader), manifest = try await installer.loadManifest(instance)
            guard worldFolder == nil || destination == .normal else { throw RuriError.message(Messages.Servers.destinationConflict) }
            let target = worldFolder.map { LaunchDestination.world(folder: $0) } ?? destination
            let selectedFolder: String? = { if case .world(let folder) = target { return folder }; return nil }()
            let world = try selectedFolder.map { folder in
                try WorldQuickPlay.requireSupport(instance: instance, manifest: manifest)
                return try WorldQuickPlay.selection(folder: folder, instanceID: instanceID, paths: paths)
            }
            try advance(.java)
            let java: JavaRuntime
            if let javaResolver { java = try await javaResolver(instance, manifest) }
            else { java = try await resolveJava(instance: instance, requirement: GameJavaRequirement(instance: instance, manifest: manifest), paths: paths) }
            try recorder.setJava(java.label + " · " + java.version)
            try advance(.arguments)
            try await installer.prepareRunDirectory(instance, manifest: manifest)
            try ExperimentalFeatures.beforeLaunch(paths: paths, instanceID: instanceID, settings: state.settings.experimental)
            let capabilities = await JavaCapabilities.load(for: java, cache: paths.cache)
            let plan = try LaunchBuilder.build(instance: instance, manifest: manifest, java: java, account: account, accessToken: token, paths: paths, destination: target, externalAuth: externalAuth, offlineSkin: offlineSkin, capabilities: capabilities)
            recorder.addSecrets(plan.environmentRedactions + [token])
            try recorder.append(plan.redactedCommand)
            try recorder.setDestination(target)
            if let world { try recorder.setWorld(.init(folder: world.folder, name: world.name, lastPlayed: world.lastPlayed, source: .quickPlay)) }
            try Task.checkCancellation()
            try advance(.starting)
            try await GameMonitorClient.start(plan: plan, recorder: recorder, paths: paths, secrets: authenticated.secrets + [token])
            // The instance launched last is the one the home page offers to
            // continue, as long as it belongs to the folder being shown.
            _ = try? StateStore.updateIfChanged(self.paths) { state in
                let directory = state.instances.first { $0.id == instanceID }.map { $0.directoryID ?? GameDirectory.defaultID }
                if directory != nil, directory == (state.selectedDirectoryID ?? GameDirectory.defaultID) { state.selectedInstanceID = instanceID }
            }
            updated(recorder.record)
            return recorder.record
        } catch {
            if !recorder.hasHandedOff { try? recorder.fail(error, cancelled: error is CancellationError || Task.isCancelled) }
            updated(recorder.record)
            if error is CancellationError { throw error }
            let failure = error as? OperationFailure
            throw OperationFailure(failure?.code ?? "LAUNCH_FAILED", recorder.redacted(error.localizedDescription), retryable: failure?.retryable ?? false,
                nextActions: failure?.nextActions ?? [.init(["session", "diagnose", instanceID.uuidString, recorder.record.id.uuidString])],
                details: .object(["instanceID": .string(instanceID.uuidString), "sessionID": .string(recorder.record.id.uuidString)]))
        }
    }
    private func resolveJava(instance: GameInstance, requirement: GameJavaRequirement, paths: LauncherPaths) async throws -> JavaRuntime {
        let runtimes = await JavaDiscovery.scan(paths: paths, extra: [instance.javaPath].compactMap { $0 })
        do { return try requirement.require(from: runtimes) }
        catch { throw OperationFailure("JAVA_REQUIRED", error.localizedDescription, nextActions: [.init(["java", "available", "--major", String(requirement.recommendedMajor), "--architecture", requirement.architecture, "--json"])],
            details: .object(["minimumMajor": .integer(requirement.minimumMajor), "recommendedMajor": .integer(requirement.recommendedMajor), "architecture": .string(requirement.architecture)])) }
    }
}
