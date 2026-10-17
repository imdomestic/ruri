import Foundation
import Testing
@testable import RuriCore

struct VexFileSafetyTests {
    @Test func cachedSyncPreservesUnmanagedFilesAndRemovesOnlyPreviousManagedFiles() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.paths.root) }
        let userFile = fixture.mods.appendingPathComponent("user.jar")
        let userBytes = Data("user content".utf8)
        try userBytes.write(to: userFile)
        let first = try fixture.file("first.jar", bytes: Data("first content".utf8))
        let second = try fixture.file("second.jar", bytes: Data("second content".utf8))
        let initial = try await fixture.sync.synchronize(fixture.build([first]), instance: fixture.instance)
        #expect(initial.unmanaged == ["user.jar"])
        let updated = try await fixture.sync.synchronize(fixture.build([second]), instance: fixture.instance)
        #expect(updated.files == ["second.jar"])
        #expect(!FileManager.default.fileExists(atPath: fixture.mods.appendingPathComponent("first.jar").path))
        #expect(try Data(contentsOf: userFile) == userBytes)
        #expect(try VexModSync.digest(fixture.mods.appendingPathComponent("second.jar")) == second.sha256)
        let receipt = try JSONDecoder().decode(VexModSync.Receipt.self, from: Data(contentsOf: fixture.mods.appendingPathComponent(".vex-managed.json")))
        #expect(receipt.project == "example")
        #expect(receipt.files == [second])
    }

    @Test func unmanagedCollisionAndEditedManagedFileFailWithoutReplacingFiles() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.paths.root) }
        let file = try fixture.file("managed.jar", bytes: Data("managed content".utf8))
        let target = fixture.mods.appendingPathComponent(file.name)
        let existing = Data("user content".utf8)
        try existing.write(to: target)
        await #expect(throws: (any Error).self) {
            try await fixture.sync.synchronize(fixture.build([file]), instance: fixture.instance)
        }
        #expect(try Data(contentsOf: target) == existing)
        try FileManager.default.removeItem(at: target)
        _ = try await fixture.sync.synchronize(fixture.build([file]), instance: fixture.instance)
        let edited = Data("user edited managed content".utf8)
        try edited.write(to: target)
        await #expect(throws: (any Error).self) {
            try await fixture.sync.synchronize(fixture.build([]), instance: fixture.instance)
        }
        #expect(try Data(contentsOf: target) == edited)
    }

    @Test func corruptedCacheFailsBeforeChangingMods() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.paths.root) }
        let file = try fixture.file("managed.jar", bytes: Data("managed content".utf8))
        try Data("corrupted cache".utf8).write(to: fixture.paths.cache.appendingPathComponent("vex/" + file.sha256 + ".jar"))
        await #expect(throws: (any Error).self) {
            try await fixture.sync.synchronize(fixture.build([file]), instance: fixture.instance)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.mods.path).isEmpty)
    }

    @Test func hiddenServerCleanupPreservesVisibleAndUnrelatedEntries() throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.paths.root) }
        let paths = fixture.paths.configured(with: try StateStore.load(fixture.paths))
        var document = try ServerNBTDocument.empty()
        func entry(_ address: String, hidden: Bool) throws -> [ServerNBTDocument.Field] {
            try [ServerNBTDocument.string("name", "Minecraft Server"), ServerNBTDocument.string("ip", address), ServerNBTDocument.byte("hidden", hidden ? 1 : 0)]
        }
        document.entries = try [entry("room--example.vex.example.com", hidden: true),
                                entry("visible.vex.example.com", hidden: false),
                                entry("unrelated.example.com", hidden: true)]
        let file = paths.game(fixture.instance.id).appendingPathComponent("servers.dat")
        let original = try document.encoded()
        try original.write(to: file)
        var settings = try VexSettings.load(paths: fixture.paths)
        settings.knownZones = ["vex.example.com"]
        try VexServerPolicy.cleanBeforeLaunch(paths: paths, instanceID: fixture.instance.id, settings: settings)
        #expect(try Data(contentsOf: file) == original)
        settings.enabled = true
        let lease = try GameRunLease.acquire(paths: paths, instanceID: fixture.instance.id)
        defer { withExtendedLifetime(lease) {} }
        try VexServerPolicy.cleanBeforeLaunch(paths: paths, instanceID: fixture.instance.id, settings: settings)
        let result = try ServerListManager(paths: paths, instanceID: fixture.instance.id).snapshot()
        #expect(result.entries.map(\.address) == ["visible.vex.example.com", "unrelated.example.com"])
        #expect(try Data(contentsOf: file.appendingPathExtension("ruri-backup")) == original)
    }

    private struct Fixture {
        let paths: LauncherPaths
        let instance: GameInstance
        let mods: URL
        let sync: VexModSync
        init() throws {
            paths = LauncherPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
            var instance = GameInstance(name: "Vex files", gameVersion: "26.3", loader: .fabric, loaderVersion: "0.19.5")
            instance.runDirectory = .isolated
            self.instance = instance
            var state = PersistentState()
            state.instances = [instance]
            try StateStore.save(state, to: paths)
            try paths.prepareInstance(instance.id)
            try VexSettings.update(paths: paths) { $0.instances["file-test"] = instance.id }
            try JSONEncoder().encode(VexInstanceManager.Marker(key: "file-test")).write(to: paths.instance(instance.id).appendingPathComponent("vex-instance.json"))
            mods = paths.configured(with: try StateStore.load(paths)).game(instance.id).appendingPathComponent("mods")
            try FileManager.default.createDirectory(at: mods, withIntermediateDirectories: true)
            let client = try VexClient(baseURL: URL(string: "https://vex.example.com")!, token: "unused", project: "example")
            sync = VexModSync(paths: paths, client: client)
        }
        func file(_ name: String, bytes: Data) throws -> VexBuild.File {
            let cache = paths.cache.appendingPathComponent("vex")
            try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            let stage = cache.appendingPathComponent(UUID().uuidString)
            try bytes.write(to: stage)
            let digest = try VexModSync.digest(stage)
            try FileManager.default.moveItem(at: stage, to: cache.appendingPathComponent(digest + ".jar"))
            return .init(name: name, sha1: nil, sha256: digest, sha512: nil, size: Int64(bytes.count), side: "both", url: "/v2/projects/example/builds/fabric-test/files/" + name)
        }
        func build(_ files: [VexBuild.File]) -> VexBuild {
            .init(project: "example", id: "fabric-test", sha: "test", loader: "fabric", status: .ready, attempt: 1,
                  queuedAt: "2026-10-17T00:00:00Z", startedAt: nil, finishedAt: nil, minecraft: "26.3", loaderVersion: "0.19.5",
                  java: 25, builtAt: nil, durationSec: nil, modIds: [], files: files, log: "", lastError: nil)
        }
    }
}
