import RuriLocalization
import ArgumentParser
import Foundation
import RuriCore

struct SchemaCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["schema"], summary: Messages.CLIInterface.schemaCommandHelp.localized, operands: [
        .init(name: "resource", type: "string", required: false, help: "resource"),
        .init(name: "action", type: "string", required: false, help: "action"),
        .init(name: "subaction", type: "string", required: false, help: "subaction")
    ], options: [
        .init(name: "input", type: "bool", required: false, help: Messages.CLIExperience.inputSchema.localized),
        .init(name: "output-schema", type: "bool", required: false, help: Messages.CLIExperience.outputSchema.localized),
        .init(name: "scope", type: "string", required: false, help: Messages.CLIExperience.schemaScope.localized, values: ["app", "defaults", "instance"]),
        .init(name: "full", type: "bool", required: false, help: Messages.CLIExperience.fullSchema.localized)
    ], examples: ["ruri schema config apply --input --scope instance --json"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.commandPathArgumentsHelp.localized)) var operands: [String] = []
    @Flag(help: ArgumentHelp(Messages.CLIExperience.inputSchema.localized)) var input = false
    @Flag(name: .customLong("output-schema"), help: ArgumentHelp(Messages.CLIExperience.outputSchema.localized)) var outputSchema = false
    @Option(help: ArgumentHelp(Messages.CLIExperience.schemaScope.localized)) var scope: String?
    @Flag(help: ArgumentHelp(Messages.CLIExperience.fullSchema.localized)) var full = false
    var parameters: [String: Value] { ["input": .bool(input), "output-schema": .bool(outputSchema), "scope": .text(scope), "full": .bool(full)].filter { $0.value != .null } }
}

struct AppInfoCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["app","info"], summary: Messages.CLIInterface.appVersionHelp.localized, operands: [

    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "") var operands: [String] = []
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct AppLanguageGetCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["app","language","get"], summary: Messages.CLIInterface.appLanguageGetHelp.localized, operands: [

    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "") var operands: [String] = []
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct AppLanguageSetCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["app","language","set"], summary: Messages.CLIInterface.appLanguageSetHelp.localized, operands: [
        .init(name: "language", type: "string", required: true, help: "language")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "language") var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct CliStatusCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["cli","status"], summary: Messages.CLIInterface.cliStatusHelp.localized, operands: [

    ], options: [
        .init(name: "bin-dir", type: "string", required: false, help: Messages.CLIInterface.cliUninstallDirectoryHelp.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "") var operands: [String] = []
    @Option(name: .customLong("bin-dir"), help: ArgumentHelp(Messages.CLIInterface.cliUninstallDirectoryHelp.localized)) var optionBinDir: String?
    var parameters: [String: Value] { [
        "bin-dir": .text(optionBinDir)
    ].filter { $0.value != .null } }
}

struct CliInstallCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["cli","install"], summary: Messages.CLIInterface.cliInstallHelp.localized, operands: [

    ], options: [
        .init(name: "bin-dir", type: "string", required: false, help: Messages.CLIInterface.cliInstallDirectoryHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: true, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "") var operands: [String] = []
    @Option(name: .customLong("bin-dir"), help: ArgumentHelp(Messages.CLIInterface.cliInstallDirectoryHelp.localized)) var optionBinDir: String?
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "bin-dir": .text(optionBinDir),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct CliUninstallCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["cli","uninstall"], summary: Messages.CLIInterface.cliUninstallHelp.localized, operands: [

    ], options: [
        .init(name: "bin-dir", type: "string", required: false, help: Messages.CLIInterface.cliUninstallDirectoryHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: true, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "") var operands: [String] = []
    @Option(name: .customLong("bin-dir"), help: ArgumentHelp(Messages.CLIInterface.cliUninstallDirectoryHelp.localized)) var optionBinDir: String?
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    @Flag(name: .customLong("yes"), help: ArgumentHelp(Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized)) var optionYes = false
    var parameters: [String: Value] { [
        "bin-dir": .text(optionBinDir),
        "dry-run": .bool(optionDryRun),
        "yes": .bool(optionYes)
    ].filter { $0.value != .null } }
}

struct ConfigGetCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["config","get"], summary: Messages.CLIInterface.configGetHelp.localized, operands: [
        .init(name: "key", type: "string", required: false, help: "key")
    ], options: [
        .init(name: "scope", type: "string", required: true, help: Messages.CLIInterface.configScopeHelp.localized, values: []),
        .init(name: "show-secrets", type: "bool", required: false, help: Messages.CLIInterface.showEnvironmentValuesHelp.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "key?") var operands: [String] = []
    @Option(name: .customLong("scope"), help: ArgumentHelp(Messages.CLIInterface.configScopeHelp.localized)) var optionScope: String?
    @Flag(name: .customLong("show-secrets"), help: ArgumentHelp(Messages.CLIInterface.showEnvironmentValuesHelp.localized)) var optionShowSecrets = false
    var parameters: [String: Value] { [
        "scope": .text(optionScope),
        "show-secrets": .bool(optionShowSecrets)
    ].filter { $0.value != .null } }
}

struct ConfigSetCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["config","set"], summary: Messages.CLIInterface.configSetHelp.localized, operands: [
        .init(name: "key", type: "string", required: true, help: "key"),
        .init(name: "value", type: "string", required: true, help: "value")
    ], options: [
        .init(name: "scope", type: "string", required: true, help: Messages.CLIInterface.configScopeHelp.localized, values: []),
        .init(name: "if-revision", type: "string", required: false, help: Messages.CLIInterface.ifRevisionHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri config set memory.maximumMB 6144 --scope defaults --json"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.configFieldValueArgumentsHelp.localized)) var operands: [String] = []
    @Option(name: .customLong("scope"), help: ArgumentHelp(Messages.CLIInterface.configScopeHelp.localized)) var optionScope: String?
    @Option(name: .customLong("if-revision"), help: ArgumentHelp(Messages.CLIInterface.ifRevisionHelp.localized)) var optionIfRevision: String?
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "scope": .text(optionScope),
        "if-revision": .text(optionIfRevision),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct ConfigApplyCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["config","apply"], summary: Messages.CLIInterface.configApplyHelp.localized, operands: [

    ], options: [
        .init(name: "scope", type: "string", required: true, help: Messages.CLIInterface.configScopeHelp.localized, values: []),
        .init(name: "file", type: "string", required: true, help: Messages.CLIInterface.configPatchFileHelp.localized, values: []),
        .init(name: "if-revision", type: "string", required: false, help: Messages.CLIInterface.ifRevisionHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri config apply --scope instance:<uuid> --file patch.json --dry-run --json"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "") var operands: [String] = []
    @Option(name: .customLong("scope"), help: ArgumentHelp(Messages.CLIInterface.configScopeHelp.localized)) var optionScope: String?
    @Option(name: .customLong("file"), help: ArgumentHelp(Messages.CLIInterface.configPatchFileHelp.localized)) var optionFile: String?
    @Option(name: .customLong("if-revision"), help: ArgumentHelp(Messages.CLIInterface.ifRevisionHelp.localized)) var optionIfRevision: String?
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "scope": .text(optionScope),
        "file": .text(optionFile),
        "if-revision": .text(optionIfRevision),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct ConfigResetCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["config","reset"], summary: Messages.CLIInterface.configResetHelp.localized, operands: [
        .init(name: "key", type: "string", required: true, help: "key")
    ], options: [
        .init(name: "scope", type: "string", required: true, help: Messages.CLIInterface.configScopeHelp.localized, values: []),
        .init(name: "if-revision", type: "string", required: false, help: Messages.CLIInterface.ifRevisionHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "key") var operands: [String] = []
    @Option(name: .customLong("scope"), help: ArgumentHelp(Messages.CLIInterface.configScopeHelp.localized)) var optionScope: String?
    @Option(name: .customLong("if-revision"), help: ArgumentHelp(Messages.CLIInterface.ifRevisionHelp.localized)) var optionIfRevision: String?
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "scope": .text(optionScope),
        "if-revision": .text(optionIfRevision),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct ConfigInheritCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["config","inherit"], summary: Messages.CLIInterface.configInheritHelp.localized, operands: [
        .init(name: "key", type: "string", required: true, help: "key")
    ], options: [
        .init(name: "scope", type: "string", required: true, help: Messages.CLIInterface.configScopeHelp.localized, values: []),
        .init(name: "if-revision", type: "string", required: false, help: Messages.CLIInterface.ifRevisionHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri config inherit memory --scope instance:<uuid> --json"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "key") var operands: [String] = []
    @Option(name: .customLong("scope"), help: ArgumentHelp(Messages.CLIInterface.configScopeHelp.localized)) var optionScope: String?
    @Option(name: .customLong("if-revision"), help: ArgumentHelp(Messages.CLIInterface.ifRevisionHelp.localized)) var optionIfRevision: String?
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "scope": .text(optionScope),
        "if-revision": .text(optionIfRevision),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct InstanceListCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["instance","list"], summary: Messages.CLIInterface.instanceListHelp.localized, operands: [

    ], options: [
        .init(name: "name", type: "string", required: false, help: Messages.CLIInterface.exactNameFilterHelp.localized, values: []),
        .init(name: "directory", type: "string", required: false, help: Messages.CLIInterface.directoryFilterHelp.localized, values: []),
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.resultLimitHelp.localized, values: []),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.resultOffsetHelp.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.allResultsHelp.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "") var operands: [String] = []
    @Option(name: .customLong("name"), help: ArgumentHelp(Messages.CLIInterface.exactNameFilterHelp.localized)) var optionName: String?
    @Option(name: .customLong("directory"), help: ArgumentHelp(Messages.CLIInterface.directoryFilterHelp.localized)) var optionDirectory: String?
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.resultLimitHelp.localized)) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.resultOffsetHelp.localized)) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.allResultsHelp.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "name": .text(optionName),
        "directory": .text(optionDirectory),
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct InstanceSelectedCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["instance","selected"], summary: Messages.CLIInterface.instanceSelectedHelp.localized, operands: [

    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "") var operands: [String] = []
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct InstanceShowCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["instance","show"], summary: Messages.CLIInterface.instanceShowHelp.localized, operands: [
        .init(name: "id", type: "string", required: false, help: "id")
    ], options: [
        .init(name: "name", type: "string", required: false, help: Messages.CLIInterface.instanceNameLookupHelp.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "id?") var operands: [String] = []
    @Option(name: .customLong("name"), help: ArgumentHelp(Messages.CLIInterface.instanceNameLookupHelp.localized)) var optionName: String?
    var parameters: [String: Value] { [
        "name": .text(optionName)
    ].filter { $0.value != .null } }
}

struct InstanceVersionsCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["instance","versions"], summary: Messages.CLIInterface.minecraftVersionsHelp.localized, operands: [

    ], options: [
        .init(name: "snapshots", type: "bool", required: false, help: Messages.CLIInterface.includeSnapshotsHelp.localized, values: []),
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.resultLimitHelp.localized, values: []),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.resultOffsetHelp.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.allResultsHelp.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "") var operands: [String] = []
    @Flag(name: .customLong("snapshots"), help: ArgumentHelp(Messages.CLIInterface.includeSnapshotsHelp.localized)) var optionSnapshots = false
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.resultLimitHelp.localized)) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.resultOffsetHelp.localized)) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.allResultsHelp.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "snapshots": .bool(optionSnapshots),
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct InstanceCreateCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["instance","create"], summary: Messages.CLIInterface.instanceCreateHelp.localized, operands: [

    ], options: [
        .init(name: "name", type: "string", required: true, help: Messages.CLIInterface.instanceNameHelp.localized, values: []),
        .init(name: "game", type: "string", required: true, help: Messages.CLIInterface.minecraftVersionHelp.localized, values: []),
        .init(name: "directory", type: "string", required: true, help: Messages.CLIInterface.instanceTargetDirectoryHelp.localized, values: []),
        .init(name: "component", type: "strings", required: false, help: Messages.CLIInterface.instanceCreateLoadersHelp.localized, values: []),
        .init(name: "no-install", type: "bool", required: false, help: Messages.CLIInterface.instanceRecordOnlyHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri instance create --name Survival --game 1.21.1 --directory default --json"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "") var operands: [String] = []
    @Option(name: .customLong("name"), help: ArgumentHelp(Messages.CLIInterface.instanceNameHelp.localized)) var optionName: String?
    @Option(name: .customLong("game"), help: ArgumentHelp(Messages.CLIInterface.minecraftVersionHelp.localized)) var optionGame: String?
    @Option(name: .customLong("directory"), help: ArgumentHelp(Messages.CLIInterface.instanceTargetDirectoryHelp.localized)) var optionDirectory: String?
    @Option(name: .customLong("component"), help: ArgumentHelp(Messages.CLIInterface.instanceCreateLoadersHelp.localized)) var optionComponent: [String] = []
    @Flag(name: .customLong("no-install"), help: ArgumentHelp(Messages.CLIInterface.instanceRecordOnlyHelp.localized)) var optionNoInstall = false
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "name": .text(optionName),
        "game": .text(optionGame),
        "directory": .text(optionDirectory),
        "component": .array(optionComponent.map(Value.string)),
        "no-install": .bool(optionNoInstall),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct InstanceInstallCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["instance","install"], summary: Messages.CLIInterface.instanceInstallHelp.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "id") var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct InstanceRepairCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["instance","repair"], summary: Messages.CLIInterface.instanceRepairHelp.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "id") var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct InstanceSelectCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["instance","select"], summary: Messages.CLIInterface.instanceSelectHelp.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "id") var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct InstanceRenameCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["instance","rename"], summary: Messages.CLIInterface.instanceRenameHelp.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id"),
        .init(name: "name", type: "string", required: true, help: "name")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.instanceRenameArgumentsHelp.localized)) var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct InstanceFavoriteCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["instance","favorite"], summary: Messages.CLIInterface.instancePinHelp.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id"),
        .init(name: "enabled", type: "string", required: true, help: "enabled")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.instancePinArgumentsHelp.localized)) var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct InstanceRemoveCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["instance","remove"], summary: Messages.CLIInterface.instanceRemoveHelp.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "id") var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    @Flag(name: .customLong("yes"), help: ArgumentHelp(Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized)) var optionYes = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun),
        "yes": .bool(optionYes)
    ].filter { $0.value != .null } }
}

