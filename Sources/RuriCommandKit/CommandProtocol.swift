import RuriLocalization
import ArgumentParser
import Foundation
import RuriCore

public typealias Value = OperationValue

package struct CommonOptions: ParsableArguments {
    @Flag(help: ArgumentHelp(Messages.CLIInterface.jsonOutputHelp.localized)) package var json = false
    @Option(help: ArgumentHelp(Messages.CLIInterface.outputFormatHelp.localized)) package var output: String = "text"
    @Option(help: ArgumentHelp(Messages.CLIInterface.dataDirectoryHelp.localized)) package var dataDir: String?
    @Option(help: ArgumentHelp(Messages.CLIInterface.messageLanguageHelp.localized)) package var language: String?
    @Flag(help: ArgumentHelp(Messages.CLIInterface.quietProgressHelp.localized)) package var quiet = false
    package init() {}
}

package struct ParameterSpec: Codable, Sendable {
    package let name: String
    package let type: String
    package let required: Bool
    package let help: String
    package var values: [String] = []
    package init(name: String, type: String, required: Bool, help: String, values: [String] = []) {
        self.name = name; self.type = type; self.required = required; self.help = help; self.values = values
    }
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
}

package struct CommandRequest: Sendable {
    package let spec: CommandSpec
    package let common: CommonOptions
    package let operands: [String]
    package let options: [String: Value]
    var path: String { spec.path.joined(separator: " ") }
    package var dryRun: Bool { flag("dry-run") }
    package func flag(_ name: String) -> Bool { options[name]?.bool ?? false }
    package func string(_ name: String) -> String? { options[name]?.string }
    func integer(_ name: String) -> Int? { options[name]?.int }
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
        guard operands.count >= minimum, operands.count <= spec.operands.count else {
            throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.positionalArgumentCountMismatch(String(describing: spec.operands.map(\.name).joined(separator: " ")), String(describing: operands.count)).localized)
        }
        guard ["text", "json", "ndjson"].contains(common.output), !common.json || ["text", "json"].contains(common.output) else {
            throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.invalidOutputFormatCombination.localized)
        }
        for option in spec.options {
            if option.required {
                let missing: Bool
                switch option.type {
                case "bool": missing = !flag(option.name)
                case "strings": missing = options[option.name] == nil || options[option.name] == .array([])
                default: missing = options[option.name] == nil || options[option.name] == .string("")
                }
                if missing { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.missingOption(String(describing: option.name)).localized) }
            }
            if !option.values.isEmpty, let value = string(option.name), !option.values.contains(value) {
                throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.invalidOptionChoice(String(describing: option.name), String(describing: option.values.joined(separator: ", "))).localized)
            }
        }
        if let limit = integer("limit"), !(1...1000).contains(limit) { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.limitOutOfRange.localized) }
        if let offset = integer("offset"), offset < 0 { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.negativeOffset.localized) }
        if spec.confirmation && !dryRun && !flag("yes") {
            throw OperationFailure("CONFIRMATION_REQUIRED", Messages.CLIInterface.confirmationRequired.localized)
        }
    }
    func page(_ values: [Value]) -> Value {
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
