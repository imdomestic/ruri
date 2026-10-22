import ArgumentParser
import Foundation
import RuriCore
import RuriLocalization

/// A command family contributed by a compiled-in extension. It joins the
/// command tree only while the extension is enabled in the data directory the
/// invocation uses, and then goes through the same help, target resolution,
/// completion, schemas and text output as the built-in families.
package protocol ExperimentalCommandProvider: Sendable {
    var id: String { get }
    /// The family's top-level group.
    var command: any ParsableCommand.Type { get }
    var commands: [CommandSpec] { get }
    /// The heading under which the root help lists the family.
    var section: String { get }
    func enabled(paths: LauncherPaths) throws -> Bool
    /// The error for a family command while the extension is off.
    func disabledError() -> any Error
    @MainActor func execute(_ request: CommandRequest, output: CommandOutput) async throws -> Value
    /// The schema of a command's `data` payload.
    func schema(_ command: CommandSpec) -> Value
    func sideEffects(_ command: CommandSpec) -> [String]
    func presenter(_ path: [String]) -> ExperimentalTextPresenter?
}

/// How the text of one command's result reads.
package struct ExperimentalTextPresenter {
    let presentation: TextPresentation
    let render: (ExperimentalText, Value) -> [String]
    package enum Purpose { case list, detail, change, diagnosis, raw }
    package init(_ purpose: Purpose, _ render: @escaping (ExperimentalText, Value) -> [String]) {
        presentation = switch purpose { case .list: .list; case .detail: .detail; case .change: .change; case .diagnosis: .diagnosis; case .raw: .raw }
        self.render = render
    }
}

/// The text building blocks extension presenters share with the built-in
/// commands. They fit the terminal width and follow --details and --color.
package struct ExperimentalText {
    let renderer: CommandTextRenderer
    package var details: Bool { renderer.layout.details }
    package struct Column {
        let column: ListColumn
        /// Lower priorities hide first on narrow terminals; 0 never hides.
        package init(_ header: String, priority: Int = 0, detailOnly: Bool = false, _ cell: @escaping (Value) -> String) {
            column = ListColumn(header: header, priority: priority, detailOnly: detailOnly, cell: cell)
        }
    }
    /// The page's items as a table, with paging and the empty state.
    package func list(_ value: Value, _ columns: [Column]) -> [String] {
        renderer.page(value, items: value["items"].elements, columns: columns.map(\.column))
    }
    package func fields(_ rows: [(String, String)]) -> [String] { renderer.layout.fields(rows) }
    package func section(_ title: String, _ rows: [(String, String)]) -> [String] { renderer.layout.section(title, rows) }
    package func prose(_ text: String) -> [String] { renderer.layout.prose(text) }
    package func bullets(_ items: [String]) -> [String] { renderer.layout.bullets(items) }
    /// Done or a preview, the command's targets, then these rows.
    package func change(_ value: Value, _ rows: [(String, String)] = []) -> [String] { renderer.change(value, rows) }
    package func plain(_ value: Value) -> String { CommandTextRenderer.plain(value) }
    package func date(_ value: Value) -> String { TextFormat.date(value) }
    package func bytes(_ value: Value) -> String { TextFormat.bytes(value) }
}

