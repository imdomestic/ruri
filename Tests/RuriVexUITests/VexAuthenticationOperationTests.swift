import Foundation
import Testing
import RuriCore
import RuriFeatureRegistration
import RuriVex
@testable import RuriVexUI

@MainActor struct VexAuthenticationOperationTests {
    init() { CompiledExperimentalFeatures.register() }

    private func configuredPresentation(paths: LauncherPaths) -> VexPresentation {
        let presentation = VexPresentation()
        var settings = VexSettings()
        settings.enabled = true
        presentation.configure(settings: settings, paths: paths)
        return presentation
    }

    private func wait(until condition: () -> Bool, seconds: Int = 2) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(seconds))
        while !condition() && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition())
    }

    @Test func stoppedAuthenticationRequiresReconfiguration() async throws {
        let paths = LauncherPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let presentation = configuredPresentation(paths: paths)
        let owner = UUID()
        var executed = false
        #expect(presentation.startAuthentication(owner: owner) { _ in executed = true })
        presentation.stop()
        await Task.yield()
        #expect(!executed)
        #expect(!presentation.startAuthentication(owner: owner) { _ in executed = true })
        presentation.configure(settings: presentation.settings, paths: paths)
        #expect(presentation.startAuthentication(owner: owner) { _ in executed = true })
        try await wait(until: { executed })
        presentation.stop()
        #expect(!FileManager.default.fileExists(atPath: paths.root.path))
    }

    @Test(arguments: [false, true])
    func previousAuthenticationCannotAffectReplacement(reuseOwner: Bool) async throws {
        let paths = LauncherPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let presentation = configuredPresentation(paths: paths)
        defer { presentation.stop() }
        let owner = UUID()
        let replacementOwner = reuseOwner ? owner : UUID()
        let first = AsyncStream<Void>.makeStream()
        let second = AsyncStream<Void>.makeStream()
        var firstID: UUID?
        var secondID: UUID?
        var firstCompleted = false
        var staleUpdate = false
        #expect(presentation.startAuthentication(owner: owner) { id in
            firstID = id
            for await _ in first.stream { break }
            staleUpdate = presentation.ownsAuthentication(owner: owner, operation: id)
            firstCompleted = true
        })
        try await wait(until: { firstID != nil })
        #expect(!presentation.startAuthentication(owner: owner) { _ in Issue.record("重复启动认证操作") })
        if reuseOwner { presentation.cancelAuthentication(owner: owner) }
        #expect(presentation.startAuthentication(owner: replacementOwner) { id in
            secondID = id
            for await _ in second.stream { break }
        })
        try await wait(until: { firstCompleted && secondID != nil })
        if !reuseOwner { presentation.cancelAuthentication(owner: owner) }
        #expect(!staleUpdate)
        #expect(!presentation.ownsAuthentication(owner: owner, operation: try #require(firstID)))
        #expect(presentation.ownsAuthentication(owner: replacementOwner, operation: try #require(secondID)))
        presentation.cancelAuthentication(owner: replacementOwner)
        first.continuation.finish()
        second.continuation.finish()
        #expect(!presentation.ownsAuthentication(owner: replacementOwner, operation: try #require(secondID)))
        #expect(!FileManager.default.fileExists(atPath: paths.root.path))
    }

    enum Cancellation: String, CaseIterable, Sendable {
        case stop, disable, closeForm
    }

    @Test(.serialized, .enabled(if: ProcessInfo.processInfo.environment["VEX_IT_URL"] != nil),
          arguments: Cancellation.allCases)
    func cancelledRealServerAdditionPreservesSettings(cancellation: Cancellation) async throws {
        let url = try VexSettings.normalizedURL(#require(ProcessInfo.processInfo.environment["VEX_IT_URL"]))
        let meta = try await VexClient(baseURL: url).meta()
        #expect(!meta.name.isEmpty)
        let paths = LauncherPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        try VexSettings.update(paths: paths) { $0.enabled = true }
        defer { try! FileManager.default.removeItem(at: paths.root) }
        let before = try Data(contentsOf: paths.state)
        let presentation = configuredPresentation(paths: paths)
        defer { presentation.stop() }
        let owner = UUID()
        let started = AsyncStream<Void>.makeStream()
        var completed = false
        var cancelled = false
        var failure: (any Error)?
        try #require(presentation.startAuthentication(owner: owner) { id in
            defer { completed = true }
            started.continuation.yield(())
            started.continuation.finish()
            do {
                _ = try await VexAuthentication.add(url.absoluteString, paths: paths)
                Issue.record("取消后的服务器添加操作返回成功")
            } catch {
                cancelled = error is CancellationError || (error as? URLError)?.code == .cancelled
                if !cancelled { failure = error }
            }
        })
        for await _ in started.stream { break }
        switch cancellation {
        case .stop: presentation.stop()
        case .disable: presentation.configure(settings: VexSettings(), paths: paths)
        case .closeForm: presentation.cancelAuthentication(owner: owner)
        }
        try await wait(until: { completed })
        if let failure { throw failure }
        #expect(cancelled)
        #expect(try Data(contentsOf: paths.state) == before)
        #expect(try VexSettings.load(paths: paths).servers.isEmpty)
    }

    @Test(.serialized, .enabled(if: ProcessInfo.processInfo.environment["VEX_IT_URL"] != nil
                              && ProcessInfo.processInfo.environment["VEX_DEVICE_CANCEL_URL"] != nil),
          arguments: Cancellation.allCases)
    func realPendingAuthenticationStops(cancellation: Cancellation) async throws {
        let url = try VexSettings.normalizedURL(#require(ProcessInfo.processInfo.environment["VEX_DEVICE_CANCEL_URL"]))
        let server = try VexServer(baseURL: url, name: "presentation-cancellation")
        let client = try VexClient(baseURL: url)
        let authorization = try await VexAuthentication.beginGitHub(server)
        let cancellationBody = try JSONEncoder().encode(["handle": authorization.handle])
        let paths = LauncherPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let presentation = configuredPresentation(paths: paths)
        let owner = UUID()
        var pending = false
        var completed = false
        var cancelled = false
        var operationID: UUID?
        var operationFailure: (any Error)?
        var testFailure: (any Error)?
        do {
            try #require(presentation.startAuthentication(owner: owner) { id in
                operationID = id
                defer { completed = true }
                do {
                    try await Task.sleep(for: .seconds(authorization.interval))
                    let response = try await client.pollDevice(handle: authorization.handle, client: "ruri cancellation test")
                    try Task.checkCancellation()
                    guard presentation.ownsAuthentication(owner: owner, operation: id) else { throw CancellationError() }
                    guard case .pending = response else {
                        Issue.record("未批准的真实设备授权返回了会话")
                        return
                    }
                    pending = true
                    _ = try await VexAuthentication.finishGitHub(server, authorization: authorization)
                    Issue.record("取消后的认证操作返回成功")
                } catch {
                    cancelled = error is CancellationError || (error as? URLError)?.code == .cancelled
                    if !cancelled { operationFailure = error }
                }
            })
            try await wait(until: { pending || completed }, seconds: 90)
            if let operationFailure { throw operationFailure }
            try #require(pending)
            switch cancellation {
            case .stop: presentation.stop()
            case .disable: presentation.configure(settings: VexSettings(), paths: paths)
            case .closeForm: presentation.cancelAuthentication(owner: owner)
            }
            try await wait(until: { completed })
            #expect(cancelled)
            #expect(!presentation.ownsAuthentication(owner: owner, operation: try #require(operationID)))
            #expect(presentation.settings.servers.isEmpty)
            #expect(!FileManager.default.fileExists(atPath: paths.root.path))
        } catch { testFailure = error }
        presentation.stop()
        _ = try await client.data("/v2/auth/device/cancel", method: "POST", body: cancellationBody)
        do {
            _ = try await client.pollDevice(handle: authorization.handle, client: "ruri cancellation test")
            Issue.record("取消后的真实设备授权仍然存在")
        } catch let error as VexHTTPError {
            #expect(error.status == 400)
            #expect(error.api?.code == "expired_token")
        }
        if let testFailure { throw testFailure }
    }
}
