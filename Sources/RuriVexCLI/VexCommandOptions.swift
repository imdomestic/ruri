import ArgumentParser
import RuriCommandKit

protocol VexCommandOptions: ParsableArguments {
    var parameters: [String: Value] { get }
}

struct VexNoOptions: VexCommandOptions {
    var parameters: [String: Value] { [:] }
}

struct VexServerOptions: VexCommandOptions {
    @Option var server: String?
    var parameters: [String: Value] { ["server": .text(server)] }
}

struct VexProjectOptions: VexCommandOptions {
    @OptionGroup var selection: VexServerOptions
    @Option var project: String?
    var parameters: [String: Value] { selection.parameters.merging(["project": .text(project)]) { _, new in new } }
}

struct VexDryRunOptions: VexCommandOptions {
    @Flag(name: .customLong("dry-run")) var dryRun = false
    var parameters: [String: Value] { ["dry-run": .bool(dryRun)] }
}

struct VexServerAddOptions: VexCommandOptions {
    @OptionGroup var preview: VexDryRunOptions
    @Option var name: String?
    @Option var project: String?
    var parameters: [String: Value] { preview.parameters.merging(["name": .text(name), "project": .text(project)]) { _, new in new } }
}

struct VexServerDefaultOptions: VexCommandOptions {
    @OptionGroup var preview: VexDryRunOptions
    @Option var project: String?
    var parameters: [String: Value] { preview.parameters.merging(["project": .text(project)]) { _, new in new } }
}

struct VexLoginOptions: VexCommandOptions {
    @OptionGroup var selection: VexServerOptions
    @OptionGroup var preview: VexDryRunOptions
    @Option var invite: String?
    @Option(completion: .list(["invite", "github"])) var method: String?
    @Flag var github = false
    @Flag(name: .customLong("token-stdin")) var tokenStdin = false
    var parameters: [String: Value] {
        selection.parameters.merging(preview.parameters) { _, new in new }
            .merging(["invite": .text(invite), "method": .text(method), "github": .bool(github), "token-stdin": .bool(tokenStdin)]) { _, new in new }
    }
}

struct VexLogoutOptions: VexCommandOptions {
    @OptionGroup var selection: VexServerOptions
    @OptionGroup var preview: VexDryRunOptions
    var parameters: [String: Value] { selection.parameters.merging(preview.parameters) { _, new in new } }
}

struct VexCommitOptions: VexCommandOptions {
    @OptionGroup var selection: VexProjectOptions
    @Option var branch: String?
    @Option var before: String?
    var parameters: [String: Value] { selection.parameters.merging(["branch": .text(branch), "before": .text(before)]) { _, new in new } }
}

struct VexProjectChangeOptions: VexCommandOptions {
    @OptionGroup var selection: VexProjectOptions
    @OptionGroup var preview: VexDryRunOptions
    var parameters: [String: Value] { selection.parameters.merging(preview.parameters) { _, new in new } }
}

struct VexBuildOptions: VexCommandOptions {
    @OptionGroup var selection: VexProjectChangeOptions
    @Option var loader: String?
    @Flag var force = false
    var parameters: [String: Value] { selection.parameters.merging(["loader": .text(loader), "force": .bool(force)]) { _, new in new } }
}

struct VexCreateOptions: VexCommandOptions {
    @OptionGroup var selection: VexProjectChangeOptions
    @Option var loader: String?
    @Option var branch: String?
    var parameters: [String: Value] { selection.parameters.merging(["loader": .text(loader), "branch": .text(branch)]) { _, new in new } }
}

struct VexStartOptions: VexCommandOptions {
    @OptionGroup var selection: VexProjectChangeOptions
    @Flag var launch = false
    var parameters: [String: Value] { selection.parameters.merging(["launch": .bool(launch)]) { _, new in new } }
}
