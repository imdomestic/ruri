import Foundation
import EventSource
import RuriLocalization

public enum VexEvent: Sendable {
    case sync(VexSync), room(VexRoom), build(VexBuild), ready(VexReady), failed(VexFailed), git
    public static func decode(name: String, data: String) throws -> Self? {
        guard !data.isEmpty else { return nil }
        let bytes = Data(data.utf8), decoder = JSONDecoder()
        switch name {
        case "sync": return .sync(try decoder.decode(VexSync.self, from: bytes))
        case "room": return .room(try decoder.decode(VexRoom.self, from: bytes))
        case "build": return .build(try decoder.decode(VexBuild.self, from: bytes))
        case "ready": return .ready(try decoder.decode(VexReady.self, from: bytes))
        case "failed": return .failed(try decoder.decode(VexFailed.self, from: bytes))
        case "branch_added", "branch_moved", "branch_deleted": return .git
        default: return nil
        }
    }
}

public struct VexEventConnectionStatus: Sendable {
    public enum State: Equatable, Sendable {
        case idle, connecting, connected, disconnected, reconnecting
        public var message: LocalizedMessage? {
            switch self {
            case .idle, .connected: nil
            case .connecting: Messages.VexLogin.eventsConnecting
            case .disconnected: Messages.VexLogin.eventsDisconnected
            case .reconnecting: Messages.VexLogin.eventsReconnecting
            }
        }
    }
    public private(set) var state: State = .idle
    private var attempted = false
    public init() {}
    public mutating func beginAttempt() {
        state = attempted ? .reconnecting : .connecting
        attempted = true
    }
    public mutating func receivedSync() { state = .connected }
    public mutating func disconnected() { state = .disconnected }
}

public struct VexEventStream: Sendable {
    public let client: VexClient
    public init(client: VexClient) { self.client = client }
    public static func retryDelay(attempt: Int) -> Duration { .seconds(min(30, 1 << min(max(0, attempt), 5))) }
    public func events(room: String? = nil, connectionChanged: @escaping @Sendable (VexEventConnectionStatus.State) async -> Void = { _ in }) -> AsyncThrowingStream<VexEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var retries = 0
                var connection = VexEventConnectionStatus()
                while !Task.isCancelled {
                    do {
                        connection.beginAttempt()
                        await connectionChanged(connection.state)
                        try Task.checkCancellation()
                        let path = try room.map { try client.projectPath("/rooms/" + VexClient.component($0) + "/events") } ?? "/v2/events"
                        var request = try client.request(path, query: room == nil && !client.project.isEmpty ? [.init(name: "project", value: client.project)] : [])
                        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                        let (bytes, response) = try await client.session.bytes(for: request)
                        try client.validate(response)
                        guard let http = response as? HTTPURLResponse,
                              http.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("text/event-stream") == true else {
                            throw RuriError.message(Messages.Vex.invalidResponse)
                        }
                        var synchronized = false
                        for try await event in bytes.events {
                            try Task.checkCancellation()
                            guard !event.data.isEmpty else { continue }
                            guard synchronized || event.event == "sync" else { throw RuriError.message(Messages.Vex.invalidResponse) }
                            let decoded = try VexEvent.decode(name: event.event ?? "message", data: event.data)
                            if !synchronized {
                                connection.receivedSync()
                                await connectionChanged(connection.state)
                            }
                            synchronized = true; retries = 0
                            if let decoded { continuation.yield(decoded) }
                        }
                    } catch is CancellationError { continuation.finish(); return }
                    catch let error as URLError {
                        if Task.isCancelled || error.code == .cancelled { continuation.finish(); return }
                    } catch let error as VexHTTPError where error.status >= 500 {
                        // 下一次连接使用服务器的 sync 重新同步状态。
                    } catch { continuation.finish(throwing: error); return }
                    if Task.isCancelled { continuation.finish(); return }
                    connection.disconnected()
                    await connectionChanged(connection.state)
                    do { try await Task.sleep(for: Self.retryDelay(attempt: retries)); retries += 1 }
                    catch { continuation.finish(); return }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
    public static func decodeRecording(_ data: Data) async throws -> [VexEvent] {
        let parser = EventSource.Parser()
        for byte in data { await parser.consume(byte) }
        await parser.finish()
        var result: [VexEvent] = []
        while let event = await parser.getNextEvent() {
            if let value = try VexEvent.decode(name: event.event ?? "message", data: event.data) { result.append(value) }
        }
        return result
    }
}