struct InstanceIconCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["instance","icon"], summary: Messages.CLIInterface.instanceIconHelp.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "file", type: "string", required: false, help: Messages.CLIInterface.instanceIconFileHelp.localized, values: []),
        .init(name: "glyph", type: "string", required: false, help: Messages.CLIInterface.instanceIconGlyphHelp.localized, values: []),
        .init(name: "tint", type: "string", required: false, help: Messages.CLIInterface.instanceIconTintHelp.localized, values: []),
        .init(name: "reset", type: "bool", required: false, help: Messages.CLIInterface.instanceIconResetHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "id") var operands: [String] = []
    @Option(name: .customLong("file"), help: ArgumentHelp(Messages.CLIInterface.instanceIconFileHelp.localized)) var optionFile: String?
    @Option(name: .customLong("glyph"), help: ArgumentHelp(Messages.CLIInterface.instanceIconGlyphHelp.localized)) var optionGlyph: String?
    @Option(name: .customLong("tint"), help: ArgumentHelp(Messages.CLIInterface.instanceIconTintHelp.localized)) var optionTint: String?
    @Flag(name: .customLong("reset"), help: ArgumentHelp(Messages.CLIInterface.instanceIconResetHelp.localized)) var optionReset = false
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "file": .text(optionFile),
        "glyph": .text(optionGlyph),
        "tint": .text(optionTint),
        "reset": .bool(optionReset),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct InstanceCopyCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["instance","copy"], summary: Messages.CLIInterface.instanceCopyHelp.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "directory", type: "string", required: true, help: Messages.CLIInterface.instanceTargetDirectoryHelp.localized, values: []),
        .init(name: "name", type: "string", required: true, help: Messages.CLIInterface.newInstanceNameHelp.localized, values: []),
        .init(name: "without-worlds", type: "bool", required: false, help: Messages.CLIInterface.excludeWorldsHelp.localized, values: []),
        .init(name: "with-backups", type: "bool", required: false, help: Messages.CLIInterface.includeWorldBackupsHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "id") var operands: [String] = []
    @Option(name: .customLong("directory"), help: ArgumentHelp(Messages.CLIInterface.instanceTargetDirectoryHelp.localized)) var optionDirectory: String?
    @Option(name: .customLong("name"), help: ArgumentHelp(Messages.CLIInterface.newInstanceNameHelp.localized)) var optionName: String?
    @Flag(name: .customLong("without-worlds"), help: ArgumentHelp(Messages.CLIInterface.excludeWorldsHelp.localized)) var optionWithoutWorlds = false
    @Flag(name: .customLong("with-backups"), help: ArgumentHelp(Messages.CLIInterface.includeWorldBackupsHelp.localized)) var optionWithBackups = false
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "directory": .text(optionDirectory),
        "name": .text(optionName),
        "without-worlds": .bool(optionWithoutWorlds),
        "with-backups": .bool(optionWithBackups),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct InstanceMoveCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["instance","move"], summary: Messages.CLIInterface.instanceMoveHelp.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "directory", type: "string", required: true, help: Messages.CLIInterface.instanceTargetDirectoryHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "id") var operands: [String] = []
    @Option(name: .customLong("directory"), help: ArgumentHelp(Messages.CLIInterface.instanceTargetDirectoryHelp.localized)) var optionDirectory: String?
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "directory": .text(optionDirectory),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct InstanceExportCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["instance","export"], summary: Messages.CLIInterface.instanceExportHelp.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id"),
        .init(name: "file", type: "string", required: true, help: "file")
    ], options: [
        .init(name: "format", type: "string", required: false, help: Messages.CLIInterface.instanceArchiveFormatHelp.localized, values: ["ruri","complete","multimc","mcbbs","mrpack"]),
        .init(name: "without-worlds", type: "bool", required: false, help: Messages.CLIInterface.excludeWorldsHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.instanceExportArgumentsHelp.localized)) var operands: [String] = []
    @Option(name: .customLong("format"), help: ArgumentHelp(Messages.CLIInterface.instanceArchiveFormatHelp.localized)) var optionFormat: String?
    @Flag(name: .customLong("without-worlds"), help: ArgumentHelp(Messages.CLIInterface.excludeWorldsHelp.localized)) var optionWithoutWorlds = false
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "format": .text(optionFormat),
        "without-worlds": .bool(optionWithoutWorlds),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct InstanceComponentListCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["instance","component","list"], summary: Messages.CLIInterface.instanceComponentsShowHelp.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "id") var operands: [String] = []
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct InstanceComponentVersionsCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["instance","component","versions"], summary: Messages.CLIInterface.instanceComponentsVersionsHelp.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id"),
        .init(name: "loader", type: "string", required: true, help: "loader")
    ], options: [
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.resultLimitHelp.localized, values: []),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.resultOffsetHelp.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.allResultsHelp.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.instanceLoaderArgumentsHelp.localized)) var operands: [String] = []
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.resultLimitHelp.localized)) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.resultOffsetHelp.localized)) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.allResultsHelp.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct InstanceComponentSetCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["instance","component","set"], summary: Messages.CLIInterface.instanceComponentsSetHelp.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "component", type: "strings", required: false, help: Messages.CLIInterface.instanceComponentLoadersHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "id") var operands: [String] = []
    @Option(name: .customLong("component"), help: ArgumentHelp(Messages.CLIInterface.instanceComponentLoadersHelp.localized)) var optionComponent: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "component": .array(optionComponent.map(Value.string)),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct InstanceComponentRestoreCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["instance","component","restore"], summary: Messages.CLIInterface.instanceComponentsRestoreHelp.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "id") var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    @Flag(name: .customLong("yes"), help: ArgumentHelp(Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized)) var optionYes = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun),
        "yes": .bool(optionYes)
    ].filter { $0.value != .null } }
}

struct DirectoryListCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["directory","list"], summary: Messages.CLIInterface.directoryListHelp.localized, operands: [

    ], options: [
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.resultLimitHelp.localized, values: []),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.resultOffsetHelp.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.allResultsHelp.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "") var operands: [String] = []
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.resultLimitHelp.localized)) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.resultOffsetHelp.localized)) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.allResultsHelp.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct DirectorySelectedCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["directory","selected"], summary: Messages.CLIInterface.directorySelectedHelp.localized, operands: [

    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "") var operands: [String] = []
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct DirectoryScanCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["directory","scan"], summary: Messages.CLIInterface.directoryInspectHelp.localized, operands: [
        .init(name: "path", type: "string", required: true, help: "path")
    ], options: [
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.resultLimitHelp.localized, values: []),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.resultOffsetHelp.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.allResultsHelp.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "path") var operands: [String] = []
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.resultLimitHelp.localized)) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.resultOffsetHelp.localized)) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.allResultsHelp.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct DirectoryAddCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["directory","add"], summary: Messages.CLIInterface.directoryAddHelp.localized, operands: [
        .init(name: "path", type: "string", required: true, help: "path")
    ], options: [
        .init(name: "name", type: "string", required: true, help: Messages.CLIInterface.directoryNameHelp.localized, values: []),
        .init(name: "layout", type: "string", required: false, help: Messages.CLIInterface.directoryLayoutHelp.localized, values: ["minecraft","managed"]),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "path") var operands: [String] = []
    @Option(name: .customLong("name"), help: ArgumentHelp(Messages.CLIInterface.directoryNameHelp.localized)) var optionName: String?
    @Option(name: .customLong("layout"), help: ArgumentHelp(Messages.CLIInterface.directoryLayoutHelp.localized)) var optionLayout: String?
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "name": .text(optionName),
        "layout": .text(optionLayout),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct DirectorySelectCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["directory","select"], summary: Messages.CLIInterface.directorySelectHelp.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "id") var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct DirectoryRefreshCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["directory","refresh"], summary: Messages.CLIInterface.directoryRefreshHelp.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "id") var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct DirectoryRemoveCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["directory","remove"], summary: Messages.CLIInterface.directoryRemoveHelp.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "id") var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    @Flag(name: .customLong("yes"), help: ArgumentHelp(Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized)) var optionYes = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun),
        "yes": .bool(optionYes)
    ].filter { $0.value != .null } }
}

