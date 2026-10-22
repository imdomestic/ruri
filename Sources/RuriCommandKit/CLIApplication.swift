import ArgumentParser
import Foundation
import RuriCore
import RuriLocalization

public enum CLIApplication {
    /// Without a custom sink, output goes to stdout and stderr and adapts to
    /// whether they are terminals. A custom sink is treated as a pipe.
    @MainActor public static func run(_ arguments: [String], write custom: (@Sendable (Data, Bool) -> Void)? = nil) async -> Int32 {
        await run(arguments, write: custom, terminal: custom == nil ? .current() : .pipe)
    }

    @MainActor static func run(_ arguments: [String], write custom: (@Sendable (Data, Bool) -> Void)?, terminal: TerminalProfile) async -> Int32 {
        let write = custom ?? { data, error in try? (error ? FileHandle.standardError : FileHandle.standardOutput).write(contentsOf: data) }
        // Enabled extensions decide the command tree, so they are read first.
        return await ExperimentalCommandRegistry.withSettings(arguments: arguments) {
            // The shell completion protocol bypasses every presentation layer.
            if arguments.first == "---completion" { return complete(arguments, write: write) }
            let invocation = CommandLineInvocation(arguments)
            let context = LocalizationContext.commandLine(language: invocation.language)
            return await LocalizationContext.$current.withValue(context) {
                await runLocalized(invocation, write: write, terminal: terminal)
            }
        }
    }

    private static func complete(_ arguments: [String], write: @Sendable (Data, Bool) -> Void) -> Int32 {
        let root = ExperimentalCommandRegistry.root
        do { _ = try root.parseAsRoot(arguments); return 1 }
        catch {
            let code = root.exitCode(for: error).rawValue
            write(Data((root.message(for: error) + "\n").utf8), code != 0)
            return code
        }
    }

