import Foundation
import Darwin
import Testing
import TOMLDecoder
@testable import RuriCore

struct ChorusTests {
    private func room(state: ChorusRoomState = .starting, generation: Int = 1, build: String = "fabric-fc16eaac252b") -> ChorusRoom {
        ChorusRoom(id: "main-fabric", kind: "branch", branch: "main", sha: "fc16eaac252bc8404e99a2368fecd768d31c8067", loader: "fabric",
                   buildId: build, generation: generation, behindHead: false, host: "main-fabric.chorus.internal", port: 25565,
                   state: state, phase: "", label: "testing", node: "encore", players: [], idleSince: nil, seed: "empty",
                   seedResolved: .init(kind: "empty", id: nil, rev: nil), asset: nil, lastSnapshot: nil, lastError: nil,
                   createdAt: "2026-10-14T18:00:00Z", updatedAt: "2026-10-14T18:00:00Z")
    }

    @Test func readyBeforeLocalLaunchesOnlyOnce() throws {
        var gate = try ChorusJoinGate(room: room(state: .ready))
        let beforeLocal = gate.claimLaunch()
        #expect(!beforeLocal)
        gate.prepareLocal()
        let first = gate.claimLaunch(), repeated = gate.claimLaunch()
        #expect(first)
        #expect(!repeated)
        try gate.observe(room(state: .ready))
        let afterEvent = gate.claimLaunch()
        #expect(!afterEvent)
    }

    @Test func localBeforeReadyWaitsForMatchingRoom() throws {
        var gate = try ChorusJoinGate(room: room())
        gate.prepareLocal()
        let beforeReady = gate.claimLaunch()
        #expect(!beforeReady)
        try gate.observe(room(state: .ready))
        let afterReady = gate.claimLaunch()
        #expect(afterReady)
    }

    @Test func reverifyRevokesEarlierReadiness() throws {
        var gate = try ChorusJoinGate(room: room(state: .ready))
        try gate.observe(room(state: .starting))
        gate.prepareLocal()
        let rechecking = gate.claimLaunch()
        #expect(!rechecking)
        try gate.observe(.init(id: "main-fabric", generation: 1, host: "main-fabric.chorus.internal", port: 25565, buildId: "fabric-fc16eaac252b"))
        let confirmed = gate.claimLaunch()
        #expect(confirmed)
    }

    @Test(arguments: [ChorusRoomState.failed, .stopping, .archiving, .closed, .lost])
    func terminalStatesCancel(state: ChorusRoomState) throws {
        var gate = try ChorusJoinGate(room: room(state: .ready))
        #expect(throws: (any Error).self) { try gate.observe(room(state: state)) }
        gate.prepareLocal()
        #expect(gate.cancelled)
        let afterCancellation = gate.claimLaunch()
        #expect(!afterCancellation)
        #expect(throws: (any Error).self) { try gate.observe(room(state: .ready)) }
    }

    @Test func changedGenerationOrBuildCancels() throws {
        var generation = try ChorusJoinGate(room: room())
        #expect(throws: (any Error).self) { try generation.observe(room(state: .ready, generation: 2)) }
        var build = try ChorusJoinGate(room: room())
        #expect(throws: (any Error).self) { try build.observe(room(state: .ready, build: "fabric-000000000000")) }
    }

    @Test func instanceIdentityIncludesLoaderVersion() {
        #expect(ChorusInstanceManager.key(minecraft: "26.3", loader: "fabric", version: "0.19.5") != ChorusInstanceManager.key(minecraft: "26.3", loader: "fabric", version: "0.19.6"))
        #expect(ChorusInstanceManager.key(minecraft: "26.3", loader: "fabric", version: "0.19.5") != ChorusInstanceManager.key(minecraft: "26.3", loader: "neoforge", version: "0.19.5"))
    }

