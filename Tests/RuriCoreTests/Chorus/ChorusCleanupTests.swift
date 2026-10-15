import Foundation
import Testing
@testable import RuriCore
@testable import RuriMonitorRuntime

struct ChorusCleanupTests {
    private func settings(_ managed: UUID = UUID()) -> ChorusSettings {
        var settings = ChorusSettings()
        settings.instances = ["26.3/fabric/0.19.5": managed]
        settings.knownZones = ["Chorus.Internal.:25565"]
        return settings
    }

    @Test func zoneMatchingUsesNormalizedDNSLabels() throws {
        let policy = try ChorusServerPolicy(settings: settings())
        for host in ["MAIN.CHORUS.INTERNAL.:25565", "chorus.internal", "room.main.chorus.internal:25566", "main.100-64-0-43.sslip.io"] {
            #expect(try policy.contains(ServerAddress(host)))
        }
        for host in ["notchorus.internal", "chorus.internal.example.org", "other.sslip.io", "127.0.0.1:25565"] {
            #expect(try !policy.contains(ServerAddress(host)))
        }
    }

    @Test func associationFilterIncludesHistoryAndPreferredInstance() throws {
        let managed = UUID(), ordinary = UUID(), policy = try ChorusServerPolicy(settings: settings(managed))
        var item = ServerLibraryItem(address: try ServerAddress("example.org"), name: "Saved", instanceIDs: [], icon: nil)
        #expect(!policy.hides(item))
        item.playedInstanceIDs = [managed]
        #expect(policy.hides(item))
        item.instanceIDs = [ordinary]
        #expect(!policy.hides(item))
        item.instanceIDs = []
        item.preference = .init(address: item.address, preferredInstanceID: ordinary)
        #expect(!policy.hides(item))
        item.preference = .init(address: item.address, preferredInstanceID: managed)
        #expect(policy.hides(item))
    }

