import Foundation
import RuriCore
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
    public func prepare(roomID: String, events: AsyncThrowingStream<VexEvent, Error>? = nil, progress: @escaping @Sendable (VexJoinProgress) async -> Void = { _ in }) async throws -> VexPreparedJoin {
        let leases = VexJoinLeases(client: client, roomID: roomID)
        do {
            let initial = try await leases.issue(reopen: true)
            try Task.checkCancellation()
            return try await prepare(initial: initial, roomID: roomID, leases: leases, events: events, progress: progress)
        } catch {
            try await leases.release()
            throw error
        }
    }
    private func prepare(initial: VexStartResult, roomID: String, leases: VexJoinLeases, events: AsyncThrowingStream<VexEvent, Error>?, progress: @escaping @Sendable (VexJoinProgress) async -> Void) async throws -> VexPreparedJoin {
        guard initial.room.project == client.project else { throw RuriError.message(Messages.Vex.invalidResponse) }
        var gate = try VexJoinGate(room: initial.room)
        let (signals, continuation) = AsyncThrowingStream<Signal, Error>.makeStream()
        let stream = Task {
            do {
                for try await event in events ?? VexEventStream(client: client).events(room: roomID) { continuation.yield(.event(event)) }
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
                let prepared = try await VexInstanceManager(paths: paths, client: client).prepare(build, roomID: roomID, generation: initial.room.generation) { install in
                    continuation.yield(.local(install.message.localized))
                }
                continuation.yield(.prepared(prepared))
            } catch { continuation.finish(throwing: error) }
        }
        let renewal = Task {
            do {
                while !Task.isCancelled {
                    try await Task.sleep(for: .seconds(120))
                    try Task.checkCancellation()
                    let result = try await leases.issue()
                    try Task.checkCancellation()
                    continuation.yield(.renewed(result))
                }
            } catch { continuation.finish(throwing: error) }
        }
        var prepared: VexPreparedInstance?
        var joined: VexPreparedJoin?
        var failure: (any Error)?
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
                case .renewed(let result): try gate.observe(result.room)
                }
                await progress(.init(room: gate.room, local: message, unmanaged: prepared?.unmanagedMods ?? []))
                if gate.claimLaunch(), let prepared { joined = .init(room: gate.room, prepared: prepared); break }
            }
        } catch { failure = error }
        stream.cancel(); local.cancel(); renewal.cancel(); continuation.finish()
        await stream.value; await local.value; await renewal.value
        if let failure { throw failure }
        try Task.checkCancellation()
        guard let joined else { throw CancellationError() }
        return joined
    }
}

actor VexJoinLeases {
    private let client: VexClient
    private let roomID: String
    private var issued: [VexLease] = []

    init(client: VexClient, roomID: String) { self.client = client; self.roomID = roomID }

    func issue(reopen: Bool = false) async throws -> VexStartResult {
        if reopen { try await client.prepareReopen(roomID) }
        try Task.checkCancellation()
        let request = Task.detached { [client, roomID] in
            try await client.start(roomID)
        }
        let result = try await request.value
        issued.append(result.lease)
        return result
    }

    func release() async throws {
        let cleanup = Task.detached { [client, roomID, issued] in
            for lease in issued { try await client.cancel(room: roomID, lease: lease.id) }
        }
        try await cleanup.value
        issued.removeAll()
    }
}
