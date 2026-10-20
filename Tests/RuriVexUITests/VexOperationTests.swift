import Foundation
import Testing
import RuriCore
import RuriVex
@testable import RuriVexUI

@MainActor struct VexOperationTests {
    @Test func cancelledViewRequestsPreserveConnectionAvailability() throws {
        let connection = VexServerConnection(try VexServer(baseURL: URL(string: "https://vex.example.com")!, name: "example"))
        connection.status = .loggedIn
        connection.record(CancellationError())
        connection.record(URLError(.cancelled))
        #expect(connection.status == .loggedIn)
        #expect(connection.error == nil)
        connection.record(URLError(.cannotConnectToHost))
        #expect(connection.status == .unreachable)
        #expect(connection.error != nil)
    }
    @Test func cancellationBeforeSchedulingDoesNotRunOperation() async {
        let operation = VexOperation()
        var executed = false
        #expect(operation.start { _ in executed = true })
        operation.cancel()
        await Task.yield()
        #expect(!executed)
        #expect(!operation.isRunning)
    }

    @Test func oldCompletionCannotReleaseReplacementOperation() async throws {
        let operation = VexOperation()
        let first = AsyncStream<Void>.makeStream()
        let second = AsyncStream<Void>.makeStream()
        var oldID: UUID?
        var newID: UUID?
        var firstCompleted = false
        #expect(operation.start { id in
            oldID = id
            for await _ in first.stream { break }
            firstCompleted = true
        })
        while oldID == nil { await Task.yield() }
        operation.cancel()
        #expect(operation.start { id in
            newID = id
            for await _ in second.stream { break }
        })
        while newID == nil { await Task.yield() }
        first.continuation.finish()
        while !firstCompleted { await Task.yield() }
        #expect(operation.isRunning)
        #expect(operation.owns(try #require(newID)))
        #expect(!operation.owns(try #require(oldID)))
        #expect(!operation.start { _ in Issue.record("An active operation accepted another start") })
        operation.cancel()
        second.continuation.finish()
        #expect(!operation.isRunning)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VEX_IT_URL"] != nil))
    func realMetadataProbeCannotRestartAfterDisable() async throws {
        let url = try VexSettings.normalizedURL(#require(ProcessInfo.processInfo.environment["VEX_IT_URL"]))
        let connection = VexServerConnection(try VexServer(baseURL: url, name: "metadata-probe"))
        let paths = LauncherPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        connection.testConnection(paths: paths)
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while connection.meta == nil && connection.error == nil && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(connection.error == nil)
        #expect(connection.meta?.name.isEmpty == false)
        connection.meta = nil
        connection.testConnection(paths: paths)
        await Task.yield()
        connection.stop()
        try await Task.sleep(for: .seconds(1))
        #expect(connection.meta == nil)
        #expect(connection.status == .loggedOut)
        #expect(connection.eventConnection == .idle)
        #expect(connection.projects.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: paths.root.path))
    }
}