    @MainActor private static func runLocalized(_ invocation: CommandLineInvocation, write: @escaping @Sendable (Data, Bool) -> Void, terminal: TerminalProfile) async -> Int32 {
        let args = invocation.arguments
        var output = CommandOutput(format: invocation.format, quiet: invocation.quiet, details: invocation.details, color: invocation.color, write: write, terminal: terminal)
        output.setUsage(invocation.path)
        var activeRequest: CommandRequest?
        do {
            try ExperimentalCommandRegistry.requireEnabled(invocation)
            if invocation.path.isEmpty && invocation.rest.first == "help" {
                let query: CommandHelp.Query
                do { query = try CommandHelp.Query.parse(Array(invocation.rest.dropFirst())) }
                catch {
                    if CommandHelp.Query.exitCode(for: error).rawValue == 0 {
                        output.help(try CommandHelp.render(path: [], width: terminal.output.width)); return 0
                    }
                    throw OperationFailure("INVALID_ARGUMENT", CommandHelp.Query.message(for: error), nextActions: [.init(["help"])])
                }
                guard ["text", "json", "ndjson"].contains(query.common.output), !query.common.json || ["text", "json"].contains(query.common.output) else {
                    throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.invalidOutputFormatCombination.localized)
                }
                output.setUsage(CommandHelp.prefix(in: query.path))
                if invocation.format == .text { output.help(try CommandHelp.render(path: query.path, all: query.all, full: query.full, width: terminal.output.width)) }
                else { output.result(.string(try CommandHelp.render(path: query.path, all: query.all, full: query.full))) }
                return 0
            }
            if invocation.path.isEmpty && args.prefix(while: { $0 != "--" }).contains("--version") {
                output.help(BuildConfiguration().version); return 0
            }
            let passthrough = args.prefix { $0 != "--" }.contains { ["--version", "--generate-completion-script", "--experimental-dump-help"].contains(CommandLineInvocation.optionName($0)) }
            if !passthrough {
                // --help and --version always print text.
                if invocation.helpRequested || (!invocation.isLeaf && invocation.hasOnlyGlobals) {
                    output.help(try CommandHelp.render(path: invocation.path, width: terminal.output.width)); return 0
                }
                if let problem = invocation.problem() { throw problem }
            }
            let command: any ExecutableCommand
            let root = ExperimentalCommandRegistry.root
            do {
                guard let executable = try root.parseAsRoot(args) as? any ExecutableCommand else {
                    output.help(try CommandHelp.render(path: invocation.path, width: terminal.output.width)); return 0
                }
                command = executable
            }
            catch {
                let code = root.exitCode(for: error).rawValue
                if code == 0 {
                    // Completion scripts and the help dump print as they are.
                    let message = root.message(for: error)
                    write(Data((message + (message.hasSuffix("\n") ? "" : "\n")).utf8), false)
                    return 0
                }
                throw CommandLineInvocation.failure(root.message(for: error), path: invocation.path)
            }
            let parsed = command.request
            try parsed.validate()
            output = CommandOutput(format: parsed.common.json ? .json : .init(rawValue: parsed.common.output)!, quiet: parsed.common.quiet, details: parsed.common.details,
                                   color: parsed.common.color, write: write, terminal: terminal)
            output.setUsage(parsed.spec.path)
            output.setRequest(parsed)
            let request = try CommandTargets.resolve(parsed)
            activeRequest = request
            output.setRequest(request)
            let result = try await OperationReadPolicy.$protectedDataRoot.withValue(request.dryRun || !request.spec.mutation ? basePaths(request).root : nil) {
                try await execute(request, output: output)
            }
            var payload = result
            if request.spec.mutation, var fields = result.object {
                fields["dryRun"] = .bool(request.dryRun); payload = .object(fields)
            }
            let warnings = (try? result["warnings"].decode([String].self)) ?? []
            output.result(payload, warnings: warnings); return 0
        } catch {
            var failure: OperationFailure
            if error is CancellationError || Task.isCancelled || (error as? InstanceMoveFailure)?.cancelled == true || (error as? RunDirectoryCopyFailure)?.cancelled == true {
                let original = error as? OperationFailure
                failure = .init("CANCELLED", Messages.CLIInterface.operationCancelled.localized, nextActions: original?.nextActions ?? [], details: original?.details ?? .null)
            }
            else if let value = error as? OperationFailure { failure = value }
            else if let value = error as? RuriError {
                if case .httpResponse(let status, let host) = value {
                    failure = .init("NETWORK_ERROR", value.localizedDescription, retryable: status == 429 || status >= 500, details: .object(["httpStatus": .integer(status), "host": .string(host)]))
                } else { failure = .init("SERVICE_ERROR", value.localizedDescription, details: .object(["messageID": .text(value.messageID)])) }
            } else if let value = error as? URLError {
                failure = .init("NETWORK_ERROR", value.localizedDescription, retryable: true)
            } else { failure = .init("IO_ERROR", error.localizedDescription) }
            if let request = activeRequest { failure = await addingRecovery(to: failure, underlying: error, request: request, output: output) }
            output.result(error: failure)
            return failure.code == "INVALID_ARGUMENT" ? 2 : failure.code == "CANCELLED" ? 130 : 1
        }
    }

    @MainActor static func execute(_ request: CommandRequest, output: CommandOutput) async throws -> Value {
        if let value = try await ExperimentalCommandRegistry.execute(request, output: output) { return value }
        if let value = try ExperimentalCommandRegistry.configure(request) { return value }
        if request.spec.path.first == "config" { return try configure(request) }
        if request.spec.path.first == "doctor" { return try await doctor(request) }
        if request.spec.path.first == "recovery" { return try await manageRecovery(request, output: output) }
        if request.spec.path == ["instance", "import"] || request.spec.path.first == "pack" { return try await managePack(request, output: output) }
        if request.spec.path.first == "download" { return try await fetch(request, output: output) }
        if request.spec.path.first == "instance" { return try await manageInstance(request, output: output) }
        if request.spec.path.first == "directory" { return try await manageDirectory(request, output: output) }
        if request.spec.path.first == "java" { return try await manageJava(request, output: output) }
        if request.spec.path.first == "account" { return try await manageAccount(request, output: output) }
        if request.spec.path.first == "launch" { return try await manageLaunch(request, output: output) }
        if request.spec.path.first == "session" { return try await manageSession(request, output: output) }
        if request.spec.path.first == "catalog" { return try await manageCatalog(request) }
        if request.spec.path.first == "content" { return try await manageContent(request, output: output) }
        if request.spec.path.first == "server" { return try await manageServer(request) }
        if request.spec.path.first == "world" { return try await manageWorld(request, output: output) }
        if request.spec.path.first == "datapack" { return try await manageDataPack(request, output: output) }
        if request.spec.path.first == "schematic" { return try await manageSchematic(request) }
        switch request.path {
        case "schema":
            return try CommandDiscovery.schema(request)
        case "completions":
            // Generated from the command tree alone; no state is read.
            let shell = try request.operand()
            guard let selected = CompletionShell(rawValue: shell) else {
                throw CommandLineInvocation.failure(Messages.CLIExperience.invalidArgumentChoice(shell, request.spec.operands[0].values.joined(separator: ", ")).localized, path: request.spec.path)
            }
            return .object(["shell": .string(shell), "script": .string(ExperimentalCommandRegistry.root.completionScript(for: selected))])
        case "app info":
            return .object(["version": .string(BuildConfiguration().version), "schemaVersion": .integer(1), "application": .text(RuriInstallation.application()?.path),
                "cli": .text(RuriInstallation.cliExecutable?.path), "dataDirectory": .string(basePaths(request).root.path)])
        case "app language get", "app language set":
            let preferences = UserDefaults(suiteName: LocalizationContext.preferenceDomain)!
            if request.path.hasSuffix("set") {
                let language = try request.operand()
                guard language == "system" || LocalizationContext.supportedLanguages.contains(language) else {
                    throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.unsupportedLanguage.localized, details: .array((["system"] + LocalizationContext.supportedLanguages).map(Value.string)))
                }
                if !request.dryRun { LocalizationContext.savePreference(language, in: preferences) }
                return .object(["language": .string(language), "restartRequired": .bool(true), "dryRun": .bool(request.dryRun)])
            }
            return .object(["language": .string(LocalizationContext.savedLanguage(in: preferences)),"supported": .array(LocalizationContext.supportedLanguages.map(Value.string))])
        case "cache status", "cache clean":
            let maintenance = CacheMaintenance(paths: basePaths(request))
            let clean = request.path == "cache clean" && !request.dryRun
            let summary = clean ? maintenance.clean() : maintenance.survey()
            var result: [String: Value] = ["bytes": .integer(Int(summary.bytes)), "files": .integer(summary.files)]
            if request.path == "cache clean" { result["dryRun"] = .bool(request.dryRun) }
            return .object(result)
        case "cli status", "cli install", "cli uninstall":
            let service = try CLIInstallation(binDirectory: request.string("bin-dir").map { URL(fileURLWithPath: $0) })
            if request.path == "cli install" { return try service.install(dryRun: request.dryRun) }
            if request.path == "cli uninstall" { return try service.uninstall(dryRun: request.dryRun) }
            return service.status()
        default: throw OperationFailure("NOT_FOUND", Messages.CLIInterface.unknownCommand.localized)
        }
    }
    static func basePaths(_ request: CommandRequest) -> LauncherPaths {
        LauncherPaths(root: (request.common.dataDir ?? ProcessInfo.processInfo.environment["RURI_DATA_DIR"]).map { URL(fileURLWithPath: $0) })
    }
}
