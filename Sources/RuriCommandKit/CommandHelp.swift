import ArgumentParser
import Foundation
import RuriCore
import RuriLocalization

/// Discovery is derived from the same descriptors as execution, without loading state.
enum CommandHelp {
    struct Query: ParsableArguments {
        @Argument var path: [String] = []
        @Flag(help: ArgumentHelp(Messages.CLIExperience.helpAll.localized)) var all = false
        @OptionGroup var common: CommonOptions
    }

    static func commandType(_ path: [String]) -> (any ParsableCommand.Type)? {
        var type: any ParsableCommand.Type = RuriCommand.self
        for component in path {
            guard let child = type.configuration.subcommands.first(where: { $0.configuration.commandName == component }) else { return nil }
            type = child
        }
        return type
    }

    static func prefix(in arguments: [String]) -> [String] {
        var path: [String] = []
        for argument in arguments {
            guard commandType(path + [argument]) != nil else { break }
            path.append(argument)
        }
        return path
    }

    static func signature(_ spec: CommandSpec) -> String {
        let operands = spec.operands.map { $0.required ? "<\($0.name)>" : "[<\($0.name)>]" }
        let required = spec.options.filter { $0.required || ($0.name == "yes" && spec.confirmation) }.map(optionUsage)
        // CHORUS: 独立 CLI 名称。
        return (["ruri-chorus"] + spec.path + operands + required).joined(separator: " ")
    }

    static func optionUsage(_ option: ParameterSpec) -> String {
        let value = option.values.isEmpty ? option.name : option.values.joined(separator: "|")
        return "--" + option.name + (option.type == "bool" ? "" : " <\(value)>" + (option.type == "strings" ? "…" : ""))
    }

    static func index(_ spec: CommandSpec) -> Value {
        .object(["path": .array(spec.path.map(Value.string)), "usage": .string(signature(spec)), "summary": .string(spec.summary)])
    }

    static func render(path: [String], all: Bool = false) throws -> String {
        guard commandType(path) != nil else {
            throw OperationFailure("INVALID_ARGUMENT", Messages.CLIExperience.unknownHelp(path.joined(separator: " ")).localized)
        }
        // CHORUS: 命令描述与实际执行共用注册信息。
        let matches = (CommandRegistry.commands + ChorusGroup.specs).filter { $0.path.starts(with: path) }
        let exact = matches.first { $0.path == path }
        var lines = ["USAGE: " + (exact.map(signature) ?? (["ruri-chorus"] + path + ["<subcommand>"]).joined(separator: " ")) + " [options]", ""]
        if path.isEmpty && !all {
            lines += RuriCommand.configuration.subcommands.map { "  " + ($0.configuration.commandName ?? "") + "  " + $0.configuration.abstract }
        } else {
            if let exact { lines.append(exact.summary) }
            for spec in matches {
                if exact == nil { lines.append(signature(spec) + "  — " + spec.summary) }
                guard !all else { continue }
                let options = exact != nil ? spec.options : spec.options.filter { !["limit", "offset", "all", "yes", "dry-run"].contains($0.name) }
                for option in options { lines.append("  " + optionUsage(option) + "  " + option.help) }
                if exact == nil {
                    let flags = spec.options.filter { ["dry-run", "yes"].contains($0.name) }.map { "--" + $0.name }
                    if !flags.isEmpty { lines.append("  " + flags.joined(separator: "  ")) }
                }
                for example in spec.examples { lines.append("  $ " + example) }
                lines.append("")
            }
        }
        if path.first == "config" && !all {
            lines += [Messages.CLIExperience.configRules.localized, Messages.CLIExperience.configFields.localized]
            for (scope, fields) in [("app", ConfigurationService.appFields), ("defaults / instance:<uuid>", ConfigurationService.launchFields)] {
                lines.append(scope + ":")
                for field in fields {
                    let bounds = [field.minimum.map(String.init), field.maximum.map(String.init)].compactMap { $0 }.joined(separator: "…")
                    let type = field.values.isEmpty ? field.type : field.values.joined(separator: "|")
                    lines.append("  " + field.name + ": " + type + (field.nullable ? "?" : "") + (bounds.isEmpty ? "" : " (\(bounds))"))
                }
            }
        }
        // Shared conventions appear once, even for the complete command index.
        lines += ["", Messages.CLIExperience.discovery.localized, Messages.CLIExperience.rules.localized,
                  Messages.CLIExperience.formats(LocalizationContext.commandLineLanguages.joined(separator: "|")).localized, Messages.CLIExperience.listRules.localized, Messages.CLIExperience.schemaHint.localized]
        return lines.joined(separator: "\n")
    }
}