    @Test func oldSettingsDecodeAndKeepEveryObservedZone() throws {
        let paths = try temporaryPaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let old = Data(#"{"baseURL":"http://encore.inner.imdomestic.com:8790","instances":{}}"#.utf8)
        try paths.prepare()
        try old.write(to: paths.root.appendingPathComponent("chorus.json"))
        #expect(try ChorusSettings.load(paths: paths).knownZones == [ChorusServerPolicy.legacyZone])
        try ChorusSettings.remember(zone: "CHORUS.INTERNAL.", paths: paths)
        let updated = try ChorusSettings.remember(zone: "new.chorus.internal", paths: paths)
        #expect(Set(updated.knownZones) == [ChorusServerPolicy.legacyZone, "chorus.internal", "new.chorus.internal"])
        #expect(try ChorusSettings.load(paths: paths).knownZones == updated.knownZones)
    }

    @Test func recentRoomsUseClosedAtAndLimitToTen() throws {
        let now = Date(timeIntervalSince1970: 1_792_092_000)
        func room(_ id: String, kind: String = "commit", state: ChorusRoomState = .closed, date: Date?) -> ChorusRoom {
            var value = ChorusRoom(id: id, kind: kind, branch: nil, sha: "fc16eaac252bc8404e99a2368fecd768d31c8067", loader: "fabric",
                buildId: "fabric-fc16eaac252b", generation: 1, behindHead: false, host: id + ".chorus.internal", port: 25565,
                state: state, phase: "", label: "testing", node: nil, players: [], idleSince: nil, seed: "empty", seedResolved: nil,
                asset: nil, lastSnapshot: nil, lastError: nil, createdAt: now.ISO8601Format(), updatedAt: now.ISO8601Format())
            value.closedAt = date?.ISO8601Format(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
            return value
        }
        let candidates = (0..<12).map { room("commit-\($0)", date: now.addingTimeInterval(Double(-$0 * 60))) }
        let excluded = [room("old", date: now.addingTimeInterval(-8 * 86400)), room("missing", date: nil),
                        room("branch", kind: "branch", date: now), room("running", state: .ready, date: now), room("future", date: now.addingTimeInterval(60))]
        let result = try ChorusServerPolicy.recentlyClosed(candidates + excluded, now: now)
        #expect(result.map(\.id) == (0..<10).map { "commit-\($0)" })
        var secondsOnly = candidates[0]
        secondsOnly.closedAt = now.ISO8601Format()
        #expect(try ChorusServerPolicy.recentlyClosed([secondsOnly], now: now).count == 1)
    }

    @Test func diskWarningOnlyUsesMeasuredEncoreAvailableBytes() {
        func node(_ name: String, _ bytes: Int64?) -> ChorusNode {
            .init(name: name, ready: true, schedulable: true, maxRunning: 2, rooms: [], rootFreeBytes: bytes)
        }
        #expect(node("encore", ChorusNode.diskWarningThreshold - 1).hasLowDiskSpace)
        #expect(!node("encore", ChorusNode.diskWarningThreshold).hasLowDiskSpace)
        #expect(!node("encore", nil).hasLowDiskSpace)
        #expect(!node("seraph", 1).hasLowDiskSpace)
    }

    @Test @MainActor func recordedServersCleanUnderLaunchLeaseAndPreserveOtherFields() throws {
        let paths = try temporaryPaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let instance = GameInstance(name: "Chorus recorded servers", gameVersion: "26.3")
        var state = PersistentState(); state.instances = [instance]
        state = try StateStore.save(state, to: paths)
        try paths.prepareInstance(instance.id)
        let fixture = try #require(Bundle.module.url(forResource: "servers", withExtension: "dat", subdirectory: "Fixtures"))
        let source = try Data(contentsOf: fixture)
        let file = paths.game(instance.id).appendingPathComponent("servers.dat")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try source.write(to: file)
        let manager = ServerListManager(paths: paths, instanceID: instance.id)
        let recorded = try manager.snapshot()
        #expect(recorded.entries.count == 5)
        #expect(recorded.entries.allSatisfy { $0.hidden })
        // 通过现有文件管理组件加入真实普通服务器条目，覆盖保留行为。
        let personal = try manager.apply(.add(name: "Personal 🐱", address: ServerAddress("play.example.org"), resourcePacks: .ask), to: recorded)
        let before = try manager.apply(.add(name: "Saved Chorus", address: ServerAddress("main-fabric.chorus.internal"), resourcePacks: .ask), to: personal)
        let original = try Data(contentsOf: file)
        let chorus = settings(instance.id)
        try ChorusSettings.update(paths: paths) { $0 = chorus }
        let library = try ServerLibrary.load(paths: paths, state: state)
        #expect(library.items.isEmpty)
        #expect(library.lists[instance.id]?.entries.count == 7)
        let recorder = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "microsoft")
        defer { try? recorder.close() }
        #expect(try recorder.prepareChorusServers(settings: chorus, state: state) == 5)
        let after = try manager.snapshot()
        #expect(after.entries.map(\.address) == ["play.example.org", "main-fabric.chorus.internal"])
        #expect(after.document.entries[0].map(\.encoded) == before.document.entries[5].map(\.encoded))
        #expect(after.document.entries[1].map(\.encoded) == before.document.entries[6].map(\.encoded))
        #expect(after.document.root.filter { $0.name != "servers" }.map(\.encoded) == before.document.root.filter { $0.name != "servers" }.map(\.encoded))
        #expect(try Data(contentsOf: file.appendingPathExtension("ruri-backup")) == original)
        #expect(try recorder.prepareChorusServers(settings: chorus, state: state) == 0)
        try recorder.close()
        #expect(throws: (any Error).self) { try recorder.prepareChorusServers(settings: chorus, state: state) }
    }

    @Test @MainActor func unmanagedAndSharedDirectoriesRemainUnchanged() throws {
        let paths = try temporaryPaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        var first = GameInstance(name: "Shared Chorus", gameVersion: "26.3")
        var second = GameInstance(name: "Personal", gameVersion: "26.3")
        first.runDirectory = .shared; second.runDirectory = .shared
        var state = PersistentState(); state.instances = [first, second]
        state = try StateStore.save(state, to: paths)
        let configured = paths.configured(with: state)
        try configured.prepareInstance(first.id)
        let fixture = try #require(Bundle.module.url(forResource: "servers", withExtension: "dat", subdirectory: "Fixtures"))
        let source = try Data(contentsOf: fixture)
        let file = configured.game(first.id).appendingPathComponent("servers.dat")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try source.write(to: file)
        let recorder = try GameSessionRecorder(paths: configured, instance: first, accountMode: "microsoft")
        defer { try? recorder.close() }
        #expect(try recorder.prepareChorusServers(settings: settings(), state: state) == 0)
        #expect(throws: (any Error).self) { try recorder.prepareChorusServers(settings: settings(first.id), state: state) }
        #expect(try Data(contentsOf: file) == source)
    }

    @Test @MainActor func cleanupPlanSurvivesMonitorHandoffAndPreservesTheCurrentFile() throws {
        let paths = try temporaryPaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let instance = GameInstance(name: "Chorus monitor cleanup", gameVersion: "26.3")
        var state = PersistentState(); state.instances = [instance]
        state = try StateStore.save(state, to: paths)
        try paths.prepareInstance(instance.id)
        let fixture = try #require(Bundle.module.url(forResource: "servers", withExtension: "dat", subdirectory: "Fixtures"))
        let source = try Data(contentsOf: fixture)
        let directory = paths.game(instance.id), file = directory.appendingPathComponent("servers.dat")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try source.write(to: file)
        let preparation = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "microsoft")
        let chorus = settings(instance.id)
        #expect(try preparation.prepareChorusServers(settings: chorus, state: state) == 5)
        var plan = LaunchPlan(executable: URL(fileURLWithPath: "/usr/bin/java"), arguments: [], directory: directory, environment: [:])
        plan.chorusServerCleanup = try preparation.chorusServerCleanup(settings: chorus, state: state)
        let transferred = try JSONDecoder().decode(LaunchPlan.self, from: JSONEncoder().encode(plan))
        let identity = try #require(ProcessIdentity.read(ProcessInfo.processInfo.processIdentifier))
        try preparation.handoff(to: identity)
        let monitor = try MonitorSessionRecorder(resuming: preparation.record.id, instanceID: instance.id,
                                                 paths: SessionLocationSnapshot(paths: paths, instanceID: instance.id), monitor: identity)
        defer { try? monitor.fail(CancellationError(), cancelled: true) }
        #expect(GameRunLease.isHeld(paths: paths, instanceID: instance.id))
        // 游戏目录可以新增内容；退出清理始终重新读取当前真实文件。
        try source.write(to: file)
        let manager = ServerListManager(paths: paths, instanceID: instance.id)
        let current = try manager.snapshot()
        var document = current.document
        document.entries = [current.document.entries[0]]
        try document.encoded().write(to: file)
        let beforeExit = try Data(contentsOf: file)
        let cleanup = try #require(transferred.chorusServerCleanup)
        #expect(try cleanup.clean(directory: transferred.directory) == 1)
        #expect(try manager.snapshot().entries.isEmpty)
        #expect(try Data(contentsOf: file.appendingPathExtension("ruri-backup")) == beforeExit)
        #expect(GameRunLease.isHeld(paths: paths, instanceID: instance.id))
        #expect(try cleanup.clean(directory: transferred.directory) == 0)
        try monitor.fail(CancellationError(), cancelled: true)
        #expect(!GameRunLease.isHeld(paths: paths, instanceID: instance.id))
    }