struct DirectoryRenameCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["directory","rename"], summary: Messages.CLIInterface.directoryRenameHelp.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id"),
        .init(name: "name", type: "string", required: true, help: "name")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.instanceRenameArgumentsHelp.localized)) var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct DirectoryRelocateCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["directory","relocate"], summary: Messages.CLIInterface.directoryRelocateHelp.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id"),
        .init(name: "path", type: "string", required: true, help: "path")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.directoryPathArgumentsHelp.localized)) var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct DirectoryRestoreCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["directory","restore"], summary: Messages.CLIInterface.directoryRecoverHelp.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id"),
        .init(name: "path", type: "string", required: true, help: "path")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.directoryPathArgumentsHelp.localized)) var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct DirectoryRunGetCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["directory","run","get"], summary: Messages.CLIInterface.instanceRunDirectoryShowHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance")
    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "instance") var operands: [String] = []
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct DirectoryRunSetCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["directory","run","set"], summary: Messages.CLIInterface.instanceRunDirectorySetHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "mode", type: "string", required: true, help: "mode")
    ], options: [
        .init(name: "path", type: "string", required: false, help: Messages.CLIInterface.customRunDirectoryPathHelp.localized, values: []),
        .init(name: "copy", type: "bool", required: false, help: Messages.CLIInterface.copyGameFilesHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.instanceRunDirectoryModeArgumentsHelp.localized)) var operands: [String] = []
    @Option(name: .customLong("path"), help: ArgumentHelp(Messages.CLIInterface.customRunDirectoryPathHelp.localized)) var optionPath: String?
    @Flag(name: .customLong("copy"), help: ArgumentHelp(Messages.CLIInterface.copyGameFilesHelp.localized)) var optionCopy = false
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "path": .text(optionPath),
        "copy": .bool(optionCopy),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct DirectoryRunRelocateCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["directory","run","relocate"], summary: Messages.CLIInterface.instanceRunDirectoryRelocateHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "path", type: "string", required: true, help: "path")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.instanceRunDirectoryPathArgumentsHelp.localized)) var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct JavaListCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["java","list"], summary: Messages.CLIInterface.javaListHelp.localized, operands: [

    ], options: [
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.resultLimitHelp.localized, values: []),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.resultOffsetHelp.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.allResultsHelp.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "") var operands: [String] = []
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.resultLimitHelp.localized)) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.resultOffsetHelp.localized)) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.allResultsHelp.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct JavaAvailableCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["java","available"], summary: Messages.CLIInterface.javaCatalogHelp.localized, operands: [

    ], options: [
        .init(name: "major", type: "int", required: false, help: Messages.CLIInterface.javaMajorFilterHelp.localized, values: []),
        .init(name: "architecture", type: "string", required: false, help: Messages.CLIInterface.javaArchitectureFilterHelp.localized, values: ["aarch64","x86_64"]),
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.resultLimitHelp.localized, values: []),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.resultOffsetHelp.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.allResultsHelp.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "") var operands: [String] = []
    @Option(name: .customLong("major"), help: ArgumentHelp(Messages.CLIInterface.javaMajorFilterHelp.localized)) var optionMajor: Int?
    @Option(name: .customLong("architecture"), help: ArgumentHelp(Messages.CLIInterface.javaArchitectureFilterHelp.localized)) var optionArchitecture: String?
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.resultLimitHelp.localized)) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.resultOffsetHelp.localized)) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.allResultsHelp.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "major": optionMajor.map(Value.integer) ?? .null,
        "architecture": .text(optionArchitecture),
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct JavaAddCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["java","add"], summary: Messages.CLIInterface.javaAddHelp.localized, operands: [
        .init(name: "path", type: "string", required: true, help: "path")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "path") var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct JavaForgetCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["java","forget"], summary: Messages.CLIInterface.javaForgetHelp.localized, operands: [
        .init(name: "path", type: "string", required: true, help: "path")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "path") var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct JavaDefaultCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["java","default"], summary: Messages.CLIInterface.javaDefaultHelp.localized, operands: [
        .init(name: "path-or-automatic", type: "string", required: true, help: "path-or-automatic")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "path-or-automatic") var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct JavaReferencesCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["java","references"], summary: Messages.CLIInterface.javaReferencesHelp.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "partial", type: "bool", required: false, help: Messages.CLIInterface.javaCheckIncompleteInstallationsHelp.localized, values: []),
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.resultLimitHelp.localized, values: []),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.resultOffsetHelp.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.allResultsHelp.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "id") var operands: [String] = []
    @Flag(name: .customLong("partial"), help: ArgumentHelp(Messages.CLIInterface.javaCheckIncompleteInstallationsHelp.localized)) var optionPartial = false
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.resultLimitHelp.localized)) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.resultOffsetHelp.localized)) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.allResultsHelp.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "partial": .bool(optionPartial),
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct JavaInstallCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["java","install"], summary: Messages.CLIInterface.javaInstallHelp.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "id") var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct JavaRepairCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["java","repair"], summary: Messages.CLIInterface.javaRepairHelp.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "id") var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct JavaRemoveCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["java","remove"], summary: Messages.CLIInterface.javaRemoveHelp.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "reset-references", type: "bool", required: false, help: Messages.CLIInterface.javaResetReferencesHelp.localized, values: []),
        .init(name: "partial", type: "bool", required: false, help: Messages.CLIInterface.javaCleanIncompleteInstallationHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "id") var operands: [String] = []
    @Flag(name: .customLong("reset-references"), help: ArgumentHelp(Messages.CLIInterface.javaResetReferencesHelp.localized)) var optionResetReferences = false
    @Flag(name: .customLong("partial"), help: ArgumentHelp(Messages.CLIInterface.javaCleanIncompleteInstallationHelp.localized)) var optionPartial = false
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    @Flag(name: .customLong("yes"), help: ArgumentHelp(Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized)) var optionYes = false
    var parameters: [String: Value] { [
        "reset-references": .bool(optionResetReferences),
        "partial": .bool(optionPartial),
        "dry-run": .bool(optionDryRun),
        "yes": .bool(optionYes)
    ].filter { $0.value != .null } }
}

struct AccountListCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["account","list"], summary: Messages.CLIInterface.accountListHelp.localized, operands: [

    ], options: [
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.resultLimitHelp.localized, values: []),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.resultOffsetHelp.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.allResultsHelp.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "") var operands: [String] = []
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.resultLimitHelp.localized)) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.resultOffsetHelp.localized)) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.allResultsHelp.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct AccountSelectedCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["account","selected"], summary: Messages.CLIInterface.accountSelectedHelp.localized, operands: [

    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "") var operands: [String] = []
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct AccountShowCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["account","show"], summary: Messages.CLIInterface.accountShowHelp.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "id") var operands: [String] = []
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct AccountAddOfflineCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["account","add-offline"], summary: Messages.CLIInterface.accountOfflineHelp.localized, operands: [
        .init(name: "username", type: "string", required: true, help: "username")
    ], options: [
        .init(name: "no-select", type: "bool", required: false, help: Messages.CLIInterface.keepCurrentAccountHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "username") var operands: [String] = []
    @Flag(name: .customLong("no-select"), help: ArgumentHelp(Messages.CLIInterface.keepCurrentAccountHelp.localized)) var optionNoSelect = false
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "no-select": .bool(optionNoSelect),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct AccountSelectCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["account","select"], summary: Messages.CLIInterface.accountSelectHelp.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "id") var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct AccountRefreshCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["account","refresh"], summary: Messages.CLIInterface.accountRefreshHelp.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "id") var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct AccountRemoveCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["account","remove"], summary: Messages.CLIInterface.accountRemoveHelp.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "id") var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    @Flag(name: .customLong("yes"), help: ArgumentHelp(Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized)) var optionYes = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun),
        "yes": .bool(optionYes)
    ].filter { $0.value != .null } }
}

struct AccountLogoutCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["account","logout"], summary: Messages.CLIInterface.accountLogoutHelp.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "id") var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    @Flag(name: .customLong("yes"), help: ArgumentHelp(Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized)) var optionYes = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun),
        "yes": .bool(optionYes)
    ].filter { $0.value != .null } }
}

struct AccountLoginStartCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["account","login","start"], summary: Messages.CLIInterface.accountLoginStartHelp.localized, operands: [

    ], options: [
        .init(name: "provider", type: "string", required: true, help: Messages.CLIInterface.loginProviderHelp.localized, values: ["microsoft","external"]),
        .init(name: "account", type: "string", required: false, help: Messages.CLIInterface.reauthenticateAccountHelp.localized, values: []),
        .init(name: "server", type: "string", required: false, help: Messages.CLIInterface.externalLoginServerHelp.localized, values: []),
        .init(name: "username", type: "string", required: false, help: Messages.CLIInterface.externalLoginIdentityHelp.localized, values: []),
        .init(name: "password-stdin", type: "bool", required: false, help: Messages.CLIInterface.passwordStdinHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: true, examples: ["ruri account login start --provider microsoft --json"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "") var operands: [String] = []
    @Option(name: .customLong("provider"), help: ArgumentHelp(Messages.CLIInterface.loginProviderHelp.localized)) var optionProvider: String?
    @Option(name: .customLong("account"), help: ArgumentHelp(Messages.CLIInterface.reauthenticateAccountHelp.localized)) var optionAccount: String?
    @Option(name: .customLong("server"), help: ArgumentHelp(Messages.CLIInterface.externalLoginServerHelp.localized)) var optionServer: String?
    @Option(name: .customLong("username"), help: ArgumentHelp(Messages.CLIInterface.externalLoginIdentityHelp.localized)) var optionUsername: String?
    @Flag(name: .customLong("password-stdin"), help: ArgumentHelp(Messages.CLIInterface.passwordStdinHelp.localized)) var optionPasswordStdin = false
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "provider": .text(optionProvider),
        "account": .text(optionAccount),
        "server": .text(optionServer),
        "username": .text(optionUsername),
        "password-stdin": .bool(optionPasswordStdin),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct AccountLoginCompleteCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["account","login","complete"], summary: Messages.CLIInterface.accountLoginCompleteHelp.localized, operands: [
        .init(name: "flow", type: "string", required: true, help: "flow")
    ], options: [
        .init(name: "profile", type: "string", required: false, help: Messages.CLIInterface.externalLoginProfileIdHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: true, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "flow") var operands: [String] = []
    @Option(name: .customLong("profile"), help: ArgumentHelp(Messages.CLIInterface.externalLoginProfileIdHelp.localized)) var optionProfile: String?
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "profile": .text(optionProfile),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct AccountLoginCancelCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["account","login","cancel"], summary: Messages.CLIInterface.accountLoginCancelHelp.localized, operands: [
        .init(name: "flow", type: "string", required: true, help: "flow")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "flow") var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct AccountServiceKeyStatusCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["account","service-key","status"], summary: Messages.CLIInterface.curseForgeKeyStatusHelp.localized, operands: [

    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "") var operands: [String] = []
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct AccountServiceKeySetCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["account","service-key","set"], summary: Messages.CLIInterface.curseForgeKeySetHelp.localized, operands: [

    ], options: [
        .init(name: "stdin", type: "bool", required: true, help: Messages.CLIInterface.apiKeyStdinHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "") var operands: [String] = []
    @Flag(name: .customLong("stdin"), help: ArgumentHelp(Messages.CLIInterface.apiKeyStdinHelp.localized)) var optionStdin = false
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "stdin": .bool(optionStdin),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct AccountServiceKeyRemoveCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["account","service-key","remove"], summary: Messages.CLIInterface.curseForgeKeyClearHelp.localized, operands: [

    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "") var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    @Flag(name: .customLong("yes"), help: ArgumentHelp(Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized)) var optionYes = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun),
        "yes": .bool(optionYes)
    ].filter { $0.value != .null } }
}

