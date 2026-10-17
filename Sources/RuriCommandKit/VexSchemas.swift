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
        switch action {
        case "projects": return CommandSchemas.array(CommandSchemas.object(["id": text, "remote": text, "defaultBranch": text, "role": text, "loaders": CommandSchemas.array(text)]))
        case "rooms": return CommandSchemas.array(room)
        case "builds": return CommandSchemas.array(build)
        case "build": return build
        case "create": return room
        case "start": return CommandSchemas.object(["room": room, "lease": CommandSchemas.object(["id": text, "generation": integer, "expiresAt": text])])
        case "branches", "commits": return CommandSchemas.array(CommandSchemas.object([:]))
        case "build-log": return CommandSchemas.object(["log": text])
        case "configure": return CommandSchemas.object(["saved": boolean])
        case "refresh": return CommandSchemas.object(["refreshed": boolean])
        default: return CommandSchemas.object(["project": text, "instanceID": text, "roomID": text, "generation": integer, "buildID": text, "sessionID": text, "room": room, "authenticationRequired": boolean, "destinationArguments": CommandSchemas.array(text)])
        }
    }
}
