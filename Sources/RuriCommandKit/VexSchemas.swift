import Foundation

enum VexSchemas {
    static func payload(_ action: String) -> Value {
        let text = CommandSchemas.string, integer = CommandSchemas.integer, boolean = CommandSchemas.boolean
        let room = CommandSchemas.object([
            "project": text, "id": text, "kind": text, "sha": text, "loader": text, "buildId": text,
            "generation": integer, "host": text, "port": integer, "state": text, "phase": text, "label": text,
            "behindHead": boolean, "players": CommandSchemas.array(CommandSchemas.object(["name": text, "uuid": text]))
        ], required: ["project", "id", "generation", "buildId", "state", "host", "port"])
        let build = CommandSchemas.object([
            "project": text, "id": text, "sha": text, "loader": text, "status": text, "attempt": integer,
            "files": CommandSchemas.array(CommandSchemas.object(["name": text, "sha256": text, "sha1": text, "sha512": text, "size": integer, "side": text, "url": text]))
        ], required: ["project", "id", "status", "attempt", "files"])
        let server = CommandSchemas.object(["baseURL": text, "name": text, "defaultProject": text, "userID": text, "sessionRevision": text], required: ["baseURL", "name"])
        func scoped(_ fields: [String: Value]) -> Value {
            CommandSchemas.object(fields.merging(["server": text, "project": text]) { current, _ in current }, required: ["server", "project"])
        }
        switch action {
        case "add", "login": return server
        case "list": return CommandSchemas.array(server)
        case "default": return CommandSchemas.object(["defaultServer": text])
        case "logout", "remove": return CommandSchemas.object(["server": text, "loggedOut": boolean, "remoteRevoked": boolean, "warnings": CommandSchemas.array(text)])
        case "whoami": return CommandSchemas.object(["server": text, "user": CommandSchemas.object(["id": text, "admin": boolean])])
        case "projects": return CommandSchemas.object(["server": text, "projects": CommandSchemas.array(CommandSchemas.object(["id": text, "remote": text, "defaultBranch": text, "role": text, "loaders": CommandSchemas.array(text)]))])
        case "rooms": return scoped(["rooms": CommandSchemas.array(room)])
        case "builds": return scoped(["builds": CommandSchemas.array(build)])
        case "build": return scoped(["build": build])
        case "create": return scoped(["room": room])
        case "start": return scoped(["room": room, "lease": CommandSchemas.object(["id": text, "generation": integer, "expiresAt": text])])
        case "branches", "commits": return scoped([action: CommandSchemas.array(CommandSchemas.object([:]))])
        case "build-log": return scoped(["build": build, "log": text])
        case "refresh": return scoped(["refreshed": boolean])
        default: return scoped(["instanceID": text, "roomID": text, "generation": integer, "buildID": text, "sessionID": text, "room": room, "authenticationRequired": boolean, "destinationArguments": CommandSchemas.array(text)])
        }
    }
}
