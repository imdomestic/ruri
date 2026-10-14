import Foundation
import ArgumentParser
import RuriCore
import RuriLocalization

struct ChorusGroup: ParsableCommand {
    static var configuration: CommandConfiguration {
        .init(commandName: "chorus", abstract: Messages.Chorus.title.localized, subcommands: [ChorusConfigureCommand.self, ChorusRoomsCommand.self, ChorusBuildsCommand.self, ChorusStartCommand.self, ChorusPrepareCommand.self, ChorusLaunchCommand.self])
    }
    static var specs: [CommandSpec] { [ChorusConfigureCommand.spec, ChorusRoomsCommand.spec, ChorusBuildsCommand.spec, ChorusStartCommand.spec, ChorusPrepareCommand.spec, ChorusLaunchCommand.spec] }
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
        operands: [.init(name: "room", type: "string", required: true, help: "room")], mutation: true) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "room") var operands: [String] = []
    var parameters: [String: Value] { [:] }
}
struct ChorusLaunchCommand: ExecutableCommand {
    static var spec: CommandSpec { .init(path: ["chorus", "launch"], summary: Messages.CLIInterface.launchStartHelp.localized,
        operands: [.init(name: "room", type: "string", required: true, help: "room")],
        options: [.init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized)], mutation: true) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "room") var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var dryRun = false
    var parameters: [String: Value] { ["dry-run": .bool(dryRun)] }
}

extension CLIApplication {
    @MainActor static func manageChorus(_ request: CommandRequest, output: CommandOutput) async throws -> Value {
        let paths = basePaths(request)
        if request.spec.path.last == "configure" {
            let url = try ChorusSettings.normalizedURL(request.required("url"))
            guard request.flag("token-stdin"), let data = try FileHandle.standardInput.read(upToCount: 16385),
                  data.count <= 16384, let token = String(data: data, encoding: .utf8) else { throw RuriError.message(Messages.Chorus.invalidToken) }
            try ChorusTokenStore.save(token, baseURL: url)
            try ChorusSettings.update(paths: paths) { $0.baseURL = url.absoluteString }
            return .object(["saved": .bool(true), "message": .string(Messages.Chorus.saved.localized)])
        }
        let client = try ChorusSettings.load(paths: paths).client()
        switch request.spec.path.last {
        case "rooms": return try .encode(await client.rooms())
        case "builds": return try .encode(await client.builds())
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
}
