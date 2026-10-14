import Foundation
import Testing
@testable import RuriCore

struct ChorusTests {
    private func room(state: ChorusRoomState = .starting, generation: Int = 1, build: String = "fabric-fc16eaac252b") -> ChorusRoom {
        ChorusRoom(id: "main-fabric", kind: "branch", branch: "main", sha: "fc16eaac252bc8404e99a2368fecd768d31c8067", loader: "fabric",
                   buildId: build, generation: generation, behindHead: false, host: "main-fabric.chorus.internal", port: 25565,
                   state: state, phase: "", label: "testing", node: "encore", players: [], idleSince: nil, seed: "empty",
                   seedResolved: .init(kind: "empty", id: nil, rev: nil), asset: nil, lastSnapshot: nil, lastError: nil,
                   createdAt: "2026-10-14T18:00:00Z", updatedAt: "2026-10-14T18:00:00Z")
    }

    @Test func readyBeforeLocalLaunchesOnlyOnce() throws {
        var gate = try ChorusJoinGate(room: room(state: .ready))
        let beforeLocal = gate.claimLaunch()
        #expect(!beforeLocal)
        gate.prepareLocal()
        let first = gate.claimLaunch(), repeated = gate.claimLaunch()
        #expect(first)
        #expect(!repeated)
        try gate.observe(room(state: .ready))
        let afterEvent = gate.claimLaunch()
        #expect(!afterEvent)
    }

    @Test func localBeforeReadyWaitsForMatchingRoom() throws {
        var gate = try ChorusJoinGate(room: room())
        gate.prepareLocal()
        let beforeReady = gate.claimLaunch()
        #expect(!beforeReady)
        try gate.observe(room(state: .ready))
        let afterReady = gate.claimLaunch()
        #expect(afterReady)
    }

    @Test func reverifyRevokesEarlierReadiness() throws {
        var gate = try ChorusJoinGate(room: room(state: .ready))
        try gate.observe(room(state: .starting))
        gate.prepareLocal()
        let rechecking = gate.claimLaunch()
        #expect(!rechecking)
        try gate.observe(.init(id: "main-fabric", generation: 1, host: "main-fabric.chorus.internal", port: 25565, buildId: "fabric-fc16eaac252b"))
        let confirmed = gate.claimLaunch()
        #expect(confirmed)
    }

    @Test(arguments: [ChorusRoomState.failed, .stopping, .archiving, .closed, .lost])
    func terminalStatesCancel(state: ChorusRoomState) throws {
        var gate = try ChorusJoinGate(room: room(state: .ready))
        #expect(throws: (any Error).self) { try gate.observe(room(state: state)) }
        gate.prepareLocal()
        #expect(gate.cancelled)
        let afterCancellation = gate.claimLaunch()
        #expect(!afterCancellation)
        #expect(throws: (any Error).self) { try gate.observe(room(state: .ready)) }
    }

    @Test func changedGenerationOrBuildCancels() throws {
        var generation = try ChorusJoinGate(room: room())
        #expect(throws: (any Error).self) { try generation.observe(room(state: .ready, generation: 2)) }
        var build = try ChorusJoinGate(room: room())
        #expect(throws: (any Error).self) { try build.observe(room(state: .ready, build: "fabric-000000000000")) }
    }

    @Test func instanceIdentityIncludesLoaderVersion() {
        #expect(ChorusInstanceManager.key(minecraft: "26.3", loader: "fabric", version: "0.19.5") != ChorusInstanceManager.key(minecraft: "26.3", loader: "fabric", version: "0.19.6"))
        #expect(ChorusInstanceManager.key(minecraft: "26.3", loader: "fabric", version: "0.19.5") != ChorusInstanceManager.key(minecraft: "26.3", loader: "neoforge", version: "0.19.5"))
    }