struct LaunchPreflightCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["launch","preflight"], summary: Messages.CLIInterface.launchCheckHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance")
    ], options: [
        .init(name: "server", type: "string", required: false, help: Messages.Servers.address.localized, values: []),
        .init(name: "account", type: "string", required: false, help: Messages.CLIInterface.launchAccountHelp.localized, values: []),
        .init(name: "world", type: "string", required: false, help: Messages.CLIInterface.quickPlayWorldHelp.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "instance") var operands: [String] = []
    @Option(name: .customLong("server"), help: ArgumentHelp(Messages.Servers.address.localized)) var optionServer: String?
    @Option(name: .customLong("account"), help: ArgumentHelp(Messages.CLIInterface.launchAccountHelp.localized)) var optionAccount: String?
    @Option(name: .customLong("world"), help: ArgumentHelp(Messages.CLIInterface.quickPlayWorldHelp.localized)) var optionWorld: String?
    var parameters: [String: Value] { [
        "server": .text(optionServer),
        "account": .text(optionAccount),
        "world": .text(optionWorld)
    ].filter { $0.value != .null } }
}

struct LaunchStartCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["launch","start"], summary: Messages.CLIInterface.launchStartHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance")
    ], options: [
        .init(name: "server", type: "string", required: false, help: Messages.Servers.address.localized, values: []),
        .init(name: "account", type: "string", required: false, help: Messages.CLIInterface.launchAccountHelp.localized, values: []),
        .init(name: "world", type: "string", required: false, help: Messages.CLIInterface.quickPlayWorldHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri launch start <instance-uuid> --account <account-uuid> --json"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "instance") var operands: [String] = []
    @Option(name: .customLong("server"), help: ArgumentHelp(Messages.Servers.address.localized)) var optionServer: String?
    @Option(name: .customLong("account"), help: ArgumentHelp(Messages.CLIInterface.launchAccountHelp.localized)) var optionAccount: String?
    @Option(name: .customLong("world"), help: ArgumentHelp(Messages.CLIInterface.quickPlayWorldHelp.localized)) var optionWorld: String?
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "server": .text(optionServer),
        "account": .text(optionAccount),
        "world": .text(optionWorld),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct SessionListCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["session","list"], summary: Messages.CLIInterface.sessionListHelp.localized, operands: [

    ], options: [
        .init(name: "instance", type: "string", required: false, help: Messages.CLIInterface.sessionInstanceIdFilterHelp.localized, values: []),
        .init(name: "search", type: "string", required: false, help: Messages.CLIInterface.sessionInstanceNameFilterHelp.localized, values: []),
        .init(name: "problems", type: "bool", required: false, help: Messages.CLIInterface.problemSessionsOnlyHelp.localized, values: []),
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.resultLimitHelp.localized, values: []),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.resultOffsetHelp.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.allResultsHelp.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "") var operands: [String] = []
    @Option(name: .customLong("instance"), help: ArgumentHelp(Messages.CLIInterface.sessionInstanceIdFilterHelp.localized)) var optionInstance: String?
    @Option(name: .customLong("search"), help: ArgumentHelp(Messages.CLIInterface.sessionInstanceNameFilterHelp.localized)) var optionSearch: String?
    @Flag(name: .customLong("problems"), help: ArgumentHelp(Messages.CLIInterface.problemSessionsOnlyHelp.localized)) var optionProblems = false
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.resultLimitHelp.localized)) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.resultOffsetHelp.localized)) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.allResultsHelp.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "instance": .text(optionInstance),
        "search": .text(optionSearch),
        "problems": .bool(optionProblems),
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct SessionShowCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["session","show"], summary: Messages.CLIInterface.sessionShowHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "session", type: "string", required: true, help: "session")
    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.sessionTargetArgumentsHelp.localized)) var operands: [String] = []
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct SessionWaitCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["session","wait"], summary: Messages.CLIInterface.sessionWaitHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "session", type: "string", required: true, help: "session")
    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.sessionTargetArgumentsHelp.localized)) var operands: [String] = []
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct SessionQuitCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["session","quit"], summary: Messages.CLIInterface.sessionStopHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "session", type: "string", required: true, help: "session")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.sessionTargetArgumentsHelp.localized)) var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct SessionStopCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["session","stop"], summary: Messages.CLIInterface.sessionKillHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "session", type: "string", required: true, help: "session")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.sessionTargetArgumentsHelp.localized)) var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    @Flag(name: .customLong("yes"), help: ArgumentHelp(Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized)) var optionYes = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun),
        "yes": .bool(optionYes)
    ].filter { $0.value != .null } }
}

struct SessionLogsCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["session","logs"], summary: Messages.CLIInterface.sessionLogsHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "session", type: "string", required: true, help: "session")
    ], options: [
        .init(name: "follow", type: "bool", required: false, help: Messages.CLIInterface.sessionLogFollowHelp.localized, values: []),
        .init(name: "source", type: "string", required: false, help: Messages.CLIInterface.sessionLogSourceHelp.localized, values: ["output","preparation","latest","debug"]),
        .init(name: "lines", type: "int", required: false, help: Messages.CLIInterface.sessionLogLineLimitHelp.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: ["ruri session logs <instance-uuid> <session-uuid> --follow --output ndjson"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.sessionTargetArgumentsHelp.localized)) var operands: [String] = []
    @Flag(name: .customLong("follow"), help: ArgumentHelp(Messages.CLIInterface.sessionLogFollowHelp.localized)) var optionFollow = false
    @Option(name: .customLong("source"), help: ArgumentHelp(Messages.CLIInterface.sessionLogSourceHelp.localized)) var optionSource: String?
    @Option(name: .customLong("lines"), help: ArgumentHelp(Messages.CLIInterface.sessionLogLineLimitHelp.localized)) var optionLines: Int?
    var parameters: [String: Value] { [
        "follow": .bool(optionFollow),
        "source": .text(optionSource),
        "lines": optionLines.map(Value.integer) ?? .null
    ].filter { $0.value != .null } }
}

struct SessionDiagnoseCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["session","diagnose"], summary: Messages.CLIInterface.sessionAnalyzeHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "session", type: "string", required: true, help: "session")
    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.sessionTargetArgumentsHelp.localized)) var operands: [String] = []
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct SessionExportCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["session","export"], summary: Messages.CLIInterface.sessionExportHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "session", type: "string", required: true, help: "session"),
        .init(name: "file", type: "string", required: true, help: "file")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.sessionExportArgumentsHelp.localized)) var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct CatalogSearchCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["catalog","search"], summary: Messages.CLIInterface.catalogSearchHelp.localized, operands: [
        .init(name: "query", type: "string", required: false, help: "query")
    ], options: [
        .init(name: "provider", type: "string", required: false, help: Messages.CLIInterface.contentProviderHelp.localized, values: ["modrinth","curseforge"]),
        .init(name: "type", type: "string", required: false, help: Messages.CLIInterface.catalogProjectTypeHelp.localized, values: ["mod","modpack","resourcepack","shader"]),
        .init(name: "game", type: "string", required: false, help: Messages.CLIInterface.minecraftVersionFilterHelp.localized, values: []),
        .init(name: "loader", type: "string", required: false, help: Messages.CLIInterface.loaderFilterHelp.localized, values: []),
        .init(name: "category", type: "string", required: false, help: Messages.CLIInterface.catalogCategoryHelp.localized, values: []),
        .init(name: "sort", type: "string", required: false, help: Messages.CLIInterface.catalogSortHelp.localized, values: ["relevance","downloads","updated","newest"]),
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.resultLimitHelp.localized, values: []),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.resultOffsetHelp.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.allResultsHelp.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "query?") var operands: [String] = []
    @Option(name: .customLong("provider"), help: ArgumentHelp(Messages.CLIInterface.contentProviderHelp.localized)) var optionProvider: String?
    @Option(name: .customLong("type"), help: ArgumentHelp(Messages.CLIInterface.catalogProjectTypeHelp.localized)) var optionType: String?
    @Option(name: .customLong("game"), help: ArgumentHelp(Messages.CLIInterface.minecraftVersionFilterHelp.localized)) var optionGame: String?
    @Option(name: .customLong("loader"), help: ArgumentHelp(Messages.CLIInterface.loaderFilterHelp.localized)) var optionLoader: String?
    @Option(name: .customLong("category"), help: ArgumentHelp(Messages.CLIInterface.catalogCategoryHelp.localized)) var optionCategory: String?
    @Option(name: .customLong("sort"), help: ArgumentHelp(Messages.CLIInterface.catalogSortHelp.localized)) var optionSort: String?
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.resultLimitHelp.localized)) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.resultOffsetHelp.localized)) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.allResultsHelp.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "provider": .text(optionProvider),
        "type": .text(optionType),
        "game": .text(optionGame),
        "loader": .text(optionLoader),
        "category": .text(optionCategory),
        "sort": .text(optionSort),
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct CatalogShowCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["catalog","show"], summary: Messages.CLIInterface.catalogProjectShowHelp.localized, operands: [
        .init(name: "project", type: "string", required: true, help: "project")
    ], options: [
        .init(name: "provider", type: "string", required: false, help: Messages.CLIInterface.contentProviderHelp.localized, values: ["modrinth","curseforge"])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "project") var operands: [String] = []
    @Option(name: .customLong("provider"), help: ArgumentHelp(Messages.CLIInterface.contentProviderHelp.localized)) var optionProvider: String?
    var parameters: [String: Value] { [
        "provider": .text(optionProvider)
    ].filter { $0.value != .null } }
}

