import Foundation
import Testing
import RuriFeatureRegistration
@testable import RuriCore
@testable import RuriVex

struct VexIntegrationTests {
    @MainActor init() { CompiledExperimentalFeatures.register() }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VEX_IT_URL"] != nil))
    func realPublicMetadataDescribesInvitationLogin() async throws {
        let baseURL = try VexSettings.normalizedURL(#require(ProcessInfo.processInfo.environment["VEX_IT_URL"]))
        let meta = try await VexClient(baseURL: baseURL).meta()
        #expect(!meta.name.isEmpty)
        #expect(meta.auth.methods.contains("invite"))
        #expect(meta.zone == nil)
        #expect(meta.publicBaseURL == nil)
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VEX_IT_URL"] != nil && ProcessInfo.processInfo.environment["VEX_IT_SECOND_URL"] != nil))
    func realServersKeepIndependentOriginsAndStreams() async throws {
        let environment = ProcessInfo.processInfo.environment
        var identifiers: Set<String> = []
        for prefix in ["VEX_IT", "VEX_IT_SECOND"] {
            let baseURL = try VexSettings.normalizedURL(#require(environment[prefix + "_URL"]))
            let tokenFile = URL(fileURLWithPath: try #require(environment[prefix + "_TOKEN_FILE"]))
            let token = try String(contentsOf: tokenFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
            let client = try VexClient(baseURL: baseURL, token: token)
            let user = try await client.me(), projects = try await client.projects()
            #expect(!user.id.isEmpty)
            #expect(!projects.isEmpty)
            for project in projects {
                identifiers.insert(VexInstanceManager.key(server: baseURL, project: project.id, minecraft: "26.3", loader: "fabric", version: "0.19.5"))
            }
            for try await event in VexEventStream(client: client).events() {
                guard case .sync(let sync) = event else { Issue.record("Expected initial sync"); break }
                #expect(sync.rooms.allSatisfy { room in projects.contains { $0.id == room.project } })
                break
            }
        }
        #expect(identifiers.count >= 2)
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VEX_IT_URL"] != nil))
    func realProjectAPIAndInitialSync() async throws {
        let environment = ProcessInfo.processInfo.environment
        let baseURL = try VexSettings.normalizedURL(#require(environment["VEX_IT_URL"]))
        let tokenFile = URL(fileURLWithPath: try #require(environment["VEX_IT_TOKEN_FILE"]))
        let token = try String(contentsOf: tokenFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        let platform = try VexClient(baseURL: baseURL, token: token)
        let projects = try await platform.projects()
        #expect(!projects.isEmpty)
        for project in projects {
            let client = try VexClient(baseURL: baseURL, token: token, project: project.id)
            let rooms = try await client.rooms(), builds = try await client.builds()
            #expect(rooms.allSatisfy { $0.project == project.id })
            #expect(builds.allSatisfy { $0.project == project.id })
            for try await event in VexEventStream(client: client).events() {
                guard case .sync(let sync) = event else { Issue.record("Expected initial sync"); break }
                #expect(sync.rooms.allSatisfy { $0.project == project.id })
                break
            }
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VEX_IT_URL"] != nil && ProcessInfo.processInfo.environment["VEX_IT_PREPARE_PROJECT"] != nil))
    func realBuildPreparationWithoutStartingRoom() async throws {
        let environment = ProcessInfo.processInfo.environment
        let baseURL = try VexSettings.normalizedURL(#require(environment["VEX_IT_URL"]))
        let tokenFile = URL(fileURLWithPath: try #require(environment["VEX_IT_TOKEN_FILE"]))
        let token = try String(contentsOf: tokenFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        let projectID = try #require(environment["VEX_IT_PREPARE_PROJECT"])
        let paths = LauncherPaths(root: URL(fileURLWithPath: try #require(environment["VEX_IT_DATA_DIR"])))
        let client = try VexClient(baseURL: baseURL, token: token, project: projectID)
        let project = try #require(await client.projects().first { $0.id == projectID })
        let branch = try #require(await client.branches().first { $0.name == project.defaultBranch })
        let roomID = try #require(branch.rooms["fabric"])
        let room = try await client.room(roomID)
        let build = try await client.build(room.buildId)
        #expect(build.status == .ready)
        let manager = VexInstanceManager(paths: paths, client: client)
        let prepared = try await manager.prepare(build, roomID: roomID, generation: room.generation)
        let installed = try await manager.installed(build)
        #expect(prepared.instance.id == installed.instance.id)
        let plan = try await VexLaunchPlan.inspect(installed, room: room, paths: paths)
        #expect(plan.project == projectID)
        #expect(plan.buildID == build.id)
        #expect(plan.javaMajor == build.java)
        #expect(plan.destinationArguments.contains(room.host + ":" + String(room.port)))
        let unchanged = try await client.room(roomID)
        #expect(unchanged.generation == room.generation)
        #expect(unchanged.state == room.state)
    }
}
