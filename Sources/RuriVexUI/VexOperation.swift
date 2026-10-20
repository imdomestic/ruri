import Foundation

@MainActor final class VexOperation {
    private var identity: UUID?
    private var task: Task<Void, Never>?
    var isRunning: Bool { identity != nil }

    @discardableResult
    func start(_ operation: @escaping @MainActor (UUID) async -> Void) -> Bool {
        guard !isRunning else { return false }
        let id = UUID()
        identity = id
        task = Task {
            guard owns(id), !Task.isCancelled else { return }
            await operation(id)
            finish(id)
        }
        return true
    }

    func owns(_ id: UUID) -> Bool { identity == id }
    func finish(_ id: UUID) {
        guard owns(id) else { return }
        identity = nil
        task = nil
    }
    func cancel() {
        task?.cancel()
        task = nil
        identity = nil
    }
}