struct CatalogVersionsCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["catalog","versions"], summary: Messages.CLIInterface.catalogVersionsHelp.localized, operands: [
        .init(name: "project", type: "string", required: true, help: "project")
    ], options: [
        .init(name: "provider", type: "string", required: false, help: Messages.CLIInterface.contentProviderHelp.localized, values: ["modrinth","curseforge"]),
        .init(name: "game", type: "string", required: false, help: Messages.CLIInterface.minecraftVersionFilterHelp.localized, values: []),
        .init(name: "loader", type: "string", required: false, help: Messages.CLIInterface.loaderFilterHelp.localized, values: []),
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.resultLimitHelp.localized, values: []),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.resultOffsetHelp.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.allResultsHelp.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "project") var operands: [String] = []
    @Option(name: .customLong("provider"), help: ArgumentHelp(Messages.CLIInterface.contentProviderHelp.localized)) var optionProvider: String?
    @Option(name: .customLong("game"), help: ArgumentHelp(Messages.CLIInterface.minecraftVersionFilterHelp.localized)) var optionGame: String?
    @Option(name: .customLong("loader"), help: ArgumentHelp(Messages.CLIInterface.loaderFilterHelp.localized)) var optionLoader: String?
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.resultLimitHelp.localized)) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.resultOffsetHelp.localized)) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.allResultsHelp.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "provider": .text(optionProvider),
        "game": .text(optionGame),
        "loader": .text(optionLoader),
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct CatalogCategoriesCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["catalog","categories"], summary: Messages.CLIInterface.catalogCategoriesHelp.localized, operands: [

    ], options: [
        .init(name: "provider", type: "string", required: false, help: Messages.CLIInterface.contentProviderHelp.localized, values: ["modrinth","curseforge"]),
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.resultLimitHelp.localized, values: []),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.resultOffsetHelp.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.allResultsHelp.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "") var operands: [String] = []
    @Option(name: .customLong("provider"), help: ArgumentHelp(Messages.CLIInterface.contentProviderHelp.localized)) var optionProvider: String?
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.resultLimitHelp.localized)) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.resultOffsetHelp.localized)) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.allResultsHelp.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "provider": .text(optionProvider),
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct ContentListCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["content","list"], summary: Messages.CLIInterface.contentListHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance")
    ], options: [
        .init(name: "kind", type: "string", required: false, help: Messages.CLIInterface.contentKindHelp.localized, values: ["mod","resourcepack","shader"]),
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.resultLimitHelp.localized, values: []),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.resultOffsetHelp.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.allResultsHelp.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "instance") var operands: [String] = []
    @Option(name: .customLong("kind"), help: ArgumentHelp(Messages.CLIInterface.contentKindHelp.localized)) var optionKind: String?
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.resultLimitHelp.localized)) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.resultOffsetHelp.localized)) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.allResultsHelp.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "kind": .text(optionKind),
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct ContentImportCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["content","import"], summary: Messages.CLIInterface.contentImportHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "file", type: "string", required: true, help: "file")
    ], options: [
        .init(name: "kind", type: "string", required: false, help: Messages.CLIInterface.contentKindHelp.localized, values: ["mod","resourcepack","shader"]),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.contentImportArgumentsHelp.localized)) var operands: [String] = []
    @Option(name: .customLong("kind"), help: ArgumentHelp(Messages.CLIInterface.contentKindHelp.localized)) var optionKind: String?
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "kind": .text(optionKind),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct ContentInstallCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["content","install"], summary: Messages.CLIInterface.contentInstallHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "project", type: "string", required: true, help: "project")
    ], options: [
        .init(name: "provider", type: "string", required: false, help: Messages.CLIInterface.contentProviderHelp.localized, values: ["modrinth","curseforge"]),
        .init(name: "version", type: "string", required: false, help: Messages.CLIInterface.contentVersionIdHelp.localized, values: []),
        .init(name: "manual", type: "strings", required: false, help: Messages.CLIInterface.manualCurseForgeFileHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri content install <instance-uuid> sodium --provider modrinth --dry-run --json"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.contentProjectArgumentsHelp.localized)) var operands: [String] = []
    @Option(name: .customLong("provider"), help: ArgumentHelp(Messages.CLIInterface.contentProviderHelp.localized)) var optionProvider: String?
    @Option(name: .customLong("version"), help: ArgumentHelp(Messages.CLIInterface.contentVersionIdHelp.localized)) var optionVersion: String?
    @Option(name: .customLong("manual"), help: ArgumentHelp(Messages.CLIInterface.manualCurseForgeFileHelp.localized)) var optionManual: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "provider": .text(optionProvider),
        "version": .text(optionVersion),
        "manual": .array(optionManual.map(Value.string)),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct ContentEnableCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["content","enable"], summary: Messages.CLIInterface.contentEnableHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance")
    ], options: [
        .init(name: "kind", type: "string", required: false, help: Messages.CLIInterface.contentKindHelp.localized, values: ["mod","resourcepack","shader"]),
        .init(name: "file", type: "strings", required: false, help: Messages.CLIInterface.contentFileSelectionHelp.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.allContentFilesHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "instance") var operands: [String] = []
    @Option(name: .customLong("kind"), help: ArgumentHelp(Messages.CLIInterface.contentKindHelp.localized)) var optionKind: String?
    @Option(name: .customLong("file"), help: ArgumentHelp(Messages.CLIInterface.contentFileSelectionHelp.localized)) var optionFile: [String] = []
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.allContentFilesHelp.localized)) var optionAll = false
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "kind": .text(optionKind),
        "file": .array(optionFile.map(Value.string)),
        "all": .bool(optionAll),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct ContentDisableCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["content","disable"], summary: Messages.CLIInterface.contentDisableHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance")
    ], options: [
        .init(name: "kind", type: "string", required: false, help: Messages.CLIInterface.contentKindHelp.localized, values: ["mod","resourcepack","shader"]),
        .init(name: "file", type: "strings", required: false, help: Messages.CLIInterface.contentFileSelectionHelp.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.allContentFilesHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "instance") var operands: [String] = []
    @Option(name: .customLong("kind"), help: ArgumentHelp(Messages.CLIInterface.contentKindHelp.localized)) var optionKind: String?
    @Option(name: .customLong("file"), help: ArgumentHelp(Messages.CLIInterface.contentFileSelectionHelp.localized)) var optionFile: [String] = []
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.allContentFilesHelp.localized)) var optionAll = false
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "kind": .text(optionKind),
        "file": .array(optionFile.map(Value.string)),
        "all": .bool(optionAll),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct ContentRemoveCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["content","remove"], summary: Messages.CLIInterface.contentRemoveHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance")
    ], options: [
        .init(name: "kind", type: "string", required: false, help: Messages.CLIInterface.contentKindHelp.localized, values: ["mod","resourcepack","shader"]),
        .init(name: "file", type: "strings", required: false, help: Messages.CLIInterface.contentFileSelectionHelp.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.allContentFilesHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "instance") var operands: [String] = []
    @Option(name: .customLong("kind"), help: ArgumentHelp(Messages.CLIInterface.contentKindHelp.localized)) var optionKind: String?
    @Option(name: .customLong("file"), help: ArgumentHelp(Messages.CLIInterface.contentFileSelectionHelp.localized)) var optionFile: [String] = []
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.allContentFilesHelp.localized)) var optionAll = false
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    @Flag(name: .customLong("yes"), help: ArgumentHelp(Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized)) var optionYes = false
    var parameters: [String: Value] { [
        "kind": .text(optionKind),
        "file": .array(optionFile.map(Value.string)),
        "all": .bool(optionAll),
        "dry-run": .bool(optionDryRun),
        "yes": .bool(optionYes)
    ].filter { $0.value != .null } }
}

struct ContentUpdateCheckCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["content","update-check"], summary: Messages.CLIInterface.contentCheckUpdatesHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance")
    ], options: [
        .init(name: "kind", type: "string", required: false, help: Messages.CLIInterface.contentKindHelp.localized, values: ["mod","resourcepack","shader"]),
        .init(name: "file", type: "strings", required: false, help: Messages.CLIInterface.contentFileSelectionHelp.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "instance") var operands: [String] = []
    @Option(name: .customLong("kind"), help: ArgumentHelp(Messages.CLIInterface.contentKindHelp.localized)) var optionKind: String?
    @Option(name: .customLong("file"), help: ArgumentHelp(Messages.CLIInterface.contentFileSelectionHelp.localized)) var optionFile: [String] = []
    var parameters: [String: Value] { [
        "kind": .text(optionKind),
        "file": .array(optionFile.map(Value.string))
    ].filter { $0.value != .null } }
}

struct ContentUpdateCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["content","update"], summary: Messages.CLIInterface.contentUpdateHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance")
    ], options: [
        .init(name: "kind", type: "string", required: false, help: Messages.CLIInterface.contentKindHelp.localized, values: ["mod","resourcepack","shader"]),
        .init(name: "file", type: "strings", required: false, help: Messages.CLIInterface.contentFileSelectionHelp.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.updateAllContentFilesHelp.localized, values: []),
        .init(name: "manual", type: "strings", required: false, help: Messages.CLIInterface.manualCurseForgeFileHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "instance") var operands: [String] = []
    @Option(name: .customLong("kind"), help: ArgumentHelp(Messages.CLIInterface.contentKindHelp.localized)) var optionKind: String?
    @Option(name: .customLong("file"), help: ArgumentHelp(Messages.CLIInterface.contentFileSelectionHelp.localized)) var optionFile: [String] = []
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.updateAllContentFilesHelp.localized)) var optionAll = false
    @Option(name: .customLong("manual"), help: ArgumentHelp(Messages.CLIInterface.manualCurseForgeFileHelp.localized)) var optionManual: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "kind": .text(optionKind),
        "file": .array(optionFile.map(Value.string)),
        "all": .bool(optionAll),
        "manual": .array(optionManual.map(Value.string)),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct WorldListCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["world","list"], summary: Messages.CLIInterface.worldListHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance")
    ], options: [
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.resultLimitHelp.localized, values: []),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.resultOffsetHelp.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.allResultsHelp.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "instance") var operands: [String] = []
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.resultLimitHelp.localized)) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.resultOffsetHelp.localized)) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.allResultsHelp.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct WorldShowCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["world","show"], summary: Messages.CLIInterface.worldShowHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "folder", type: "string", required: true, help: "folder")
    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.worldFolderArgumentsHelp.localized)) var operands: [String] = []
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct WorldImportCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["world","import"], summary: Messages.CLIInterface.worldImportHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "file", type: "string", required: true, help: "file")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.contentImportArgumentsHelp.localized)) var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct WorldExportCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["world","export"], summary: Messages.CLIInterface.worldExportHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "folder", type: "string", required: true, help: "folder"),
        .init(name: "file", type: "string", required: true, help: "file")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.worldExportArgumentsHelp.localized)) var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct WorldRemoveCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["world","remove"], summary: Messages.CLIInterface.worldRemoveHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "folder", type: "string", required: true, help: "folder")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.worldFolderArgumentsHelp.localized)) var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    @Flag(name: .customLong("yes"), help: ArgumentHelp(Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized)) var optionYes = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun),
        "yes": .bool(optionYes)
    ].filter { $0.value != .null } }
}

struct WorldBackupCreateCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["world","backup","create"], summary: Messages.CLIInterface.worldBackupCreateHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "folder", type: "string", required: true, help: "folder")
    ], options: [
        .init(name: "reason", type: "string", required: false, help: Messages.CLIInterface.worldBackupReasonHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.worldFolderArgumentsHelp.localized)) var operands: [String] = []
    @Option(name: .customLong("reason"), help: ArgumentHelp(Messages.CLIInterface.worldBackupReasonHelp.localized)) var optionReason: String?
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "reason": .text(optionReason),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct WorldBackupListCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["world","backup","list"], summary: Messages.CLIInterface.worldBackupListHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance")
    ], options: [
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.resultLimitHelp.localized, values: []),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.resultOffsetHelp.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.allResultsHelp.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "instance") var operands: [String] = []
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.resultLimitHelp.localized)) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.resultOffsetHelp.localized)) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.allResultsHelp.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct WorldBackupRestoreCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["world","backup","restore"], summary: Messages.CLIInterface.worldBackupRestoreHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "backup", type: "string", required: true, help: "backup")
    ], options: [
        .init(name: "replace", type: "bool", required: false, help: Messages.CLIInterface.worldBackupReplaceHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.worldBackupArgumentsHelp.localized)) var operands: [String] = []
    @Flag(name: .customLong("replace"), help: ArgumentHelp(Messages.CLIInterface.worldBackupReplaceHelp.localized)) var optionReplace = false
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    @Flag(name: .customLong("yes"), help: ArgumentHelp(Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized)) var optionYes = false
    var parameters: [String: Value] { [
        "replace": .bool(optionReplace),
        "dry-run": .bool(optionDryRun),
        "yes": .bool(optionYes)
    ].filter { $0.value != .null } }
}