    @Test func backendAddressRejectsCredentialsAndPaths() throws {
        #expect(try ChorusSettings.normalizedURL("http://encore.inner.imdomestic.com:8790/").absoluteString == ChorusSettings.defaultBaseURL)
        for input in ["file:///etc/passwd", "http://user:password@example.com", "http://example.com/path", "http://example.com?secret=value", "http://example.com#fragment"] {
            #expect(throws: (any Error).self) { try ChorusSettings.normalizedURL(input) }
        }
    }

    @Test func retryBackoffIsBounded() {
        #expect(ChorusEventStream.retryDelay(attempt: 0) == .seconds(1))
        #expect(ChorusEventStream.retryDelay(attempt: 2) == .seconds(4))
        #expect(ChorusEventStream.retryDelay(attempt: 200) == .seconds(30))
    }

    @Test func independentDataAndCommandLocations() throws {
        #expect(LauncherPaths().root.lastPathComponent == "Ruri Chorus")
        let install = try CLIInstallation(executable: URL(fileURLWithPath: "/Applications/Ruri Chorus.app/Contents/Helpers/ruri-cli"))
        #expect(install.link.lastPathComponent == "ruri-chorus")
    }

    @Test func chorusRuntimeSettingsPreserveOtherOverrides() {
        var instance = GameInstance(name: "Chorus", gameVersion: "26.3")
        var defaults = AppSettings()
        var macOS = MacOSGameSettings()
        macOS.instanceAppearance = false
        macOS.nativeFullscreen = false
        defaults.defaultMacOSGameSettings = macOS
        var overrides = InstanceLaunchOverrides()
        overrides.gameArguments = "--demo"
        overrides.window = .init(width: 900, height: 600)
        instance.launchOverrides = overrides
        let configured = ChorusInstanceManager.applyingRuntimeSettings(to: instance, defaults: defaults, javaMajor: 25)
        #expect(configured.launchOverrides?.gameArguments == overrides.gameArguments)
        #expect(configured.launchOverrides?.window == overrides.window)
        #expect(configured.launchOverrides?.macOS?.enabled == false)
        #expect(configured.launchOverrides?.macOS?.instanceAppearance == false)
        #expect(configured.launchOverrides?.macOS?.nativeFullscreen == false)
        #expect(configured.javaMajor == 25)
    }

    @Test func initialGameOptionsPreserveExistingFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try ChorusInstanceManager.initializeGameOptions(at: directory)
        let options = directory.appendingPathComponent("options.txt")
        #expect(try String(contentsOf: options, encoding: .utf8) == "enableVsync:false\nonboardAccessibility:false\npauseOnLostFocus:false\n")
        let userSettings = Data("enableVsync:true\nfov:0.75\ncustom:value\n".utf8)
        try userSettings.write(to: options)
        try ChorusInstanceManager.initializeGameOptions(at: directory)
        #expect(try Data(contentsOf: options) == userSettings)
    }

    @Test func manifestSideAndNameValidation() throws {
        let file = ChorusBuild.File(name: "chorus.jar", sha256: String(repeating: "a", count: 64), size: 1, side: "both", url: "/v1/deps/sha")
        let server = ChorusBuild.File(name: "hop.jar", sha256: file.sha256, size: 1, side: "server", url: "/v1/deps/sha")
        func build(_ files: [ChorusBuild.File]) -> ChorusBuild {
            .init(id: "fabric-fc16eaac252b", sha: room().sha, loader: "fabric", status: .ready, attempt: 1, queuedAt: room().createdAt,
                  startedAt: room().createdAt, finishedAt: room().createdAt, minecraft: "26.3", loaderVersion: "0.19.5", java: 25,
                  builtAt: room().createdAt, durationSec: 1, modIds: ["chorus"], files: files, log: "/v1/builds/fabric-fc16eaac252b/log", lastError: nil)
        }
        #expect(try ChorusModSync.clientFiles(build([file, server])) == [file])
        #expect(throws: (any Error).self) { try ChorusModSync.clientFiles(build([file, file])) }
        let traversal = ChorusBuild.File(name: "../chorus.jar", sha256: file.sha256, size: 1, side: "both", url: file.url)
        #expect(throws: (any Error).self) { try ChorusModSync.clientFiles(build([traversal])) }
    }
}