    @Test func cleanupRejectsAnExternalServerFile() throws {
        let paths = try temporaryPaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let directory = paths.root.appendingPathComponent("game")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fixture = try #require(Bundle.module.url(forResource: "servers", withExtension: "dat", subdirectory: "Fixtures"))
        let original = try Data(contentsOf: fixture)
        let outside = paths.root.appendingPathComponent("outside.dat")
        try original.write(to: outside)
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("servers.dat"), withDestinationURL: outside)
        let cleanup = try ChorusServerCleanupPlan(zones: ["chorus.internal", ChorusServerPolicy.legacyZone], directory: directory)
        #expect(throws: (any Error).self) { try cleanup.clean(directory: directory) }
        #expect(try Data(contentsOf: outside) == original)
    }

    @Test(arguments: [false, true]) func cleanupRejectsReplacedOrRedirectedGameDirectory(symlink: Bool) throws {
        let paths = try temporaryPaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let directory = paths.root.appendingPathComponent("game")
        let other = paths.root.appendingPathComponent("personal-instance")
        let retained = paths.root.appendingPathComponent("retained-game")
        for url in [directory, other] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        let fixture = try #require(Bundle.module.url(forResource: "servers", withExtension: "dat", subdirectory: "Fixtures"))
        let source = try Data(contentsOf: fixture)
        for url in [directory, other] { try source.write(to: url.appendingPathComponent("servers.dat")) }
        let cleanup = try ChorusServerCleanupPlan(zones: ["chorus.internal", ChorusServerPolicy.legacyZone], directory: directory)
        try FileManager.default.moveItem(at: directory, to: retained)
        if symlink { try FileManager.default.createSymbolicLink(at: directory, withDestinationURL: other) }
        else {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try source.write(to: directory.appendingPathComponent("servers.dat"))
        }
        #expect(throws: (any Error).self) { try cleanup.clean(directory: directory) }
        for url in [directory, other, retained] {
            #expect(try Data(contentsOf: url.appendingPathComponent("servers.dat")) == source)
            #expect(!FileManager.default.fileExists(atPath: url.appendingPathComponent("servers.dat.ruri-backup").path))
        }
    }

    private func temporaryPaths() throws -> LauncherPaths {
        let root = try #require(ProcessInfo.processInfo.environment["TMPDIR"])
        return LauncherPaths(root: URL(fileURLWithPath: root).appendingPathComponent("chorus-cleanup-" + UUID().uuidString))
    }
}

