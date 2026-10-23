import Foundation
import Testing
import RuriFeatureRegistration
@testable import RuriCore
@testable import RuriVex

struct VexLeaseIntegrationTests {
    @MainActor init() { CompiledExperimentalFeatures.register() }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VEX_IT_URL"] != nil && ProcessInfo.processInfo.environment["VEX_IT_LEASE_ROOM"] != nil))
    func cancelledRenewalRetainsItsReceiptForRelease() async throws {
        let environment = ProcessInfo.processInfo.environment
        let baseURL = try VexSettings.normalizedURL(#require(environment["VEX_IT_URL"]))
        let tokenFile = URL(fileURLWithPath: try #require(environment["VEX_IT_TOKEN_FILE"]))
        let token = try String(contentsOf: tokenFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        let project = try #require(environment["VEX_IT_LEASE_PROJECT"])
        let roomID = try #require(environment["VEX_IT_LEASE_ROOM"])
        let client = try VexClient(baseURL: baseURL, token: token, project: project)
        let leases = VexJoinLeases(client: client, roomID: roomID)
        var issued: [VexLease] = []
        var pending: Task<VexStartResult, Error>?
        do {
            issued.append(try await leases.issue(reopen: true).lease)
            let renewal = Task { try await leases.issue() }
            pending = renewal
            let deadline = ContinuousClock.now + .seconds(10)
            while await client.session.allTasks.isEmpty {
                try #require(ContinuousClock.now < deadline, "Actual renewal request did not become observable")
                await Task.yield()
            }
            renewal.cancel()
            issued.append(try await renewal.value.lease)
            #expect(renewal.isCancelled)
            #expect(issued[0].id != issued[1].id)
            #expect(issued[0].generation == issued[1].generation)
        } catch {
            pending?.cancel()
            if let pending { _ = await pending.result }
            try await leases.release()
            throw error
        }
        try await leases.release()
        struct Evidence: Encodable {
            let project: String
            let room: String
            let released: [VexLease]
        }
        let evidence = URL(fileURLWithPath: try #require(environment["VEX_IT_LEASE_EVIDENCE"]))
        try JSONEncoder().encode(Evidence(project: project, room: roomID, released: issued)).write(to: evidence, options: .atomic)
    }
}
