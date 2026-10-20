import Foundation
import Testing
import RuriCore
import RuriVex
import RuriFeatureRegistration
@testable import RuriCommandKit

@MainActor struct VexCommandTests {
    init() { CompiledExperimentalFeatures.register() }
    @Test func disabledCommandsMatchUpstreamGoldenBytes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cases: [([String], String)] = [(["help"], "help.txt"), (["help", "--all"], "help-all.txt"),
                                         (["schema", "--json"], "schema-index.json"), (["schema", "--full", "--json"], "schema-full.json")]
        for (arguments, fixture) in cases {
            let output = CommandCapture()
            #expect(await CLIApplication.run(arguments + ["--language", "zh-Hans", "--data-dir", root.path], write: output.write) == 0)
            let url = try #require(Bundle.module.url(forResource: fixture, withExtension: nil, subdirectory: "VexFixtures"))
            #expect(output.output == (try Data(contentsOf: url)))
            #expect(output.errors.isEmpty)
        }
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }
    @Test func disabledDiscoveryAndDirectInvocation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for arguments in [["help"], ["help", "--all"], ["schema", "--json"], ["schema", "--full", "--json"]] {
            let output = CommandCapture()
            #expect(await CLIApplication.run(arguments + ["--data-dir", root.path], write: output.write) == 0)
            #expect(!String(decoding: output.output, as: UTF8.self).contains("vex"))
        }
        let direct = CommandCapture()
        #expect(await CLIApplication.run(["vex", "rooms", "--data-dir", root.path, "--json"], write: direct.write) == 1)
        #expect(try direct.value["error"]["message"].string?.contains("experimental.vex.enabled") == true)
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }
    @Test func existingConfigCommandEnablesAndDisablesDiscovery() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let options = ["--data-dir", root.path, "--json"]
        let enabled = CommandCapture()
        #expect(await CLIApplication.run(["config", "set", "experimental.vex.enabled", "true", "--scope", "app"] + options, write: enabled.write) == 0)
        #expect(try VexSettings.load(paths: LauncherPaths(root: root)).enabled)
        let discovery = CommandCapture()
        #expect(await CLIApplication.run(["schema", "vex", "--full"] + options, write: discovery.write) == 0)
        #expect(String(decoding: discovery.output, as: UTF8.self).contains("\"project\""))
        let disabled = CommandCapture()
        #expect(await CLIApplication.run(["config", "set", "experimental.vex.enabled", "false", "--scope", "app"] + options, write: disabled.write) == 0)
        let hidden = CommandCapture()
        #expect(await CLIApplication.run(["help"] + options, write: hidden.write) == 0)
        #expect(!String(decoding: hidden.output, as: UTF8.self).contains("Vex"))
    }
    @Test func invalidSettingsStopVexExecution() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = LauncherPaths(root: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let invalid = try JSONEncoder().encode(["settings": ["experimental": ["vex": ["enabled": "invalid"]]]])
        try invalid.write(to: paths.state)
        let output = CommandCapture()
        #expect(await CLIApplication.run(["vex", "rooms", "--json", "--data-dir", root.path], write: output.write) == 1)
        #expect(try output.value["error"]["code"].string == "IO_ERROR")
        #expect(try Data(contentsOf: paths.state) == invalid)
    }
    @Test func serverCommandsPersistDefaultsAndExposeLoginDiscovery() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = LauncherPaths(root: root)
        let first = try VexServer(baseURL: URL(string: "https://one.example")!, name: "one")
        let second = try VexServer(baseURL: URL(string: "https://two.example")!, name: "two")
        try VexSettings.update(paths: paths) { settings in
            settings.enabled = true; try settings.save(first); try settings.save(second)
        }
        let options = ["--data-dir", root.path, "--json"]
        let output = CommandCapture()
        #expect(await CLIApplication.run(["vex", "servers", "list"] + options, write: output.write) == 0)
        let text = String(decoding: output.output, as: UTF8.self)
        #expect(text.contains(first.baseURL)); #expect(text.contains(second.baseURL))
        let changed = CommandCapture()
        #expect(await CLIApplication.run(["vex", "servers", "default", "two", "--project", "example"] + options, write: changed.write) == 0)
        let settings = try VexSettings.load(paths: paths)
        #expect(try settings.server().id == second.id)
        #expect(settings.servers.last?.defaultProject == "example")
        let schema = CommandCapture()
        #expect(await CLIApplication.run(["schema", "vex", "--full"] + options, write: schema.write) == 0)
        let discovery = String(decoding: schema.output, as: UTF8.self)
        #expect(discovery.contains("token-stdin")); #expect(discovery.contains("invite")); #expect(discovery.contains("whoami"))
        #expect(discovery.contains("method"))
        #expect(!discovery.contains("configure"))
    }
}
