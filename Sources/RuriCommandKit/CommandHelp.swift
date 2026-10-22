import ArgumentParser
import Foundation
import RuriCore
import RuriLocalization

/// Discovery is derived from the same descriptors as execution, without loading state.
enum CommandHelp {
    struct Query: ParsableArguments {
        @Argument var path: [String] = []
        @Flag(help: ArgumentHelp(Messages.CLIExperience.helpAll.localized)) var all = false
        @Flag(help: ArgumentHelp(Messages.CLIExperience.helpFull.localized)) var full = false
        @OptionGroup var common: CommonOptions
    }

    /// The root navigation groups top-level commands by what they are for.
    static var sections: [(title: String, commands: [String])] {
        [(Messages.CLIExperience.sectionPlay.localized, ["launch", "session", "server"]),
         (Messages.CLIExperience.sectionInstances.localized, ["instance", "directory", "java", "account"]),
         (Messages.CLIExperience.sectionContent.localized, ["catalog", "content", "pack", "download"]),
         (Messages.CLIExperience.sectionWorlds.localized, ["world", "datapack", "schematic"]),
         (Messages.CLIExperience.sectionSettings.localized, ["config", "app", "cli", "completions"]),
         (Messages.CLIExperience.sectionMaintenance.localized, ["doctor", "recovery", "cache", "schema"])] + ExperimentalCommandRegistry.sections
    }

    static func commandType(_ path: [String]) -> (any ParsableCommand.Type)? {
        var type: any ParsableCommand.Type = ExperimentalCommandRegistry.root
        for component in path {
            guard let child = type.configuration.subcommands.first(where: { $0.configuration.commandName == component }) else { return nil }
            type = child
        }
        return type
    }

    static func subcommands(_ path: [String]) -> [any ParsableCommand.Type] { commandType(path)?.configuration.subcommands ?? [] }

    static func spec(_ path: [String]) -> CommandSpec? { (commandType(path) as? any ExecutableCommand.Type)?.spec }

    static func prefix(in arguments: [String]) -> [String] {
        var path: [String] = []
        for argument in arguments {
            guard commandType(path + [argument]) != nil else { break }
            path.append(argument)
        }
        return path
    }

    static func operandUsage(_ operand: ParameterSpec) -> String { operand.required ? "<\(operand.name)>" : "[<\(operand.name)>]" }

    static func signature(_ spec: CommandSpec) -> String {
        let required = spec.options.filter { $0.required || ($0.name == "yes" && spec.confirmation) }.map(optionUsage)
        return (["ruri"] + spec.path + spec.operands.map(operandUsage) + required).joined(separator: " ")
    }

    static func usage(_ path: [String]) -> String {
        if let spec = spec(path) { return signature(spec) + " [options]" }
        return (["ruri"] + path + [path.isEmpty ? "<command>" : "<subcommand>"]).joined(separator: " ") + " [options]"
    }

    static func optionUsage(_ option: ParameterSpec) -> String {
        guard option.type != "bool" else { return "--" + option.name }
        // Accepted values are listed with the option's description.
        return "--" + option.name + " <\(option.placeholder)>" + (option.type == "strings" ? "…" : "")
    }

    static func index(_ spec: CommandSpec) -> Value {
        .object(["path": .array(spec.path.map(Value.string)), "usage": .string(signature(spec)), "summary": .string(spec.summary)])
    }

