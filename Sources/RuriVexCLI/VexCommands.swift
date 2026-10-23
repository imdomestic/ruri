import AppKit
import Darwin
import Foundation
import RuriCommandKit
import RuriCore
import RuriLocalization
import RuriVex

enum VexCLI {
    @MainActor static func execute(_ request: CommandRequest, output: CommandOutput) async throws -> Value {
        let paths = LauncherPaths(root: (request.common.dataDir ?? ProcessInfo.processInfo.environment["RURI_DATA_DIR"]).map { URL(fileURLWithPath: $0) })
        let settings = try VexSettings.load(paths: paths)
        guard settings.enabled else { throw RuriError.message(Messages.Vex.disabled) }
        if request.spec.path.starts(with: ["vex", "servers"]) {
            return try await servers(request, settings: settings, paths: paths, output: output)
        }
        let server = try settings.server(named: request.string("server")), action = request.spec.path.last!
        if action == "login" {
            try validateLogin(request)
            guard !request.dryRun else { return .object(["server": .string(server.id), "dryRun": .bool(true)]) }
            let loggedIn = try await login(request, server: server, output: output)
            try Task.checkCancellation()
            try VexSettings.update(paths: paths) { try $0.save(loggedIn) }
            return try .encode(loggedIn)
        }
        if action == "logout" {
            guard !request.dryRun else { return .object(["server": .string(server.id), "dryRun": .bool(true)]) }
            return logoutResult(server, remote: try await VexAuthentication.logout(server, paths: paths))
        }
        let base = try server.client(migrateLegacy: !request.dryRun)
        if action == "whoami" { return .object(["server": .string(server.id), "user": try .encode(await base.me())]) }
        let available = try await base.projects()
        if action == "projects" { return .object(["server": .string(server.id), "projects": try .encode(available)]) }
        let selected = try server.resolveProject(request.string("project"), available: available)
        let client = try base.selecting(project: selected.id)
        let branch = request.string("branch") ?? selected.defaultBranch
        let loader = request.string("loader") ?? selected.loaders?.first
        func scoped(_ fields: [String: Value]) -> Value {
            .object(fields.merging(["server": .string(server.id), "project": .string(selected.id)]) { existing, _ in existing })
        }
        switch action {
        case "rooms": return try scoped(["rooms": .encode(await client.rooms())])
        case "pulls": return try scoped(["pulls": .encode(await client.pulls())])
        case "builds": return try scoped(["builds": .encode(await client.builds())])
        case "branches": return try scoped(["branches": .encode(await client.branches())])
        case "build-log":
            let build = try await client.build(request.operand())
            return try scoped(["build": .encode(build), "log": .string(await client.log(build: build.id))])
        case "commits":
            guard let branch else { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.missingOption("branch").localized) }
            return try scoped(["commits": .encode(await client.commits(branch: branch, before: request.string("before")))])
        case "refresh":
            if !request.dryRun { try await client.refreshGit() }
            return scoped(["refreshed": .bool(!request.dryRun)])
        case "build":
            guard let loader else { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.missingOption("loader").localized) }
            if request.dryRun { return try scoped(["sha": .string(request.operand()), "loader": .string(loader), "force": .bool(request.flag("force"))]) }
            return try scoped(["build": .encode(await client.createBuild(sha: request.operand(), loader: loader, force: request.flag("force")))])
        case "create":
            guard let loader else { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.missingOption("loader").localized) }
            guard let branch else { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.missingOption("branch").localized) }
            if request.dryRun { return try scoped(["sha": .string(request.operand()), "loader": .string(loader), "branch": .string(branch)]) }
            return try scoped(["room": .encode(await client.createRoom(sha: request.operand(), loader: loader, branch: branch))])
        case "start" where !request.flag("launch"):
            if request.dryRun { return try scoped(["room": .encode(await client.room(request.operand()))]) }
            let result = try await client.start(request.operand())
            return try scoped(["room": .encode(result.room), "lease": .encode(result.lease)])
        case "launch" where request.dryRun, "start" where request.dryRun:
            let room = try await client.room(request.operand()), build = try await client.build(room.buildId)
            let prepared = try await VexInstanceManager(paths: paths, client: client).installed(build)
            return try .encode(await VexLaunchPlan.inspect(prepared, room: room, paths: paths))
        case "prepare", "launch", "start":
            let joined = try await VexLaunchCoordinator(client: client, paths: paths).prepare(roomID: request.operand())
            if action == "prepare" { return try .encode(await VexLaunchPlan.inspect(joined.prepared, room: joined.room, paths: paths)) }
            let address = try ServerAddress(joined.room.host + ":" + String(joined.room.port))
            let session = try await ExperimentalLaunchCapabilities(paths: paths).start(instanceID: joined.prepared.instance.id, address: address)
            return try scoped(["sessionID": .string(session.id.uuidString), "room": .encode(joined.room)])
        default: throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.unknownCommand.localized)
        }
    }

    @MainActor private static func servers(_ request: CommandRequest, settings: VexSettings, paths: LauncherPaths, output: CommandOutput) async throws -> Value {
        let action = request.spec.path.last!
        if action == "list" { return try .encode(settings.servers) }
        if action == "add" {
            let input = try request.operand()
            output.addSecrets([input])
            if request.dryRun {
                let parsed = try VexServerInput(input)
                return .object(["baseURL": .string(parsed.baseURL.absoluteString), "name": .text(request.string("name")), "defaultProject": .text(request.string("project"))])
            }
            var server = try await VexAuthentication.add(input, name: request.string("name"), paths: paths)
            try Task.checkCancellation()
            if let project = request.string("project") {
                server.defaultProject = project
                try VexSettings.update(paths: paths) { try $0.save(server) }
            }
            return try .encode(server)
        }
        let server = try settings.server(named: request.operand())
        if action == "remove" {
            if request.dryRun { return .object(["server": .string(server.id)]) }
            return logoutResult(server, remote: try await VexAuthentication.logout(server, paths: paths, remove: true))
        }
        guard action == "default" else { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.unknownCommand.localized) }
        if !request.dryRun {
            try VexSettings.update(paths: paths) { settings in
                settings.defaultServer = server.id
                if let project = request.string("project"), let index = settings.servers.firstIndex(where: { $0.id == server.id }) {
                    settings.servers[index].defaultProject = project
                }
            }
        }
        return .object(["defaultServer": .string(server.name), "defaultProject": .text(request.string("project") ?? server.defaultProject)])
    }

    static func validateLogin(_ request: CommandRequest) throws {
        let method = request.string("method"), invite = request.string("invite")
        guard !request.flag("token-stdin") || (method == nil && invite == nil && !request.flag("github")),
              !request.flag("github") || (method == nil && invite == nil),
              method != "github" || invite == nil else {
            throw OperationFailure("INVALID_ARGUMENT", Messages.VexDevices.method.localized)
        }
    }

    @MainActor private static func login(_ request: CommandRequest, server: VexServer, output: CommandOutput) async throws -> VexServer {
        if request.flag("token-stdin") {
            let token = try readToken()
            output.addSecrets([token])
            return try await VexAuthentication.serviceLogin(server, token: token)
        }
        let meta = try await VexClient(baseURL: VexSettings.normalizedURL(server.baseURL)).meta()
        let methods = meta.auth.methods.filter { ["invite", "github"].contains($0) }
        var method = request.flag("github") ? "github" : request.string("method") ?? (request.string("invite") == nil ? nil : "invite")
        if method == nil {
            guard isatty(STDIN_FILENO) == 1 else { throw RuriError.message(Messages.VexDevices.method) }
            if methods.count == 1 { method = methods[0] }
            else {
                output.interaction("authentication", .object(["message": .string(Messages.VexDevices.chooseMethod.localized), "methods": .array(methods.map(Value.string))]))
                method = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        guard let method, methods.contains(method) else { throw RuriError.message(Messages.VexDevices.unavailable) }
        if method == "github" {
            let authorization = try await VexAuthentication.beginGitHub(server)
            output.interaction("authentication", .object(["verificationURL": .string(authorization.verificationURL.absoluteString),
                                        "userCode": .string(authorization.userCode), "message": .string(Messages.VexDevices.waiting.localized)]))
            if !request.common.json && request.common.output == "text" { NSWorkspace.shared.open(authorization.verificationURL) }
            return try await VexAuthentication.finishGitHub(server, authorization: authorization)
        }
        let input: String
        if let invite = request.string("invite") { input = invite }
        else {
            guard isatty(STDIN_FILENO) == 1 else { throw RuriError.message(Messages.VexLogin.inviteHelp) }
            output.interaction("authentication", .object(["message": .string(Messages.VexLogin.inviteHelp.localized)]))
            guard let value = readLine() else { throw RuriError.message(Messages.VexLogin.inviteInvalid) }
            input = value
        }
        output.addSecrets([input])
        return try await VexAuthentication.login(server, invite: input)
    }

    private static func logoutResult(_ server: VexServer, remote: VexLogoutOutcome) -> Value {
        .object(["server": .string(server.id), "loggedOut": .bool(true), "remoteRevoked": .bool(remote.remoteRevoked),
                 "warnings": .array(remote.warning.map { [.string($0)] } ?? [])])
    }
    private static func readToken() throws -> String {
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
