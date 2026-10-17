import Foundation
import RuriLocalization

public struct VexJoinProgress: Sendable { public let room: VexRoom; public let local: String; public let unmanaged: [String] }
public struct VexPreparedJoin: Sendable { public let room: VexRoom; public let prepared: VexPreparedInstance }

public struct VexLaunchCoordinator: Sendable {
    public let client: VexClient
    public let paths: LauncherPaths
    public init(client: VexClient, paths: LauncherPaths) { self.client = client; self.paths = paths }
    private enum Signal: Sendable {
        case event(VexEvent), prepared(VexPreparedInstance), local(String), renewed(VexStartResult)
    }
    public func prepare(roomID: String, progress: @escaping @Sendable (VexJoinProgress) async -> Void = { _ in }) async throws -> VexPreparedJoin {
        let initial = try await client.reopen(roomID)
        guard initial.room.project == client.project else { throw RuriError.message(Messages.Vex.invalidResponse) }
        var gate = try VexJoinGate(room: initial.room)
        var leases = [initial.lease]
        let (signals, continuation) = AsyncThrowingStream<Signal, Error>.makeStream()
        let stream = Task {
            do {
                for try await event in VexEventStream(client: client).events(room: roomID) { continuation.yield(.event(event)) }
            } catch { continuation.finish(throwing: error) }
        }
        let local = Task {
            do {
                var build = try await client.build(initial.room.buildId)
                while build.status != .ready {
                    if build.status == .failed { throw build.lastError ?? VexAPIError(code: "build_failed", message: Messages.Vex.buildUnavailable.localized, details: nil) }
                    try await Task.sleep(for: .seconds(2))
                    build = try await client.build(initial.room.buildId)
                }
                let prepared = try await VexInstanceManager(paths: paths, client: client).prepare(build) { install in
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
        var prepared: VexPreparedInstance?
        var message = Messages.Vex.preparing.localized
        await progress(.init(room: gate.room, local: message, unmanaged: []))
        do {
            for try await signal in signals {
                try Task.checkCancellation()
                switch signal {
                case .event(let event):
                    switch event {
                    case .sync(let sync): for room in sync.rooms { try gate.observe(room) }
                    case .room(let room): try gate.observe(room)
                    case .ready(let ready): try gate.observe(ready)
                    case .failed(let failed):
                        if failed.project == client.project && failed.id == roomID { throw failed.error }
                    case .build, .git: break
                    }
                case .prepared(let value): prepared = value; gate.prepareLocal(); message = Messages.Vex.localReady.localized
                case .local(let value): message = value
                case .renewed(let result): leases.append(result.lease); try gate.observe(result.room)
                }
                await progress(.init(room: gate.room, local: message, unmanaged: prepared?.unmanagedMods ?? []))
                if gate.claimLaunch(), let prepared { return .init(room: gate.room, prepared: prepared) }
            }
            throw CancellationError()
        } catch {
            let issued = leases
            let cleanup = Task.detached { for lease in issued { try await client.cancel(room: roomID, lease: lease.id) } }
            try await cleanup.value
            throw error
        }
    }
}
