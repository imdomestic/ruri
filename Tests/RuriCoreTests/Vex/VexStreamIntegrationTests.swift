import Foundation
import Testing
@testable import RuriCore

struct VexStreamIntegrationTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VEX_IT_SSH_HOST"] != nil))
    func realEventDisconnectAndRecoveryRemainIsolated() async throws {
        let environment = ProcessInfo.processInfo.environment
        let primaryURL = try VexSettings.normalizedURL(#require(environment["VEX_IT_URL"]))
        let secondaryURL = try VexSettings.normalizedURL(#require(environment["VEX_IT_SECOND_URL"]))
        let forwardedURL = try VexSettings.normalizedURL(#require(environment["VEX_IT_TUNNEL_URL"]))
        let primaryFile = URL(fileURLWithPath: try #require(environment["VEX_IT_SESSION_FILE"]))
        struct Session: Decodable { let token: String }
        let primaryToken = try JSONDecoder().decode(Session.self, from: Data(contentsOf: primaryFile)).token
        let secondaryFile = URL(fileURLWithPath: try #require(environment["VEX_IT_SECOND_TOKEN_FILE"]))
        let secondaryToken = try String(contentsOf: secondaryFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        let primary = try VexClient(baseURL: primaryURL, token: primaryToken)
        let secondary = try VexClient(baseURL: secondaryURL, token: secondaryToken)
        let forwarded = try VexClient(baseURL: forwardedURL, token: secondaryToken)
        #expect(!(try await primary.me()).id.isEmpty)
        #expect(!(try await secondary.me()).id.isEmpty)
        let localPort = try #require(forwardedURL.port)
        let remotePortValue = try #require(environment["VEX_IT_SSH_REMOTE_PORT"])
        let remotePort = try #require(Int(remotePortValue))
        try #require(forwardedURL.host == "127.0.0.1" && localPort != secondaryURL.port)
        let host = try #require(environment["VEX_IT_SSH_HOST"])
        let tunnel = try startTunnel(host: host, localPort: localPort, remotePort: remotePort)
        defer { stopTunnel(tunnel) }
        let first = Observation(), second = Observation()
        let firstTask = consume(primary, observation: first), secondTask = consume(forwarded, observation: second)
        defer { firstTask.cancel(); secondTask.cancel() }
        try await first.wait(for: .connected)
        try await second.wait(for: .connected)
        try #require(tunnel.isRunning)
        let boundary = await second.states.count
        stopTunnel(tunnel)
        try await second.wait(for: .disconnected, after: boundary)
        try await second.wait(for: .reconnecting, after: boundary)
        #expect(!(try await secondary.me()).id.isEmpty)
        #expect(!(try await primary.me()).id.isEmpty)
        #expect(await first.states == [.connecting, .connected])
        print("SSE secondary disconnected; both direct APIs remain available; primary stream remains connected")
        let restored = try startTunnel(host: host, localPort: localPort, remotePort: remotePort)
        defer { stopTunnel(restored) }
        try await second.wait(for: .connected, after: boundary, minimumSyncs: 2)
        try #require(restored.isRunning)
        #expect(await first.states == [.connecting, .connected])
        #expect(await second.syncs >= 2)
        print("SSE secondary recovered through a fresh sync; primary stream remained independent")
    }

    private func startTunnel(host: String, localPort: Int, remotePort: Int) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = ["-N", "-T", "-o", "BatchMode=yes", "-o", "ExitOnForwardFailure=yes",
                             "-o", "ControlMaster=no", "-o", "ControlPath=none",
                             "-L", "127.0.0.1:\(localPort):127.0.0.1:\(remotePort)", host]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }
    private func stopTunnel(_ process: Process) {
        if process.isRunning { process.terminate(); process.waitUntilExit() }
    }
    private func consume(_ client: VexClient, observation: Observation) -> Task<Void, Never> {
        Task {
            do {
                for try await event in VexEventStream(client: client).events(connectionChanged: { await observation.record($0) }) {
                    if case .sync = event { await observation.synchronized() }
                }
            } catch { await observation.failed(error) }
        }
    }
    private actor Observation {
        var states: [VexEventConnectionStatus.State] = []
        var syncs = 0
        var failure: (any Error)?
        func record(_ state: VexEventConnectionStatus.State) { states.append(state) }
        func synchronized() { syncs += 1 }
        func failed(_ error: any Error) { failure = error }
        func wait(for state: VexEventConnectionStatus.State, after index: Int = 0, minimumSyncs: Int = 1) async throws {
            let deadline = ContinuousClock.now + .seconds(30)
            while !states.dropFirst(index).contains(state) || state == .connected && syncs < minimumSyncs {
                if let failure { throw failure }
                try #require(ContinuousClock.now < deadline, "Timed out waiting for real SSE connection state")
                try await Task.sleep(for: .milliseconds(50))
            }
        }
    }
}
