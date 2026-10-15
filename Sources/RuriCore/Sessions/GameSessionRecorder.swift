import Foundation
import RuriLocalization

/// Preparation owns the launch lease until the durable monitor handoff.
@MainActor public final class GameSessionRecorder {
    package let writer: SessionRecordWriter
    public private(set) var record: GameSession { get { writer.record } set { writer.record = newValue } }
    public var directory: URL { writer.directory }
    public private(set) var hasHandedOff: Bool { get { writer.hasHandedOff } set { writer.hasHandedOff = newValue } }
    private let paths: LauncherPaths
    private var lease: GameRunLease?
    public init(paths: LauncherPaths, instance: GameInstance, accountMode: String) throws {
        let instance = (try? instance.resolvingPersistedLaunchSettings(paths: paths)) ?? instance
        let memory = try? JVMHeapArguments.resolve(base: instance.frozenMemory ?? MemorySettings(maximumMB: instance.memoryMB).resolve(), arguments: ArgumentTokenizer.split(instance.extraJVMArguments))
        self.paths = paths
        try paths.validateBinding(instance)
        lease = try GameRunLease.acquire(paths: paths, instanceID: instance.id)
        let now = Date(), id = UUID()
        var record = GameSession(id: id, instanceID: instance.id, instanceName: instance.name, gameVersion: instance.gameVersion, loader: instance.loader.rawValue,
                             loaderVersion: instance.loaderVersion, memoryMB: memory?.maximumMB ?? instance.memoryMB,
                             operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString, hostArchitecture: JavaRuntime.hostArchitecture,
                             accountMode: accountMode, ownerPID: ProcessInfo.processInfo.processIdentifier, createdAt: now, updatedAt: now,
                             state: .preparing, stage: .preparing, events: [], evidence: [])
        record.memory = memory
        record.launcherVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        record.debugLogging = instance.launchPresentation?.debugLogging == true
        record.gameDirectory = paths.game(instance.id)
        writer = try SessionRecordWriter(record: record, paths: paths)
        try transition(.preparing)
        try lease?.reserve(paths: paths, session: record)
    }

    public func handoff(to monitor: ProcessIdentity) throws {
        try writer.requireWritable()
        guard record.processID == nil, !record.state.isFinished, !hasHandedOff else { throw RuriError.message(Messages.CoreGameSession.runCannotBeHandedToMonitor) }
        record.monitorIdentity = monitor; record.updatedAt = Date(); try writer.save()
        hasHandedOff = true
        try close()
    }
    func acknowledgeHandoff(_ current: GameSession) {
        guard hasHandedOff, current.id == record.id, current.monitorIdentity == record.monitorIdentity else { return }
        record = current
    }
    public func fail(_ error: any Error, cancelled: Bool) throws {
        let persistence = try writer.recordFailure(error, cancelled: cancelled)
        defer { try? close() }
        try close()
        try? GameSessionRetention.prune(paths: paths, instanceID: record.instanceID, keeping: record.id)
        try persistence.get()
    }

    public func close() throws {
        guard !writer.closed else { return }
        defer { writer.closed = true; lease = nil }
        do { try lease?.clearReservation(session: record) } catch { writer.storageWarning(error) }
    }
    public func addSecrets(_ values: [String]) { writer.addSecrets(values) }
    public func redacted(_ text: String) -> String { writer.redacted(text) }
    func configureLogging(debug: Bool) throws { try writer.configureLogging(debug: debug) }
    public func append(_ text: String) throws { try writer.append(text) }
    public func transition(_ stage: GameSession.Stage, message: String? = nil) throws { try writer.transition(stage, message: message) }
    public func transition(_ stage: GameSession.Stage, message: LocalizedMessage) throws { try writer.transition(stage, message: message) }
    public func setJava(_ label: String) throws { try writer.setJava(label) }
    public func setMemory(_ memory: LaunchMemory) throws { try writer.setMemory(memory) }
    public func setTuning(_ tuning: JVMTuning) throws { try writer.setTuning(tuning) }
    public func setWorld(_ world: GameWorldPlay) throws { try writer.setWorld(world) }
    public func setDestination(_ destination: LaunchDestination) throws { try writer.setDestination(destination) }
    @discardableResult public func prepareChorusServers(settings: ChorusSettings, state: PersistentState) throws -> Int {
        try chorusServerCleanup(settings: settings, state: state)?.clean(directory: paths.game(record.instanceID)) ?? 0
    }
    package func chorusServerCleanup(settings: ChorusSettings, state: PersistentState) throws -> ChorusServerCleanupPlan? {
        try writer.requireWritable()
        guard lease != nil, !hasHandedOff, record.processID == nil else {
            throw RuriError.message(Messages.CoreGameSession.runCannotBeHandedToMonitor)
        }
        let configured = paths.configured(with: state)
        guard configured.game(record.instanceID).standardizedFileURL.resolvingSymlinksInPath().path ==
                paths.game(record.instanceID).standardizedFileURL.resolvingSymlinksInPath().path else {
            throw RuriError.message(Messages.Servers.listChanged)
        }
        return try ServerListManager(paths: configured, instanceID: record.instanceID)
            .chorusCleanupPlanDuringPreparation(policy: ChorusServerPolicy(settings: settings), state: state)
    }
}
