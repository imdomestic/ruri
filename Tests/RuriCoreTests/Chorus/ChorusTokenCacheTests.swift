import Foundation
import Testing
@testable import RuriCore

struct ChorusTokenCacheTests {
    private let firstURL = URL(string: "https://first.chorus.internal")!
    private let secondURL = URL(string: "https://second.chorus.internal")!

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func successfulReadRemainsCachedUntilExplicitInvalidation() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("value")
        let cache = ChorusTokenCache()
        try "original".write(to: file, atomically: true, encoding: .utf8)
        #expect(try cache.load(baseURL: firstURL) { try String(contentsOf: file, encoding: .utf8) } == "original")
        try "changed".write(to: file, atomically: true, encoding: .utf8)
        #expect(try cache.load(baseURL: firstURL) { try String(contentsOf: file, encoding: .utf8) } == "original")
        cache.invalidate(baseURL: firstURL)
        #expect(try cache.load(baseURL: firstURL) { try String(contentsOf: file, encoding: .utf8) } == "changed")
    }

    @Test func failedReadIsCachedUntilExplicitInvalidation() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("missing")
        let cache = ChorusTokenCache()
        #expect(throws: CocoaError.self) { try cache.load(baseURL: firstURL) { try String(contentsOf: file, encoding: .utf8) } }
        try "available".write(to: file, atomically: true, encoding: .utf8)
        #expect(throws: CocoaError.self) { try cache.load(baseURL: firstURL) { try String(contentsOf: file, encoding: .utf8) } }
        cache.invalidate(baseURL: firstURL)
        #expect(try cache.load(baseURL: firstURL) { try String(contentsOf: file, encoding: .utf8) } == "available")
    }

    @Test func successfulSaveReplacesReadFailureWithoutAnotherRead() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("value")
        let cache = ChorusTokenCache()
        #expect(throws: CocoaError.self) { try cache.load(baseURL: firstURL) { try String(contentsOf: file, encoding: .utf8) } }
        try cache.save("saved", baseURL: firstURL) { try "saved".write(to: file, atomically: true, encoding: .utf8) }
        #expect(try String(contentsOf: file, encoding: .utf8) == "saved")
        try FileManager.default.removeItem(at: file)
        #expect(try cache.load(baseURL: firstURL) { try String(contentsOf: file, encoding: .utf8) } == "saved")
    }

    @Test func failedSavePreservesPreviousValue() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("value")
        let cache = ChorusTokenCache()
        try "original".write(to: file, atomically: true, encoding: .utf8)
        _ = try cache.load(baseURL: firstURL) { try String(contentsOf: file, encoding: .utf8) }
        try FileManager.default.removeItem(at: file)
        let invalid = root.appendingPathComponent("absent/value")
        #expect(throws: CocoaError.self) {
            try cache.save("changed", baseURL: firstURL) { try "changed".write(to: invalid, atomically: true, encoding: .utf8) }
        }
        #expect(try cache.load(baseURL: firstURL) { try String(contentsOf: file, encoding: .utf8) } == "original")
    }

    @Test func backendValuesAndInvalidationRemainIndependent() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("first")
        let second = root.appendingPathComponent("second")
        let cache = ChorusTokenCache()
        try "first".write(to: first, atomically: true, encoding: .utf8)
        try "second".write(to: second, atomically: true, encoding: .utf8)
        _ = try cache.load(baseURL: firstURL) { try String(contentsOf: first, encoding: .utf8) }
        _ = try cache.load(baseURL: secondURL) { try String(contentsOf: second, encoding: .utf8) }
        try "updated".write(to: first, atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: second)
        cache.invalidate(baseURL: firstURL)
        #expect(try cache.load(baseURL: firstURL) { try String(contentsOf: first, encoding: .utf8) } == "updated")
        #expect(try cache.load(baseURL: secondURL) { try String(contentsOf: second, encoding: .utf8) } == "second")
    }

    @Test func concurrentFirstReadsConsumeTheFileOnce() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("value")
        try "one file read".write(to: file, atomically: true, encoding: .utf8)
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let cache = ChorusTokenCache()
        try await withThrowingTaskGroup(of: String.self) { tasks in
            for _ in 0..<64 {
                tasks.addTask {
                    try cache.load(baseURL: firstURL) { String(decoding: try handle.readToEnd() ?? Data(), as: UTF8.self) }
                }
            }
            for try await value in tasks { #expect(value == "one file read") }
        }
        #expect(try handle.offset() == UInt64(Data("one file read".utf8).count))
    }

    @Test func concurrentSavesKeepTheCacheConsistentWithTheFile() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("value")
        let cache = ChorusTokenCache()
        try await withThrowingTaskGroup(of: Void.self) { tasks in
            for index in 0..<64 {
                tasks.addTask {
                    let value = "value-\(index)"
                    try cache.save(value, baseURL: firstURL) { try value.write(to: file, atomically: true, encoding: .utf8) }
                }
            }
            try await tasks.waitForAll()
        }
        let saved = try String(contentsOf: file, encoding: .utf8)
        try FileManager.default.removeItem(at: file)
        #expect(try cache.load(baseURL: firstURL) { try String(contentsOf: file, encoding: .utf8) } == saved)
    }

    @Test func changingConnectionPersistsNormalizedURLAndPreservesInstances() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = LauncherPaths(root: root)
        let instance = UUID()
        try ChorusSettings.update(paths: paths) { $0.instances["26.3-fabric"] = instance }
        let configured = try ChorusSettings.configure(paths: paths, baseURL: secondURL.absoluteString + "/")
        #expect(configured.baseURL == secondURL.absoluteString)
        let persisted = try ChorusSettings.load(paths: paths)
        #expect(persisted.baseURL == secondURL.absoluteString)
        #expect(persisted.instances == ["26.3-fabric": instance])
        #expect(throws: (any Error).self) { try ChorusSettings.configure(paths: paths, baseURL: "file:///invalid") }
        #expect(try ChorusSettings.load(paths: paths).baseURL == secondURL.absoluteString)
    }
}
