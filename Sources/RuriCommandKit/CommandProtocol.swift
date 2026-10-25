import RuriLocalization
import ArgumentParser
import Foundation
import RuriCore

public typealias Value = OperationValue

package struct CommonOptions: ParsableArguments {
    @Flag(help: ArgumentHelp(Messages.CLIInterface.jsonOutputHelp.localized)) package var json = false
    @Option(help: ArgumentHelp(Messages.CLIInterface.outputFormatHelp.localized), completion: .list(["text", "json", "ndjson"])) package var output: String = "text"
    @Option(help: ArgumentHelp(Messages.CLIInterface.dataDirectoryHelp.localized), completion: .directory) package var dataDir: String?
    @Option(help: ArgumentHelp(Messages.CLIInterface.messageLanguageHelp.localized), completion: .list(LocalizationContext.commandLineLanguages)) package var language: String?
    @Flag(help: ArgumentHelp(Messages.CLIInterface.quietProgressHelp.localized)) package var quiet = false
    @Flag(help: ArgumentHelp(Messages.CLIExperience.detailsHelp.localized)) package var details = false
    @Option(help: ArgumentHelp(Messages.CLIExperience.colorHelp.localized), completion: .list(Self.colorModes)) package var color: String = "auto"
    package init() {}

    /// Options every command accepts, before, between or after command names.
    static let flags: Set<String> = ["--json", "--quiet", "--details", "--help", "-h", "--help-hidden"]
    static let valued: Set<String> = ["--output", "--data-dir", "--language", "--color"]
    static let colorModes = ["auto", "always", "never"]
    static var synopsis: [String] {
        ["--json", "--output text|json|ndjson", "--data-dir <path>", "--language " + LocalizationContext.commandLineLanguages.joined(separator: "|"),
         "--details", "--color " + colorModes.joined(separator: "|"), "--quiet", "--help"]
    }
}

/// What a parameter refers to. Help, target resolution and completion all read
/// the role, so they cannot disagree about a parameter.
package enum ParameterRole: Sendable, Equatable {
    case text
    case instance, directory, account
    /// A session within the instance named by the command's instance operand.
    case session
    /// app, defaults or instance:<instance>.
    case scope
    /// An instance, or none.
    case preferredInstance
    /// An instance or a directory, depending on the recovery kind before it.
    case recoveryTarget
    case configKey, configGroup
    /// A value for the configuration field named by the operand before it.
    case configValue
    /// An existing file or folder to read, a file to create, or a folder.
    case file, newFile, folder
    case commandPath
}

package struct ParameterSpec: Encodable, Sendable {
    package let name: String
    package let type: String
    package let required: Bool
    package let help: String
    package var values: [String] = []
    package var role: ParameterRole = .text
    package var defaultValue: String? = nil
    package var minimum: Int? = nil
    package var maximum: Int? = nil
    package init(name: String, type: String, required: Bool, help: String, values: [String] = [], role: ParameterRole = .text,
                 defaultValue: String? = nil, minimum: Int? = nil, maximum: Int? = nil) {
        self.name = name; self.type = type; self.required = required; self.help = help; self.values = values; self.role = role
        self.defaultValue = defaultValue; self.minimum = minimum; self.maximum = maximum
    }
    // Presentation metadata stays out of the published descriptor.
    enum CodingKeys: String, CodingKey { case name, type, required, help, values }
    /// The value name shown in usage, such as `--directory <directory>`.
    var placeholder: String {
        switch role {
        case .instance, .preferredInstance: return "instance"
        case .directory, .account, .session, .scope: return String(describing: role)
        case .file, .newFile: return "file"
        case .folder: return "path"
        default: return ["if-revision": "revision", "game": "version", "component": "loader=version", "manual": "fileID=path"][name] ?? name
        }
    }
    var isTarget: Bool { [.instance, .directory, .account, .session, .scope, .preferredInstance, .recoveryTarget].contains(role) }
}

package struct CommandSpec: Encodable, Sendable {
    package let path: [String]
    package let summary: String
    package var operands: [ParameterSpec] = []
    package var options: [ParameterSpec] = []
    package var mutation = false
    package var confirmation = false
    package var userParticipation = false
    package var examples: [String] = []
    package init(path: [String], summary: String, operands: [ParameterSpec] = [], options: [ParameterSpec] = [],
                 mutation: Bool = false, confirmation: Bool = false, userParticipation: Bool = false, examples: [String] = []) {
        self.path = path; self.summary = summary; self.operands = operands; self.options = options
        self.mutation = mutation; self.confirmation = confirmation; self.userParticipation = userParticipation; self.examples = examples
    }
    var supportsDryRun: Bool { options.contains { $0.name == "dry-run" } }
    var configuration: CommandConfiguration { .init(commandName: path.last!, abstract: summary) }
    enum CodingKeys: String, CodingKey { case path, summary, operands, options, mutation, confirmation, userParticipation, examples, supportsDryRun, inputSchema, resultSchema, sideEffects }
    package func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(path, forKey: .path); try c.encode(summary, forKey: .summary)
        try c.encode(operands, forKey: .operands); try c.encode(options, forKey: .options)
        try c.encode(mutation, forKey: .mutation); try c.encode(confirmation, forKey: .confirmation)
        try c.encode(userParticipation, forKey: .userParticipation); try c.encode(examples, forKey: .examples)
        try c.encode(supportsDryRun, forKey: .supportsDryRun)
        try c.encode(CommandSchemas.input(self), forKey: .inputSchema)
        try c.encode(CommandSchemas.result(self), forKey: .resultSchema)
        try c.encode(CommandSchemas.sideEffects(self), forKey: .sideEffects)
    }
}

