import RuriCommandKit

enum VexSchemas {
    private static let text = CommandSchemas.string, integer = CommandSchemas.integer, boolean = CommandSchemas.boolean
    private static func object(_ fields: [String: Value], required: [String] = []) -> Value { CommandSchemas.object(fields, required: required) }
    private static func strings(_ names: [String]) -> [String: Value] { Dictionary(uniqueKeysWithValues: names.map { ($0, text) }) }
    private static func array(_ value: Value) -> Value { CommandSchemas.array(value) }
    private static func map(_ value: Value) -> Value { .object(["type": .string("object"), "additionalProperties": value]) }
    private static func either(_ values: [Value]) -> Value { .object(["anyOf": .array(values)]) }
    private static let error = object(["code": text, "message": text, "details": map(text)], required: ["code", "message"])
    private static let pullMetadata = object(strings(["title", "author", "url", "headSha"]).merging(["number": integer, "fromFork": boolean]) { _, new in new },
                                             required: ["number", "title", "author", "url", "headSha", "fromFork"])
    static let room = object(strings(["project", "id", "kind", "branch", "sha", "loader", "buildId", "host", "state", "phase", "label", "node", "idleSince", "seed", "world", "lastSnapshot", "createdAt", "updatedAt", "closedAt"])
        .merging(["generation": integer, "port": integer, "behindHead": boolean, "pr": pullMetadata,
                  "players": array(object(["name": text, "uuid": text], required: ["name", "uuid"])),
                  "seedResolved": object(["kind": text, "id": text, "rev": text], required: ["kind"]), "lastError": error]) { _, new in new },
        required: ["project", "id", "kind", "sha", "loader", "buildId", "generation", "behindHead", "host", "port", "state", "phase", "label", "players", "seed", "createdAt", "updatedAt"])
    static let build = object(strings(["project", "id", "sha", "loader", "status", "queuedAt", "startedAt", "finishedAt", "minecraft", "loaderVersion", "builtAt", "clientFingerprint", "log"])
        .merging(["attempt": integer, "java": integer, "durationSec": CommandSchemas.number, "modIds": array(text), "lastError": error,
                  "files": array(object(strings(["name", "sha1", "sha256", "sha512", "side", "url"]).merging(["size": integer]) { _, new in new },
                                        required: ["name", "sha256", "size", "side", "url"]))]) { _, new in new },
        required: ["project", "id", "sha", "loader", "status", "attempt", "queuedAt", "modIds", "files", "log"])
    static let server = object(strings(["baseURL", "name", "defaultProject", "userID", "sessionRevision"]), required: ["baseURL", "name"])
    private static let summary = object(["id": text, "status": text], required: ["id", "status"])
    private static let project = object(["id": text, "remote": text, "defaultBranch": text, "role": text, "loaders": array(text)], required: ["id"])
    private static let branch = object(["project": text, "name": text, "head": text, "rooms": map(text), "builds": map(CommandSchemas.nullable(summary))],
                                       required: ["project", "name", "head", "rooms", "builds"])
    private static let commit = object(strings(["project", "sha", "subject", "author", "time"]).merging([
        "parents": array(text), "refs": array(text), "builds": map(CommandSchemas.nullable(summary))]) { _, new in new },
        required: ["project", "sha", "subject", "author", "time", "parents", "refs", "builds"])
    private static let pull = object(strings(["project", "title", "url", "author", "state", "headSha", "headRepository", "baseBranch", "updatedAt"]).merging([
        "number": integer, "draft": boolean, "fork": boolean, "approved": boolean, "rooms": map(text), "builds": map(text)]) { _, new in new },
        required: ["project", "number", "title", "url", "author", "state", "draft", "headSha", "headRepository", "baseBranch", "fork", "approved", "rooms", "builds", "updatedAt"])
    static let plan = object(strings(["server", "project", "instanceID", "roomID", "buildID", "javaPath", "mainClass", "gameDirectory"]).merging([
        "generation": integer, "javaMajor": integer, "destinationArguments": array(text), "authenticationRequired": boolean, "unmanagedMods": array(text)]) { _, new in new },
        required: ["server", "project", "instanceID", "roomID", "generation", "buildID", "javaPath", "javaMajor", "mainClass", "gameDirectory", "destinationArguments", "authenticationRequired", "unmanagedMods"])
    private static func scoped(_ fields: [String: Value], required: [String] = []) -> Value {
        object(fields.merging(["server": text, "project": text]) { existing, _ in existing }, required: ["server", "project"] + required)
    }
    private static func mutationResult(_ schema: Value) -> Value {
        var fields = schema.object!
        if case .array(let alternatives) = fields["anyOf"] {
            fields["anyOf"] = .array(alternatives.map(mutationResult))
        } else {
            var properties = fields["properties"]!.object!
            properties["dryRun"] = boolean
            fields["properties"] = .object(properties)
            if case .array(let required) = fields["required"] { fields["required"] = .array(required + [.string("dryRun")]) }
        }
        return .object(fields)
    }

