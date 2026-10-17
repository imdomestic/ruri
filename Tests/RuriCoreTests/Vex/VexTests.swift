import Foundation
import Testing
@testable import RuriCore

struct VexTests {
    @Test func disabledSettingsDoNotCreateFilesOrReadCredentials() throws {
        let paths = LauncherPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let settings = try VexSettings.load(paths: paths)
        #expect(!settings.enabled)
        #expect(settings.servers.isEmpty)
        #expect(throws: (any Error).self) { try settings.server() }
        #expect(!FileManager.default.fileExists(atPath: paths.root.path))
    }
    @Test func settingsRoundTripInUpstreamStoreWithoutChangingAccounts() throws {
        let paths = LauncherPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: paths.root) }
        var original = PersistentState()
        original.settings.appearance = "dark"
        try StateStore.save(original, to: paths)
        let server = try VexServer(baseURL: URL(string: "https://vex.example.com")!, name: "example")
        try VexSettings.update(paths: paths) { $0.enabled = true; try $0.save(server) }
        let state = try StateStore.load(paths)
        #expect(state.settings.experimental?.vex?.enabled == true)
        #expect(state.settings.appearance == "dark")
        #expect(state.accounts == original.accounts)
        try VexSettings.update(paths: paths) { $0.enabled = false }
        #expect(try VexSettings.load(paths: paths).servers.first?.baseURL == "https://vex.example.com")
    }
    @Test func requestScopesProjectAndRejectsForeignOrigins() throws {
        let client = try VexClient(baseURL: URL(string: "https://vex.example.com")!, token: "unit-input", project: "example")
        #expect(try client.projectPath("/rooms") == "/v2/projects/example/rooms")
        #expect(try client.request(client.projectPath("/rooms")).url?.path == "/v2/projects/example/rooms")
        for invalid in ["https://other.example/v2/rooms", "/v1/rooms", "https://user@vex.example.com/v2/projects"] {
            #expect(throws: (any Error).self) { try client.request(invalid) }
        }
        for invalid in ["two--parts", "bad-", "UPPER", "../room", ""] { #expect(!VexClient.validProject(invalid)) }
        #expect(VexClient.validProject("example-two"))
    }
    @Test func instanceIdentityIncludesServerProjectAndRuntime() {
        let first = VexInstanceManager.key(server: URL(string: "https://one.example")!, project: "one", minecraft: "26.3", loader: "fabric", version: "0.19.5")
        let second = VexInstanceManager.key(server: URL(string: "https://one.example")!, project: "two", minecraft: "26.3", loader: "fabric", version: "0.19.5")
        let third = VexInstanceManager.key(server: URL(string: "https://two.example")!, project: "one", minecraft: "26.3", loader: "fabric", version: "0.19.5")
        #expect(Set([first, second, third]).count == 3)
    }
    @Test func gateWaitsForMatchingProjectGenerationAndLocalFiles() throws {
        var gate = try VexJoinGate(room: room(state: .starting))
        gate.prepareLocal()
        let beforeReady = gate.claimLaunch()
        #expect(!beforeReady)
        try gate.observe(room(project: "other", state: .ready))
        let otherProject = gate.claimLaunch()
        #expect(!otherProject)
        try gate.observe(room(state: .ready))
        let first = gate.claimLaunch(), second = gate.claimLaunch()
        #expect(first)
        #expect(!second)
        var changed = try VexJoinGate(room: room(state: .starting))
        #expect(throws: (any Error).self) { try changed.observe(room(generation: 2, state: .ready)) }
        #expect(changed.cancelled)
    }
    @Test func graphPreservesMergeEdgesAndRejectsInvalidTopology() throws {
        let rows = try VexCommitGraph.layout([.init(sha: "merge", parents: ["left", "right"]), .init(sha: "left", parents: ["root"]), .init(sha: "right", parents: ["root"]), .init(sha: "root", parents: [])])
        #expect(rows[0].edges.count == 2)
        #expect(rows[0].bottom.count == 2)
        #expect(rows.last?.bottom.isEmpty == true)
        #expect(throws: VexCommitGraph.InvalidHistory.invalidTopologicalOrder) {
            try VexCommitGraph.layout([.init(sha: "root", parents: []), .init(sha: "child", parents: ["root"])])
        }
    }
    @Test func recentRoomsRespectAgeAndLimit() {
        let now = ISO8601DateFormatter().date(from: "2026-10-17T12:00:00Z")!
        let values = (0..<15).map { room(id: "c\($0)-fabric", state: .closed, closedAt: "2026-10-17T11:00:00Z") }
        #expect(VexServerPolicy.recentlyClosed(values, now: now).count == 10)
        #expect(VexServerPolicy.recentlyClosed([room(state: .closed, closedAt: "2026-09-01T00:00:00Z")], now: now).isEmpty)
    }
    @Test func serverFilteringChangesOnlyWhileEnabled() throws {
        var settings = VexSettings()
        settings.knownZones = ["vex.example.com"]
        let item = ServerLibraryItem(address: try ServerAddress("main-fabric--example.vex.example.com"), name: "Preview", preference: nil, instanceIDs: [], icon: nil)
        #expect(!VexServerPolicy(settings: settings).hides(item))
        settings.enabled = true
        #expect(VexServerPolicy(settings: settings).hides(item))
        #expect(!VexServerPolicy(settings: settings).contains(try ServerAddress("vex.example.com.evil.test")))
    }
    @Test func tokenCacheReadsOnceAndUpdatesAfterSave() throws {
        let cache = VexTokenCache(), url = URL(string: "https://vex.example.com")!
        var reads = 0
        func read() -> String { reads += 1; return "input" }
        #expect(try cache.load(baseURL: url, read: read) == "input")
        #expect(try cache.load(baseURL: url, read: read) == "input")
        #expect(reads == 1)
        try cache.save("updated", baseURL: url, write: {})
        #expect(try cache.load(baseURL: url, read: read) == "updated")
        #expect(reads == 1)
    }
    @Test func invitationAddressesNormalizeOriginsAndRejectForeignLinks() throws {
        let parsed = try VexServerInput(" HTTPS://VEX.EXAMPLE:443/i/abco-il23 ")
        #expect(parsed.baseURL.absoluteString == "https://vex.example")
        #expect(parsed.invite == "ABC01123")
        #expect(try VexServerInput("vex.example:8791/").baseURL.absoluteString == "http://vex.example:8791")
        #expect(try VexServerInput.invite("abcd-1234", for: parsed.baseURL) == "ABCD1234")
        for input in ["https://other.example/i/ABCD-1234", "https://vex.example/i/ABCD-1234?token=bad", "https://user@vex.example/i/ABCD-1234"] {
            #expect(throws: (any Error).self) { try VexServerInput.invite(input, for: parsed.baseURL) }
        }
        for input in ["abcd", "ABCD_U234", "ABCD-U234"] {
            #expect(throws: (any Error).self) { try VexServerInput.code(input) }
        }
        #expect(throws: (any Error).self) { try VexServerInput("https://vex.example/api") }
    }
    @Test func serverDefaultsAndProjectSelectionRemainIndependent() throws {
        var settings = VexSettings(); settings.enabled = true
        var first = try VexServer(baseURL: URL(string: "https://one.example")!, name: "one")
        let second = try VexServer(baseURL: URL(string: "https://two.example")!, name: "two")
        try settings.save(first); try settings.save(second)
        #expect(try settings.server().id == first.id)
        #expect(try settings.server(named: "two").id == second.id)
        settings.defaultServer = nil
        #expect(throws: (any Error).self) { try settings.server() }
        let one = VexProject(id: "one", defaultBranch: "main", remote: nil, role: "tester", loaders: ["fabric"])
        let two = VexProject(id: "two", defaultBranch: "main", remote: nil, role: "viewer", loaders: ["fabric"])
        #expect(try first.resolveProject(nil, available: [one]).id == "one")
        #expect(throws: (any Error).self) { try first.resolveProject(nil, available: [one, two]) }
        first.defaultProject = "two"
        #expect(try first.resolveProject(nil, available: [one, two]).id == "two")
        #expect(try first.resolveProject("one", available: [one, two]).id == "one")
        var renamed = second; renamed.name = "one"
        #expect(throws: (any Error).self) { try settings.save(renamed) }
    }
    @Test func oldSingleServerSettingsDoNotCreateNewConnections() throws {
        let input = Data(#"{"enabled":true,"baseURL":"https://old.example","project":"old"}"#.utf8)
        let settings = try JSONDecoder().decode(VexSettings.self, from: input)
        #expect(settings.enabled)
        #expect(settings.servers.isEmpty)
        #expect(settings.defaultServer == nil)
    }
    @Test func tokenCacheInvalidationIsIsolatedByServer() throws {
        let cache = VexTokenCache(), first = URL(string: "https://one.example")!, second = URL(string: "https://two.example")!
        try cache.save("one", baseURL: first, write: {})
        try cache.save("two", baseURL: second, write: {})
        cache.invalidate(baseURL: first)
        #expect(try cache.load(baseURL: first) { "new" } == "new")
        #expect(try cache.load(baseURL: second) { "changed" } == "two")
    }
    private func room(project: String = "example", id: String = "c12345678-fabric", generation: Int = 1, state: VexRoomState, closedAt: String? = nil) -> VexRoom {
        VexRoom(project: project, id: id, kind: "commit", branch: nil, sha: "12345678", loader: "fabric", buildId: "fabric-12345678",
                generation: generation, behindHead: false, host: id + "--" + project + ".vex.example.com", port: 25565, state: state,
                phase: "", label: "testing", node: nil, players: [], idleSince: nil, seed: "empty", seedResolved: nil,
                world: nil, lastSnapshot: nil, lastError: nil, createdAt: "2026-10-17T00:00:00Z", updatedAt: "2026-10-17T00:00:00Z", closedAt: closedAt)
    }
}