    @Test func backendAddressRejectsCredentialsAndPaths() throws {
        #expect(try ChorusSettings.normalizedURL("http://encore.inner.imdomestic.com:8790/").absoluteString == ChorusSettings.defaultBaseURL)
        for input in ["file:///etc/passwd", "http://user:password@example.com", "http://example.com/path", "http://example.com?secret=value", "http://example.com#fragment"] {
            #expect(throws: (any Error).self) { try ChorusSettings.normalizedURL(input) }
        }
    }

    @Test func retryBackoffIsBounded() {
        #expect(ChorusEventStream.retryDelay(attempt: 0) == .seconds(1))
        #expect(ChorusEventStream.retryDelay(attempt: 2) == .seconds(4))
        #expect(ChorusEventStream.retryDelay(attempt: 200) == .seconds(30))
    }

    @Test func independentDataAndCommandLocations() throws {
        #expect(LauncherPaths().root.lastPathComponent == "Ruri Chorus")
        let install = try CLIInstallation(executable: URL(fileURLWithPath: "/Applications/Ruri Chorus.app/Contents/Helpers/ruri-cli"))
        #expect(install.link.lastPathComponent == "ruri-chorus")
    }

    @Test func manifestSideAndNameValidation() throws {
        let file = ChorusBuild.File(name: "chorus.jar", sha256: String(repeating: "a", count: 64), size: 1, side: "both", url: "/v1/deps/sha")
        let server = ChorusBuild.File(name: "hop.jar", sha256: file.sha256, size: 1, side: "server", url: "/v1/deps/sha")
        func build(_ files: [ChorusBuild.File]) -> ChorusBuild {
            .init(id: "fabric-fc16eaac252b", sha: room().sha, loader: "fabric", status: .ready, attempt: 1, queuedAt: room().createdAt,
                  startedAt: room().createdAt, finishedAt: room().createdAt, minecraft: "26.3", loaderVersion: "0.19.5", java: 25,
                  builtAt: room().createdAt, durationSec: 1, modIds: ["chorus"], files: files, log: "/v1/builds/fabric-fc16eaac252b/log", lastError: nil)
        }
        #expect(try ChorusModSync.clientFiles(build([file, server])) == [file])
        #expect(throws: (any Error).self) { try ChorusModSync.clientFiles(build([file, file])) }
        let traversal = ChorusBuild.File(name: "../chorus.jar", sha256: file.sha256, size: 1, side: "both", url: file.url)
        #expect(throws: (any Error).self) { try ChorusModSync.clientFiles(build([traversal])) }
    }
}

@Suite(.enabled(if: ProcessInfo.processInfo.environment["CHORUS_IT_URL"] != nil))
struct ChorusIntegrationTests {
    @Test func liveModelsAndInitialSynchronization() async throws {
        let url = try ChorusSettings.normalizedURL(#require(ProcessInfo.processInfo.environment["CHORUS_IT_URL"]))
        let client = try ChorusClient(baseURL: url, token: ChorusTokenStore.load(baseURL: url))
        let meta = try await client.meta()
        #expect(meta.minecraft == "26.3")
        #expect(meta.loaders.contains("fabric"))
        _ = try await client.rooms()
        _ = try await client.builds()
        let branches = try await client.branches()
        #expect(branches.contains { $0.name == "main" })
        let commits = try await client.commits(branch: "main")
        #expect(!commits.isEmpty)
        var iterator = ChorusEventStream(client: client).events().makeAsyncIterator()
        guard case .sync(let sync) = try await iterator.next() else { Issue.record("sync"); return }
        #expect(sync.rooms.contains { $0.id == "main-fabric" })
    }
}

@Suite(.enabled(if: ProcessInfo.processInfo.environment["CHORUS_SSE_RECORDING"] != nil))
struct ChorusRecordingTests {
    @Test func recordedStreamDecodesAndStartsWithSync() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["CHORUS_SSE_RECORDING"])
        let events = try await ChorusEventStream.decodeRecording(Data(contentsOf: URL(fileURLWithPath: path)))
        #expect(!events.isEmpty)
        guard case .sync = events.first else { Issue.record("sync"); return }
    }
}