struct WorldBackupRemoveCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["world","backup","remove"], summary: Messages.CLIInterface.worldBackupRemoveHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "backup", type: "string", required: true, help: "backup")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.worldBackupArgumentsHelp.localized)) var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    @Flag(name: .customLong("yes"), help: ArgumentHelp(Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized)) var optionYes = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun),
        "yes": .bool(optionYes)
    ].filter { $0.value != .null } }
}

struct DatapackListCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["datapack","list"], summary: Messages.CLIInterface.dataPackListHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "world", type: "string", required: true, help: "world")
    ], options: [
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.resultLimitHelp.localized, values: []),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.resultOffsetHelp.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.allResultsHelp.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.dataPackWorldArgumentsHelp.localized)) var operands: [String] = []
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.resultLimitHelp.localized)) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.resultOffsetHelp.localized)) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.allResultsHelp.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct DatapackOrderGetCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["datapack","order","get"], summary: Messages.CLIInterface.dataPackOrderGetHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "world", type: "string", required: true, help: "world")
    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.dataPackWorldArgumentsHelp.localized)) var operands: [String] = []
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct DatapackOrderSetCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["datapack","order","set"], summary: Messages.CLIInterface.dataPackOrderSetHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "world", type: "string", required: true, help: "world")
    ], options: [
        .init(name: "key", type: "strings", required: true, help: Messages.CLIInterface.dataPackPriorityListHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.dataPackWorldArgumentsHelp.localized)) var operands: [String] = []
    @Option(name: .customLong("key"), help: ArgumentHelp(Messages.CLIInterface.dataPackPriorityListHelp.localized)) var optionKey: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "key": .array(optionKey.map(Value.string)),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct DatapackImportCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["datapack","import"], summary: Messages.CLIInterface.dataPackImportHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "world", type: "string", required: true, help: "world"),
        .init(name: "file", type: "string", required: true, help: "file")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.dataPackImportArgumentsHelp.localized)) var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct DatapackEnableCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["datapack","enable"], summary: Messages.CLIInterface.dataPackEnableHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "world", type: "string", required: true, help: "world"),
        .init(name: "name", type: "string", required: true, help: "name")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.dataPackTargetArgumentsHelp.localized)) var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct DatapackDisableCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["datapack","disable"], summary: Messages.CLIInterface.dataPackDisableHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "world", type: "string", required: true, help: "world"),
        .init(name: "name", type: "string", required: true, help: "name")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.dataPackTargetArgumentsHelp.localized)) var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct DatapackRemoveCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["datapack","remove"], summary: Messages.CLIInterface.dataPackRemoveHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "world", type: "string", required: true, help: "world"),
        .init(name: "name", type: "string", required: true, help: "name")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.dataPackTargetArgumentsHelp.localized)) var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    @Flag(name: .customLong("yes"), help: ArgumentHelp(Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized)) var optionYes = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun),
        "yes": .bool(optionYes)
    ].filter { $0.value != .null } }
}

struct DatapackSearchCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["datapack","search"], summary: Messages.CLIInterface.dataPackSearchHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "query", type: "string", required: true, help: "query")
    ], options: [
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.resultLimitHelp.localized, values: []),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.resultOffsetHelp.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.allResultsHelp.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.dataPackSearchArgumentsHelp.localized)) var operands: [String] = []
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.resultLimitHelp.localized)) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.resultOffsetHelp.localized)) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.allResultsHelp.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct DatapackVersionsCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["datapack","versions"], summary: Messages.CLIInterface.dataPackVersionsHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "project", type: "string", required: true, help: "project")
    ], options: [
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.resultLimitHelp.localized, values: []),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.resultOffsetHelp.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.allResultsHelp.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.contentProjectArgumentsHelp.localized)) var operands: [String] = []
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.resultLimitHelp.localized)) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.resultOffsetHelp.localized)) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.allResultsHelp.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct DatapackInstallCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["datapack","install"], summary: Messages.CLIInterface.dataPackInstallHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "world", type: "string", required: true, help: "world"),
        .init(name: "project", type: "string", required: true, help: "project")
    ], options: [
        .init(name: "version", type: "string", required: false, help: Messages.CLIInterface.dataPackVersionIdHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.dataPackProjectArgumentsHelp.localized)) var operands: [String] = []
    @Option(name: .customLong("version"), help: ArgumentHelp(Messages.CLIInterface.dataPackVersionIdHelp.localized)) var optionVersion: String?
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "version": .text(optionVersion),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct SchematicListCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["schematic","list"], summary: Messages.CLIInterface.schematicListHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance")
    ], options: [
        .init(name: "directory", type: "string", required: false, help: Messages.CLIInterface.schematicRelativePathHelp.localized, values: []),
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.resultLimitHelp.localized, values: []),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.resultOffsetHelp.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.allResultsHelp.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "instance") var operands: [String] = []
    @Option(name: .customLong("directory"), help: ArgumentHelp(Messages.CLIInterface.schematicRelativePathHelp.localized)) var optionDirectory: String?
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.resultLimitHelp.localized)) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.resultOffsetHelp.localized)) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.allResultsHelp.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "directory": .text(optionDirectory),
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct SchematicInfoCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["schematic","info"], summary: Messages.CLIInterface.schematicShowHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "path", type: "string", required: true, help: "path")
    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.instanceRunDirectoryPathArgumentsHelp.localized)) var operands: [String] = []
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct SchematicImportCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["schematic","import"], summary: Messages.CLIInterface.schematicImportHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "file", type: "string", required: true, help: "file")
    ], options: [
        .init(name: "directory", type: "string", required: false, help: Messages.CLIInterface.schematicRelativePathHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.contentImportArgumentsHelp.localized)) var operands: [String] = []
    @Option(name: .customLong("directory"), help: ArgumentHelp(Messages.CLIInterface.schematicRelativePathHelp.localized)) var optionDirectory: String?
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "directory": .text(optionDirectory),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct SchematicMkdirCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["schematic","mkdir"], summary: Messages.CLIInterface.schematicCreateFolderHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "name", type: "string", required: true, help: "name")
    ], options: [
        .init(name: "directory", type: "string", required: false, help: Messages.CLIInterface.schematicParentDirectoryHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.schematicFolderArgumentsHelp.localized)) var operands: [String] = []
    @Option(name: .customLong("directory"), help: ArgumentHelp(Messages.CLIInterface.schematicParentDirectoryHelp.localized)) var optionDirectory: String?
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "directory": .text(optionDirectory),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct SchematicExportCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["schematic","export"], summary: Messages.CLIInterface.schematicExportHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "path", type: "string", required: true, help: "path"),
        .init(name: "file", type: "string", required: true, help: "file")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.schematicExportArgumentsHelp.localized)) var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct SchematicRemoveCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["schematic","remove"], summary: Messages.CLIInterface.schematicRemoveHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "path", type: "string", required: true, help: "path")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.instanceRunDirectoryPathArgumentsHelp.localized)) var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    @Flag(name: .customLong("yes"), help: ArgumentHelp(Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized)) var optionYes = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun),
        "yes": .bool(optionYes)
    ].filter { $0.value != .null } }
}

