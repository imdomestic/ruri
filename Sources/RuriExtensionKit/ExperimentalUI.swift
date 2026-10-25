import Foundation
import SwiftUI
import Observation
import RuriCore

/// What the application offers an extension's views: launcher paths, the
/// extension's own settings, account state, launches and sessions, and the
/// application's error and account presentation.
@MainActor @Observable public final class ExperimentalHost {
    private let readPaths: () -> LauncherPaths
    private let readConfiguration: () -> ExperimentalSettings?
    private let readAccountAvailable: () -> Bool
    private let readOnlyValue: () -> Bool
    private let readBusy: () -> Bool
    private let reloadState: () throws -> Void
    private let presentAccount: () -> Void
    private let presentError: (String) -> Void
    public var paths: LauncherPaths { readPaths() }
    public var accountAvailable: Bool { readAccountAvailable() }
    public var readOnly: Bool { readOnlyValue() }
    public var busy: Bool { readBusy() }
    public init(paths: @escaping () -> LauncherPaths, configuration: @escaping () -> ExperimentalSettings?,
                accountAvailable: @escaping () -> Bool, readOnly: @escaping () -> Bool, busy: @escaping () -> Bool,
                reload: @escaping () throws -> Void, openAccount: @escaping () -> Void, error: @escaping (String) -> Void) {
        readPaths = paths; readConfiguration = configuration; readAccountAvailable = accountAvailable
        readOnlyValue = readOnly; readBusy = busy; reloadState = reload; presentAccount = openAccount; presentError = error
    }
    /// The extension's own settings as the application currently holds them.
    public func settings(_ context: ExperimentalExtensionContext) -> ExperimentalExtensionSettings { context.settings(readConfiguration()) }
    public func reload() throws { try reloadState() }
    public func openAccount() { presentAccount() }
    public func report(_ message: String) { presentError(message) }
    public func beginLaunch(instanceID: UUID, address: ServerAddress) -> ExperimentalLaunchOperation {
        ExperimentalLaunchCapabilities(paths: paths).begin(instanceID: instanceID, address: address)
    }
    public func cancelLaunch(_ operation: ExperimentalLaunchOperation) { operation.cancel() }
    public func start(instanceID: UUID, address: ServerAddress) async throws -> GameSession {
        try await ExperimentalLaunchCapabilities(paths: paths).start(instanceID: instanceID, address: address)
    }
    public func session(instanceID: UUID, sessionID: UUID) throws -> GameSession {
        try ExperimentalLaunchCapabilities(paths: paths).session(instanceID: instanceID, sessionID: sessionID)
    }
    public func sessions(instanceID: UUID) throws -> [GameSession] {
        try ExperimentalLaunchCapabilities(paths: paths).sessions(instanceID: instanceID)
    }
}

/// A sidebar entry contributed by an extension, shown in its own section
/// between the main pages and the records.
public struct ExperimentalPage: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let symbol: String
    public init(id: String, title: String, symbol: String) { self.id = id; self.title = title; self.symbol = symbol }
}

/// The views an extension adds to the application. A disabled extension
/// returns no pages and empty views.
@MainActor public protocol ExperimentalUIProvider: AnyObject {
    var id: String { get }
    func pages(host: ExperimentalHost) -> [ExperimentalPage]
    func page(_ id: String, host: ExperimentalHost) -> AnyView
    /// A section of the settings page, after the command line section.
    func settings(host: ExperimentalHost) -> AnyView
    /// Rows above the server list.
    func servers(host: ExperimentalHost) -> AnyView
    /// Runs when the application starts and whenever extension settings change.
    func configure(host: ExperimentalHost) async
    /// A view to present in a sheet for a URL the application was asked to open, or nil.
    func open(_ url: URL, host: ExperimentalHost) throws -> AnyView?
    /// Stops background work before the application quits.
    func stop()
}

@MainActor public enum ExperimentalUIRegistry {
    public private(set) static var providers: [any ExperimentalUIProvider] = []
    public static func register(_ provider: any ExperimentalUIProvider) {
        precondition(ExperimentalFeatures.compiled.contains(provider.id) && !providers.contains { $0.id == provider.id })
        providers.append(provider)
    }
    public static func pages(host: ExperimentalHost) -> [ExperimentalPage] { providers.flatMap { $0.pages(host: host) } }
    public static func page(_ id: String, host: ExperimentalHost) -> AnyView? {
        providers.first { $0.pages(host: host).contains { $0.id == id } }?.page(id, host: host)
    }
    public static func configure(host: ExperimentalHost) async {
        for provider in providers { await provider.configure(host: host) }
    }
    public static func open(_ url: URL, host: ExperimentalHost) throws -> AnyView? {
        for provider in providers { if let view = try provider.open(url, host: host) { return view } }
        return nil
    }
    public static func stop() { for provider in providers { provider.stop() } }
}
