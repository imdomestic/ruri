import Foundation
import CryptoKit
import Testing
import RuriFeatureRegistration
import ZIPFoundation
@testable import RuriCore
@testable import RuriVex

struct VexFileSafetyTests {
    @MainActor init() { CompiledExperimentalFeatures.register() }

    @Test func identicalContentReusesManagedNamesAndRejectsAnyModifiedDigest() throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.paths.root) }
        let original = try fixture.file("original.jar", bytes: Data("managed content".utf8))
        let userBytes = Data("unmanaged content".utf8)
        try userBytes.write(to: fixture.mods.appendingPathComponent("user.jar"))
        try fixture.receipt([original])
        try VexMRPack.adoptLegacy(instance: fixture.instance, paths: fixture.paths, project: "example")
        let pack = try #require(try ModpackRegistry.load(paths: fixture.paths, instanceID: fixture.instance.id))
        let target = ExperimentalManagedFile(path: "mods/renamed.jar", sha1: try #require(original.sha1), sha256: original.sha256,
                                             sha512: try #require(original.sha512), size: original.size)
        #expect(try ExperimentalInstanceCapabilities.verifyModContent(pack, game: fixture.mods.deletingLastPathComponent(), expected: [target]) == ["mods/original.jar"])
        #expect(try Data(contentsOf: fixture.mods.appendingPathComponent("user.jar")) == userBytes)
        let changedSHA256 = ExperimentalManagedFile(path: target.path, sha1: target.sha1, sha256: String(repeating: "0", count: 64), sha512: target.sha512, size: target.size)
        #expect(throws: (any Error).self) {
            try ExperimentalInstanceCapabilities.verifyModContent(pack, game: fixture.mods.deletingLastPathComponent(), expected: [changedSHA256])
        }
        try Data("user edited content".utf8).write(to: fixture.mods.appendingPathComponent(original.name))
        #expect(throws: (any Error).self) {
            try ExperimentalInstanceCapabilities.verifyModContent(pack, game: fixture.mods.deletingLastPathComponent(), expected: [target])
        }
    }
    @Test func legacyRegistryPreservesUnmanagedFilesAndChecksOriginalHashes() throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.paths.root) }
        let userFile = fixture.mods.appendingPathComponent("user.jar")
        let userBytes = Data("user content".utf8)
        try userBytes.write(to: userFile)
        let first = try fixture.file("first.jar", bytes: Data("first content".utf8))
        try fixture.receipt([first])
        try VexMRPack.adoptLegacy(instance: fixture.instance, paths: fixture.paths, project: "example")
        let baseline = try #require(try ModpackRegistry.load(paths: fixture.paths, instanceID: fixture.instance.id))
        #expect(baseline.version == "fabric-test")
        #expect(baseline.files.map(\.path) == ["mods/first.jar"])
        try VexMRPack.verifyInstalled(baseline, game: fixture.mods.deletingLastPathComponent())
        #expect(try Data(contentsOf: userFile) == userBytes)
        try Data("edited managed content".utf8).write(to: fixture.mods.appendingPathComponent(first.name))
        #expect(throws: (any Error).self) { try VexMRPack.verifyInstalled(baseline, game: fixture.mods.deletingLastPathComponent()) }
    }

    @Test func corruptedLegacyAndWrongProjectCannotCreateRegistry() throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.paths.root) }
        let file = try fixture.file("managed.jar", bytes: Data("managed content".utf8))
        let target = fixture.mods.appendingPathComponent(file.name)
        try fixture.receipt([file])
        #expect(throws: (any Error).self) { try VexMRPack.adoptLegacy(instance: fixture.instance, paths: fixture.paths, project: "different") }
        let edited = Data("user edited managed content".utf8)
        try edited.write(to: target)
        #expect(throws: (any Error).self) { try VexMRPack.adoptLegacy(instance: fixture.instance, paths: fixture.paths, project: "example") }
        #expect(try ModpackRegistry.load(paths: fixture.paths, instanceID: fixture.instance.id) == nil)
        #expect(try Data(contentsOf: target) == edited)
    }

    @Test func realMRPackImportChecksRuntimeAndClientFiles() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.paths.root) }
        let file = try fixture.file("managed.jar", bytes: Data("managed content".utf8))
        let source = fixture.paths.cache.appendingPathComponent("source")
        let bundled = source.appendingPathComponent("overrides/mods")
        try FileManager.default.createDirectory(at: bundled, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixture.mods.appendingPathComponent(file.name), to: bundled.appendingPathComponent(file.name))
        let index = ModpackIndex(formatVersion: 1, game: "minecraft", name: "Vex example", versionId: "main-fabric-g1-fabric-test-a1",
                                dependencies: ["minecraft": "26.3", "fabric-loader": "0.19.5"], files: [])
        try JSONEncoder().encode(index).write(to: source.appendingPathComponent("modrinth.index.json"))
        try Data("excluded server list".utf8).write(to: source.appendingPathComponent("overrides/servers.dat"))
        let archive = fixture.paths.cache.appendingPathComponent("example.mrpack")
        try FileManager.default.zipItem(at: source, to: archive, shouldKeepParent: false)
        let transfer = InstanceTransfer(paths: fixture.paths)
        let prepared = try await transfer.prepare(archive, excludingFiles: ["servers.dat"])
        #expect(!FileManager.default.fileExists(atPath: prepared.game.appendingPathComponent("servers.dat").path))
        try VexMRPack.validate(prepared, build: fixture.build([file]), roomID: "main-fabric", generation: 1)
        #expect(throws: (any Error).self) { try VexMRPack.validate(prepared, build: fixture.build([file]), roomID: "main-fabric", generation: 2) }
        #expect(throws: (any Error).self) { try VexMRPack.validate(prepared, build: fixture.build([file]), roomID: "other-fabric", generation: 1) }
        #expect(throws: (any Error).self) { try VexMRPack.validate(prepared, build: fixture.build([]), roomID: "main-fabric", generation: 1) }
        try Data("modified archive".utf8).write(to: prepared.game.appendingPathComponent("mods/" + file.name))
        #expect(throws: (any Error).self) { try VexMRPack.validate(prepared, build: fixture.build([file]), roomID: "main-fabric", generation: 1) }
        await transfer.discard(prepared)
    }

    @Test func upstreamPlannerPreservesUnmanagedFilesAndIdentifiesConflicts() throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.paths.root) }
        let first = try fixture.file("first.jar", bytes: Data("first content".utf8))
        try fixture.receipt([first])
        try VexMRPack.adoptLegacy(instance: fixture.instance, paths: fixture.paths, project: "example")
        let baseline = try #require(try ModpackRegistry.load(paths: fixture.paths, instanceID: fixture.instance.id))
        let local = try fixture.file("user.jar", bytes: Data("local content".utf8))
        let incoming = InstalledModpack(format: "Modrinth", name: "Example", version: "next", origin: nil, settings: fixture.instance,
                                       files: [.init(path: "mods/user.jar", sha1: String(repeating: "a", count: 40), size: 10, force: false, identities: [])])
        let changes = try ModpackUpdatePlanner.changes(from: baseline, to: incoming, game: fixture.mods.deletingLastPathComponent(), records: [])
        #expect(changes.first(where: { $0.id == "mods/first.jar" })?.action == .remove)
        #expect(changes.first(where: { $0.id == "mods/user.jar" })?.conflict == true)
        #expect(changes.first(where: { $0.id == "mods/user.jar" })?.action == .keep)
        try VexMRPack.verify(fixture.mods.appendingPathComponent(local.name), file: local)
        for file in [first, local] {
            #expect(FileManager.default.fileExists(atPath: fixture.mods.appendingPathComponent(file.name).path))
        }
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
            try JSONEncoder().encode(VexInstanceManager.Marker(key: "file-test", server: "https://vex.example.com", project: "example", room: "main-fabric"))
                .write(to: paths.instance(instance.id).appendingPathComponent("vex-instance.json"))
            mods = paths.configured(with: try StateStore.load(paths)).game(instance.id).appendingPathComponent("mods")
            try FileManager.default.createDirectory(at: mods, withIntermediateDirectories: true)
        }
        func file(_ name: String, bytes: Data) throws -> VexBuild.File {
            let target = mods.appendingPathComponent(name)
            try bytes.write(to: target)
            return .init(name: name, sha1: try InstanceTransfer.sha1(target), sha256: try VexMRPack.digest(target),
                         sha512: SHA512.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
                         size: Int64(bytes.count), side: "both", url: "/v2/projects/example/builds/fabric-test/files/" + name)
        }
        func receipt(_ files: [VexBuild.File]) throws {
            struct Receipt: Encodable { let project: String; let buildID: String; let files: [VexBuild.File] }
            try JSONEncoder().encode(Receipt(project: "example", buildID: "fabric-test", files: files))
                .write(to: mods.appendingPathComponent(".vex-managed.json"))
        }
        func build(_ files: [VexBuild.File]) -> VexBuild {
            .init(project: "example", id: "fabric-test", sha: "test", loader: "fabric", status: .ready, attempt: 1,
                  queuedAt: "2026-10-17T00:00:00Z", startedAt: nil, finishedAt: nil, minecraft: "26.3", loaderVersion: "0.19.5",
                  java: 25, builtAt: nil, durationSec: nil, modIds: [], files: files, log: "", lastError: nil)
        }
    }
}
