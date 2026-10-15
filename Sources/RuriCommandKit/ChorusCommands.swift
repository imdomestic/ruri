import Foundation
import ArgumentParser
import RuriCore
import RuriLocalization

struct ChorusGroup: ParsableCommand {
    static var configuration: CommandConfiguration {
        .init(commandName: "chorus", abstract: Messages.Chorus.title.localized, subcommands: [ChorusConfigureCommand.self, ChorusRoomsCommand.self, ChorusBuildsCommand.self, ChorusBuildLogCommand.self, ChorusStartCommand.self, ChorusPrepareCommand.self, ChorusLaunchCommand.self, ChorusBranchesCommand.self, ChorusCommitsCommand.self, ChorusBuildCommand.self, ChorusCreateCommand.self])
    }
    static var specs: [CommandSpec] { [ChorusConfigureCommand.spec, ChorusRoomsCommand.spec, ChorusBuildsCommand.spec, ChorusBuildLogCommand.spec, ChorusStartCommand.spec, ChorusPrepareCommand.spec, ChorusLaunchCommand.spec, ChorusBranchesCommand.spec, ChorusCommitsCommand.spec, ChorusBuildCommand.spec, ChorusCreateCommand.spec] }
}

struct ChorusConfigureCommand: ExecutableCommand {
    static var spec: CommandSpec { .init(path: ["chorus", "configure"], summary: Messages.Chorus.token.localized, options: [
        .init(name: "url", type: "string", required: true, help: Messages.Chorus.backendURL.localized),
        .init(name: "token-stdin", type: "bool", required: true, help: Messages.Chorus.token.localized)
    ], mutation: true) }
    @OptionGroup var common: CommonOptions
    @Option(help: ArgumentHelp(Messages.Chorus.backendURL.localized)) var url: String
    @Flag(name: .customLong("token-stdin"), help: ArgumentHelp(Messages.Chorus.token.localized)) var tokenStdin = false
    var operands: [String] { [] }
    var parameters: [String: Value] { ["url": .string(url), "token-stdin": .bool(tokenStdin)] }
}
struct ChorusRoomsCommand: ExecutableCommand {
    static var spec: CommandSpec { .init(path: ["chorus", "rooms"], summary: Messages.Servers.page.localized) }
    @OptionGroup var common: CommonOptions
    var operands: [String] { [] }
    var parameters: [String: Value] { [:] }
}
struct ChorusBuildsCommand: ExecutableCommand {
    static var spec: CommandSpec { .init(path: ["chorus", "builds"], summary: Messages.Chorus.buildOnly.localized) }
    @OptionGroup var common: CommonOptions
    var operands: [String] { [] }
    var parameters: [String: Value] { [:] }
}
struct ChorusBuildLogCommand: ExecutableCommand {
    static var spec: CommandSpec { .init(path: ["chorus", "build-log"], summary: Messages.Chorus.buildLog.localized,
        operands: [.init(name: "build", type: "string", required: true, help: "build")],
        options: [.init(name: "token-stdin", type: "bool", required: false, help: Messages.Chorus.token.localized)]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "build") var operands: [String] = []
    @Flag(name: .customLong("token-stdin"), help: ArgumentHelp(Messages.Chorus.token.localized)) var tokenStdin = false
    var parameters: [String: Value] { ["token-stdin": .bool(tokenStdin)] }
}
struct ChorusStartCommand: ExecutableCommand {
    static var spec: CommandSpec { .init(path: ["chorus", "start"], summary: Messages.Chorus.preparing.localized,
        operands: [.init(name: "room", type: "string", required: true, help: "room")],
        options: [.init(name: "launch", type: "bool", required: false, help: Messages.CLIInterface.launchStartHelp.localized)], mutation: true) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "room") var operands: [String] = []
    @Flag(help: ArgumentHelp(Messages.CLIInterface.launchStartHelp.localized)) var launch = false
    var parameters: [String: Value] { ["launch": .bool(launch)] }
}
struct ChorusPrepareCommand: ExecutableCommand {
    static var spec: CommandSpec { .init(path: ["chorus", "prepare"], summary: Messages.Chorus.preparing.localized,
        operands: [.init(name: "room", type: "string", required: true, help: "room")],
        options: [.init(name: "token-stdin", type: "bool", required: false, help: Messages.Chorus.token.localized)], mutation: true) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "room") var operands: [String] = []
    @Flag(name: .customLong("token-stdin"), help: ArgumentHelp(Messages.Chorus.token.localized)) var tokenStdin = false
    var parameters: [String: Value] { ["token-stdin": .bool(tokenStdin)] }
}
struct ChorusLaunchCommand: ExecutableCommand {
    static var spec: CommandSpec { .init(path: ["chorus", "launch"], summary: Messages.CLIInterface.launchStartHelp.localized,
        operands: [.init(name: "room", type: "string", required: true, help: "room")],
        options: [.init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized),
                  .init(name: "token-stdin", type: "bool", required: false, help: Messages.Chorus.token.localized)], mutation: true) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "room") var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var dryRun = false
    @Flag(name: .customLong("token-stdin"), help: ArgumentHelp(Messages.Chorus.token.localized)) var tokenStdin = false
    var parameters: [String: Value] { ["dry-run": .bool(dryRun), "token-stdin": .bool(tokenStdin)] }
}

