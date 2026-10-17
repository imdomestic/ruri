import Foundation
import ArgumentParser
import RuriCore
import RuriLocalization

enum VexCLI {
    @TaskLocal static var settings: Result<VexSettings, any Error> = .success(VexSettings())
    static var enabled: Bool {
        switch settings {
        case .success(let value): value.enabled
        case .failure: false
        }
    }
    static func requireEnabled() throws {
        guard try settings.get().enabled else { throw RuriError.message(Messages.Vex.disabled) }
    }
    static var root: any ParsableCommand.Type { enabled ? VexRootCommand.self : RuriCommand.self }
    static var commands: [CommandSpec] { CommandRegistry.commands + (enabled ? VexGroup.specs : []) }
    @MainActor static func withSettings(arguments: [String], operation: () async -> Int32) async -> Int32 {
        var directory = ProcessInfo.processInfo.environment["RURI_DATA_DIR"]
        for (index, argument) in arguments.enumerated() {
            if argument.hasPrefix("--data-dir=") { directory = String(argument.dropFirst(11)) }
            else if argument == "--data-dir", arguments.indices.contains(index + 1) { directory = arguments[index + 1] }
        }
        let paths = LauncherPaths(root: directory.map { URL(fileURLWithPath: $0) })
        let value = Result { try VexSettings.load(paths: paths) }
        return await $settings.withValue(value, operation: operation)
    }
    static func configure(_ request: CommandRequest, paths: LauncherPaths) throws -> Value? {
        guard request.spec.path.first == "config", request.operands.first == "experimental.vex.enabled" else { return nil }
        guard try request.required("scope") == "app" else { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.invalidConfigScope.localized) }
        let before = try VexSettings.load(paths: paths).enabled
        if request.spec.path.last == "get" { return .object(["key": .string("experimental.vex.enabled"), "effective": .bool(before)]) }
        let after: Bool
        if request.spec.path.last == "reset" { after = false }
        else if request.spec.path.last == "set" {
            guard let value = try? JSONDecoder().decode(Bool.self, from: Data(request.operand(1).utf8)) else {
                throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.configValueMustBeJson.localized)
            }
            after = value
        } else { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.unknownCommand.localized) }
        if !request.dryRun { try VexSettings.update(paths: paths) { $0.enabled = after } }
        return .object(["changed": .bool(before != after), "enabled": .bool(after), "dryRun": .bool(request.dryRun)])
    }
}

private struct VexRootCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        var configuration = RuriCommand.configuration
        configuration.subcommands.append(VexGroup.self)
        return configuration
    }
}

struct VexGroup: ParsableCommand {
    static var configuration: CommandConfiguration {
        .init(commandName: "vex", abstract: Messages.Vex.title.localized,
              subcommands: [VexCommand<Configure>.self, VexCommand<Projects>.self, VexCommand<Rooms>.self,
                            VexCommand<Builds>.self, VexCommand<Branches>.self, VexCommand<Commits>.self,
                            VexCommand<Refresh>.self, VexCommand<BuildLog>.self, VexCommand<Build>.self,
                            VexCommand<Create>.self, VexCommand<Start>.self, VexCommand<Prepare>.self, VexCommand<Launch>.self])
    }
    static var specs: [CommandSpec] {
        configuration.subcommands.compactMap { ($0 as? any ExecutableCommand.Type)?.spec }
    }
}

protocol VexAction { static var name: String { get }; static var operand: String? { get }; static var mutation: Bool { get } }
extension VexAction { static var operand: String? { nil }; static var mutation: Bool { false } }
enum Configure: VexAction { static let name = "configure"; static let mutation = true }
enum Projects: VexAction { static let name = "projects" }
enum Rooms: VexAction { static let name = "rooms" }
enum Builds: VexAction { static let name = "builds" }
enum Branches: VexAction { static let name = "branches" }
enum Commits: VexAction { static let name = "commits" }
enum Refresh: VexAction { static let name = "refresh"; static let mutation = true }
enum BuildLog: VexAction { static let name = "build-log"; static let operand: String? = "build" }
enum Build: VexAction { static let name = "build"; static let operand: String? = "sha"; static let mutation = true }
enum Create: VexAction { static let name = "create"; static let operand: String? = "sha"; static let mutation = true }
enum Start: VexAction { static let name = "start"; static let operand: String? = "room"; static let mutation = true }
enum Prepare: VexAction { static let name = "prepare"; static let operand: String? = "room"; static let mutation = true }
enum Launch: VexAction { static let name = "launch"; static let operand: String? = "room"; static let mutation = true }

