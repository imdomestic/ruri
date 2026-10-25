import Foundation
import Security
import SwiftUI
import Testing
@testable import RuriCore
@testable import RuriCommandKit
import RuriExtensionKit

final class Capture: @unchecked Sendable {
    private let lock = NSLock()
    private var stdout = Data(), stderr = Data()
    func write(_ data: Data, _ error: Bool) { lock.withLock { if error { stderr.append(data) } else { stdout.append(data) } } }
    var output: String { lock.withLock { String(decoding: stdout, as: UTF8.self) } }
    var errors: String { lock.withLock { String(decoding: stderr, as: UTF8.self) } }
}

@MainActor struct ExtensionPointTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("ruri-extension-\(UUID().uuidString)")
    var paths: LauncherPaths { LauncherPaths(root: root) }
    init() { _ = SampleExtension.context }

    private func run(_ arguments: [String]) async -> (status: Int32, output: String, errors: String) {
        let capture = Capture()
        let status = await CLIApplication.run(arguments + ["--data-dir", root.path, "--language", "en"], write: capture.write)
        return (status, capture.output, capture.errors)
    }
    private func json(_ arguments: [String]) async throws -> OperationValue {
        let result = await run(arguments + ["--json"])
        return try JSONDecoder().decode(OperationValue.self, from: Data(result.output.utf8))
    }

    @Test func commandFamilyJoinsOnlyWhileEnabled() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try paths.prepare()
        let help = await run(["help"])
        #expect(help.status == 0 && !help.output.contains("sample"))
        let disabled = try await json(["sample", "status"])
        #expect(disabled["ok"] == .bool(false) && disabled["error"]["code"] == .string("FEATURE_DISABLED"))

        let enabled = try await json(["config", "set", "experimental.sample.enabled", "true", "--scope", "app"])
        #expect(enabled["data"]["changed"] == .bool(true) && enabled["data"]["enabled"] == .bool(true))
        #expect(try await json(["config", "get", "experimental.sample.enabled", "--scope", "app"])["data"]["effective"] == .bool(true))

        let root = await run(["help"])
        #expect(root.output.contains("Sample") && root.output.contains("sample"))
        #expect(await run(["help", "--all"]).output.contains("ruri sample note <instance> <text>"))
        let group = await run(["sample", "--help"])
        #expect(group.status == 0 && group.output.contains("ruri sample <subcommand>") && group.output.contains("instances"))
        let leaf = await run(["help", "sample", "note"])
        #expect(leaf.output.contains("ruri sample note <instance> <text>") && leaf.output.contains("ruri sample note Survival hello"))
        // Global options are accepted before, between and after command names.
        #expect(await run(["--details", "sample", "--color", "never", "status"]).status == 0)

        let status = await run(["sample", "status"])
        #expect(status.status == 0 && status.output.contains("Enabled") && status.output.contains("Yes") == false)
        let schema = try await json(["schema", "sample", "status", "--output-schema"])
        let payload = schema["data"]["commands"].elements[0]["resultSchema"]["properties"]["data"]["anyOf"].elements[0]
        #expect(payload["properties"]["notes"]["type"] == .string("integer"))
        let descriptor = try await json(["schema", "sample", "note"])
        #expect(descriptor["data"]["commands"].elements[0]["sideEffects"] == .array([.string("configuration")]))
        let queryDescriptor = try await json(["schema", "sample", "status"])
        #expect(queryDescriptor["data"]["commands"].elements[0]["mutation"] == .bool(false))
        #expect(queryDescriptor["data"]["commands"].elements[0]["sideEffects"] == .array([.string("configuration")]))
        let completion = try await json(["completions", "zsh"])
        #expect(completion["data"]["script"].string?.contains("sample") == true)

        #expect(try await json(["config", "reset", "experimental.sample.enabled", "--scope", "app"])["data"]["enabled"] == .bool(false))
        #expect(await run(["sample", "status"]).status == 1)
    }

    @Test func targetsResolveByNameAndTextFollowsTheTerminal() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try paths.prepare()
        let instance = GameInstance(name: "Survival", gameVersion: "26.3")
        try StateStore.updateIfChanged(paths) { $0.instances.append(instance) }
        try ExperimentalFeatures.setEnabled(SampleExtension.id, true, paths: paths)

        let preview = try await json(["sample", "note", "Survival", "hello", "--dry-run"])
        #expect(preview["data"]["instance"] == .string(instance.id.uuidString) && preview["data"]["dryRun"] == .bool(true))
        let change = await run(["sample", "note", String(instance.id.uuidString.prefix(8)).lowercased(), "hello"])
        #expect(change.status == 0 && change.output.contains("Note") && change.output.contains("hello"))
        #expect(try SampleExtension.context.configuration(paths).load(as: SampleSettings.self)?.notes[instance.id.uuidString] == "hello")

        let list = await run(["sample", "instances"])
        #expect(list.output.contains("Name") && list.output.contains("Survival"))
        let colored = await run(["sample", "status", "--color", "always"])
        #expect(colored.status == 0)
        let missing = try await json(["sample", "note", "Missing", "x"])
        #expect(missing["ok"] == .bool(false))
    }

    @Test func settingsStayOpaqueAndOtherExtensionsAreKept() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try paths.prepare()
        // Settings of an extension that is not compiled into this build.
        let foreign = #"{"enabled":true,"servers":[{"url":"https://example.invalid","nested":{"a":[1,2,3]}}]}"#
        try StateStore.updateIfChanged(paths) { state in
            state.settings.experimental = try JSONDecoder().decode(ExperimentalSettings.self, from: Data(#"{"other":\#(foreign)}"#.utf8))
        }
        try SampleExtension.context.configuration(paths).update(default: SampleSettings()) { $0.hiddenHost = "hidden.invalid" }
        try ExperimentalFeatures.setEnabled(SampleExtension.id, true, paths: paths)
        // An unrelated save by the host keeps both values.
        try StateStore.updateIfChanged(paths) { $0.settings.concurrentDownloads = 3 }
        let saved = try StateStore.load(paths).settings.experimental
        let encoded = try JSONEncoder().encode(saved)
        let decoded = try JSONDecoder().decode([String: OperationValue].self, from: encoded)
        #expect(decoded["other"] == (try JSONDecoder().decode(OperationValue.self, from: Data(foreign.utf8))))
        #expect(decoded["sample"]?["hiddenHost"] == .string("hidden.invalid") && decoded["sample"]?["enabled"] == .bool(true))
        #expect(saved?.enabled("other") == true && saved?.enabled("sample") == true)
        // The context reads only its own part.
        #expect(SampleExtension.context.settings(saved).enabled)
        #expect(try SampleExtension.context.settings(saved).decode([String: OperationValue].self)?["servers"] == nil)
    }

    @Test func hooksRunOnlyForEnabledExtensions() throws {
        let item = ServerLibraryItem(address: try ServerAddress("hidden.invalid"), name: "Hidden", preference: nil, instanceIDs: [], icon: nil)
        let other = ServerLibraryItem(address: try ServerAddress("shown.invalid"), name: "Shown", preference: nil, instanceIDs: [], icon: nil)
        var settings = ExperimentalSettings()
        try settings.set(SampleSettings(enabled: false, hiddenHost: "hidden.invalid"), for: SampleExtension.id)
        #expect(try ExperimentalFeatures.visibleServers([item, other], settings: settings).count == 2)
        try settings.set(SampleSettings(enabled: true, hiddenHost: "hidden.invalid"), for: SampleExtension.id)
        #expect(try ExperimentalFeatures.visibleServers([item, other], settings: settings).map(\.name) == ["Shown"])
        #expect(try ExperimentalFeatures.visibleServers([item, other], settings: nil).count == 2)

        let launched = UUID()
        try ExperimentalFeatures.beforeLaunch(paths: paths, instanceID: launched, settings: settings)
        #expect(SampleRecorder.shared.recorded.contains("launch:" + launched.uuidString))
        let skipped = UUID()
        settings.setEnabled(false, for: SampleExtension.id)
        try ExperimentalFeatures.beforeLaunch(paths: paths, instanceID: skipped, settings: settings)
        #expect(!SampleRecorder.shared.recorded.contains("launch:" + skipped.uuidString))
    }

    @Test func viewsAppearOnlyWhileEnabled() async throws {
        var settings = ExperimentalSettings()
        let host = ExperimentalHost(paths: { LauncherPaths(root: nil) }, configuration: { settings }, accountAvailable: { false },
                                    readOnly: { false }, busy: { false }, reload: {}, openAccount: {}, error: { _ in })
        #expect(ExperimentalUIRegistry.pages(host: host).isEmpty)
        #expect(throws: (any Error).self) { try ExperimentalUIRegistry.open(URL(string: "ruri-sample://join")!, host: host) }
        settings.setEnabled(true, for: SampleExtension.id)
        #expect(ExperimentalUIRegistry.pages(host: host) == [ExperimentalPage(id: "sample.page", title: "Sample", symbol: "puzzlepiece")])
        #expect(ExperimentalUIRegistry.page("sample.page", host: host) != nil)
        #expect(ExperimentalUIRegistry.page("missing", host: host) == nil)
        #expect(try ExperimentalUIRegistry.open(URL(string: "ruri-sample://join")!, host: host) != nil)
        #expect(try ExperimentalUIRegistry.open(URL(string: "https://example.invalid")!, host: host) == nil)
        let provider = try #require(ExperimentalUIRegistry.providers.first { $0.id == SampleExtension.id } as? SampleUIProvider)
        let before = provider.configured
        await ExperimentalUIRegistry.configure(host: host)
        #expect(provider.configured == before + 1)
        ExperimentalUIRegistry.stop()
        #expect(provider.stopped)
    }

    @Test func secureStorageStaysInTheExtensionsService() throws {
        #expect(SampleExtension.context.secureStorage.service == "dev.ruri.launcher.ext.sample")
        // A file keychain of its own, so the test never touches the login keychain.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ruri-keychain-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var keychain: SecKeychain?
        let password = UUID().uuidString
        #expect(SecKeychainCreate(directory.appendingPathComponent("test.keychain-db").path, UInt32(password.utf8.count), password, false, nil, &keychain) == errSecSuccess)
        let file = try #require(keychain)
        defer { SecKeychainDelete(file) }
        let storage = ExperimentalSecureStorage(extension: SampleExtension.id, keychain: file)
        let other = ExperimentalSecureStorage(extension: "other", keychain: file)
        #expect(try storage.read("account") == nil)
        try storage.write(Data("first".utf8), account: "account")
        try storage.write(Data("second".utf8), account: "account")
        #expect(try storage.read("account") == Data("second".utf8))
        #expect(try other.read("account") == nil)
        #expect(try storage.accounts() == ["account"])
        try storage.remove("account")
        try storage.remove("account")
        #expect(try storage.read("account") == nil && storage.accounts().isEmpty)
    }

    @Test func importsLeaveOutFilesTheExtensionManages() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source")
        let game = source.appendingPathComponent(".minecraft")
        try FileManager.default.createDirectory(at: game.appendingPathComponent("mods"), withIntermediateDirectories: true)
        // A Prism / MultiMC instance.
        try Data(#"{"formatVersion":1,"components":[{"uid":"net.minecraft","version":"26.3"}]}"#.utf8).write(to: source.appendingPathComponent("mmc-pack.json"))
        try Data("kept".utf8).write(to: game.appendingPathComponent("mods/kept.jar"))
        try Data("managed".utf8).write(to: game.appendingPathComponent("mods/managed.jar"))
        try Data("{}".utf8).write(to: game.appendingPathComponent("options.txt"))
        let capabilities = ExperimentalInstanceCapabilities(paths: LauncherPaths(root: root.appendingPathComponent("data")))
        await #expect(throws: (any Error).self) { try await capabilities.prepareImport(source, excludingFiles: ["../outside.jar"]) }
        let prepared = try await capabilities.prepareImport(source, excludingFiles: ["mods/managed.jar"])
        #expect(FileManager.default.fileExists(atPath: prepared.game.appendingPathComponent("mods/kept.jar").path))
        #expect(!FileManager.default.fileExists(atPath: prepared.game.appendingPathComponent("mods/managed.jar").path))
        await capabilities.discardImport(prepared)
    }
}
