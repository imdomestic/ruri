import Foundation
import EventSource
import RuriLocalization

public enum ChorusEvent: Sendable {
    case sync(ChorusSync)
    case room(ChorusRoom)
    case build(ChorusBuild)
    case ready(ChorusReady)
    case failed(ChorusFailed)
    case git

    public static func decode(name: String, data: String) throws -> Self? {
        let bytes = Data(data.utf8), decoder = JSONDecoder()
        switch name {
        case "sync": return .sync(try decoder.decode(ChorusSync.self, from: bytes))
        case "room": return .room(try decoder.decode(ChorusRoom.self, from: bytes))
        case "build": return .build(try decoder.decode(ChorusBuild.self, from: bytes))
        case "ready": return .ready(try decoder.decode(ChorusReady.self, from: bytes))
        case "failed": return .failed(try decoder.decode(ChorusFailed.self, from: bytes))
        case "branch_added", "branch_moved", "branch_deleted": return .git
        default: return nil
        }
    }
}

public struct ChorusEventStream: Sendable {
    public let client: ChorusClient
    public init(client: ChorusClient) { self.client = client }
    public static func retryDelay(attempt: Int) -> Duration { .seconds(min(30, 1 << min(max(0, attempt), 5))) }

    public func events(room: String? = nil) -> AsyncThrowingStream<ChorusEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var retries = 0
                while !Task.isCancelled {
                    do {
                        let path = room.map { "/v1/rooms/" + ChorusClient.component($0) + "/events" } ?? "/v1/events"
                        var request = try client.request(path)
                        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                        let (bytes, response) = try await client.session.bytes(for: request)
                        try client.validate(response)
                        guard let http = response as? HTTPURLResponse,
                              http.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("text/event-stream") == true else {
                            throw RuriError.message(Messages.Chorus.invalidResponse)
                        }
                        var synchronized = false
                        for try await event in bytes.events {
                            try Task.checkCancellation()
                            guard synchronized || event.event == "sync" else { throw RuriError.message(Messages.Chorus.invalidResponse) }
                            synchronized = true
                            retries = 0
                            if let decoded = try ChorusEvent.decode(name: event.event ?? "message", data: event.data) { continuation.yield(decoded) }
                        }
                    } catch is CancellationError {
                        continuation.finish(); return
                    } catch let error as URLError {
                        if Task.isCancelled || error.code == .cancelled { continuation.finish(); return }
                    } catch let error as ChorusHTTPError where error.status >= 500 {
                        // 暂时的服务器错误在重新连接后重新同步全部状态。
                    } catch {
                        continuation.finish(throwing: error); return
                    }
                    do { try await Task.sleep(for: Self.retryDelay(attempt: retries)); retries += 1 }
                    catch { continuation.finish(); return }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public static func decodeRecording(_ data: Data) async throws -> [ChorusEvent] {
        let parser = EventSource.Parser()
        for byte in data { await parser.consume(byte) }
        await parser.finish()
        var result: [ChorusEvent] = []
        while let event = await parser.getNextEvent() {
            if let value = try ChorusEvent.decode(name: event.event ?? "message", data: event.data) { result.append(value) }
        }
        return result
    }
}
