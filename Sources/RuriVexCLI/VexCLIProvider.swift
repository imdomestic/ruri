import ArgumentParser
import RuriCore
import RuriCommandKit
import RuriLocalization
import RuriVex

public struct VexCLIProvider: ExperimentalCommandProvider {
    public init() {}
    package var id: String { "vex" }
    package var command: any ParsableCommand.Type { VexGroup.self }
    package var commands: [CommandSpec] { VexGroup.specs }
    package func enabled(paths: LauncherPaths) throws -> Bool { try VexSettings.load(paths: paths).enabled }
    package func disabledError() -> any Error { RuriError.message(Messages.Vex.disabled) }
    @MainActor package func execute(_ request: CommandRequest, output: CommandOutput) async throws -> Value? {
        try await VexCLI.manageVex(request, output: output)
    }
    package func configure(_ request: CommandRequest, paths: LauncherPaths) throws -> Value? { try VexCLI.configure(request, paths: paths) }
    package func schema(_ command: CommandSpec) -> Value { VexSchemas.payload(command.path.last!) }
}
