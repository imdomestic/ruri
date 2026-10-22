import RuriLocalization
import SwiftUI
import Observation
import AppKit
import RuriCore
import RuriExtensionKit

@MainActor @Observable final class AppModel {
    var state: PersistentState
    let basePaths: LauncherPaths
    let downloader = DownloadManager()
    var paths: LauncherPaths { basePaths.configured(with: state) }
    var installer: GameInstaller { GameInstaller(paths: paths, downloader: downloader) }
    let discovery = CatalogBrowser()
    let catalogRepository = CatalogRepository()
    var page = Page.home
    var catalog: VersionCatalog?
    var catalogLoading = false
    var catalogError: String?
    var runtimes: [JavaRuntime] = []
    /// The Java each instance would launch with and its flags, for the heap
    /// and tuning summaries; refreshed by the pages that show them.
    var runtimeContexts: [UUID: JVMRuntimeContext] = [:]
    var javaEntries: [JavaRuntimeEntry] = []
    var scanningJava = false
    var javaScanAgain = false
    var journal = LauncherJournal()
    var journalStorageError: String?
    var selectedLogID: UUID?
    var logNavigationID = UUID()
    var journalPersistenceEnabled = true
    @ObservationIgnored var journalWriteTask: Task<Void, Never>?
    @ObservationIgnored var persistedJournal = LauncherJournal()
    @ObservationIgnored var journalCheckpoint = Date.distantPast
    var operation: Task<Void, Never>?
    var activeSessions: [UUID: GameSession] = [:]
    var runningID: UUID? { selected.flatMap { activeSessions[$0.id] }?.instanceID ?? activeSessions.values.max(by: { $0.createdAt < $1.createdAt })?.instanceID }
    var logs: [String] = []
    var showLogs = false
    var lastGameExit: GameExit?
    var crashReports: [GameCrashReport] = []
    var sessions: [GameSession] = []
    var logsSessionID: UUID?
    var requestedLogSessionID: UUID?
    var inspectedSession: GameSession?
    var historyInstanceID: UUID?
    var historyRevision = UUID()
    var historyStorageError: String?
    @ObservationIgnored var sessionSubscriptions: [UUID: Task<Void, Never>] = [:]
    var restoringGames = true
    var isQuitting = false
    var pendingOpenURLs: [URL] = []
    @ObservationIgnored var openMainWindow: (@MainActor () -> Void)?
    @ObservationIgnored var monitorTask: Task<Void, Never>?
    @ObservationIgnored var restoredPlaytimeSessions: [UUID: Set<UUID>] = [:]
    @ObservationIgnored var handledExits: Set<UUID> = []
    @ObservationIgnored var launchPresentations: [UUID: LaunchPresentation] = [:]
    @ObservationIgnored var automaticallyHiddenSessions: Set<UUID> = []
    @ObservationIgnored var bootTask: Task<Void, Never>?
    @ObservationIgnored lazy var experimentalHost = makeExperimentalHost()
    var showCLISetup = false
    var showCreate = false
    var showDirectories = false
    var showAddDirectory = false
    var detectedMinecraftLocations: [URL]?
    var discoveringMinecraftLocations = false
    var minecraftFolderDiscoveryError: String?
    @ObservationIgnored var minecraftFolderDiscoveryDate: Date?
    @ObservationIgnored var minecraftFolderDiscoveryTask: Task<[URL], Error>?
    var directoryErrors: [UUID: String] = [:]
    var customDirectoryErrors: [UUID: String] = [:]
    var pendingDirectoryCopyIDs: Set<UUID> = []
    var pendingInstanceCopyIDs: Set<UUID> = []
    var pendingInstanceMoveIDs: Set<UUID> = []
    var failedSessionReadIDs: Set<UUID> = []
    var showAccount = false
    var accountSkins: [UUID: SavedPlayerSkin] = [:]
    var accountCapes: [UUID: PlayerTextureImage] = [:]
    @ObservationIgnored let accountOperations = AccountOperationGate()
    @ObservationIgnored let accountAppearanceCache: AccountAppearanceCache
    var loadedAccountPreviews: Set<UUID> = []
    var editingInstance: GameInstance?
    var contentPresentation: InstanceContentPresentation?
    var worldInstance: GameInstance?
    var serverInstance: GameInstance?
    /// A server the server center should reveal and select when it next appears.
    var serverFocus: String?
    /// An instance the library should reveal and select when it next appears.
    var libraryFocus: UUID?
    var schematicInstance: GameInstance?
    var curseForgeConfigured = CurseForgeKeyStore.isConfigured()
    var importingInstance: PreparedInstanceImport?
    var exportingInstance: GameInstance?
    var copyingInstance: GameInstance?
    var movingInstance: GameInstance?
    var error: String? {
        didSet {
            if let error, !journal.entries.contains(where: { $0.id == LauncherActivityContext.id && $0.status == .failed }) {
                report(error, level: .error)
            }
        }
    }
    private(set) var readOnly = false
    private var retryPersistence = false
    private(set) var persistedState: PersistentState?
    var sessionRecorder: GameSessionRecorder?
    var recordingErrorShown = false
    var selected: GameInstance? { directoryInstances.first(where: { $0.id == state.selectedInstanceID }) ?? directoryInstances.first }
    var activeAccount: Account? { state.accounts.first { $0.id == state.activeAccountID } }
    var busy: Bool { operation != nil || restoringGames || isQuitting }
    var isPresentingSheet: Bool {
        showCLISetup || showCreate || showDirectories || showAddDirectory || showAccount || showLogs
            || editingInstance != nil || contentPresentation != nil || worldInstance != nil || serverInstance != nil || schematicInstance != nil
            || importingInstance != nil || exportingInstance != nil || copyingInstance != nil || movingInstance != nil
    }
    var activeActivity: LauncherLogEntry? { journal.entries.first { $0.status == .running } }
    var selectedDirectoryID: UUID { state.selectedDirectoryID ?? GameDirectory.defaultID }
    var selectedDirectoryName: String { state.gameDirectories?.first(where: { $0.id == selectedDirectoryID })?.name ?? Messages.AppAppModel.defaultInstanceDirectory.localized }
    var directoryInstances: [GameInstance] { state.instances.filter { ($0.directoryID ?? GameDirectory.defaultID) == selectedDirectoryID } }

