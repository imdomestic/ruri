import Foundation

public struct ExperimentalLaunchOperation: Sendable {
    public let instanceID: UUID
    private let task: Task<GameSession, any Error>
    fileprivate init(instanceID: UUID, task: Task<GameSession, any Error>) {
        self.instanceID = instanceID
        self.task = task
    }
    public func cancel() { task.cancel() }
    public func result() async throws -> GameSession {
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}

/// Launching and reading sessions through the same service the launcher uses.
@MainActor public struct ExperimentalLaunchCapabilities {
    public let paths: LauncherPaths
    public init(paths: LauncherPaths) { self.paths = paths }
    public func begin(instanceID: UUID, address: ServerAddress) -> ExperimentalLaunchOperation {
        let task = Task { @MainActor in
            try Task.checkCancellation()
            return try await LaunchService(paths: paths).start(instanceID: instanceID, destination: .server(address))
        }
        return ExperimentalLaunchOperation(instanceID: instanceID, task: task)
    }
    public func start(instanceID: UUID, address: ServerAddress) async throws -> GameSession {
        try await begin(instanceID: instanceID, address: address).result()
    }
    public func cancel(_ operation: ExperimentalLaunchOperation) { operation.cancel() }
    public func session(instanceID: UUID, sessionID: UUID) throws -> GameSession {
        let configured = paths.configured(with: try StateStore.load(paths))
        return try GameSessionStore.load(paths: configured, instanceID: instanceID, sessionID: sessionID)
    }
    public func sessions(instanceID: UUID) throws -> [GameSession] {
        let configured = paths.configured(with: try StateStore.load(paths))
        return try GameSessionStore.list(paths: configured, instanceID: instanceID)
    }
}