@Suite(.enabled(if: ProcessInfo.processInfo.environment["CHORUS_IT_URL"] != nil))
struct ChorusIntegrationTests {
    @Test func unavailableTCPServiceReportsAConnectionError() async throws {
        let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        #expect(descriptor >= 0)
        guard descriptor >= 0 else { return }
        defer { Darwin.close(descriptor) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        try #require(bound == 0)
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) }
        }
        try #require(named == 0)
        // 已保留的 TCP 端口没有监听进程；请求应由系统直接报告连接失败。
        let url = try #require(URL(string: "http://127.0.0.1:" + String(UInt16(bigEndian: address.sin_port))))
        let token = UUID().uuidString
        let client = try ChorusClient(baseURL: url, token: token)
        do {
            _ = try await client.meta()
            Issue.record("An unavailable TCP service responded")
        } catch let error as URLError {
            #expect([URLError.cannotConnectToHost, .timedOut].contains(error.code))
            #expect(!error.localizedDescription.isEmpty)
            #expect(!error.localizedDescription.contains(token))
        }
    }

    @Test func realArtifactsSynchronizeAndProtectUnmanagedFiles() async throws {
        let url = try ChorusSettings.normalizedURL(#require(ProcessInfo.processInfo.environment["CHORUS_IT_URL"]))
        let token = try ProcessInfo.processInfo.environment["CHORUS_IT_SSH_HOST"].map { try ChorusIntegrationCredentials.read(host: $0) }
            ?? ChorusTokenStore.load(baseURL: url)
        let client = try ChorusClient(baseURL: url, token: token)
        let builds = try await client.builds()
        let requested = ProcessInfo.processInfo.environment["CHORUS_IT_BUILD_ID"]
        let build = try #require(builds.first { $0.status == .ready && (requested == nil || $0.id == requested) })
        let files = try ChorusModSync.clientFiles(build)
        #expect(files.count >= 2)
        let temporary = try #require(ProcessInfo.processInfo.environment["TMPDIR"])
        let root = URL(fileURLWithPath: temporary).appendingPathComponent("chorus-sync-" + UUID().uuidString)
        let paths = LauncherPaths(root: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let instance = try InstanceService(paths: paths).create(name: "Chorus artifact verification", game: #require(build.minecraft),
            selections: [.init(loader: .fabric, version: #require(build.loaderVersion))], directoryID: GameDirectory.defaultID)
        let sync = ChorusModSync(paths: paths, client: client)
        let first = try await sync.synchronize(build, instance: instance)
        #expect(first.files == files.map(\.name))
        let mods = paths.configured(with: try StateStore.load(paths)).game(instance.id).appendingPathComponent("mods")
        for file in build.files where file.side == "server" {
            #expect(!FileManager.default.fileExists(atPath: mods.appendingPathComponent(file.name).path))
        }
        let unmanaged = mods.appendingPathComponent("user-owned.jar")
        try FileManager.default.copyItem(at: mods.appendingPathComponent(files[0].name), to: unmanaged)
        let unmanagedHash = try ChorusModSync.digest(unmanaged)
        // 文件子集来自真实构建；远端下载与本地事务使用完整实现。
        let subset = ChorusBuild(id: build.id, sha: build.sha, loader: build.loader, status: build.status, attempt: build.attempt,
            queuedAt: build.queuedAt, startedAt: build.startedAt, finishedAt: build.finishedAt, minecraft: build.minecraft,
            loaderVersion: build.loaderVersion, java: build.java, builtAt: build.builtAt, durationSec: build.durationSec,
            modIds: build.modIds, files: [files[0]], log: build.log, lastError: build.lastError)
        let reduced = try await sync.synchronize(subset, instance: instance)
        #expect(reduced.unmanaged == [unmanaged.lastPathComponent])
        for file in files.dropFirst() { #expect(!FileManager.default.fileExists(atPath: mods.appendingPathComponent(file.name).path)) }
        _ = try await sync.synchronize(build, instance: instance)
        for file in files { try ChorusModSync.verify(mods.appendingPathComponent(file.name), file: file) }
        #expect(try ChorusModSync.digest(unmanaged) == unmanagedHash)
        let receipt = try Data(contentsOf: mods.appendingPathComponent(".chorus-managed.json"))
        let changed = mods.appendingPathComponent(files[0].name)
        let handle = try FileHandle(forWritingTo: changed)
        try handle.seekToEnd(); try handle.write(contentsOf: Data([0])); try handle.close()
        await #expect(throws: (any Error).self) { try await sync.synchronize(build, instance: instance) }
        #expect(try Data(contentsOf: mods.appendingPathComponent(".chorus-managed.json")) == receipt)
        #expect(try ChorusModSync.digest(unmanaged) == unmanagedHash)
    }

    @Test func liveModelsAndInitialSynchronization() async throws {
        let url = try ChorusSettings.normalizedURL(#require(ProcessInfo.processInfo.environment["CHORUS_IT_URL"]))
        let token: String
        if let host = ProcessInfo.processInfo.environment["CHORUS_IT_SSH_HOST"] {
            token = try ChorusIntegrationCredentials.read(host: host)
        } else { token = try ChorusTokenStore.load(baseURL: url) }
        let client = try ChorusClient(baseURL: url, token: token)
        let meta = try await client.meta()
        #expect(meta.minecraft == "26.3")
        #expect(meta.loaders.contains("fabric"))
        _ = try await client.rooms()
        _ = try await client.builds()
        let branches = try await client.branches()
        #expect(branches.contains { $0.name == "main" })
        let commits = try await client.commits(branch: "main")
        #expect(!commits.isEmpty)
        let graph = try ChorusCommitGraph.layout(commits.map { .init(sha: $0.sha, parents: $0.parents) })
        #expect(graph.count == commits.count)
        if let last = commits.last {
            let next = try await client.commits(branch: "main", before: last.sha)
            #expect(Set(next.map(\.sha)).isDisjoint(with: Set(commits.map(\.sha))))
            _ = try ChorusCommitGraph.layout((commits + next).map { .init(sha: $0.sha, parents: $0.parents) })
        }
        var iterator = ChorusEventStream(client: client).events().makeAsyncIterator()
        guard case .sync(let sync) = try await iterator.next() else { Issue.record("sync"); return }
        #expect(sync.rooms.contains { $0.id == "main-fabric" })
    }
}

private enum ChorusIntegrationCredentials {
    enum Failure: Error { case sshFailed, invalidDocument, missingUser }
    static func read(host: String) throws -> String {
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        let file = ProcessInfo.processInfo.environment["CHORUS_IT_SECRETS_FILE"] ?? "/var/lib/chorusd/secrets/users.toml"
        guard file.hasPrefix("/"), !file.contains("\n"), !file.contains("\0") else { throw Failure.invalidDocument }
        let quoted = "'" + file.replacingOccurrences(of: "'", with: "'\\''") + "'"
        process.arguments = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=10", host, "sudo -n cat -- " + quoted]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = try output.fileHandleForReading.readToEnd() ?? Data()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure.sshFailed }
        struct Users: Decodable { let users: [String: String] }
        let users: Users
        do { users = try TOMLDecoder().decode(Users.self, from: data) }
        catch { throw Failure.invalidDocument }
        guard let token = users.users["linwhite"] else { throw Failure.missingUser }
        return token
    }
}

@Suite(.enabled(if: ProcessInfo.processInfo.environment["CHORUS_SSE_RECORDING"] != nil))
struct ChorusRecordingTests {
    @Test func recordedStreamDecodesAndStartsWithSync() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["CHORUS_SSE_RECORDING"])
        let events = try await ChorusEventStream.decodeRecording(Data(contentsOf: URL(fileURLWithPath: path)))
        #expect(!events.isEmpty)
        guard case .sync = events.first else { Issue.record("sync"); return }
    }
}

@Suite(.enabled(if: ProcessInfo.processInfo.environment["CHORUS_FAILED_BUILD_RECORDING"] != nil))
struct ChorusBuildFailureRecordingTests {
    @Test func recordedProductionFailurePreservesTheDisplayedError() throws {
        let path = try #require(ProcessInfo.processInfo.environment["CHORUS_FAILED_BUILD_RECORDING"])
        let build = try JSONDecoder().decode(ChorusBuild.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        #expect(build.id == "fabric-cb7f59da8fe5")
        #expect(build.status == .failed)
        #expect(build.attempt == 2)
        #expect(build.startedAt == nil)
        #expect(build.files.isEmpty)
        let error = try #require(build.lastError)
        #expect(error.code == "build_failed")
        #expect(error.message.contains("chorus-build@fabric-cb7f59da8fe5.service"))
        #expect(error.localizedDescription == error.message)
        #expect(try JSONDecoder().decode(ChorusBuild.self, from: JSONEncoder().encode(build)) == build)
    }
}

@Suite(.enabled(if: ProcessInfo.processInfo.environment["CHORUS_GAME_MANIFEST"] != nil))
struct ChorusGameManifestTests {
    @Test func installedMinecraftSDLManifestSupportsNormalQuit() throws {
        let path = try #require(ProcessInfo.processInfo.environment["CHORUS_GAME_MANIFEST"])
        let manifest = try JSONDecoder().decode(VersionManifest.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        #expect(manifest.libraries.contains { $0.name.hasPrefix("org.lwjgl:lwjgl-sdl:") })
        #expect(!manifest.libraries.contains { $0.name.hasPrefix("org.lwjgl:lwjgl-glfw:") })
        #expect(LaunchBuilder.supportsNativeQuit(manifest))
        var withoutWindowLibrary = manifest
        withoutWindowLibrary.libraries.removeAll { $0.name.hasPrefix("org.lwjgl:lwjgl-sdl:") }
        #expect(!LaunchBuilder.supportsNativeQuit(withoutWindowLibrary))
    }
}

@Suite(.enabled(if: ProcessInfo.processInfo.environment["CHORUS_IT_RECONNECT"] == "1"))
struct ChorusReconnectTests {
    enum Failure: Error { case timeout, streamEnded }

    @Test func actualServiceRestartResynchronizes() async throws {
        let url = try ChorusSettings.normalizedURL(#require(ProcessInfo.processInfo.environment["CHORUS_IT_URL"]))
        let host = try #require(ProcessInfo.processInfo.environment["CHORUS_IT_SSH_HOST"])
        let client = try ChorusClient(baseURL: url, token: ChorusIntegrationCredentials.read(host: host))
        try await withThrowingTaskGroup(of: Void.self) { tasks in
            tasks.addTask {
                var synchronized = 0
                for try await event in ChorusEventStream(client: client).events() {
                    guard case .sync(let value) = event else { continue }
                    #expect(value.rooms.contains { $0.id == "main-fabric" })
                    synchronized += 1
                    print("CHORUS_RECONNECT_SYNC \(synchronized)")
                    if synchronized == 2 { return }
                }
                throw Failure.streamEnded
            }
            tasks.addTask { try await Task.sleep(for: .seconds(300)); throw Failure.timeout }
            defer { tasks.cancelAll() }
            try await tasks.next()
        }
    }
}