package protocol ExecutableCommand: ParsableCommand {
    static var spec: CommandSpec { get }
    var common: CommonOptions { get }
    var operands: [String] { get }
    var parameters: [String: Value] { get }
}

package extension ExecutableCommand {
    static var configuration: CommandConfiguration { spec.configuration }
    var request: CommandRequest { .init(spec: Self.spec, common: common, operands: operands, options: parameters) }
    static func help(operand index: Int) -> ArgumentHelp {
        let operand = spec.operands[index]
        return ArgumentHelp(operand.help, valueName: operand.name)
    }
    static func completion(operand index: Int) -> CompletionKind? { CommandCompletion.kind(for: .operand(index), in: spec) }
    static func completion(option name: String) -> CompletionKind? { CommandCompletion.kind(for: .option(name), in: spec) }
}

package struct CommandRequest: Sendable {
    package let spec: CommandSpec
    package let common: CommonOptions
    package let operands: [String]
    package let options: [String: Value]
    package var path: String { spec.path.joined(separator: " ") }
    package var dryRun: Bool { flag("dry-run") }
    package func flag(_ name: String) -> Bool { options[name]?.bool ?? false }
    package func string(_ name: String) -> String? { options[name]?.string }
    package func integer(_ name: String) -> Int? { options[name]?.int }
    package func required(_ name: String) throws -> String {
        guard let value = string(name), !value.isEmpty else { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.missingOption(String(describing: name)).localized) }
        return value
    }
    package func operand(_ index: Int = 0) throws -> String {
        guard operands.indices.contains(index) else { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.missingArgument(String(describing: spec.operands[safe: index]?.name ?? String(index + 1))).localized) }
        return operands[index]
    }
    func validate() throws {
        let minimum = spec.operands.filter(\.required).count
        guard operands.count >= minimum else {
            let missing = spec.operands.dropFirst(operands.count).filter(\.required).map(CommandHelp.operandUsage).joined(separator: " ")
            throw CommandLineInvocation.failure(Messages.CLIExperience.missingArguments(missing).localized, path: spec.path)
        }
        guard operands.count <= spec.operands.count else {
            throw CommandLineInvocation.failure(Messages.CLIExperience.unexpectedArgument(operands[spec.operands.count]).localized, path: spec.path)
        }
        guard ["text", "json", "ndjson"].contains(common.output), !common.json || ["text", "json"].contains(common.output) else {
            throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.invalidOutputFormatCombination.localized)
        }
        guard CommonOptions.colorModes.contains(common.color) else {
            throw CommandLineInvocation.failure(Messages.CLIInterface.invalidOptionChoice("color", CommonOptions.colorModes.joined(separator: ", ")).localized, path: spec.path)
        }
        for option in spec.options {
            if option.required {
                let missing: Bool
                switch option.type {
                case "bool": missing = !flag(option.name)
                case "strings": missing = options[option.name] == nil || options[option.name] == .array([])
                default: missing = options[option.name] == nil || options[option.name] == .string("")
                }
                if missing { throw CommandLineInvocation.failure(Messages.CLIInterface.missingOption(String(describing: option.name)).localized, path: spec.path) }
            }
            if !option.values.isEmpty, let value = string(option.name), !option.values.contains(value) {
                throw CommandLineInvocation.failure(Messages.CLIInterface.invalidOptionChoice(String(describing: option.name), String(describing: option.values.joined(separator: ", "))).localized, path: spec.path)
            }
        }
        if let limit = integer("limit"), !(1...1000).contains(limit) { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.limitOutOfRange.localized) }
        if let offset = integer("offset"), offset < 0 { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.negativeOffset.localized) }
        if spec.confirmation && !dryRun && !flag("yes") {
            throw OperationFailure("CONFIRMATION_REQUIRED", Messages.CLIInterface.confirmationRequired.localized)
        }
    }
    package func page(_ values: [Value]) -> Value {
        let offset = integer("offset") ?? 0, limit = integer("limit") ?? 50
        let items = flag("all") ? values : Array(values.dropFirst(offset).prefix(limit))
        return .object(["items": .array(items), "total": .integer(values.count), "offset": .integer(flag("all") ? 0 : offset), "hasMore": .bool(!flag("all") && offset + items.count < values.count)])
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

// ArgumentParser's option wrappers contain only value types here. Requests stay
// on MainActor; these declarations also allow immutable options in progress work.
extension CommonOptions: @unchecked Sendable {}
