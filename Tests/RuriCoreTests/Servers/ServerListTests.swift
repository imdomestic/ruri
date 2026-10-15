import Foundation
import Testing
@testable import RuriCore

struct ServerListTests {
    @Test func addressesNormalizeWithoutMergingDifferentHosts() throws {
        #expect(try ServerAddress(" EXAMPLE.test. ").key == ServerAddress("example.test:25565").key)
        #expect(try ServerAddress("[2001:0db8::1]:25566").key == "[2001:db8::1]:25566")
        #expect(try ServerAddress("::1").authority == "[::1]")
        #expect(try ServerAddress("localhost").port == 25565)
        #expect(try ServerAddress("example.test").key != ServerAddress("alias.test").key)
        for invalid in ["", "host:", "host:0", "host:65536", "host:-1", "https://host", "host/path", "a b", "[broken]", "a..b", "host\nname"] {
            #expect(throws: (any Error).self) { try ServerAddress(invalid) }
        }
    }
    @Test func editingPreservesUnknownTagsDuplicatesAndTriState() throws {
        let paths = LauncherPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let instance = GameInstance(name: "Servers", gameVersion: "1.21.1")
        var state = PersistentState(); state.instances = [instance]; try StateStore.save(state, to: paths)
        try paths.prepareInstance(instance.id)
        let helper = WorldTests()
        let unknown = helper.named(11, "modInts", Data([0,0,0,2,0,0,0,1,0,0,0,2]))
        let empty = helper.named(9, "emptyShorts", Data([2,0,0,0,0]))
        let row = helper.named(8, "name", helper.string("Original")) + helper.named(8, "ip", helper.string("example.test")) + unknown + empty + Data([0])
        let rootExtra = helper.named(2, "custom", Data([0,42]))
        let original = Data([10,0,0]) + rootExtra + helper.named(9, "servers", Data([10,0,0,0,2]) + row + row) + Data([0])
        let file = paths.game(instance.id).appendingPathComponent("servers.dat")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try original.write(to: file)
        let manager = ServerListManager(paths: paths, instanceID: instance.id)
        let initial = try manager.snapshot()
        #expect(initial.entries.count == 2 && initial.entries[0].resourcePacks == .ask)
        var result = try manager.apply(.edit(id: 0, name: "World 🐱", address: ServerAddress("other.test"), resourcePacks: .never), to: initial)
        let rewritten = try Data(contentsOf: file)
        #expect(rewritten.range(of: unknown) != nil && rewritten.range(of: empty) != nil && rewritten.range(of: rootExtra) != nil)
        #expect(result.entries[0].name == "World 🐱" && result.entries[0].resourcePacks == .never)
        #expect(result.entries[1].name == "Original")
        #expect(try Data(contentsOf: file.appendingPathExtension("ruri-backup")) == original)
        result = try manager.apply(.move(id: 0, to: 1), to: result)
        #expect(result.entries[0].name == "Original")
        result = try manager.apply(.edit(id: 1, name: "Edited", address: ServerAddress("other.test"), resourcePacks: .ask), to: result)
        #expect(result.entries[1].resourcePacks == .ask)
        #expect(!result.document.entries[1].contains { $0.name == "acceptTextures" })
    }
    @Test func staleSnapshotsCorruptionAndGameLeaseNeverOverwriteList() throws {
        let paths = LauncherPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let instance = GameInstance(name: "Servers", gameVersion: "1.21.1")
        var state = PersistentState(); state.instances = [instance]; try StateStore.save(state, to: paths)
        try paths.prepareInstance(instance.id)
        let manager = ServerListManager(paths: paths, instanceID: instance.id)
        let empty = try manager.snapshot()
        let change = ServerListChange.add(name: "Test", address: try ServerAddress("localhost"), resourcePacks: .ask)
        let current = try manager.apply(change, to: empty)
        #expect(throws: (any Error).self) { try manager.apply(change, to: empty) }
        do {
            let lease = try GameRunLease.acquire(paths: paths, instanceID: instance.id)
            defer { withExtendedLifetime(lease) {} }
            #expect(throws: (any Error).self) { try manager.apply(change, to: current) }
        }
        let file = paths.game(instance.id).appendingPathComponent("servers.dat")
        try Data([1,2,3]).write(to: file)
        #expect(throws: (any Error).self) { try manager.snapshot() }
        #expect(throws: (any Error).self) { try manager.apply(change, to: current) }
        #expect(try Data(contentsOf: file) == Data([1,2,3]))
    }
    @Test func preferencesAreIndependentFromGameEntries() throws {
        let paths = LauncherPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let address = try ServerAddress("example.test")
        let state = try ServerLibrary.save(.init(address: address, favorite: true, alias: "Favorite"), paths: paths)
        let library = try ServerLibrary.load(paths: paths, state: state)
        #expect(library.items.count == 1 && library.items[0].instanceIDs.isEmpty)
        #expect(library.items[0].name == "Favorite")
        #expect(try StateStore.load(paths).servers?.first?.address == address)
    }
    @Test func unpinningKeepsSavedServersAndLegacyFavoritesStaySaved() throws {
        let paths = LauncherPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let address = try ServerAddress("example.test")
        try ServerLibrary.save(.init(address: address, favorite: true, saved: true), paths: paths)
        try ServerLibrary.save(.init(address: address, favorite: false, saved: true), paths: paths)
        #expect(try StateStore.load(paths).servers?.first?.saved == true)
        try ServerLibrary.remove(address, paths: paths)
        #expect(try StateStore.load(paths).servers?.isEmpty == true)
        let legacy = #"{"address":"example.test","favorite":true,"alias":"","notes":""}"#
        let decoded = try JSONDecoder().decode(ServerPreference.self, from: Data(legacy.utf8))
        #expect(decoded.favorite && decoded.saved)
    }
    @Test func sharedDirectoriesHaveOneListAndOneWriterAndRemovedInstancesCannotWrite() throws {
        let base = LauncherPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: base.root) }
        var first = GameInstance(name: "First", gameVersion: "1.20.1"), second = GameInstance(name: "Second", gameVersion: "1.21.1")
        first.runDirectory = .shared; second.runDirectory = .shared
        var state = PersistentState(); state.instances = [first, second]
        state = try StateStore.save(state, to: base)
        let paths = base.configured(with: state), address = try ServerAddress("example.test")
        let manager = ServerListManager(paths: paths, instanceID: first.id)
        let snapshot = try manager.apply(.add(name: "Shared", address: address, resourcePacks: .ask), to: manager.snapshot())
        let library = try ServerLibrary.load(paths: paths, state: state)
        #expect(library.items.count == 1 && Set(library.items[0].instanceIDs) == Set([first.id, second.id]))
        #expect(library.lists[first.id]?.directory == library.lists[second.id]?.directory)
        do {
            let lease = try GameRunLease.acquire(paths: paths, instanceID: second.id)
            defer { withExtendedLifetime(lease) {} }
            #expect(throws: (any Error).self) { try manager.apply(.remove(id: 0), to: snapshot) }
        }
        try StateStore.update(paths) { $0.instances.removeAll { $0.id == first.id } }
        #expect(throws: (any Error).self) { try manager.apply(.remove(id: 0), to: snapshot) }
        #expect(try ServerListManager(paths: paths, instanceID: second.id).snapshot().entries.count == 1)
    }
}
