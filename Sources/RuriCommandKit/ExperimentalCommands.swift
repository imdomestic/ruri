import ArgumentParser
import Foundation
import RuriCore

package protocol ExperimentalCommandProvider: Sendable {
    var id: String { get }
    var command: any ParsableCommand.Type { get }
    var commands: [CommandSpec] { get }
    func enabled(paths: LauncherPaths) throws -> Bool
    func disabledError() -> any Error
    @MainActor func execute(_ request: CommandRequest, output: CommandOutput) async throws -> Value?
    func configure(_ request: CommandRequest, paths: LauncherPaths) throws -> Value?
    func schema(_ command: CommandSpec) -> Value
}

package enum ExperimentalCommandRegistry {
    private final class Storage: @unchecked Sendable {
        let lock = NSLock()
        var providers: [any ExperimentalCommandProvider] = []
    }
    private static let storage = Storage()
    @TaskLocal private static var availability: [String: Result<Bool, any Error>] = [:]
    package static func register(_ provider: any ExperimentalCommandProvider) {
        storage.lock.withLock {
            precondition(!storage.providers.contains { $0.id == provider.id })
            storage.providers.append(provider)
        }
    }
    private static var providers: [any ExperimentalCommandProvider] { storage.lock.withLock { storage.providers } }
    private static var active: [any ExperimentalCommandProvider] {
        providers.filter { provider in if case .success(true) = availability[provider.id] { true } else { false } }
    }
    package static var root: any ParsableCommand.Type { active.isEmpty ? RuriCommand.self : ExtendedRoot.self }
    package static var commands: [CommandSpec] { CommandRegistry.commands + active.flatMap(\.commands) }
    @MainActor package static func withSettings(arguments: [String], operation: () async -> Int32) async -> Int32 {
        var directory = ProcessInfo.processInfo.environment["RURI_DATA_DIR"]
        for (index, argument) in arguments.enumerated() {
            if argument.hasPrefix("--data-dir=") { directory = String(argument.dropFirst(11)) }
            else if argument == "--data-dir", arguments.indices.contains(index + 1) { directory = arguments[index + 1] }
        }
        let paths = LauncherPaths(root: directory.map { URL(fileURLWithPath: $0) })
        let values = Dictionary(uniqueKeysWithValues: providers.map { provider in (provider.id, Result { try provider.enabled(paths: paths) }) })
        return await $availability.withValue(values, operation: operation)
    }
    package static func requireEnabled(_ namespace: String?) throws {
        guard let provider = providers.first(where: { $0.command.configuration.commandName == namespace }) else { return }
        guard try availability[provider.id]?.get() == true else { throw provider.disabledError() }
    }
    @MainActor package static func execute(_ request: CommandRequest, output: CommandOutput) async throws -> Value? {
        guard let provider = active.first(where: { $0.command.configuration.commandName == request.spec.path.first }) else { return nil }
        return try await provider.execute(request, output: output)
    }
    package static func configure(_ request: CommandRequest, paths: LauncherPaths) throws -> Value? {
        for provider in providers { if let result = try provider.configure(request, paths: paths) { return result } }
        return nil
    }
    package static func schema(_ command: CommandSpec) -> Value? {
        active.first { $0.command.configuration.commandName == command.path.first }?.schema(command)
    }
    private struct ExtendedRoot: ParsableCommand {
        static var configuration: CommandConfiguration {
            var configuration = RuriCommand.configuration
            configuration.subcommands += active.map(\.command)
            return configuration
        }
    }
}