struct InstanceImportCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["instance","import"], summary: Messages.CLIInterface.instanceImportHelp.localized, operands: [
        .init(name: "file", type: "string", required: true, help: "file")
    ], options: [
        .init(name: "name", type: "string", required: true, help: Messages.CLIInterface.newInstanceNameHelp.localized, values: []),
        .init(name: "directory", type: "string", required: true, help: Messages.CLIInterface.instanceImportDirectoryHelp.localized, values: []),
        .init(name: "manual", type: "strings", required: false, help: Messages.CLIInterface.manualCurseForgeFileHelp.localized, values: []),
        .init(name: "import-jvm-arguments", type: "bool", required: false, help: Messages.CLIInterface.importModpackJvmArgumentsHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "file") var operands: [String] = []
    @Option(name: .customLong("name"), help: ArgumentHelp(Messages.CLIInterface.newInstanceNameHelp.localized)) var optionName: String?
    @Option(name: .customLong("directory"), help: ArgumentHelp(Messages.CLIInterface.instanceImportDirectoryHelp.localized)) var optionDirectory: String?
    @Option(name: .customLong("manual"), help: ArgumentHelp(Messages.CLIInterface.manualCurseForgeFileHelp.localized)) var optionManual: [String] = []
    @Flag(name: .customLong("import-jvm-arguments"), help: ArgumentHelp(Messages.CLIInterface.importModpackJvmArgumentsHelp.localized)) var optionImportJvmArguments = false
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "name": .text(optionName),
        "directory": .text(optionDirectory),
        "manual": .array(optionManual.map(Value.string)),
        "import-jvm-arguments": .bool(optionImportJvmArguments),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct PackImportCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["pack","import"], summary: Messages.CLIInterface.modpackImportHelp.localized, operands: [
        .init(name: "file", type: "string", required: true, help: "file")
    ], options: [
        .init(name: "name", type: "string", required: true, help: Messages.CLIInterface.newInstanceNameHelp.localized, values: []),
        .init(name: "directory", type: "string", required: true, help: Messages.CLIInterface.instanceImportDirectoryHelp.localized, values: []),
        .init(name: "manual", type: "strings", required: false, help: Messages.CLIInterface.manualCurseForgeFileHelp.localized, values: []),
        .init(name: "import-jvm-arguments", type: "bool", required: false, help: Messages.CLIInterface.importModpackJvmArgumentsHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "file") var operands: [String] = []
    @Option(name: .customLong("name"), help: ArgumentHelp(Messages.CLIInterface.newInstanceNameHelp.localized)) var optionName: String?
    @Option(name: .customLong("directory"), help: ArgumentHelp(Messages.CLIInterface.instanceImportDirectoryHelp.localized)) var optionDirectory: String?
    @Option(name: .customLong("manual"), help: ArgumentHelp(Messages.CLIInterface.manualCurseForgeFileHelp.localized)) var optionManual: [String] = []
    @Flag(name: .customLong("import-jvm-arguments"), help: ArgumentHelp(Messages.CLIInterface.importModpackJvmArgumentsHelp.localized)) var optionImportJvmArguments = false
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "name": .text(optionName),
        "directory": .text(optionDirectory),
        "manual": .array(optionManual.map(Value.string)),
        "import-jvm-arguments": .bool(optionImportJvmArguments),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct PackInstallCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["pack","install"], summary: Messages.CLIInterface.modpackInstallHelp.localized, operands: [
        .init(name: "project", type: "string", required: true, help: "project")
    ], options: [
        .init(name: "provider", type: "string", required: false, help: Messages.CLIInterface.contentProviderHelp.localized, values: ["modrinth","curseforge"]),
        .init(name: "version", type: "string", required: false, help: Messages.CLIInterface.contentVersionIdHelp.localized, values: []),
        .init(name: "archive", type: "string", required: false, help: Messages.CLIInterface.manualModpackArchiveHelp.localized, values: []),
        .init(name: "name", type: "string", required: true, help: Messages.CLIInterface.newInstanceNameHelp.localized, values: []),
        .init(name: "directory", type: "string", required: true, help: Messages.CLIInterface.instanceImportDirectoryHelp.localized, values: []),
        .init(name: "manual", type: "strings", required: false, help: Messages.CLIInterface.manualCurseForgeFileHelp.localized, values: []),
        .init(name: "import-jvm-arguments", type: "bool", required: false, help: Messages.CLIInterface.importModpackJvmArgumentsHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "project") var operands: [String] = []
    @Option(name: .customLong("provider"), help: ArgumentHelp(Messages.CLIInterface.contentProviderHelp.localized)) var optionProvider: String?
    @Option(name: .customLong("version"), help: ArgumentHelp(Messages.CLIInterface.contentVersionIdHelp.localized)) var optionVersion: String?
    @Option(name: .customLong("archive"), help: ArgumentHelp(Messages.CLIInterface.manualModpackArchiveHelp.localized)) var optionArchive: String?
    @Option(name: .customLong("name"), help: ArgumentHelp(Messages.CLIInterface.newInstanceNameHelp.localized)) var optionName: String?
    @Option(name: .customLong("directory"), help: ArgumentHelp(Messages.CLIInterface.instanceImportDirectoryHelp.localized)) var optionDirectory: String?
    @Option(name: .customLong("manual"), help: ArgumentHelp(Messages.CLIInterface.manualCurseForgeFileHelp.localized)) var optionManual: [String] = []
    @Flag(name: .customLong("import-jvm-arguments"), help: ArgumentHelp(Messages.CLIInterface.importModpackJvmArgumentsHelp.localized)) var optionImportJvmArguments = false
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "provider": .text(optionProvider),
        "version": .text(optionVersion),
        "archive": .text(optionArchive),
        "name": .text(optionName),
        "directory": .text(optionDirectory),
        "manual": .array(optionManual.map(Value.string)),
        "import-jvm-arguments": .bool(optionImportJvmArguments),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct PackShowCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["pack","show"], summary: Messages.CLIInterface.modpackShowHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance")
    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "instance") var operands: [String] = []
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct PackUpdateCheckCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["pack","update-check"], summary: Messages.CLIInterface.modpackVersionsHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance")
    ], options: [
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.resultLimitHelp.localized, values: []),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.resultOffsetHelp.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.allResultsHelp.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "instance") var operands: [String] = []
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.resultLimitHelp.localized)) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.resultOffsetHelp.localized)) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.allResultsHelp.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct PackUpdateCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["pack","update"], summary: Messages.CLIInterface.modpackUpdateHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance")
    ], options: [
        .init(name: "file", type: "string", required: false, help: Messages.CLIInterface.modpackUpdateFileHelp.localized, values: []),
        .init(name: "version", type: "string", required: false, help: Messages.CLIInterface.modpackUpdateVersionHelp.localized, values: []),
        .init(name: "archive", type: "string", required: false, help: Messages.CLIInterface.manualModpackUpdateArchiveHelp.localized, values: []),
        .init(name: "manual", type: "strings", required: false, help: Messages.CLIInterface.manualCurseForgeFileHelp.localized, values: []),
        .init(name: "replace", type: "bool", required: false, help: Messages.CLIInterface.replaceLocalModificationsHelp.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.confirmLocalModificationsReplacementHelp.localized, values: []),
        .init(name: "import-jvm-arguments", type: "bool", required: false, help: Messages.CLIInterface.importModpackJvmArgumentsHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "instance") var operands: [String] = []
    @Option(name: .customLong("file"), help: ArgumentHelp(Messages.CLIInterface.modpackUpdateFileHelp.localized)) var optionFile: String?
    @Option(name: .customLong("version"), help: ArgumentHelp(Messages.CLIInterface.modpackUpdateVersionHelp.localized)) var optionVersion: String?
    @Option(name: .customLong("archive"), help: ArgumentHelp(Messages.CLIInterface.manualModpackUpdateArchiveHelp.localized)) var optionArchive: String?
    @Option(name: .customLong("manual"), help: ArgumentHelp(Messages.CLIInterface.manualCurseForgeFileHelp.localized)) var optionManual: [String] = []
    @Flag(name: .customLong("replace"), help: ArgumentHelp(Messages.CLIInterface.replaceLocalModificationsHelp.localized)) var optionReplace = false
    @Flag(name: .customLong("yes"), help: ArgumentHelp(Messages.CLIInterface.confirmLocalModificationsReplacementHelp.localized)) var optionYes = false
    @Flag(name: .customLong("import-jvm-arguments"), help: ArgumentHelp(Messages.CLIInterface.importModpackJvmArgumentsHelp.localized)) var optionImportJvmArguments = false
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "file": .text(optionFile),
        "version": .text(optionVersion),
        "archive": .text(optionArchive),
        "manual": .array(optionManual.map(Value.string)),
        "replace": .bool(optionReplace),
        "yes": .bool(optionYes),
        "import-jvm-arguments": .bool(optionImportJvmArguments),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct PackRollbackCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["pack","rollback"], summary: Messages.CLIInterface.modpackRollbackHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "instance") var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    @Flag(name: .customLong("yes"), help: ArgumentHelp(Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized)) var optionYes = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun),
        "yes": .bool(optionYes)
    ].filter { $0.value != .null } }
}

struct DownloadFetchCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["download","fetch"], summary: Messages.CLIInterface.downloadFetchHelp.localized, operands: [
        .init(name: "url", type: "string", required: true, help: "url"),
        .init(name: "file", type: "string", required: true, help: "file")
    ], options: [
        .init(name: "sha1", type: "string", required: true, help: Messages.CLIInterface.downloadSha1Help.localized, values: []),
        .init(name: "size", type: "int", required: true, help: Messages.CLIInterface.downloadSizeHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.downloadTargetArgumentsHelp.localized)) var operands: [String] = []
    @Option(name: .customLong("sha1"), help: ArgumentHelp(Messages.CLIInterface.downloadSha1Help.localized)) var optionSha1: String?
    @Option(name: .customLong("size"), help: ArgumentHelp(Messages.CLIInterface.downloadSizeHelp.localized)) var optionSize: Int?
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "sha1": .text(optionSha1),
        "size": optionSize.map(Value.integer) ?? .null,
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct RecoveryListCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["recovery","list"], summary: Messages.CLIInterface.recoveryListHelp.localized, operands: [

    ], options: [
        .init(name: "instance", type: "string", required: false, help: Messages.CLIInterface.recoveryInstanceFilterHelp.localized, values: []),
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.resultLimitHelp.localized, values: []),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.resultOffsetHelp.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.allResultsHelp.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "") var operands: [String] = []
    @Option(name: .customLong("instance"), help: ArgumentHelp(Messages.CLIInterface.recoveryInstanceFilterHelp.localized)) var optionInstance: String?
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.resultLimitHelp.localized)) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.resultOffsetHelp.localized)) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.allResultsHelp.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "instance": .text(optionInstance),
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct RecoveryApplyCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["recovery","apply"], summary: Messages.CLIInterface.recoveryApplyHelp.localized, operands: [
        .init(name: "kind", type: "string", required: true, help: "kind"),
        .init(name: "target", type: "string", required: true, help: "target")
    ], options: [
        .init(name: "transaction", type: "string", required: false, help: Messages.CLIInterface.recoveryTransactionHelp.localized, values: []),
        .init(name: "mode", type: "string", required: false, help: Messages.CLIInterface.libraryImportRecoveryModeHelp.localized, values: ["finish","keep-files"]),
        .init(name: "keep-source", type: "bool", required: false, help: Messages.CLIInterface.keepSourceAfterMoveHelp.localized, values: []),
        .init(name: "confirm-game-ended", type: "bool", required: false, help: Messages.CLIInterface.confirmUnmonitoredGameExitHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.recoveryTargetArgumentsHelp.localized)) var operands: [String] = []
    @Option(name: .customLong("transaction"), help: ArgumentHelp(Messages.CLIInterface.recoveryTransactionHelp.localized)) var optionTransaction: String?
    @Option(name: .customLong("mode"), help: ArgumentHelp(Messages.CLIInterface.libraryImportRecoveryModeHelp.localized)) var optionMode: String?
    @Flag(name: .customLong("keep-source"), help: ArgumentHelp(Messages.CLIInterface.keepSourceAfterMoveHelp.localized)) var optionKeepSource = false
    @Flag(name: .customLong("confirm-game-ended"), help: ArgumentHelp(Messages.CLIInterface.confirmUnmonitoredGameExitHelp.localized)) var optionConfirmGameEnded = false
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    @Flag(name: .customLong("yes"), help: ArgumentHelp(Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized)) var optionYes = false
    var parameters: [String: Value] { [
        "transaction": .text(optionTransaction),
        "mode": .text(optionMode),
        "keep-source": .bool(optionKeepSource),
        "confirm-game-ended": .bool(optionConfirmGameEnded),
        "dry-run": .bool(optionDryRun),
        "yes": .bool(optionYes)
    ].filter { $0.value != .null } }
}

struct DoctorCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["doctor"], summary: Messages.CLIInterface.doctorCommandHelp.localized, operands: [

    ], options: [
        .init(name: "instance", type: "string", required: false, help: Messages.CLIInterface.doctorInstanceHelp.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "") var operands: [String] = []
    @Option(name: .customLong("instance"), help: ArgumentHelp(Messages.CLIInterface.doctorInstanceHelp.localized)) var optionInstance: String?
    var parameters: [String: Value] { [
        "instance": .text(optionInstance)
    ].filter { $0.value != .null } }
}

struct CacheStatusCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["cache","status"], summary: Messages.CLIInterface.cacheStatusHelp.localized, operands: [

    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "") var operands: [String] = []
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct CacheCleanCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["cache","clean"], summary: Messages.CLIInterface.cacheCleanHelp.localized, operands: [

    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "") var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct CacheGroup: ParsableCommand {
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "cache", abstract: Messages.CLIInterface.cacheCommands.localized, subcommands: [CacheStatusCommand.self, CacheCleanCommand.self]) }
}

struct AccountServiceKeyGroup: ParsableCommand {
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "service-key", abstract: Messages.CLIInterface.accountServiceKeyCommands.localized, subcommands: [AccountServiceKeyStatusCommand.self, AccountServiceKeySetCommand.self, AccountServiceKeyRemoveCommand.self]) }
}

struct InstanceComponentGroup: ParsableCommand {
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "component", abstract: Messages.CLIInterface.instanceComponentCommands.localized, subcommands: [InstanceComponentListCommand.self, InstanceComponentVersionsCommand.self, InstanceComponentSetCommand.self, InstanceComponentRestoreCommand.self]) }
}

struct DatapackOrderGroup: ParsableCommand {
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "order", abstract: Messages.CLIInterface.dataPackOrderCommands.localized, subcommands: [DatapackOrderGetCommand.self, DatapackOrderSetCommand.self]) }
}

struct DirectoryRunGroup: ParsableCommand {
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "run", abstract: Messages.CLIInterface.instanceRunDirectoryCommands.localized, subcommands: [DirectoryRunGetCommand.self, DirectoryRunSetCommand.self, DirectoryRunRelocateCommand.self]) }
}

struct AccountLoginGroup: ParsableCommand {
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "login", abstract: Messages.CLIInterface.accountLoginCommands.localized, subcommands: [AccountLoginStartCommand.self, AccountLoginCompleteCommand.self, AccountLoginCancelCommand.self]) }
}

struct AppLanguageGroup: ParsableCommand {
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "language", abstract: Messages.CLIInterface.appLanguageCommands.localized, subcommands: [AppLanguageGetCommand.self, AppLanguageSetCommand.self]) }
}

struct WorldBackupGroup: ParsableCommand {
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "backup", abstract: Messages.CLIInterface.worldBackupCommands.localized, subcommands: [WorldBackupCreateCommand.self, WorldBackupListCommand.self, WorldBackupRestoreCommand.self, WorldBackupRemoveCommand.self]) }
}