    init() {
        let root = ProcessInfo.processInfo.environment["RURI_DATA_DIR"].map { URL(fileURLWithPath: $0) }
        basePaths = LauncherPaths(root: root)
        accountAppearanceCache = AccountAppearanceCache(paths: basePaths)
        do {
            state = try StateStore.load(basePaths)
            persistedState = state
            try basePaths.configured(with: state).validateDirectoryConfiguration()
        }
        catch { state = PersistentState(); self.error = Messages.AppAppModel.unreadableData(error.localizedDescription).localized; readOnly = true }
        do {
            journal = try LauncherJournalStore.load(paths: basePaths)
            persistedJournal = journal
            journal.recoverInterrupted()
        } catch {
            journalPersistenceEnabled = false
            journalStorageError = Messages.LauncherLog.historyUnavailable.localized
            journal.record(Messages.LauncherLog.historyReadError(error.localizedDescription), level: .warning)
        }
        if let error { journal.record(.verbatim(error), level: .error) }
        persistJournal()
    }
    func save() {
        guard !readOnly, state != persistedState else { return }
        do { acceptState(try StateStore.save(state, to: paths, basedOn: persistedState)) }
        catch {
            readOnly = true
            retryPersistence = (error as? OperationFailure).map { ["STATE_CONFLICT", "RESOURCE_BUSY"].contains($0.code) } ?? false
            self.error = Messages.AppAppModel.savePaused(error.localizedDescription).localized
        }
    }
    func boot() async {
        if let bootTask { await bootTask.value; return }
        let work = Task { await initializeApplication() }
        bootTask = work
        await work.value
    }
    private func initializeApplication() async {
        Task.detached(priority: .utility) { _ = ModNameIndex.shared }
        if !readOnly {
            let maintenance = CacheMaintenance(paths: basePaths)
            Task.detached(priority: .background) { maintenance.removeLeftovers() }
        }
        if !readOnly {
            do {
                let basePaths = basePaths
                _ = try await Task.detached(priority: .utility) { try GameDirectoryStore.resolveBookmarks(paths: basePaths) }.value
                state = try await CustomRunDirectoryRelocation(paths: basePaths).resolveBookmarks(); persistedState = state
            } catch { self.error = Messages.AppAppModel.directoryRecoveryFailed(error.localizedDescription).localized }
        }
        if !readOnly {
            let base = basePaths, id = selectedDirectoryID
            do { acceptState(try await Task.detached(priority: .utility) { try MinecraftFolderStore.refresh(id, paths: base) }.value) }
            catch { directoryErrors[id] = error.localizedDescription }
        }
        await refreshDirectoryAvailability()
        await refreshSessions()
        await pollGames()
        restoringGames = false
        startGameObservation()
        await applyNetworkSettings()
        if !readOnly {
            for account in state.accounts where account.kind != .offline {
                loadAccountPreview(account)
                refreshAccountPreview(account, forceRefresh: false)
            }
        }
        async let versions: () = refreshCatalog()
        async let java: () = scanJava()
        _ = await (versions, java)
    }
    func perform(_ title: String, presentErrors: Bool = true, instanceID: UUID? = nil, recording: TaskRecording = .standard, work: @escaping @MainActor @Sendable (UUID) async throws -> Void) {
        perform(.verbatim(title), presentErrors: presentErrors, instanceID: instanceID, recording: recording, work: work)
    }
    func perform(_ title: LocalizedMessage, presentErrors: Bool = true, instanceID: UUID? = nil, recording: TaskRecording = .standard, work: @escaping @MainActor @Sendable (UUID) async throws -> Void) {
        guard !busy, !readOnly else { return }
        let id = journal.begin(title)
        persistJournal()
        operation = Task {
            await LauncherActivityContext.$id.withValue(id) {
                var lease: GameRunLease?
                defer { withExtendedLifetime(lease) {} }
                do {
                    if let instanceID { lease = try GameRunLease.acquire(paths: paths, instanceID: instanceID) }
                    await applyNetworkSettings()
                    try await InstallerJavaRuntime.$request.withValue({ [self] minimum, component in
                        return try await self.javaForInstaller(minimumMajor: minimum, component: component, activityID: id)
                    }) {
                        try await work(id)
                    }
                    finishTask(id, recording: recording)
                } catch {
                    let cancelled = Task.isCancelled || error is CancellationError
                    let detail = error is RunDirectoryCopyFailure || error is InstanceMoveFailure || error is RepositoryImportFailure ? error.localizedDescription : cancelled ? Messages.AppAppModel.taskCancelled.localized : error.localizedDescription
                    journal.finish(id, status: cancelled ? .cancelled : .failed, detail: detail)
                    if !cancelled && (presentErrors || (instanceID != nil && lease == nil)) { self.error = error.localizedDescription }
                }
                persistJournal()
                operation = nil
            }
        }
    }
    func progress(_ id: UUID, _ progress: InstallProgress) {
        journal.progress(id, progress)
        if Date().timeIntervalSince(journalCheckpoint) >= 5 {
            journalCheckpoint = Date()
            persistJournal()
        }
    }
    func synchronizeExternalState() async {
        guard operation == nil else { return }
        if readOnly {
            guard retryPersistence else { return }
            do {
                do { acceptState(try StateStore.save(state, to: paths, basedOn: persistedState)) }
                catch let failure as OperationFailure where failure.code == "STATE_CONFLICT" {
                    // Keep the conflict message visible, but accept the latest
                    // valid state so the user can retry the edit immediately.
                    acceptState(try StateStore.load(basePaths))
                }
                readOnly = false; retryPersistence = false
            } catch {
                retryPersistence = (error as? OperationFailure)?.code == "RESOURCE_BUSY"
            }
            return
        }
        let baselineRevision = persistedState?.revision, basePaths = basePaths
        do {
            let remote = try await Task.detached(priority: .utility) { try StateStore.load(basePaths) }.value
            // A local save may have completed while the disk read was running.
            guard operation == nil, persistedState?.revision == baselineRevision, remote.revision != baselineRevision else { return }
            if baselineRevision != nil && remote.revision == nil { throw RuriError.message(Messages.AppAppModel.externalIndexChanged) }
            if state == persistedState {
                acceptState(remote)
            }
            else { save() }
        } catch { readOnly = true; self.error = Messages.AppAppModel.externalChangesDetected(error.localizedDescription).localized }
    }
    /// Accept a state already committed by a core service, keeping the merge
    /// baseline in sync without exposing a writable baseline to feature code.
    func acceptState(_ saved: PersistentState) {
        let networkChanged = state.settings.downloadSource != saved.settings.downloadSource || state.settings.concurrentDownloads != saved.settings.concurrentDownloads
        let previousJava = Set(state.instances.compactMap { $0.resolvedLaunchSettings(defaults: state.settings).java.path })
        let nextJava = Set(saved.instances.compactMap { $0.resolvedLaunchSettings(defaults: saved.settings).java.path })
        let javaChanged = previousJava != nextJava || state.settings.defaultJava != saved.settings.defaultJava || state.settings.javaLocations != saved.settings.javaLocations
        state = saved
        persistedState = saved
        if networkChanged { Task { await applyNetworkSettings() } }
        if javaChanged { Task { await scanJava() } }
    }
}
