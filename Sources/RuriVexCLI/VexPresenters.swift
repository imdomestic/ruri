import RuriCommandKit
import RuriLocalization
import RuriVex

enum VexPresenters {
    static func presenter(_ path: [String]) -> ExperimentalTextPresenter? {
        guard path.first == "vex", let action = path.last else { return nil }
        if action == "list" || ["projects", "rooms", "pulls", "builds", "branches", "commits"].contains(action) {
            return .init(.list) { text, value in
                let records = action == "list" ? value : value[action]
                guard case .array(let items) = records else { preconditionFailure() }
                let page: Value = .object(["items": .array(items), "total": .integer(items.count), "offset": .integer(0), "hasMore": .bool(false)])
                let scope = text.details ? text.fields(scopeRows(text, value)) : []
                return scope + text.list(page, columns(action, text: text))
            }
        }
        if action == "build-log" { return .init(.raw) { _, value in [value["log"].string ?? ""] } }
        if action == "whoami" {
            return .init(.detail) { text, value in
                text.fields(scopeRows(text, value) + [
                    (Messages.CLIExperience.labelAccount.localized, text.plain(value["user"]["id"])),
                    (Messages.VexCLI.admin.localized, text.plain(value["user"]["admin"]))])
            }
        }
        guard VexGroup.specs.contains(where: { $0.path == path }) else { return nil }
        return .init(.change) { text, value in
            var rows = scopeRows(text, value)
            if value["baseURL"] != .null {
                rows += [(Messages.Servers.name.localized, text.plain(value["name"])),
                         (Messages.Vex.backendURL.localized, text.plain(value["baseURL"]))]
                if value["userID"] != .null { rows.append((Messages.CLIExperience.labelAccount.localized, text.plain(value["userID"]))) }
            }
            if value["defaultServer"] != .null { rows.append((Messages.VexLogin.makeDefault.localized, text.plain(value["defaultServer"]))) }
            if value["defaultProject"] != .null { rows.append((Messages.VexLogin.defaultProject.localized, text.plain(value["defaultProject"]))) }
            if value["remoteRevoked"] != .null { rows.append((Messages.VexCLI.revoked.localized, text.plain(value["remoteRevoked"]))) }
            if value["build"] != .null { rows += buildRows(text, value["build"]) }
            if value["room"] != .null { rows += roomRows(text, value["room"]) }
            if value["sha"] != .null { rows.append((Messages.VexCLI.commits.localized, text.plain(value["sha"]))) }
            if value["loader"] != .null { rows.append((Messages.CLIExperience.columnLoaders.localized, text.plain(value["loader"]))) }
            if value["branch"] != .null { rows.append((Messages.VexCLI.branches.localized, text.plain(value["branch"]))) }
            if value["roomID"] != .null { rows.append((Messages.VexCLI.rooms.localized, text.plain(value["roomID"]))) }
            if value["buildID"] != .null { rows.append((Messages.VexCLI.builds.localized, text.plain(value["buildID"]))) }
            if value["instanceID"] != .null { rows.append((Messages.CLIExperience.labelInstance.localized, text.plain(value["instanceID"]))) }
            if value["sessionID"] != .null { rows.append((Messages.CLIExperience.labelSession.localized, text.plain(value["sessionID"]))) }
            if value["authenticationRequired"] != .null {
                rows.append((Messages.CLIExperience.labelSignIn.localized, value["authenticationRequired"].bool == true
                    ? Messages.CLIExperience.signInAtLaunch.localized : Messages.CLIExperience.signInChecked.localized))
            }
            if text.details {
                if value["javaPath"] != .null { rows.append((Messages.CLIExperience.labelJava.localized, text.plain(value["javaPath"]))) }
                if value["gameDirectory"] != .null { rows.append((Messages.CLIExperience.labelGameFolder.localized, text.plain(value["gameDirectory"]))) }
                if value["destinationArguments"] != .null { rows.append((Messages.CLIExperience.labelCommand.localized, text.plain(value["destinationArguments"]))) }
                if value["lease"]["expiresAt"] != .null { rows.append((Messages.CLIExperience.labelExpires.localized, text.date(value["lease"]["expiresAt"]))) }
                if value["unmanagedMods"] != .null { rows.append((Messages.CLIExperience.labelContents.localized, text.plain(value["unmanagedMods"]))) }
            }
            return text.change(value, rows)
        }
    }

