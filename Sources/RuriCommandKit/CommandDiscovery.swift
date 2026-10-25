import Foundation
import RuriCore
import RuriLocalization

enum CommandDiscovery {
    static func schema(_ request: CommandRequest) throws -> Value {
        let matches = ExperimentalCommandRegistry.commands.filter { $0.path.starts(with: request.operands) }
        guard !matches.isEmpty else { throw OperationFailure("NOT_FOUND", Messages.CLIInterface.unknownCommandPath.localized) }
        let exact = matches.first { $0.path == request.operands }
        let input = request.flag("input"), output = request.flag("output-schema"), scope = request.string("scope")
        guard !(input || output || scope != nil) || exact != nil,
              scope == nil || (request.operands.first == "config" && (!output || input)) else {
            throw OperationFailure("INVALID_ARGUMENT", Messages.CLIExperience.schemaSelection.localized)
        }
        if exact == nil && !request.flag("full") {
            return .object(["commands": .array(matches.map(CommandHelp.index))])
        }
        let commands = try matches.map { spec -> Value in
            if input || output {
                var descriptor: [String: Value] = ["path": .array(spec.path.map(Value.string))]
                if input { descriptor["inputSchema"] = CommandSchemas.input(spec) }
                if output { descriptor["resultSchema"] = CommandSchemas.result(spec) }
                return .object(descriptor)
            }
            return try .encode(spec)
        }
        var result: [String: Value] = ["commands": .array(commands)]
        if matches.contains(where: { $0.path.first == "config" }) && (!output || input) {
            if matches.contains(where: { $0.path == ["config", "apply"] }) {
                let patches = CommandSchemas.patches.object!
                result["patchSchemas"] = .object(scope.map { [$0: patches[$0]!] } ?? patches)
            } else {
                let fields = scope == "app" ? ConfigurationService.appFields : scope == nil ? ConfigurationService.appFields + ConfigurationService.launchFields : ConfigurationService.launchFields
                result["configuration"] = try .encode(fields)
            }
        }
        return .object(result)
    }
}
