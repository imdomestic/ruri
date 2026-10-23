import ArgumentParser
import RuriCore
import RuriCommandKit
import RuriLocalization
import RuriVex

public struct VexCLIProvider: ExperimentalCommandProvider {
    private let context: ExperimentalExtensionContext
    public init(context: ExperimentalExtensionContext) { self.context = context; VexCLILocalization.register() }
    package var id: String { context.id }
    package var command: any ParsableCommand.Type { VexGroup.self }
    package var commands: [CommandSpec] { VexGroup.specs }
    package var section: String { Messages.Vex.experimental.localized }
    package func enabled(paths: LauncherPaths) throws -> Bool {
        try context.configuration(paths).load(as: VexSettings.self)?.enabled ?? false
    }
    package func disabledError() -> any Error { RuriError.message(Messages.Vex.disabled) }
    @MainActor package func execute(_ request: CommandRequest, output: CommandOutput) async throws -> Value {
        try await VexCLI.execute(request, output: output)
    }
    package func schema(_ command: CommandSpec) -> Value { VexSchemas.payload(command) }
    package func sideEffects(_ command: CommandSpec) -> [String] { VexSchemas.sideEffects(command) }
    package func presenter(_ path: [String]) -> ExperimentalTextPresenter? { VexPresenters.presenter(path) }
}