    static func payload(_ command: CommandSpec) -> Value {
        let action = command.path.last!
        let result: Value
        switch action {
        case "add", "login": result = server
        case "list": result = array(server)
        case "default": result = object(["defaultServer": text, "defaultProject": CommandSchemas.nullable(text)], required: ["defaultServer"])
        case "logout", "remove": result = object(["server": text, "loggedOut": boolean, "remoteRevoked": boolean, "warnings": array(text)], required: ["server", "loggedOut", "remoteRevoked", "warnings"])
        case "whoami": result = object(["server": text, "user": object(["id": text, "admin": boolean], required: ["id", "admin"])], required: ["server", "user"])
        case "projects": result = object(["server": text, "projects": array(project)], required: ["server", "projects"])
        case "rooms": result = scoped(["rooms": array(room)], required: ["rooms"])
        case "pulls": result = scoped(["pulls": array(pull)], required: ["pulls"])
        case "builds": result = scoped(["builds": array(build)], required: ["builds"])
        case "branches": result = scoped(["branches": array(branch)], required: ["branches"])
        case "commits": result = scoped(["commits": array(commit)], required: ["commits"])
        case "build": result = scoped(["build": build], required: ["build"])
        case "create": result = scoped(["room": room], required: ["room"])
        case "start": result = either([
            scoped(["room": room, "lease": object(["id": text, "generation": integer, "expiresAt": text], required: ["id", "generation", "expiresAt"])], required: ["room", "lease"]),
            scoped(["sessionID": text, "room": room], required: ["sessionID", "room"]), plan])
        case "build-log": result = scoped(["build": build, "log": text], required: ["build", "log"])
        case "refresh": result = scoped(["refreshed": boolean], required: ["refreshed"])
        case "prepare": result = plan
        case "launch": result = either([plan, scoped(["sessionID": text, "room": room], required: ["sessionID", "room"])])
        default: preconditionFailure()
        }
        let actual = command.mutation ? mutationResult(result) : result
        guard command.options.contains(where: { $0.name == "dry-run" }) else { return actual }
        let preview: Value
        switch action {
        case "add": preview = object(["baseURL": text, "name": CommandSchemas.nullable(text), "defaultProject": CommandSchemas.nullable(text)])
        case "build": preview = scoped(["sha": text, "loader": text, "force": boolean], required: ["sha", "loader", "force"])
        case "create": preview = scoped(["sha": text, "loader": text, "branch": text], required: ["sha", "loader", "branch"])
        case "start": preview = either([plan, scoped(["room": room], required: ["room"])])
        case "login", "logout", "remove": preview = object(["server": text], required: ["server"])
        default: preview = actual
        }
        return either([actual, .object(["allOf": .array([preview, object(["dryRun": .object(["const": .bool(true)])], required: ["dryRun"])])])])
    }

    static func sideEffects(_ command: CommandSpec) -> [String] {
        switch command.path.last! {
        case "list": return []
        case "whoami", "projects", "rooms", "pulls", "builds", "branches", "commits", "build-log":
            // 正式查询首次读取旧凭据时会执行迁移。
            return ["credentials"]
        case "add": return ["configuration", "credentials", "remoteSession"]
        case "default": return ["configuration"]
        case "remove", "login", "logout": return ["configuration", "credentials", "remoteSession"]
        case "refresh": return ["credentials", "remoteGit"]
        case "build": return ["credentials", "remoteBuild"]
        case "create": return ["credentials", "remoteRoom", "remoteBuild"]
        case "prepare": return ["remoteRoom", "remoteLease", "configuration", "credentials", "downloads", "gameFiles"]
        case "launch", "start": return ["remoteRoom", "remoteLease", "configuration", "credentials", "downloads", "gameFiles", "process", "sessionHistory"]
        default: preconditionFailure()
        }
    }
}
