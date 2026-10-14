import ArgumentParser
import Foundation
import RuriCore
import RuriLocalization

public enum CLIApplication {
    @MainActor public static func run(_ arguments: [String], write: @escaping @Sendable (Data, Bool) -> Void = { data, error in
        try? (error ? FileHandle.standardError : FileHandle.standardOutput).write(contentsOf: data)
    }) async -> Int32 {
        let args = normalizeGlobals(arguments)
        let options = Array(args.prefix { $0 != "--" })
        var language: String?
        for (index, argument) in options.enumerated() {
            if argument.hasPrefix("--language=") { language = String(argument.dropFirst(11)) }
            else if argument == "--language" { language = options[safe: index + 1] }
        }
        let context = LocalizationContext.commandLine(language: language)
        return await LocalizationContext.$current.withValue(context) {
            await runLocalized(args, write: write)
        }
    }

    @MainActor private static func runLocalized(_ args: [String], write: @escaping @Sendable (Data, Bool) -> Void) async -> Int32 {
        var output = CommandOutput(format: requestedFormat(args), quiet: args.contains("--quiet"), write: write)
        var activeRequest: CommandRequest?
        do {
            if args.first == "help" {
                let query: CommandHelp.Query
                do { query = try CommandHelp.Query.parse(Array(args.dropFirst())) }
                catch {
                    if CommandHelp.Query.exitCode(for: error).rawValue == 0 {
                        output.help(try CommandHelp.render(path: [])); return 0
                    }
                    throw OperationFailure("INVALID_ARGUMENT", CommandHelp.Query.message(for: error))
                }
                guard ["text", "json", "ndjson"].contains(query.common.output), !query.common.json || ["text", "json"].contains(query.common.output) else {
                    throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.invalidOutputFormatCombination.localized)
                }
                let help = try CommandHelp.render(path: query.path, all: query.all)
                if requestedFormat(args) == .text { output.help(help) }
                else { output.result(.string(help)) }
                return 0
            }
            let command: any ExecutableCommand
            do {
                var parsed = try RuriCommand.parseAsRoot(args)
                if let executable = parsed as? any ExecutableCommand { command = executable }
                else {
                    // ArgumentParser returns a built-in help command carrying
                    // the requested command stack. Running it produces the
                    // correct help request, including the root command name.
                    try parsed.run()
                    return 0
                }
            }
            catch {
                let code = RuriCommand.exitCode(for: error).rawValue
                if code == 0 {
                    let options = args.prefix { $0 != "--" }
                    if options.contains("--version") || options.contains("--experimental-dump-help") {
                        output.help(RuriCommand.message(for: error))
                    } else {
                        output.help(try CommandHelp.render(path: CommandHelp.prefix(in: args)))
                    }
                    return 0
                }
                throw OperationFailure("INVALID_ARGUMENT", RuriCommand.message(for: error))
            }
            let request = command.request
            try request.validate()
            activeRequest = request
            output = CommandOutput(format: request.common.json ? .json : .init(rawValue: request.common.output)!, quiet: request.common.quiet, write: write)
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
        // CHORUS: 独立后端命令。
        if request.spec.path.first == "chorus" { return try await manageChorus(request, output: output) }
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
    private static func requestedFormat(_ args: [String]) -> CommandOutput.Format {
        let options = Array(args.prefix { $0 != "--" })
        if options.contains("--json") { return .json }
        if let item = options.first(where: { $0.hasPrefix("--output=") }), let format = CommandOutput.Format(rawValue: String(item.dropFirst(9))) { return format }
        if let index = options.firstIndex(of: "--output"), let name = options[safe: index + 1], let format = CommandOutput.Format(rawValue: name) { return format }
        return .text
    }
    /// Leading global options, including help, move to the leaf command.
    /// Options after `--` remain literal operands.
    static func normalizeGlobals(_ args: [String]) -> [String] {
        var prefix: [String] = [], remaining = args
        while let first = remaining.first {
            let name = first.split(separator: "=", maxSplits: 1).first.map(String.init) ?? first
            if ["--json", "--quiet", "--help", "-h", "--help-hidden"].contains(name) { prefix.append(remaining.removeFirst()) }
            else if ["--output", "--data-dir", "--language"].contains(name) {
                prefix.append(remaining.removeFirst())
                if !first.contains("="), let next = remaining.first, !next.hasPrefix("--") { prefix.append(remaining.removeFirst()) }
            } else { break }
        }
        if let index = remaining.firstIndex(of: "--") { remaining.insert(contentsOf: prefix, at: index) }
        else { remaining.append(contentsOf: prefix) }
        return remaining
    }
}