@Suite(.enabled(if: ProcessInfo.processInfo.environment["CHORUS_IT_DATA_DIR"] != nil))
struct ChorusRealLibraryTests {
    @Test func realInstanceFilteringPreservesHistoryAndServerFiles() throws {
        let root = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["CHORUS_IT_DATA_DIR"]))
        try #require(root.lastPathComponent == "Ruri Chorus")
        let base = LauncherPaths(root: root), state = try StateStore.load(base)
        let paths = base.configured(with: state), settings = try ChorusSettings.load(paths: base)
        let policy = try ChorusServerPolicy(settings: settings)
        var original: [UUID: Data] = [:]
        for id in policy.managedInstanceIDs {
            let file = paths.game(id).appendingPathComponent("servers.dat")
            if FileManager.default.fileExists(atPath: file.path) { original[id] = try Data(contentsOf: file) }
        }
        let before = try GameActivityStore.servers(paths: paths)
        let library = try ServerLibrary.load(paths: paths, state: state)
        let after = try GameActivityStore.servers(paths: paths)
        #expect(library.items.allSatisfy { !policy.hides($0) })
        #expect(Set(library.history.keys) == Set(before.map(\.id)))
        #expect(before.map(\.id) == after.map(\.id))
        #expect(before.map(\.visits) == after.map(\.visits))
        #expect(before.map(\.seconds) == after.map(\.seconds))
        #expect(before.map(\.lastPlayed) == after.map(\.lastPlayed))
        for (id, data) in original {
            #expect(try Data(contentsOf: paths.game(id).appendingPathComponent("servers.dat")) == data)
        }
    }
}