    static func render(path: [String], all: Bool = false, full: Bool = false, width: Int = 80) throws -> String {
        guard let type = commandType(path) else {
            throw OperationFailure("INVALID_ARGUMENT", Messages.CLIExperience.unknownHelp(path.joined(separator: " ")).localized)
        }
        guard !(all && full) else { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIExperience.fullAndAllExclusive.localized) }
        let lines: [String]
        if all { lines = index(path: path, width: width) }
        else if full { lines = complete(path: path, width: width) }
        else if let spec = (type as? any ExecutableCommand.Type)?.spec { lines = leaf(spec, width: width) + [""] + notes(for: [spec], width: width) + globalOptions(width: width) }
        else if path.isEmpty { lines = root(width: width) }
        else { lines = group(path, type: type, width: width) }
        return Self.trimmed(lines).joined(separator: "\n")
    }

    // MARK: Layers

    private static func root(width: Int) -> [String] {
        let sections = sections, labelWidth = sections.map { TerminalText.width($0.title) }.max() ?? 0
        let nameWidth = sections.flatMap { $0.commands }.map(TerminalText.width).max() ?? 0
        var lines = [Messages.CLIExperience.usageLine(usage([])).localized, ""]
        for section in sections {
            for (index, name) in section.commands.enumerated() {
                let label = TerminalText.pad(index == 0 ? section.title : "", to: labelWidth) + "  " + TerminalText.pad(name, to: nameWidth)
                lines += hanging(label, abstract(path: [name]), width: width)
            }
        }
        let examples = ["ruri instance list", "ruri launch start Survival"]
        let examplesLabel = Messages.CLIExperience.helpExamples.localized, moreLabel = Messages.CLIExperience.helpMore.localized
        let column = max(TerminalText.width(examplesLabel), TerminalText.width(moreLabel)) + 1
        lines.append("")
        for (index, example) in examples.enumerated() { lines.append(TerminalText.pad(index == 0 ? examplesLabel : "", to: column) + example) }
        let more = TerminalText.flow(["ruri <command> --help", "ruri help --all"], separator: " · ", width: max(20, width - column))
        lines += more.enumerated().map { TerminalText.pad($0.offset == 0 ? moreLabel : "", to: column) + $0.element }
        return lines
    }

    private static func group(_ path: [String], type: any ParsableCommand.Type, width: Int) -> [String] {
        var lines = TerminalText.wrap(type.configuration.abstract, width: width) + ["", Messages.CLIExperience.usageLine(usage(path)).localized, "", Messages.CLIExperience.helpSubcommands.localized]
        lines += TerminalText.columns(type.configuration.subcommands.map { child in
            let name = child.configuration.commandName ?? ""
            return (name, abstract(path: path + [name]))
        }, maximumLabel: 24, width: width)
        let commands = [(["ruri"] + path + ["<subcommand>", "--help"]).joined(separator: " "), (["ruri", "help"] + path + ["--full"]).joined(separator: " ")]
        lines += [""] + TerminalText.wrap(Messages.CLIExperience.moreLine(TerminalText.flow(commands, separator: " · ", width: .max)[0]).localized, width: width)
        return lines
    }

    /// Purpose, usage, arguments, options and examples of one command.
    static func leaf(_ spec: CommandSpec, width: Int) -> [String] {
        var lines = TerminalText.wrap(spec.summary, width: width) + ["", Messages.CLIExperience.usageLine(signature(spec) + " [options]").localized]
        if !spec.operands.isEmpty {
            lines += ["", Messages.CLIExperience.helpArguments.localized]
            lines += TerminalText.columns(spec.operands.map { operand in ("<\(operand.name)>", TerminalText.sentences([operand.help] + details(operand, operand: true))) }, width: width)
        }
        if !spec.options.isEmpty {
            lines += ["", Messages.CLIExperience.helpOptions.localized]
            lines += TerminalText.columns(spec.options.map { option in (optionUsage(option), TerminalText.sentences([option.help] + details(option, operand: false))) }, width: width)
        }
        if !spec.examples.isEmpty {
            lines += ["", Messages.CLIExperience.helpExamples.localized] + spec.examples.map { "  " + $0 }
        }
        return lines
    }

    private static func index(path: [String], width: Int) -> [String] {
        var lines: [String] = [], previous: String?
        let order = sections.flatMap { $0.commands }
        let specs = ExperimentalCommandRegistry.commands.filter { $0.path.starts(with: path) }.enumerated().sorted { a, b in
            let (x, y) = (order.firstIndex(of: a.element.path[0]) ?? order.count, order.firstIndex(of: b.element.path[0]) ?? order.count)
            return x == y ? a.offset < b.offset : x < y
        }.map(\.element)
        for spec in specs {
            if let previous, previous != spec.path.first { lines.append("") }
            previous = spec.path.first
            lines.append(signature(spec))
            lines += TerminalText.wrap(spec.summary, width: max(20, width - 4)).map { "    " + $0 }
        }
        return lines + [""] + globalOptions(width: width)
    }

    private static func complete(path: [String], width: Int) -> [String] {
        let specs = ExperimentalCommandRegistry.commands.filter { $0.path.starts(with: path) }
        var lines: [String] = []
        for spec in specs { lines += leaf(spec, width: width) + [""] }
        return lines + notes(for: specs, width: width) + globalOptions(width: width)
    }

    // MARK: Parts

    /// Rules that apply to the given commands, each stated once.
    private static func notes(for specs: [CommandSpec], width: Int) -> [String] {
        var notes: [String] = []
        func add(_ message: LocalizedMessage, when condition: Bool) { if condition && !notes.contains(message.localized) { notes.append(message.localized) } }
        let parameters = specs.flatMap { $0.operands + $0.options }
        add(Messages.CLIExperience.noteTargets, when: parameters.contains { [.instance, .directory, .account, .scope, .preferredInstance, .recoveryTarget].contains($0.role) })
        add(Messages.CLIExperience.noteSessions, when: parameters.contains { $0.role == .session })
        add(Messages.CLIExperience.noteConfirmation, when: specs.contains(where: \.confirmation) || parameters.contains { $0.name == "yes" })
        add(Messages.CLIExperience.noteReplace, when: parameters.contains { $0.name == "replace" })
        add(Messages.CLIExperience.notePaging, when: parameters.contains { $0.name == "limit" })
        add(Messages.CLIExperience.noteConfigScopes, when: parameters.contains { $0.role == .scope })
        add(Messages.CLIExperience.noteConfigValues, when: specs.contains { $0.path == ["config", "set"] })
        add(Messages.CLIExperience.noteConfigFields, when: parameters.contains { $0.role == .configKey || $0.role == .configGroup })
        add(Messages.CLIExperience.noteStandardInput, when: specs.contains { $0.path == ["config", "apply"] })
        add(Messages.CLIExperience.noteBrowserSignIn, when: specs.contains { $0.path == ["account", "login", "start"] })
        add(Messages.CLIExperience.noteCompletions, when: specs.contains { $0.path == ["completions"] })
        guard !notes.isEmpty else { return [] }
        return [Messages.CLIExperience.helpNotes.localized] + notes.flatMap { note in
            TerminalText.wrap(note, width: max(20, width - 4)).enumerated().map { ($0.offset == 0 ? "  - " : "    ") + $0.element }
        } + [""]
    }

    private static func globalOptions(width: Int) -> [String] {
        [Messages.CLIExperience.helpGlobalOptions.localized] + TerminalText.flow(CommonOptions.synopsis, width: max(20, width - 2)).map { "  " + $0 }
    }

    private static func details(_ parameter: ParameterSpec, operand: Bool) -> [String] {
        var result: [String] = []
        // Operands show whether they are required in the usage line.
        if parameter.required && !operand { result.append(Messages.CLIExperience.helpRequired.localized) }
        if !parameter.values.isEmpty { result.append(Messages.CLIExperience.helpValues(parameter.values.joined(separator: ", ")).localized) }
        if let value = parameter.defaultValue { result.append(Messages.CLIExperience.helpDefault(value).localized) }
        switch (parameter.minimum, parameter.maximum) {
        case let (minimum?, maximum?): result.append(Messages.CLIExperience.helpRange("\(minimum)–\(maximum)").localized)
        case let (minimum?, nil): result.append(Messages.CLIExperience.helpRange("≥ \(minimum)").localized)
        default: break
        }
        if parameter.type == "strings" { result.append(Messages.CLIExperience.helpRepeatable.localized) }
        return result
    }

    private static func abstract(path: [String]) -> String {
        var text = commandType(path)?.configuration.abstract ?? ""
        if text.hasSuffix(".") || text.hasSuffix("\u{3002}") { text.removeLast() }
        return text
    }

    /// `label  text`, with continuation lines under the start of the text.
    private static func hanging(_ label: String, _ text: String, width: Int) -> [String] {
        let column = TerminalText.width(label) + 2
        if width - column < 24 { return [label] + TerminalText.wrap(text, width: max(10, width - 4)).map { "    " + $0 } }
        let lines = TerminalText.wrap(text, width: max(20, width - column))
        guard let first = lines.first else { return [label] }
        return [label + "  " + first] + lines.dropFirst().map { String(repeating: " ", count: column) + $0 }
    }

    private static func trimmed(_ lines: [String]) -> [String] {
        var result = lines
        while result.last?.isEmpty == true { result.removeLast() }
        // Collapse runs of blank lines left by optional sections.
        return result.enumerated().filter { index, line in !(line.isEmpty && index > 0 && result[index - 1].isEmpty) }.map(\.element)
    }
}
