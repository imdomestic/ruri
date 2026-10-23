import ArgumentParser
import CryptoKit
import Foundation
import Testing
import RuriCore
import RuriVex
import RuriFeatureRegistration
@testable import RuriCommandKit
@testable import RuriVexCLI

@MainActor struct VexCommandTests {
    init() { CompiledExperimentalFeatures.register() }

    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    private func enabled(_ root: URL) throws -> LauncherPaths {
        let paths = LauncherPaths(root: root)
        try VexSettings.update(paths: paths) { $0.enabled = true }
        return paths
    }
    private func savedServers(_ root: URL) throws -> LauncherPaths {
        let paths = try enabled(root)
        let first = try VexServer(baseURL: URL(string: "https://one.example")!, name: "one")
        let second = try VexServer(baseURL: URL(string: "https://two.example")!, name: "two")
        try VexSettings.update(paths: paths) { settings in try settings.save(first); try settings.save(second) }
        return paths
    }
    private func run(_ arguments: [String], root: URL, terminal: TerminalProfile = .pipe) async -> (Int32, CommandCapture) {
        let capture = CommandCapture()
        let status = await CLIApplication.run(arguments + ["--data-dir", root.path], write: capture.write, terminal: terminal)
        return (status, capture)
    }

    @Test func disabledCommandsMatchUpstreamGoldenBytes() async throws {
        struct Entry: Decodable { let sha256: String; let size: Int }
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("RuriCLITests/ExtensionGolden.json")
        let expected = try JSONDecoder().decode([String: Entry].self, from: Data(contentsOf: manifest))
        let cases: [(String, [String])] = [
            ("help", ["help"]), ("help-all", ["help", "--all"]), ("help-json", ["help", "--json"]),
            ("help-all-json", ["help", "--all", "--json"]), ("root-help", ["--help"]),
            ("schema", ["schema"]), ("schema-json", ["schema", "--json"]),
            ("schema-full", ["schema", "--full"]), ("schema-full-json", ["schema", "--full", "--json"])]
        for (name, arguments) in cases {
            for language in ["en", "zh-Hans"] {
                let (status, capture) = await run(arguments + ["--language", language], root: root)
                let data = Data("exit=\(status)\n".utf8) + capture.output + Data("\n--- stderr\n".utf8) + capture.errors
                let entry = try #require(expected["\(name).\(language)"])
                #expect(data.count == entry.size)
                #expect(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == entry.sha256)
            }
        }
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }

    @Test func disabledInvocationAndInvalidSettingsDoNotCreateOrReplaceState() async throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (disabled, first) = await run(["vex", "rooms", "--json"], root: root)
        #expect(disabled == 1)
        #expect(try first.value["error"]["message"].string?.contains("experimental.vex.enabled") == true)
        #expect(!FileManager.default.fileExists(atPath: root.path))
        let paths = LauncherPaths(root: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let invalid = try JSONEncoder().encode(["settings": ["experimental": ["vex": ["enabled": "invalid"]]]])
        try invalid.write(to: paths.state)
        let (status, result) = await run(["vex", "rooms", "--json"], root: root)
        #expect(status == 1)
        #expect(try result.value["error"]["code"].string == "IO_ERROR")
        #expect(try Data(contentsOf: paths.state) == invalid)
    }

