import Foundation
import RuriLocalization

public struct ChorusJoinProgress: Sendable {
    public let room: ChorusRoom
    public let local: String
    public let unmanaged: [String]
    public init(room: ChorusRoom, local: String, unmanaged: [String]) { self.room = room; self.local = local; self.unmanaged = unmanaged }
}
public struct ChorusPreparedJoin: Sendable {
    public let room: ChorusRoom
    public let prepared: ChorusPreparedInstance
}

public struct ChorusLaunchCoordinator: Sendable {
    public let client: ChorusClient
    public let paths: LauncherPaths
    public init(client: ChorusClient, paths: LauncherPaths) { self.client = client; self.paths = paths }
    private enum Signal: Sendable {
        case event(ChorusEvent)
        case prepared(ChorusPreparedInstance)
        case local(String)
        case renewed(ChorusStartResult)
    }

    public func prepare(roomID: String, progress: @escaping @Sendable (ChorusJoinProgress) async -> Void = { _ in }) async throws -> ChorusPreparedJoin {
        let initial = try await client.start(roomID)
        var gate = try ChorusJoinGate(room: initial.room)
        var leases = [initial.lease]
        let (signals, continuation) = AsyncThrowingStream<Signal, Error>.makeStream()
        let stream = Task {
            do {
                for try await event in ChorusEventStream(client: client).events(room: roomID) { continuation.yield(.event(event)) }
            } catch { continuation.finish(throwing: error) }
        }
        let local = Task {
            do {
                var build = try await client.build(initial.room.buildId)
                while build.status != .ready {
                    if build.status == .failed { throw build.lastError ?? ChorusAPIError(code: "build_failed", message: Messages.Chorus.buildUnavailable.localized, details: nil) }
                    try await Task.sleep(for: .seconds(2))
                    build = try await client.build(initial.room.buildId)
                }
                let prepared = try await ChorusInstanceManager(paths: paths, client: client).prepare(build) { install in
                    continuation.yield(.local(install.message.localized))
                }
                continuation.yield(.prepared(prepared))
            } catch { continuation.finish(throwing: error) }
        }
        let renewal = Task {
            do {
                while !Task.isCancelled {
                    try await Task.sleep(for: .seconds(120))
                    continuation.yield(.renewed(try await client.start(roomID)))
                }
            } catch { continuation.finish(throwing: error) }
        }
        defer { stream.cancel(); local.cancel(); renewal.cancel(); continuation.finish() }
        var prepared: ChorusPreparedInstance?
        var localMessage = Messages.Chorus.preparing.localized
        await progress(.init(room: gate.room, local: localMessage, unmanaged: []))
        do {
            for try await signal in signals {
                try Task.checkCancellation()
                switch signal {
                case .event(let event):
                    switch event {
                    case .sync(let sync): for room in sync.rooms { try gate.observe(room) }
                    case .room(let room): try gate.observe(room)
                    case .ready(let value): try gate.observe(value)
                    case .failed(let value):
                        if value.id == roomID { throw value.error }
                    case .build, .git: break
                    }
                case .prepared(let value): prepared = value; gate.prepareLocal(); localMessage = Messages.Chorus.localReady.localized
                case .local(let message): localMessage = message
                case .renewed(let result): leases.append(result.lease); try gate.observe(result.room)
                }
                await progress(.init(room: gate.room, local: localMessage, unmanaged: prepared?.unmanagedMods ?? []))
                if gate.claimLaunch(), let prepared { return .init(room: gate.room, prepared: prepared) }
            }
            throw CancellationError()
        } catch {
            // 使用独立任务取消本次操作发放的租约，父任务取消不阻止清理请求。
            let issued = leases
            let cleanup = Task.detached {
                for lease in issued { try await client.cancel(room: roomID, lease: lease.id) }
            }
            do { try await cleanup.value }
            catch { throw error }
            throw error
        }
    }
}
