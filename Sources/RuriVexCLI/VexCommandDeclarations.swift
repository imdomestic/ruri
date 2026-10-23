import ArgumentParser
import RuriCommandKit
import RuriLocalization
import RuriVex

struct VexGroup: ParsableCommand {
    @OptionGroup var common: CommonOptions
    static var configuration: CommandConfiguration {
        .init(commandName: "vex", abstract: Messages.Vex.description.localized,
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
    @OptionGroup var common: CommonOptions
    static var configuration: CommandConfiguration {
        .init(commandName: "servers", abstract: Messages.VexLogin.servers.localized,
              subcommands: [VexCommand<ServerAdd>.self, VexCommand<ServerList>.self, VexCommand<ServerRemove>.self, VexCommand<ServerDefault>.self])
    }
    static var specs: [CommandSpec] { configuration.subcommands.compactMap { ($0 as? any ExecutableCommand.Type)?.spec } }
}

protocol VexAction {
    associatedtype Options: VexCommandOptions = VexProjectOptions
    static var name: String { get }
    static var prefix: [String] { get }
    static var operand: String? { get }
    static var mutation: Bool { get }
    static var summary: String { get }
    static var options: [String] { get }
}
extension VexAction {
    static var prefix: [String] { ["vex"] }
    static var operand: String? { nil }
    static var mutation: Bool { false }
    static var options: [String] { ["server", "project"] }
}
protocol VexServerAction: VexAction {}
extension VexServerAction { static var prefix: [String] { ["vex", "servers"] } }
enum ServerAdd: VexServerAction {
    typealias Options = VexServerAddOptions
    static let name = "add", operand: String? = "address", mutation = true
    static var summary: String { Messages.VexLogin.addServer.localized }
    static let options = ["name", "project", "dry-run"]
}
enum ServerList: VexServerAction {
    typealias Options = VexNoOptions
    static let name = "list"
    static var summary: String { Messages.VexLogin.servers.localized }
    static let options: [String] = []
}
enum ServerRemove: VexServerAction {
    typealias Options = VexDryRunOptions
    static let name = "remove", operand: String? = "name", mutation = true
    static var summary: String { Messages.VexLogin.removeServer.localized }
    static let options = ["dry-run"]
}
enum ServerDefault: VexServerAction {
    typealias Options = VexServerDefaultOptions
    static let name = "default", operand: String? = "name", mutation = true
    static var summary: String { Messages.VexLogin.makeDefault.localized }
    static let options = ["project", "dry-run"]
}
enum Login: VexAction {
    typealias Options = VexLoginOptions
    static let name = "login", mutation = true
    static var summary: String { Messages.VexLogin.login.localized }
    static let options = ["server", "invite", "method", "github", "token-stdin", "dry-run"]
}
enum Logout: VexAction {
    typealias Options = VexLogoutOptions
    static let name = "logout", mutation = true
    static var summary: String { Messages.VexLogin.logout.localized }
    static let options = ["server", "dry-run"]
}
enum Whoami: VexAction {
    typealias Options = VexServerOptions
    static let name = "whoami"
    static var summary: String { Messages.VexCLI.whoami.localized }
    static let options = ["server"]
}
enum Projects: VexAction {
    typealias Options = VexServerOptions
    static let name = "projects"
    static var summary: String { Messages.Vex.project.localized }
    static let options = ["server"]
}
enum Rooms: VexAction {
    static let name = "rooms"
    static var summary: String { Messages.VexCLI.rooms.localized }
}
enum Pulls: VexAction {
    static let name = "pulls"
    static var summary: String { Messages.VexDevices.pulls.localized }
}
enum Builds: VexAction {
    static let name = "builds"
    static var summary: String { Messages.VexCLI.builds.localized }
}
enum Branches: VexAction {
    static let name = "branches"
    static var summary: String { Messages.VexCLI.branches.localized }
}
enum Commits: VexAction {
    typealias Options = VexCommitOptions
    static let name = "commits"
    static var summary: String { Messages.VexCLI.commits.localized }
    static let options = ["server", "project", "branch", "before"]
}
enum Refresh: VexAction {
    typealias Options = VexProjectChangeOptions
    static let name = "refresh", mutation = true
    static var summary: String { Messages.Discovery.refresh.localized }
    static let options = ["server", "project", "dry-run"]
}
enum BuildLog: VexAction {
    static let name = "build-log", operand: String? = "build"
    static var summary: String { Messages.Vex.buildLog.localized }
}
enum Build: VexAction {
    typealias Options = VexBuildOptions
    static let name = "build", operand: String? = "sha", mutation = true
    static var summary: String { Messages.Vex.buildOnly.localized }
    static let options = ["server", "project", "loader", "force", "dry-run"]
}
enum Create: VexAction {
    typealias Options = VexCreateOptions
    static let name = "create", operand: String? = "sha", mutation = true
    static var summary: String { Messages.Vex.startTemporary.localized }
    static let options = ["server", "project", "loader", "branch", "dry-run"]
}
enum Start: VexAction {
    typealias Options = VexStartOptions
    static let name = "start", operand: String? = "room", mutation = true
    static var summary: String { Messages.VexCLI.start.localized }
    static let options = ["server", "project", "launch", "dry-run"]
}
enum Prepare: VexAction {
    static let name = "prepare", operand: String? = "room", mutation = true
    static var summary: String { Messages.VexCLI.prepare.localized }
    static let options = ["server", "project"]
}
enum Launch: VexAction {
    typealias Options = VexProjectChangeOptions
    static let name = "launch", operand: String? = "room", mutation = true
    static var summary: String { Messages.AppLaunchButton.launchGame.localized }
    static let options = ["server", "project", "dry-run"]
}

struct VexCommand<Action: VexAction>: ExecutableCommand {
    static var spec: CommandSpec {
        let path: [String] = Action.prefix + [Action.name]
        let operands: [ParameterSpec]
        let exampleOperands: [String]
        if let name = Action.operand {
            let help: String = name == "address" ? Messages.VexNetwork.addressHelp.localized : name
            let operand: ParameterSpec = .init(name: name, type: "string", required: true, help: help)
            operands = [operand]
            exampleOperands = ["<" + name + ">"]
        } else {
            operands = []
            exampleOperands = []
        }
        let options: [ParameterSpec] = Action.options.map(VexParameters.option)
        let exampleArguments: [String] = ["ruri"] + path + exampleOperands
        let examples: [String] = [exampleArguments.joined(separator: " ")]
        return .init(path: path, summary: Action.summary, operands: operands, options: options,
                     mutation: Action.mutation, userParticipation: Action.name == "login", examples: examples)
    }
    @OptionGroup var common: CommonOptions
    @Argument var operands: [String] = []
    @OptionGroup var options: Action.Options
    var parameters: [String: Value] { options.parameters.filter { $0.value != .null } }
}

enum VexParameters {
    static func option(_ name: String) -> ParameterSpec {
        let flags = ["github", "token-stdin", "force", "launch", "dry-run"]
        let help: String = switch name {
        case "project": Messages.Vex.project.localized
        case "server": Messages.VexLogin.servers.localized
        case "name": Messages.Servers.name.localized
        case "invite": Messages.VexLogin.inviteHelp.localized
        case "method": Messages.VexDevices.method.localized
        case "github": Messages.VexDevices.github.localized
        case "token-stdin": Messages.VexLogin.serviceToken.localized
        case "launch": Messages.CLIInterface.launchStartHelp.localized
        case "dry-run": Messages.CLIInterface.dryRunHelp.localized
        case "loader": Messages.CLIExperience.columnLoaders.localized
        case "before": Messages.VexCLI.before.localized
        case "branch": Messages.VexCLI.branches.localized
        case "force": Messages.VexCLI.force.localized
        default: name
        }
        return .init(name: name, type: flags.contains(name) ? "bool" : "string", required: false, help: help,
                     values: name == "method" ? ["invite", "github"] : [])
    }
}