struct DirectoryGroup: ParsableCommand {
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "directory", abstract: Messages.CLIInterface.directoryCommands.localized, subcommands: [DirectoryListCommand.self, DirectorySelectedCommand.self, DirectoryScanCommand.self, DirectoryAddCommand.self, DirectorySelectCommand.self, DirectoryRefreshCommand.self, DirectoryRemoveCommand.self, DirectoryRenameCommand.self, DirectoryRelocateCommand.self, DirectoryRestoreCommand.self, DirectoryRunGroup.self]) }
}

struct SchematicGroup: ParsableCommand {
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "schematic", abstract: Messages.CLIInterface.schematicCommands.localized, subcommands: [SchematicListCommand.self, SchematicInfoCommand.self, SchematicImportCommand.self, SchematicMkdirCommand.self, SchematicExportCommand.self, SchematicRemoveCommand.self]) }
}

struct InstanceGroup: ParsableCommand {
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "instance", abstract: Messages.CLIInterface.instanceCommands.localized, subcommands: [InstanceListCommand.self, InstanceSelectedCommand.self, InstanceShowCommand.self, InstanceVersionsCommand.self, InstanceCreateCommand.self, InstanceInstallCommand.self, InstanceRepairCommand.self, InstanceSelectCommand.self, InstanceRenameCommand.self, InstanceFavoriteCommand.self, InstanceRemoveCommand.self, InstanceIconCommand.self, InstanceCopyCommand.self, InstanceMoveCommand.self, InstanceExportCommand.self, InstanceComponentGroup.self, InstanceImportCommand.self]) }
}

struct DatapackGroup: ParsableCommand {
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "datapack", abstract: Messages.CLIInterface.dataPackCommands.localized, subcommands: [DatapackListCommand.self, DatapackOrderGroup.self, DatapackImportCommand.self, DatapackEnableCommand.self, DatapackDisableCommand.self, DatapackRemoveCommand.self, DatapackSearchCommand.self, DatapackVersionsCommand.self, DatapackInstallCommand.self]) }
}

struct DownloadGroup: ParsableCommand {
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "download", abstract: Messages.CLIInterface.downloadCommands.localized, subcommands: [DownloadFetchCommand.self]) }
}

struct RecoveryGroup: ParsableCommand {
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "recovery", abstract: Messages.CLIInterface.recoveryCommands.localized, subcommands: [RecoveryListCommand.self, RecoveryApplyCommand.self]) }
}

struct AccountGroup: ParsableCommand {
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "account", abstract: Messages.CLIInterface.accountCommands.localized, subcommands: [AccountListCommand.self, AccountSelectedCommand.self, AccountShowCommand.self, AccountAddOfflineCommand.self, AccountSelectCommand.self, AccountRefreshCommand.self, AccountRemoveCommand.self, AccountLogoutCommand.self, AccountLoginGroup.self, AccountServiceKeyGroup.self]) }
}

struct SessionGroup: ParsableCommand {
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "session", abstract: Messages.CLIInterface.sessionCommands.localized, subcommands: [SessionListCommand.self, SessionShowCommand.self, SessionWaitCommand.self, SessionQuitCommand.self, SessionStopCommand.self, SessionLogsCommand.self, SessionDiagnoseCommand.self, SessionExportCommand.self]) }
}

struct CatalogGroup: ParsableCommand {
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "catalog", abstract: Messages.CLIInterface.catalogCommands.localized, subcommands: [CatalogSearchCommand.self, CatalogShowCommand.self, CatalogVersionsCommand.self, CatalogCategoriesCommand.self]) }
}

struct ContentGroup: ParsableCommand {
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "content", abstract: Messages.CLIInterface.contentCommands.localized, subcommands: [ContentListCommand.self, ContentImportCommand.self, ContentInstallCommand.self, ContentEnableCommand.self, ContentDisableCommand.self, ContentRemoveCommand.self, ContentUpdateCheckCommand.self, ContentUpdateCommand.self]) }
}

struct ConfigGroup: ParsableCommand {
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "config", abstract: Messages.CLIInterface.configCommands.localized, subcommands: [ConfigGetCommand.self, ConfigSetCommand.self, ConfigApplyCommand.self, ConfigResetCommand.self, ConfigInheritCommand.self]) }
}

struct LaunchGroup: ParsableCommand {
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "launch", abstract: Messages.CLIInterface.launchCommands.localized, subcommands: [LaunchPreflightCommand.self, LaunchStartCommand.self]) }
}

struct WorldGroup: ParsableCommand {
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "world", abstract: Messages.CLIInterface.worldCommands.localized, subcommands: [WorldListCommand.self, WorldShowCommand.self, WorldImportCommand.self, WorldExportCommand.self, WorldRemoveCommand.self, WorldBackupGroup.self]) }
}

struct JavaGroup: ParsableCommand {
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "java", abstract: Messages.CLIInterface.javaCommands.localized, subcommands: [JavaListCommand.self, JavaAvailableCommand.self, JavaAddCommand.self, JavaForgetCommand.self, JavaDefaultCommand.self, JavaReferencesCommand.self, JavaInstallCommand.self, JavaRepairCommand.self, JavaRemoveCommand.self]) }
}

struct PackGroup: ParsableCommand {
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "pack", abstract: Messages.CLIInterface.modpackCommands.localized, subcommands: [PackImportCommand.self, PackInstallCommand.self, PackShowCommand.self, PackUpdateCheckCommand.self, PackUpdateCommand.self, PackRollbackCommand.self]) }
}

struct AppGroup: ParsableCommand {
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "app", abstract: Messages.CLIInterface.appCommands.localized, subcommands: [AppInfoCommand.self, AppLanguageGroup.self]) }
}

struct CliGroup: ParsableCommand {
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "cli", abstract: Messages.CLIInterface.cliCommands.localized, subcommands: [CliStatusCommand.self, CliInstallCommand.self, CliUninstallCommand.self]) }
}

struct RuriCommand: ParsableCommand {
    // CHORUS: 注册命令组。
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "ruri-chorus", abstract: Messages.CLIInterface.rootCommandHelp.localized, version: BuildConfiguration().version, subcommands: [ChorusGroup.self, SchemaCommand.self, AppGroup.self, CliGroup.self, ConfigGroup.self, InstanceGroup.self, DirectoryGroup.self, JavaGroup.self, AccountGroup.self, LaunchGroup.self, ServerGroup.self, SessionGroup.self, CatalogGroup.self, ContentGroup.self, WorldGroup.self, DatapackGroup.self, SchematicGroup.self, PackGroup.self, DownloadGroup.self, CacheGroup.self, RecoveryGroup.self, DoctorCommand.self]) }
}

enum CommandRegistry {
    static var commands: [CommandSpec] { [SchemaCommand.spec, AppInfoCommand.spec, AppLanguageGetCommand.spec, AppLanguageSetCommand.spec, CliStatusCommand.spec, CliInstallCommand.spec, CliUninstallCommand.spec, ConfigGetCommand.spec, ConfigSetCommand.spec, ConfigApplyCommand.spec, ConfigResetCommand.spec, ConfigInheritCommand.spec, InstanceListCommand.spec, InstanceSelectedCommand.spec, InstanceShowCommand.spec, InstanceVersionsCommand.spec, InstanceCreateCommand.spec, InstanceInstallCommand.spec, InstanceRepairCommand.spec, InstanceSelectCommand.spec, InstanceRenameCommand.spec, InstanceFavoriteCommand.spec, InstanceRemoveCommand.spec, InstanceIconCommand.spec, InstanceCopyCommand.spec, InstanceMoveCommand.spec, InstanceExportCommand.spec, InstanceComponentListCommand.spec, InstanceComponentVersionsCommand.spec, InstanceComponentSetCommand.spec, InstanceComponentRestoreCommand.spec, DirectoryListCommand.spec, DirectorySelectedCommand.spec, DirectoryScanCommand.spec, DirectoryAddCommand.spec, DirectorySelectCommand.spec, DirectoryRefreshCommand.spec, DirectoryRemoveCommand.spec, DirectoryRenameCommand.spec, DirectoryRelocateCommand.spec, DirectoryRestoreCommand.spec, DirectoryRunGetCommand.spec, DirectoryRunSetCommand.spec, DirectoryRunRelocateCommand.spec, JavaListCommand.spec, JavaAvailableCommand.spec, JavaAddCommand.spec, JavaForgetCommand.spec, JavaDefaultCommand.spec, JavaReferencesCommand.spec, JavaInstallCommand.spec, JavaRepairCommand.spec, JavaRemoveCommand.spec, AccountListCommand.spec, AccountSelectedCommand.spec, AccountShowCommand.spec, AccountAddOfflineCommand.spec, AccountSelectCommand.spec, AccountRefreshCommand.spec, AccountRemoveCommand.spec, AccountLogoutCommand.spec, AccountLoginStartCommand.spec, AccountLoginCompleteCommand.spec, AccountLoginCancelCommand.spec, AccountServiceKeyStatusCommand.spec, AccountServiceKeySetCommand.spec, AccountServiceKeyRemoveCommand.spec, LaunchPreflightCommand.spec, LaunchStartCommand.spec, ServerListCommand.spec, ServerAddCommand.spec, ServerEditCommand.spec, ServerRemoveCommand.spec, ServerMoveCommand.spec, ServerFavoriteCommand.spec, ServerPreferencesCommand.spec, ServerQueryCommand.spec, SessionListCommand.spec, SessionShowCommand.spec, SessionWaitCommand.spec, SessionQuitCommand.spec, SessionStopCommand.spec, SessionLogsCommand.spec, SessionDiagnoseCommand.spec, SessionExportCommand.spec, CatalogSearchCommand.spec, CatalogShowCommand.spec, CatalogVersionsCommand.spec, CatalogCategoriesCommand.spec, ContentListCommand.spec, ContentImportCommand.spec, ContentInstallCommand.spec, ContentEnableCommand.spec, ContentDisableCommand.spec, ContentRemoveCommand.spec, ContentUpdateCheckCommand.spec, ContentUpdateCommand.spec, WorldListCommand.spec, WorldShowCommand.spec, WorldImportCommand.spec, WorldExportCommand.spec, WorldRemoveCommand.spec, WorldBackupCreateCommand.spec, WorldBackupListCommand.spec, WorldBackupRestoreCommand.spec, WorldBackupRemoveCommand.spec, DatapackListCommand.spec, DatapackOrderGetCommand.spec, DatapackOrderSetCommand.spec, DatapackImportCommand.spec, DatapackEnableCommand.spec, DatapackDisableCommand.spec, DatapackRemoveCommand.spec, DatapackSearchCommand.spec, DatapackVersionsCommand.spec, DatapackInstallCommand.spec, SchematicListCommand.spec, SchematicInfoCommand.spec, SchematicImportCommand.spec, SchematicMkdirCommand.spec, SchematicExportCommand.spec, SchematicRemoveCommand.spec, InstanceImportCommand.spec, PackImportCommand.spec, PackInstallCommand.spec, PackShowCommand.spec, PackUpdateCheckCommand.spec, PackUpdateCommand.spec, PackRollbackCommand.spec, DownloadFetchCommand.spec, CacheStatusCommand.spec, CacheCleanCommand.spec, RecoveryListCommand.spec, RecoveryApplyCommand.spec, DoctorCommand.spec] }
}
