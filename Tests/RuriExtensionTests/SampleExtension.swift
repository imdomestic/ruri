import ArgumentParser
import Foundation
import SwiftUI
import RuriCore
import RuriCommandKit
import RuriExtensionKit
import RuriFeatureRegistration

/// An extension implementing the contribution interfaces for integration tests.
/// It exists only in tests; products contain no extension.
enum SampleExtension {
    static let id = "sample"
    /// Registers the extension once per test process and returns its context.
    @MainActor static let context: ExperimentalExtensionContext = {
        var captured: ExperimentalExtensionContext?
        CompiledExperimentalFeatures.install(id) { context in
            captured = context
            return (SampleHooks.make(context), SampleUIProvider(context: context), SampleCLIProvider(context: context))
        }
        return captured!
    }()
}

/// The extension's own settings, stored opaquely by the host. The host may
/// write `enabled` alone, so every other field has a default when missing.
struct SampleSettings: Codable, Equatable {
    var enabled = false
    var hiddenHost: String?
    var notes: [String: String] = [:]
    init(enabled: Bool = false, hiddenHost: String? = nil) { self.enabled = enabled; self.hiddenHost = hiddenHost }
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        hiddenHost = try container.decodeIfPresent(String.self, forKey: .hiddenHost)
        notes = try container.decodeIfPresent([String: String].self, forKey: .notes) ?? [:]
    }
}

/// Calls the hooks received, for assertions.
final class SampleRecorder: @unchecked Sendable {
    static let shared = SampleRecorder()
    private let lock = NSLock()
    private var values: [String] = []
    func record(_ value: String) { lock.withLock { values.append(value) } }
    var recorded: [String] { lock.withLock { values } }
}

enum SampleHooks {
    static func make(_ context: ExperimentalExtensionContext) -> ExperimentalFeatureHooks {
        ExperimentalFeatureHooks(id: context.id, beforeLaunch: { _, instanceID, _ in
            SampleRecorder.shared.record("launch:" + instanceID.uuidString)
        }, hidesServer: { server, settings in
            try settings.decode(SampleSettings.self)?.hiddenHost == server.address.host
        })
    }
}

@MainActor final class SampleUIProvider: ExperimentalUIProvider {
    let context: ExperimentalExtensionContext
    var configured = 0
    var stopped = false
    init(context: ExperimentalExtensionContext) { self.context = context }
    var id: String { context.id }
    func pages(host: ExperimentalHost) -> [ExperimentalPage] {
        host.settings(context).enabled ? [ExperimentalPage(id: "sample.page", title: "Sample", symbol: "puzzlepiece")] : []
    }
    func page(_ id: String, host: ExperimentalHost) -> AnyView { AnyView(Text("Sample page")) }
    /// The settings section holds the extension's on and off switch, so it shows while the extension is off.
    func settings(host: ExperimentalHost) -> AnyView {
        AnyView(Section("Sample") { Text(host.settings(context).enabled ? "Sample is on" : "Sample is off") })
    }
    func servers(host: ExperimentalHost) -> AnyView { host.settings(context).enabled ? AnyView(Text("Sample servers")) : AnyView(EmptyView()) }
    func configure(host: ExperimentalHost) async { configured += 1 }
    func open(_ url: URL, host: ExperimentalHost) throws -> AnyView? {
        guard url.scheme == "ruri-sample" else { return nil }
        guard host.settings(context).enabled else { throw OperationFailure("FEATURE_DISABLED", "The sample extension is off.") }
        return AnyView(Text(url.absoluteString))
    }
    func stop() { stopped = true }
}

