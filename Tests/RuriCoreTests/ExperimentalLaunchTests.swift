import Foundation
import Testing
@testable import RuriCore

@MainActor struct ExperimentalLaunchTests {
    @Test func cancellationStopsBeforeAccountOrGameAccess() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = ExperimentalLaunchCapabilities(paths: LauncherPaths(root: root))
        let operation = service.begin(instanceID: UUID(), address: try ServerAddress("localhost:25565"))
        service.cancel(operation)
        await #expect(throws: CancellationError.self) { try await operation.result() }
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }

    @Test func sessionQueriesUseRealHistoryAndRejectDifferentInstance() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = LauncherPaths(root: root)
        let instance = GameInstance(name: "实验功能会话查询", gameVersion: "26.3")
        try paths.prepare()
        let recorder = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline")
        try recorder.fail(CancellationError(), cancelled: true)
        let service = ExperimentalLaunchCapabilities(paths: paths)
        #expect(try service.session(instanceID: instance.id, sessionID: recorder.record.id).id == recorder.record.id)
        #expect(try service.sessions(instanceID: instance.id).contains { $0.id == recorder.record.id })
        #expect(throws: (any Error).self) { try service.session(instanceID: UUID(), sessionID: recorder.record.id) }
    }

    @Test func configurationAndInstanceCapabilitiesPreserveUnrelatedState() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = LauncherPaths(root: root)
        let instance = GameInstance(name: "实验功能实例", gameVersion: "26.3")
        try paths.prepare()
        try StateStore.updateIfChanged(paths) { $0.instances.append(instance) }
        let first = ExperimentalConfigurationStore(paths: paths, feature: "first")
        let second = ExperimentalConfigurationStore(paths: paths, feature: "second")
        try first.update(default: [String: Bool]()) { $0["enabled"] = true }
        try second.update(default: [String: Bool]()) { $0["enabled"] = false }
        #expect(try first.load(as: [String: Bool].self)?["enabled"] == true)
        #expect(try second.load(as: [String: Bool].self)?["enabled"] == false)
        let service = ExperimentalInstanceCapabilities(paths: paths)
        #expect(try service.instance(id: instance.id).name == instance.name)
        #expect(try service.setJavaMajor(25, instanceID: instance.id).javaMajor == 25)
        #expect(try service.context().accountAvailable == false)
        #expect(throws: (any Error).self) { try service.setJavaMajor(25, instanceID: UUID()) }
        #expect(try first.load(as: [String: Bool].self)?["enabled"] == true)
        #expect(try StateStore.load(paths).instances.count == 1)
    }
}