    @Test func configurationControlsDiscoveryAndRetainsSavedServers() async throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = try savedServers(root)
        let before = try VexSettings.load(paths: paths).servers
        let (disabled, _) = await run(["config", "set", "experimental.vex.enabled", "false", "--scope", "app", "--json"], root: root)
        #expect(disabled == 0)
        #expect(try !VexSettings.load(paths: paths).enabled)
        let (hiddenStatus, hidden) = await run(["help"], root: root)
        #expect(hiddenStatus == 0)
        #expect(!String(decoding: hidden.output, as: UTF8.self).contains("Vex"))
        let (status, _) = await run(["config", "set", "experimental.vex.enabled", "true", "--scope", "app", "--json"], root: root)
        #expect(status == 0)
        #expect(try VexSettings.load(paths: paths).servers == before)
        let (schemaStatus, schema) = await run(["schema", "vex", "--full", "--json"], root: root)
        #expect(schemaStatus == 0)
        let commands = try schema.value["data"]["commands"].decode([Value].self)
        #expect(commands.count == 20)
        for command in commands {
            let path = try command["path"].decode([String].self)
            #expect(VexPresenters.presenter(path) != nil)
            #expect(command["resultSchema"]["properties"]["data"] != .null)
        }
    }

    @Test func globalOptionsWorkAroundEveryCommandName() async throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try savedServers(root)
        let (status, expected) = await run(["vex", "servers", "list", "--json"], root: root)
        #expect(status == 0)
        for arguments in [
            ["--json", "--language", "en", "vex", "--color", "always", "servers", "--details", "list"],
            ["--data-dir", root.path, "vex", "--json", "servers", "list", "--quiet"],
            ["vex", "servers", "--output=json", "list", "--language=en", "--details", "--color=never"]] {
            let (result, output) = await run(arguments, root: root)
            #expect(result == 0)
            #expect(output.output == expected.output)
            #expect(output.errors.isEmpty)
        }
        let (helpStatus, help) = await run(["vex", "--language", "en", "servers", "--help"], root: root)
        #expect(helpStatus == 0)
        let text = String(decoding: help.output, as: UTF8.self)
        #expect(text.contains("add") && text.contains("default") && text.contains("remove"))
    }

    @Test func commandSpecificOptionsRejectUnsupportedOperationsBeforeExecution() async throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = try savedServers(root), before = try Data(contentsOf: paths.state)
        for arguments in [["vex", "rooms", "--force"], ["vex", "servers", "list", "--invite", "unused"],
                          ["vex", "prepare", "room", "--dry-run"], ["vex", "login", "--method", "invalid"],
                          ["vex", "login", "--github", "--token-stdin", "--dry-run"],
                          ["vex", "login", "--method", "github", "--invite", "unused", "--dry-run"]] {
            let (status, capture) = await run(arguments + ["--json"], root: root)
            #expect(status == 2)
            #expect(try capture.value["error"]["code"].string == "INVALID_ARGUMENT")
        }
        #expect(try Data(contentsOf: paths.state) == before)
    }

    @Test func typedParserAndDescriptorsAcceptTheSameOptions() throws {
        for spec in VexGroup.specs {
            var arguments = Array(spec.path.dropFirst()) + spec.operands.map { $0.name }
            for option in spec.options {
                arguments.append("--" + option.name)
                if option.type != "bool" { arguments.append(option.values.first ?? option.name) }
            }
            let command = try #require(try VexGroup.parseAsRoot(arguments) as? any ExecutableCommand)
            let request = command.request
            #expect(Set(request.options.keys) == Set(spec.options.map(\.name)))
            #expect(request.spec.path == spec.path)
            try request.validate()
        }
        #expect(throws: (any Error).self) { try VexGroup.parseAsRoot(["whoami", "--launch"]) }
        #expect(throws: (any Error).self) { try VexGroup.parseAsRoot(["rooms", "--invite", "unused"]) }
    }

    @Test func serverDefaultsResolveByNameAndURLWithReadOnlyPreviews() async throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = try savedServers(root), before = try Data(contentsOf: paths.state)
        let (previewStatus, preview) = await run(["vex", "servers", "default", "two", "--project", "project", "--dry-run", "--json"], root: root)
        #expect(previewStatus == 0)
        #expect(try preview.value["data"]["defaultServer"] == .string("two"))
        #expect(try Data(contentsOf: paths.state) == before)
        let (status, changed) = await run(["vex", "servers", "default", "https://two.example", "--project", "project", "--json"], root: root)
        #expect(status == 0)
        #expect(try changed.value["data"]["defaultProject"] == .string("project"))
        let settings = try VexSettings.load(paths: paths)
        #expect(try settings.server().name == "two")
        #expect(try settings.server().defaultProject == "project")
        let (invalid, _) = await run(["vex", "servers", "default", "missing", "--dry-run", "--json"], root: root)
        #expect(invalid == 1)
    }

    @Test func serverTextUsesHostLayoutDetailsAndColor() async throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try savedServers(root)
        for width in [40, 80, 120] {
            let terminal = TerminalProfile(output: .init(isTerminal: true, width: width), error: .init(isTerminal: true, width: width), environment: ["TERM": "xterm-256color"])
            let (status, ordinary) = await run(["vex", "servers", "list", "--language", "en", "--color", "never"], root: root, terminal: terminal)
            #expect(status == 0)
            let text = String(decoding: ordinary.output, as: UTF8.self)
            #expect(text.contains("one") && text.contains("two"))
            #expect(!text.contains("\u{1B}"))
            for line in text.split(separator: "\n") { #expect(TerminalText.width(String(line)) <= width) }
            let (detailStatus, details) = await run(["vex", "servers", "list", "--language", "en", "--details", "--color", "always"], root: root, terminal: terminal)
            #expect(detailStatus == 0)
            let detailed = String(decoding: details.output, as: UTF8.self)
            #expect(detailed.contains("https://one.example") && detailed.contains("https://two.example"))
            #expect(detailed.contains("Username") && detailed.contains("\u{1B}["))
        }
    }

    @Test func schemaDescribesMutationsListsAndLaunchPreviews() async throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try enabled(root)
        let (status, capture) = await run(["schema", "vex", "--full", "--json"], root: root)
        #expect(status == 0)
        let commands = try capture.value["data"]["commands"].decode([Value].self)
        let build = try #require(commands.first { $0["path"] == .array([.string("vex"), .string("build")]) })
        #expect(build["supportsDryRun"] == .bool(true))
        #expect(build["sideEffects"] == .array([.string("credentials"), .string("remoteBuild")]))
        let options = build["inputSchema"]["properties"]["options"]["properties"]
        #expect(options["force"]["type"] == .string("boolean"))
        #expect(options["invite"] == .null)
        for action in ["pulls", "branches", "commits"] {
            let command = try #require(commands.first { $0["path"] == .array([.string("vex"), .string(action)]) })
            let payloads = try command["resultSchema"]["properties"]["data"]["anyOf"].decode([Value].self)
            #expect(payloads[0]["properties"][action]["items"]["properties"].object?.isEmpty == false)
            #expect(command["sideEffects"] == .array([.string("credentials")]))
        }
        let prepare = try #require(commands.first { $0["path"] == .array([.string("vex"), .string("prepare")]) })
        let payloads = try prepare["resultSchema"]["properties"]["data"]["anyOf"].decode([Value].self)
        #expect(payloads[0]["properties"]["javaPath"] != .null)
        #expect(payloads[0]["properties"]["authenticationRequired"] != .null)
        #expect(payloads[0]["properties"]["dryRun"]["type"] == .string("boolean"))
        #expect(prepare["supportsDryRun"] == .bool(false))
    }

    @Test func credentialEffectsCoverAuthenticatedCommandsAndPreviewsRemainReadOnly() async throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try enabled(root)
        let (status, capture) = await run(["schema", "vex", "--full", "--json", "--language", "zh-Hans"], root: root)
        #expect(status == 0)
        let commands = try capture.value["data"]["commands"].decode([Value].self)
        let credentialFree = [["vex", "servers", "list"], ["vex", "servers", "default"]]
        let queries = ["whoami", "projects", "rooms", "pulls", "builds", "branches", "commits", "build-log"]
        for command in commands {
            let path = try command["path"].decode([String].self)
            let effects = try command["sideEffects"].decode([String].self)
            #expect(effects.contains("credentials") == !credentialFree.contains(path))
            if path.count == 2, queries.contains(path[1]) {
                #expect(command["mutation"] == .bool(false))
                #expect(effects == ["credentials"])
            }
            if command["supportsDryRun"].bool == true {
                #expect(command["inputSchema"]["properties"]["options"]["properties"]["dry-run"]["description"] == .string("预览操作，不更改用户数据。"))
                let arguments = Array(path.dropFirst()) + (try command["operands"].decode([Value].self)).compactMap { $0["name"].string } + ["--dry-run"]
                let parsed = try #require(try VexGroup.parseAsRoot(arguments) as? any ExecutableCommand)
                #expect(parsed.request.dryRun)
            }
        }
    }
}