package enum ExperimentalCommandRegistry {
    private final class Storage: @unchecked Sendable {
        let lock = NSLock()
        var providers: [any ExperimentalCommandProvider] = []
    }
    private static let storage = Storage()
    /// Whether each provider is enabled for the running invocation.
    @TaskLocal private static var availability: [String: Result<Bool, any Error>] = [:]

    package static func register(_ provider: any ExperimentalCommandProvider) {
        precondition(ExperimentalFeatures.compiled.contains(provider.id))
        storage.lock.withLock {
            precondition(!storage.providers.contains { $0.id == provider.id })
            storage.providers.append(provider)
        }
    }
    private static var providers: [any ExperimentalCommandProvider] { storage.lock.withLock { storage.providers } }
    private static var active: [any ExperimentalCommandProvider] {
        providers.filter { provider in if case .success(true) = availability[provider.id] { true } else { false } }
    }

    /// The root of the command tree: the built-in tree alone unless an extension is enabled.
    static var root: any ParsableCommand.Type { active.isEmpty ? RuriCommand.self : ExtendedRoot.self }
    static var commands: [CommandSpec] { CommandRegistry.commands + active.flatMap(\.commands) }
    static var sections: [(title: String, commands: [String])] {
        active.map { ($0.section, [$0.command.configuration.commandName ?? $0.id]) }
    }

    /// Reads which extensions are enabled in the invocation's data directory,
    /// then runs the invocation with that tree. Without registered extensions
    /// no state is read.
    @MainActor static func withSettings<T>(arguments: [String], operation: () async -> T) async -> T {
        guard !providers.isEmpty else { return await operation() }
        var directory = ProcessInfo.processInfo.environment["RURI_DATA_DIR"]
        let options = arguments.prefix { $0 != "--" }
        for (index, argument) in options.enumerated() {
            if argument.hasPrefix("--data-dir=") { directory = String(argument.dropFirst(11)) }
            else if argument == "--data-dir", options.indices.contains(index + 1) { directory = options[index + 1] }
        }
        let paths = LauncherPaths(root: directory.map { URL(fileURLWithPath: $0) })
        let values = Dictionary(uniqueKeysWithValues: providers.map { provider in (provider.id, Result { try provider.enabled(paths: paths) }) })
        return await $availability.withValue(values, operation: operation)
    }

    /// A family name typed while its extension is off reports that, not an unknown command.
    static func requireEnabled(_ invocation: CommandLineInvocation) throws {
        guard invocation.path.isEmpty, let word = invocation.rest.first,
              let provider = providers.first(where: { $0.command.configuration.commandName == word }) else { return }
        guard try availability[provider.id]?.get() == true else { throw provider.disabledError() }
    }

    @MainActor static func execute(_ request: CommandRequest, output: CommandOutput) async throws -> Value? {
        guard let provider = active.first(where: { $0.command.configuration.commandName == request.spec.path.first }) else { return nil }
        return try await provider.execute(request, output: output)
    }

    /// `config get|set|reset experimental.<id>.enabled --scope app` for compiled extensions.
    static func configure(_ request: CommandRequest) throws -> Value? {
        guard request.spec.path.first == "config", ["get", "set", "reset"].contains(request.spec.path.last),
              let key = request.operands.first, let id = providers.map(\.id).first(where: { key == "experimental.\($0).enabled" }) else { return nil }
        guard try request.required("scope") == "app" else { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.invalidConfigScope.localized) }
        let paths = CLIApplication.basePaths(request)
        let before = try ExperimentalFeatures.enabled(id, paths: paths)
        if request.spec.path.last == "get" { return .object(["scope": .string("app"), "key": .string(key), "effective": .bool(before)]) }
        let after: Bool
        if request.spec.path.last == "reset" { after = false }
        else {
            guard let value = try? JSONDecoder().decode(Bool.self, from: Data(request.operand(1).utf8)) else {
                throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.configValueMustBeJson.localized)
            }
            after = value
        }
        if !request.dryRun { try ExperimentalFeatures.setEnabled(id, after, paths: paths) }
        return .object(["scope": .string("app"), "key": .string(key), "changed": .bool(before != after), "enabled": .bool(after)])
    }

    static func schema(_ command: CommandSpec) -> Value? {
        active.first { $0.command.configuration.commandName == command.path.first }?.schema(command)
    }
    static func sideEffects(_ command: CommandSpec) -> [String]? {
        active.first { $0.command.configuration.commandName == command.path.first }?.sideEffects(command)
    }
    static func presenter(_ path: [String]) -> CommandTextRenderer.Presenter? {
        guard let presenter = active.first(where: { $0.command.configuration.commandName == path.first })?.presenter(path) else { return nil }
        return CommandTextRenderer.Presenter(presenter.presentation) { renderer, value in presenter.render(ExperimentalText(renderer: renderer), value) }
    }

    private struct ExtendedRoot: ParsableCommand {
        @OptionGroup var common: CommonOptions
        static var configuration: CommandConfiguration {
            var configuration = RuriCommand.configuration
            configuration.subcommands += active.map(\.command)
            return configuration
        }
    }
}