struct VexCommand<Action: VexAction>: ExecutableCommand {
    static var spec: CommandSpec {
        .init(path: ["vex", Action.name], summary: Messages.Vex.title.localized,
              operands: Action.operand.map { [.init(name: $0, type: "string", required: true, help: $0)] } ?? [],
              options: [
                .init(name: "project", type: "string", required: false, help: Messages.Vex.project.localized),
                .init(name: "url", type: "string", required: false, help: Messages.Vex.backendURL.localized),
                .init(name: "token-stdin", type: "bool", required: false, help: Messages.Vex.token.localized),
                .init(name: "branch", type: "string", required: false, help: "branch"),
                .init(name: "before", type: "string", required: false, help: "sha"),
                .init(name: "loader", type: "string", required: false, help: "loader"),
                .init(name: "force", type: "bool", required: false, help: "force"),
                .init(name: "launch", type: "bool", required: false, help: Messages.CLIInterface.launchStartHelp.localized),
                .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized)
              ], mutation: Action.mutation)
    }
    @OptionGroup var common: CommonOptions
    @Argument var operands: [String] = []
    @Option var project: String?
    @Option var url: String?
    @Option var branch: String?
    @Option var before: String?
    @Option var loader: String?
    @Flag(name: .customLong("token-stdin")) var tokenStdin = false
    @Flag var force = false
    @Flag var launch = false
    @Flag(name: .customLong("dry-run")) var dryRun = false
    var parameters: [String: Value] {
        ["project": .text(project), "url": .text(url), "branch": .text(branch), "before": .text(before),
         "loader": .text(loader), "token-stdin": .bool(tokenStdin), "force": .bool(force), "launch": .bool(launch), "dry-run": .bool(dryRun)].filter { $0.value != .null }
    }
}

extension CLIApplication {
    @MainActor static func manageVex(_ request: CommandRequest, output: CommandOutput) async throws -> Value {
        let paths = basePaths(request)
        let settings = try VexSettings.load(paths: paths)
        guard settings.enabled else { throw RuriError.message(Messages.Vex.disabled) }
        if request.spec.path.last == "configure" {
            let url = try VexSettings.normalizedURL(request.required("url"))
            guard !request.dryRun, request.flag("token-stdin") else { throw RuriError.message(Messages.Vex.invalidToken) }
            try VexTokenStore.save(readVexToken(), baseURL: url)
            try VexSettings.update(paths: paths) { value in
                value.baseURL = url.absoluteString
                if let project = request.string("project") { value.project = project }
            }
            return .object(["saved": .bool(true)])
        }
        let project = request.string("project") ?? settings.project
        let client = try request.flag("token-stdin")
            ? VexClient(baseURL: VexSettings.normalizedURL(settings.baseURL), token: readVexToken(), project: project)
            : settings.client(project: project)
        if request.spec.path.last == "projects" { return try .encode(await client.projects()) }
        guard VexClient.validProject(project) else { throw RuriError.message(Messages.Vex.projectRequired) }
        let selected = try await client.projects().first { $0.id == project }
        guard let selected else { throw RuriError.message(Messages.Vex.projectRequired) }
        let branch = request.string("branch") ?? selected.defaultBranch
        let loader = request.string("loader") ?? selected.loaders?.first
        switch request.spec.path.last {
        case "rooms": return try .encode(await client.rooms())
        case "builds": return try .encode(await client.builds())
        case "branches": return try .encode(await client.branches())
        case "build-log":
            let build = try await client.build(request.operand())
            return .object(["build": try .encode(build), "log": .string(try await client.log(build: build.id))])
        case "commits":
            guard let branch else { throw RuriError.message(Messages.Vex.invalidResponse) }
            return try .encode(await client.commits(branch: branch, before: request.string("before")))
        case "refresh":
            guard !request.dryRun else { return .object(["dryRun": .bool(true)]) }
            try await client.refreshGit(); return .object(["refreshed": .bool(true)])
        case "build":
            guard let loader, !request.dryRun else { throw RuriError.message(Messages.Vex.invalidResponse) }
            return try .encode(await client.createBuild(sha: request.operand(), loader: loader, force: request.flag("force")))
        case "create":
            guard let loader, let branch, !request.dryRun else { throw RuriError.message(Messages.Vex.invalidResponse) }
            return try .encode(await client.createRoom(sha: request.operand(), loader: loader, branch: branch))
        case "start" where !request.flag("launch"):
            guard !request.dryRun else { return .object(["dryRun": .bool(true)]) }
            return try .encode(await client.start(request.operand()))
        case "launch" where request.dryRun:
            let room = try await client.room(request.operand()), build = try await client.build(room.buildId)
            let prepared = try await VexInstanceManager(paths: paths, client: client).installed(build)
            return try .encode(await VexLaunchPlan.inspect(prepared, room: room, paths: paths))
        default:
            guard !request.dryRun else { throw RuriError.message(Messages.Vex.invalidResponse) }
            let joined = try await VexLaunchCoordinator(client: client, paths: paths).prepare(roomID: request.operand())
            if request.spec.path.last == "prepare" { return try .encode(await VexLaunchPlan.inspect(joined.prepared, room: joined.room, paths: paths)) }
            let address = try ServerAddress(joined.room.host + ":" + String(joined.room.port))
            let session = try await LaunchService(paths: paths).start(instanceID: joined.prepared.instance.id, destination: .server(address))
            return .object(["sessionID": .string(session.id.uuidString), "room": try .encode(joined.room)])
        }
    }
    private static func readVexToken() throws -> String {
        var data = Data()
        while let chunk = try FileHandle.standardInput.read(upToCount: 4096), !chunk.isEmpty {
            data.append(chunk)
            guard data.count <= 16384 else { throw RuriError.message(Messages.Vex.invalidToken) }
        }
        guard let token = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else {
            throw RuriError.message(Messages.Vex.invalidToken)
        }
        return token
    }
}