struct SampleCLIProvider: ExperimentalCommandProvider {
    let context: ExperimentalExtensionContext
    var id: String { context.id }
    var command: any ParsableCommand.Type { SampleGroup.self }
    var commands: [CommandSpec] { [SampleStatusCommand.spec, SampleInstancesCommand.spec, SampleNoteCommand.spec] }
    var section: String { "Sample" }
    func enabled(paths: LauncherPaths) throws -> Bool { try context.configuration(paths).load(as: SampleSettings.self)?.enabled ?? false }
    func disabledError() -> any Error { OperationFailure("FEATURE_DISABLED", "The sample extension is off.") }
    @MainActor func execute(_ request: CommandRequest, output: CommandOutput) async throws -> Value {
        let paths = LauncherPaths(root: request.common.dataDir.map { URL(fileURLWithPath: $0) })
        let store = context.configuration(paths)
        switch request.spec.path.last {
        case "status":
            let settings = try store.load(as: SampleSettings.self) ?? SampleSettings()
            return .object(["enabled": .bool(settings.enabled), "notes": .integer(settings.notes.count)])
        case "instances":
            let instances = try ExperimentalInstanceCapabilities(paths: paths).context().paths
            let state = try StateStore.load(instances)
            return request.page(state.instances.map { .object(["id": .string($0.id.uuidString), "name": .string($0.name)]) })
        default:
            let instance = try request.operand(), text = try request.operand(1)
            let before = try store.load(as: SampleSettings.self)?.notes[instance]
            if !request.dryRun { try store.update(default: SampleSettings()) { $0.notes[instance] = text } }
            return .object(["changed": .bool(before != text), "instance": .string(instance), "note": .string(text)])
        }
    }
    func schema(_ command: CommandSpec) -> Value {
        switch command.path.last {
        case "status": CommandSchemas.object(["enabled": CommandSchemas.boolean, "notes": CommandSchemas.integer], required: ["enabled", "notes"])
        case "instances": CommandSchemas.object(["items": CommandSchemas.array(CommandSchemas.object(["id": CommandSchemas.string, "name": CommandSchemas.string]))])
        default: CommandSchemas.object(["changed": CommandSchemas.boolean, "instance": CommandSchemas.string, "note": CommandSchemas.string])
        }
    }
    func sideEffects(_ command: CommandSpec) -> [String] { ["configuration"] }
    func presenter(_ path: [String]) -> ExperimentalTextPresenter? {
        switch path.last {
        case "status": ExperimentalTextPresenter(.detail) { text, value in text.fields([("Enabled", text.plain(value["enabled"])), ("Notes", text.plain(value["notes"]))]) }
        case "instances": ExperimentalTextPresenter(.list) { text, value in
            text.list(value, [.init("Name") { $0["name"].string ?? "" }, .init("ID", priority: 1) { $0["id"].string ?? "" }])
        }
        default: ExperimentalTextPresenter(.change) { text, value in text.change(value, [("Note", text.plain(value["note"]))]) }
        }
    }
}

struct SampleGroup: ParsableCommand {
    @OptionGroup var common: CommonOptions
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "sample", abstract: "Sample extension commands.", subcommands: [SampleStatusCommand.self, SampleInstancesCommand.self, SampleNoteCommand.self])
    }
}

struct SampleStatusCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["sample", "status"], summary: "Show the sample extension's settings.") }
    @OptionGroup var common: CommonOptions
    var operands: [String] { [] }
    var parameters: [String: Value] { [:] }
}

struct SampleInstancesCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["sample", "instances"], summary: "List instances the sample extension can see.", options: [
        .init(name: "limit", type: "int", required: false, help: "Rows per page."), .init(name: "offset", type: "int", required: false, help: "Rows to skip.")
    ]) }
    @OptionGroup var common: CommonOptions
    @Option(name: .customLong("limit")) var limit: Int?
    @Option(name: .customLong("offset")) var offset: Int?
    var operands: [String] { [] }
    var parameters: [String: Value] { ["limit": limit.map { .integer($0) } ?? .null, "offset": offset.map { .integer($0) } ?? .null].filter { $0.value != .null } }
}

struct SampleNoteCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["sample", "note"], summary: "Attach a note to an instance.", operands: [
        .init(name: "instance", type: "string", required: true, help: "Instance name, short ID or ID.", role: .instance),
        .init(name: "text", type: "string", required: true, help: "The note.")
    ], options: [.init(name: "dry-run", type: "bool", required: false, help: "Show the change without saving it.")],
    mutation: true, examples: ["ruri sample note Survival hello"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var instance: String
    @Argument(help: Self.help(operand: 1)) var text: String
    @Flag(name: .customLong("dry-run")) var dryRun = false
    var operands: [String] { [instance, text] }
    var parameters: [String: Value] { dryRun ? ["dry-run": .bool(true)] : [:] }
}