    private static func columns(_ action: String, text: ExperimentalText) -> [ExperimentalText.Column] {
        switch action {
        case "list": return [
            .init(Messages.CLIExperience.columnName.localized) { text.plain($0["name"]) },
            .init(Messages.Vex.backendURL.localized, priority: 1) { text.plain($0["baseURL"]) },
            .init(Messages.VexLogin.defaultProject.localized, priority: 2) { text.plain($0["defaultProject"]) },
            .init(Messages.CLIExperience.columnUsername.localized, detailOnly: true) { text.plain($0["userID"]) }]
        case "projects": return [
            .init(Messages.Vex.project.localized) { text.plain($0["id"]) },
            .init(Messages.VexCLI.branches.localized, priority: 1) { text.plain($0["defaultBranch"]) },
            .init(Messages.CLIExperience.columnLoaders.localized, priority: 2) { text.plain($0["loaders"]) },
            .init(Messages.CLIExperience.labelSource.localized, detailOnly: true) { text.plain($0["remote"]) }]
        case "rooms": return [
            .init(Messages.VexCLI.rooms.localized) { text.plain($0["id"]) },
            .init(Messages.CLIExperience.columnStatus.localized) { text.plain($0["state"]) },
            .init(Messages.CLIExperience.labelPlayers.localized, priority: 2) { value in
                guard case .array(let players) = value["players"] else { return "0" }
                return String(players.count)
            },
            .init(Messages.CLIExperience.labelAddress.localized, priority: 1) { address(text, $0) },
            .init(Messages.VexCLI.builds.localized, detailOnly: true) { text.plain($0["buildId"]) }]
        case "builds": return [
            .init(Messages.CLIExperience.columnID.localized) { text.plain($0["id"]) },
            .init(Messages.CLIExperience.columnStatus.localized) { text.plain($0["status"]) },
            .init(Messages.CLIExperience.columnLoaders.localized, priority: 2) { text.plain($0["loader"]) },
            .init(Messages.VexCLI.commits.localized, priority: 1) { sha($0["sha"], details: text.details) },
            .init(Messages.CLIExperience.labelGameVersion.localized, detailOnly: true) { text.plain($0["minecraft"]) }]
        case "pulls": return [
            .init(Messages.CLIExperience.columnID.localized) { text.plain($0["number"]) },
            .init(Messages.CLIExperience.columnTitle.localized) { text.plain($0["title"]) },
            .init(Messages.CLIExperience.columnStatus.localized, priority: 1) { text.plain($0["state"]) },
            .init(Messages.CLIExperience.labelAuthor.localized, priority: 2) { text.plain($0["author"]) },
            .init(Messages.CLIExperience.labelLink.localized, detailOnly: true) { text.plain($0["url"]) }]
        case "branches": return [
            .init(Messages.VexCLI.branches.localized) { text.plain($0["name"]) },
            .init(Messages.VexCLI.commits.localized) { sha($0["head"], details: text.details) },
            .init(Messages.VexCLI.rooms.localized, priority: 1) { text.plain($0["rooms"]) },
            .init(Messages.VexCLI.builds.localized, detailOnly: true) { text.plain($0["builds"]) }]
        case "commits": return [
            .init(Messages.VexCLI.commits.localized) { sha($0["sha"], details: text.details) },
            .init(Messages.CLIExperience.columnTitle.localized) { text.plain($0["subject"]) },
            .init(Messages.CLIExperience.labelAuthor.localized, priority: 2) { text.plain($0["author"]) },
            .init(Messages.CLIExperience.labelCreated.localized, priority: 1) { text.date($0["time"]) },
            .init(Messages.VexCLI.builds.localized, detailOnly: true) { text.plain($0["builds"]) }]
        default: preconditionFailure()
        }
    }

    private static func scopeRows(_ text: ExperimentalText, _ value: Value) -> [(String, String)] {
        var rows: [(String, String)] = []
        if value["server"] != .null { rows.append((Messages.CLIExperience.labelServer.localized, text.plain(value["server"]))) }
        if value["project"] != .null { rows.append((Messages.Vex.project.localized, text.plain(value["project"]))) }
        return rows
    }
    private static func roomRows(_ text: ExperimentalText, _ room: Value) -> [(String, String)] {
        [(Messages.VexCLI.rooms.localized, text.plain(room["id"])),
         (Messages.CLIExperience.labelStatus.localized, text.plain(room["state"])),
         (Messages.CLIExperience.labelAddress.localized, address(text, room))]
    }
    private static func buildRows(_ text: ExperimentalText, _ build: Value) -> [(String, String)] {
        [(Messages.VexCLI.builds.localized, text.plain(build["id"])),
         (Messages.CLIExperience.labelStatus.localized, text.plain(build["status"])),
         (Messages.VexCLI.commits.localized, sha(build["sha"], details: text.details))]
    }
    private static func address(_ text: ExperimentalText, _ room: Value) -> String { text.plain(room["host"]) + ":" + text.plain(room["port"]) }
    private static func sha(_ value: Value, details: Bool) -> String {
        let value = value.string ?? ""
        return details ? value : String(value.prefix(12))
    }
}
