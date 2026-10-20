import Foundation
import AppKit
import ArgumentParser
import Darwin
import RuriCore
import RuriVex
import RuriCommandKit
import RuriLocalization

enum VexCLI {
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

struct VexGroup: ParsableCommand {
    static var configuration: CommandConfiguration {
        .init(commandName: "vex", abstract: Messages.Vex.title.localized,
              subcommands: [VexServersGroup.self, VexCommand<Login>.self, VexCommand<Logout>.self, VexCommand<Whoami>.self,
                            VexCommand<Projects>.self, VexCommand<Rooms>.self, VexCommand<Pulls>.self,
                            VexCommand<Builds>.self, VexCommand<Branches>.self, VexCommand<Commits>.self,
                            VexCommand<Refresh>.self, VexCommand<BuildLog>.self, VexCommand<Build>.self,
                            VexCommand<Create>.self, VexCommand<Start>.self, VexCommand<Prepare>.self, VexCommand<Launch>.self])
    }
    static var specs: [CommandSpec] {
        configuration.subcommands.compactMap { ($0 as? any ExecutableCommand.Type)?.spec } + VexServersGroup.specs
    }
}

struct VexServersGroup: ParsableCommand {
    static var configuration: CommandConfiguration {
        .init(commandName: "servers", abstract: Messages.VexLogin.servers.localized,
              subcommands: [VexCommand<ServerAdd>.self, VexCommand<ServerList>.self, VexCommand<ServerRemove>.self, VexCommand<ServerDefault>.self])
    }
    static var specs: [CommandSpec] { configuration.subcommands.compactMap { ($0 as? any ExecutableCommand.Type)?.spec } }
}
protocol VexAction { static var name: String { get }; static var prefix: [String] { get }; static var operand: String? { get }; static var mutation: Bool { get } }
extension VexAction { static var prefix: [String] { ["vex"] }; static var operand: String? { nil }; static var mutation: Bool { false } }
protocol VexServerAction: VexAction {}
extension VexServerAction { static var prefix: [String] { ["vex", "servers"] } }
enum ServerAdd: VexServerAction { static let name = "add"; static let operand: String? = "address"; static let mutation = true }
enum ServerList: VexServerAction { static let name = "list" }
enum ServerRemove: VexServerAction { static let name = "remove"; static let operand: String? = "name"; static let mutation = true }
enum ServerDefault: VexServerAction { static let name = "default"; static let operand: String? = "name"; static let mutation = true }
enum Login: VexAction { static let name = "login"; static let mutation = true }
enum Logout: VexAction { static let name = "logout"; static let mutation = true }
enum Whoami: VexAction { static let name = "whoami" }
enum Projects: VexAction { static let name = "projects" }
enum Rooms: VexAction { static let name = "rooms" }
enum Pulls: VexAction { static let name = "pulls" }
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
        .init(path: Action.prefix + [Action.name], summary: Messages.Vex.title.localized,
              operands: Action.operand.map { [.init(name: $0, type: "string", required: true, help: $0 == "address" ? Messages.VexNetwork.addressHelp.localized : $0)] } ?? [],
              options: [
                .init(name: "project", type: "string", required: false, help: Messages.Vex.project.localized),
                .init(name: "server", type: "string", required: false, help: Messages.VexLogin.servers.localized),
                .init(name: "name", type: "string", required: false, help: Messages.Servers.name.localized),
                .init(name: "invite", type: "string", required: false, help: Messages.VexLogin.invite.localized),
                .init(name: "method", type: "string", required: false, help: Messages.VexDevices.method.localized),
                .init(name: "github", type: "bool", required: false, help: Messages.VexDevices.github.localized),
                .init(name: "token-stdin", type: "bool", required: false, help: Messages.VexLogin.serviceToken.localized),
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
    @Option var server: String?
    @Option(name: .customLong("name")) var serverName: String?
    @Option var invite: String?
    @Option var method: String?
    @Option var branch: String?
    @Option var before: String?
    @Option var loader: String?
    @Flag(name: .customLong("token-stdin")) var tokenStdin = false
    @Flag var force = false
    @Flag var launch = false
    @Flag var github = false
    @Flag(name: .customLong("dry-run")) var dryRun = false
    var parameters: [String: Value] {
        ["project": .text(project), "server": .text(server), "name": .text(serverName), "invite": .text(invite), "method": .text(method), "branch": .text(branch), "before": .text(before),
         "loader": .text(loader), "token-stdin": .bool(tokenStdin), "force": .bool(force), "launch": .bool(launch), "github": .bool(github), "dry-run": .bool(dryRun)].filter { $0.value != .null }
    }
}

extension VexCLI {
    @MainActor static func manageVex(_ request: CommandRequest, output: CommandOutput) async throws -> Value {
        let paths = CLIApplication.basePaths(request)
        let settings = try VexSettings.load(paths: paths)
        guard settings.enabled else { throw RuriError.message(Messages.Vex.disabled) }
        if request.spec.path.starts(with: ["vex", "servers"]) {
            if request.spec.path.last == "list" { return try .encode(settings.servers) }
            guard !request.dryRun else { return .object(["dryRun": .bool(true)]) }
            if request.spec.path.last == "add" {
                let input = try request.operand()
                output.addSecrets([input])
                var server = try await VexAuthentication.add(input, name: request.string("name"), paths: paths)
                if let project = request.string("project") {
                    server.defaultProject = project
                    try VexSettings.update(paths: paths) { try $0.save(server) }
                }
                return try .encode(server)
            }
            let server = try settings.server(named: request.operand())
            if request.spec.path.last == "remove" {
                let remote = try await VexAuthentication.logout(server, paths: paths, remove: true)
                return logoutResult(server, remote: remote)
            }
            try VexSettings.update(paths: paths) { settings in
                settings.defaultServer = server.id
                if let project = request.string("project"), let index = settings.servers.firstIndex(where: { $0.id == server.id }) {
                    settings.servers[index].defaultProject = project
                }
            }
            return .object(["defaultServer": .string(server.name)])
        }
        let server = try settings.server(named: request.string("server"))
        if request.spec.path.last == "login" {
            guard !request.dryRun else { return .object(["dryRun": .bool(true)]) }
            let loggedIn: VexServer
            if request.flag("token-stdin") {
                guard request.string("method") == nil, request.string("invite") == nil, !request.flag("github") else { throw RuriError.message(Messages.VexDevices.method) }
                let token = try readVexToken()
                output.addSecrets([token])
                loggedIn = try await VexAuthentication.serviceLogin(server, token: token)
            } else {
                let meta = try await VexClient(baseURL: VexSettings.normalizedURL(server.baseURL)).meta()
                let methods = meta.auth.methods.filter { ["invite", "github"].contains($0) }
                guard !request.flag("github") || request.string("method") == nil else { throw RuriError.message(Messages.VexDevices.method) }
                var method = request.flag("github") ? "github" : request.string("method") ?? (request.string("invite") == nil ? nil : "invite")
                if method == nil {
                    guard isatty(STDIN_FILENO) == 1 else { throw RuriError.message(Messages.VexDevices.method) }
                    if methods.count == 1 { method = methods[0] }
                    else { output.help(Messages.VexDevices.chooseMethod.localized); method = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) }
                }
                guard let method, methods.contains(method) else { throw RuriError.message(Messages.VexDevices.unavailable) }
                if method == "github" {
                    guard request.string("invite") == nil else { throw RuriError.message(Messages.VexDevices.method) }
                    let authorization = try await VexAuthentication.beginGitHub(server)
                    output.help(authorization.verificationURL.absoluteString)
                    output.help(authorization.userCode)
                    output.help(Messages.VexDevices.waiting.localized)
                    if !request.common.json && request.common.output == "text" { NSWorkspace.shared.open(authorization.verificationURL) }
                    loggedIn = try await VexAuthentication.finishGitHub(server, authorization: authorization)
                } else {
                    let input: String
                    if let invite = request.string("invite") { input = invite }
                    else {
                        guard isatty(STDIN_FILENO) == 1 else { throw RuriError.message(Messages.VexLogin.inviteHelp) }
                        output.help(Messages.VexLogin.invite.localized)
                        output.help(Messages.VexLogin.inviteHelp.localized)
                        guard let value = readLine() else { throw RuriError.message(Messages.VexLogin.inviteInvalid) }
                        input = value
                    }
                    output.addSecrets([input])
                    loggedIn = try await VexAuthentication.login(server, invite: input)
                }
            }
            try VexSettings.update(paths: paths) { try $0.save(loggedIn) }
            return try .encode(loggedIn)
        }
        if request.spec.path.last == "logout" {
            guard !request.dryRun else { return .object(["dryRun": .bool(true)]) }
            return logoutResult(server, remote: try await VexAuthentication.logout(server, paths: paths))
        }
        let base = try server.client()
        if request.spec.path.last == "whoami" { return .object(["server": .string(server.id), "user": try .encode(await base.me())]) }
        let available = try await base.projects()
        if request.spec.path.last == "projects" { return .object(["server": .string(server.id), "projects": try .encode(available)]) }
        let selected = try server.resolveProject(request.string("project"), available: available)
        let client = try base.selecting(project: selected.id)
        let branch = request.string("branch") ?? selected.defaultBranch
        let loader = request.string("loader") ?? selected.loaders?.first
        switch request.spec.path.last {
        case "rooms": return .object(["server": .string(server.id), "project": .string(selected.id), "rooms": try .encode(await client.rooms())])
        case "pulls": return .object(["server": .string(server.id), "project": .string(selected.id), "pulls": try .encode(await client.pulls())])
        case "builds": return .object(["server": .string(server.id), "project": .string(selected.id), "builds": try .encode(await client.builds())])
        case "branches": return .object(["server": .string(server.id), "project": .string(selected.id), "branches": try .encode(await client.branches())])
        case "build-log":
            let build = try await client.build(request.operand())
            return .object(["server": .string(server.id), "project": .string(selected.id), "build": try .encode(build), "log": .string(try await client.log(build: build.id))])
        case "commits":
            guard let branch else { throw RuriError.message(Messages.Vex.invalidResponse) }
            return .object(["server": .string(server.id), "project": .string(selected.id), "commits": try .encode(await client.commits(branch: branch, before: request.string("before")))])
        case "refresh":
            guard !request.dryRun else { return .object(["dryRun": .bool(true)]) }
            try await client.refreshGit(); return .object(["server": .string(server.id), "project": .string(selected.id), "refreshed": .bool(true)])
        case "build":
            guard let loader, !request.dryRun else { throw RuriError.message(Messages.Vex.invalidResponse) }
            return .object(["server": .string(server.id), "project": .string(selected.id), "build": try .encode(await client.createBuild(sha: request.operand(), loader: loader, force: request.flag("force")))])
        case "create":
            guard let loader, let branch, !request.dryRun else { throw RuriError.message(Messages.Vex.invalidResponse) }
            return .object(["server": .string(server.id), "project": .string(selected.id), "room": try .encode(await client.createRoom(sha: request.operand(), loader: loader, branch: branch))])
        case "start" where !request.flag("launch"):
            guard !request.dryRun else { return .object(["dryRun": .bool(true)]) }
            let result = try await client.start(request.operand())
            return .object(["server": .string(server.id), "project": .string(selected.id), "room": try .encode(result.room), "lease": try .encode(result.lease)])
        case "launch" where request.dryRun:
            let room = try await client.room(request.operand()), build = try await client.build(room.buildId)
            let prepared = try await VexInstanceManager(paths: paths, client: client).installed(build)
            return try .encode(await VexLaunchPlan.inspect(prepared, room: room, paths: paths))
        default:
            guard !request.dryRun else { throw RuriError.message(Messages.Vex.invalidResponse) }
            let joined = try await VexLaunchCoordinator(client: client, paths: paths).prepare(roomID: request.operand())
            if request.spec.path.last == "prepare" { return try .encode(await VexLaunchPlan.inspect(joined.prepared, room: joined.room, paths: paths)) }
            let address = try ServerAddress(joined.room.host + ":" + String(joined.room.port))
            let session = try await ExperimentalLaunchCapabilities(paths: paths).start(instanceID: joined.prepared.instance.id, address: address)
            return .object(["server": .string(server.id), "project": .string(selected.id), "sessionID": .string(session.id.uuidString), "room": try .encode(joined.room)])
        }
    }
    private static func logoutResult(_ server: VexServer, remote: VexLogoutOutcome) -> Value {
        .object(["server": .string(server.id), "loggedOut": .bool(true), "remoteRevoked": .bool(remote.remoteRevoked),
                 "warnings": .array(remote.warning.map { [.string($0)] } ?? [])])
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