struct ChorusBranchesCommand: ExecutableCommand {
    static var spec: CommandSpec { .init(path: ["chorus", "branches"], summary: Messages.Chorus.git.localized) }
    @OptionGroup var common: CommonOptions
    var operands: [String] { [] }
    var parameters: [String: Value] { [:] }
}
struct ChorusCommitsCommand: ExecutableCommand {
    static var spec: CommandSpec { .init(path: ["chorus", "commits"], summary: Messages.Chorus.git.localized, options: [
        .init(name: "branch", type: "string", required: false, help: "branch"),
        .init(name: "before", type: "string", required: false, help: "SHA")
    ]) }
    @OptionGroup var common: CommonOptions
    @Option(help: "branch") var branch = "main"
    @Option(help: "SHA") var before: String?
    var operands: [String] { [] }
    var parameters: [String: Value] { var values: [String: Value] = ["branch": .string(branch)]; if let before { values["before"] = .string(before) }; return values }
}
struct ChorusBuildCommand: ExecutableCommand {
    static var spec: CommandSpec { .init(path: ["chorus", "build"], summary: Messages.Chorus.buildOnly.localized,
        operands: [.init(name: "sha", type: "string", required: true, help: "SHA")], options: [
            .init(name: "loader", type: "string", required: false, help: "loader"),
            .init(name: "force", type: "bool", required: false, help: "force")
        ], mutation: true) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "SHA") var operands: [String] = []
    @Option(help: "loader") var loader = "fabric"
    @Flag(help: "force") var force = false
    var parameters: [String: Value] { ["loader": .string(loader), "force": .bool(force)] }
}
struct ChorusCreateCommand: ExecutableCommand {
    static var spec: CommandSpec { .init(path: ["chorus", "create"], summary: Messages.Chorus.startTemporary.localized,
        operands: [.init(name: "sha", type: "string", required: true, help: "SHA")], options: [
            .init(name: "loader", type: "string", required: false, help: "loader"),
            .init(name: "branch", type: "string", required: false, help: "branch")
        ], mutation: true) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "SHA") var operands: [String] = []
    @Option(help: "loader") var loader = "fabric"
    @Option(help: "branch") var branch = "main"
    var parameters: [String: Value] { ["loader": .string(loader), "branch": .string(branch)] }
}

extension CLIApplication {
    @MainActor static func manageChorus(_ request: CommandRequest, output: CommandOutput) async throws -> Value {
        let paths = basePaths(request)
        if request.spec.path.last == "configure" {
            let url = try ChorusSettings.normalizedURL(request.required("url"))
            guard request.flag("token-stdin") else { throw RuriError.message(Messages.Chorus.invalidToken) }
            try ChorusSettings.configure(paths: paths, baseURL: url.absoluteString, token: readChorusToken())
            return .object(["saved": .bool(true), "message": .string(Messages.Chorus.saved.localized)])
        }
        let settings = try ChorusSettings.load(paths: paths)
        let client = try request.flag("token-stdin")
            ? ChorusClient(baseURL: ChorusSettings.normalizedURL(settings.baseURL), token: readChorusToken())
            : settings.client()
        switch request.spec.path.last {
        case "rooms": return try .encode(await client.rooms())
        case "builds": return try .encode(await client.builds())
        case "build-log":
            let build = try await client.build(request.operand())
            let log = try await client.log(build: build.id)
            return .object(["build": try .encode(build), "log": .string(log)])
        case "branches": return try .encode(await client.branches())
        case "commits": return try .encode(await client.commits(branch: request.required("branch"), before: request.string("before")))
        case "build": return try .encode(await client.createBuild(sha: request.operand(), loader: request.required("loader"), force: request.flag("force")))
        case "create": return try .encode(await client.createRoom(sha: request.operand(), loader: request.required("loader"), branch: request.required("branch")))
        case "start" where !request.flag("launch"): return try .encode(await client.start(request.operand()))
        case "launch" where request.dryRun:
            let room = try await client.room(request.operand())
            let build = try await client.build(room.buildId)
            let prepared = try await ChorusInstanceManager(paths: paths, client: client).installed(build)
            return try .encode(await ChorusLaunchPlan.inspect(prepared, room: room, paths: paths))
        default:
            let joined = try await ChorusLaunchCoordinator(client: client, paths: paths).prepare(roomID: request.operand())
            if request.spec.path.last == "prepare" { return try .encode(await ChorusLaunchPlan.inspect(joined.prepared, room: joined.room, paths: paths)) }
            let address = try ServerAddress(joined.room.host + ":" + String(joined.room.port))
            let session = try await LaunchService(paths: paths).start(instanceID: joined.prepared.instance.id, destination: .server(address))
            return .object(["sessionID": .string(session.id.uuidString), "room": try .encode(joined.room)])
        }
    }

    private static func readChorusToken() throws -> String {
        var data = Data()
        while let chunk = try FileHandle.standardInput.read(upToCount: 4096), !chunk.isEmpty {
            data.append(chunk)
            guard data.count <= 16384 else { throw RuriError.message(Messages.Chorus.invalidToken) }
        }
        guard let token = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else {
            throw RuriError.message(Messages.Chorus.invalidToken)
        }
        return token
    }
}
