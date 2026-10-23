import Foundation
import Testing
import RuriFeatureRegistration
import RuriLocalization
@testable import RuriVex

struct VexDeviceIntegrationTests {
    @MainActor init() { CompiledExperimentalFeatures.register() }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VEX_IT_URL"] != nil && ProcessInfo.processInfo.environment["VEX_DEVICE_EXPIRY_URL"] != nil))
    func realUnapprovedDeviceAuthorizationExpiresWithoutSavingCredentials() async throws {
        let baseURL = try VexSettings.normalizedURL(#require(ProcessInfo.processInfo.environment["VEX_DEVICE_EXPIRY_URL"]))
        let server = try VexServer(baseURL: baseURL, name: "device-expiry-validation")
        let authorization = try await VexAuthentication.beginGitHub(server)
        let deadline = try authorization.deadline()
        do {
            _ = try await VexAuthentication.finishGitHub(server, authorization: authorization)
            Issue.record("An unapproved device authorization unexpectedly succeeded")
        } catch {
            #expect(VexAuthentication.message(for: error) == Messages.VexDevices.expired.localized)
            #expect(Date() >= deadline)
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VEX_IT_URL"] != nil && ProcessInfo.processInfo.environment["VEX_DEVICE_CANCEL_URL"] != nil))
    func realUnapprovedDeviceAuthorizationCanBeCancelled() async throws {
        let baseURL = try VexSettings.normalizedURL(#require(ProcessInfo.processInfo.environment["VEX_DEVICE_CANCEL_URL"]))
        let server = try VexServer(baseURL: baseURL, name: "device-cancellation-validation")
        let authorization = try await VexAuthentication.beginGitHub(server)
        let operation = Task { try await VexAuthentication.finishGitHub(server, authorization: authorization) }
        try await Task.sleep(for: .milliseconds(100))
        operation.cancel()
        do {
            _ = try await operation.value
            Issue.record("A cancelled authorization unexpectedly succeeded")
        } catch {
            #expect(error is CancellationError)
        }
    }
}
