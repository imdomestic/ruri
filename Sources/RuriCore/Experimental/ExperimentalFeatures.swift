import Foundation

/// Every extension's settings, kept as opaque values under the extension's ID.
/// The host stores and returns them unchanged, including those of extensions
/// that are not compiled into this build.
public struct ExperimentalSettings: Codable, Equatable, Sendable {
    private var values: [String: OperationValue] = [:]
    public init() {}
    public init(from decoder: any Decoder) throws {
        values = try decoder.singleValueContainer().decode([String: OperationValue].self)
    }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(values)
    }
    func own(_ id: String) -> ExperimentalExtensionSettings { ExperimentalExtensionSettings(value: values[id]) }
    mutating func set<T: Encodable>(_ value: T, for id: String) throws {
        values[id] = try .encode(value)
    }
    /// Extensions are off until their own settings turn them on.
    public func enabled(_ id: String) -> Bool { values[id]?["enabled"].bool == true }
    /// Changes only the `enabled` field of an extension's value.
    mutating func setEnabled(_ enabled: Bool, for id: String) {
        var fields = values[id]?.object ?? [:]
        fields["enabled"] = .bool(enabled)
        values[id] = .object(fields)
    }
}

/// One extension's part of the settings.
public struct ExperimentalExtensionSettings: Sendable {
    let value: OperationValue?
    public var enabled: Bool { value?["enabled"].bool == true }
    public func decode<T: Decodable>(_ type: T.Type) throws -> T? { try value.map { try $0.decode(type) } }
}

/// What an extension receives from the host. Only the host creates contexts,
/// one per claimed ID, so an extension reaches its own settings and secure
/// storage and no other's.
public struct ExperimentalExtensionContext: Sendable {
    public let id: String
    fileprivate init(id: String) { self.id = id }
    public func configuration(_ paths: LauncherPaths) -> ExperimentalConfigurationStore { ExperimentalConfigurationStore(paths: paths, feature: id) }
    public func settings(_ all: ExperimentalSettings?) -> ExperimentalExtensionSettings { all?.own(id) ?? ExperimentalExtensionSettings(value: nil) }
    public var secureStorage: ExperimentalSecureStorage { ExperimentalSecureStorage(extension: id) }
}

/// Points in core operations where an enabled extension takes part.
public struct ExperimentalFeatureHooks: Sendable {
    public let id: String
    public let beforeLaunch: @Sendable (LauncherPaths, UUID, ExperimentalExtensionSettings) throws -> Void
    public let hidesServer: @Sendable (ServerLibraryItem, ExperimentalExtensionSettings) throws -> Bool
    public init(id: String,
                beforeLaunch: @escaping @Sendable (LauncherPaths, UUID, ExperimentalExtensionSettings) throws -> Void,
                hidesServer: @escaping @Sendable (ServerLibraryItem, ExperimentalExtensionSettings) throws -> Bool) {
        self.id = id; self.beforeLaunch = beforeLaunch; self.hidesServer = hidesServer
    }
}

public enum ExperimentalFeatures {
    private final class Storage: @unchecked Sendable {
        let lock = NSLock()
        var claimed: [String] = []
        var entries: [ExperimentalFeatureHooks] = []
    }
    private static let storage = Storage()

    /// Reserves an extension ID and returns its context. Each ID is claimed
    /// once per process, by the build's registration code.
    public static func claim(_ id: String) -> ExperimentalExtensionContext {
        precondition(id.wholeMatch(of: /[a-z][a-z0-9-]{0,31}/) != nil)
        storage.lock.withLock {
            precondition(!storage.claimed.contains(id))
            storage.claimed.append(id)
        }
        return ExperimentalExtensionContext(id: id)
    }
    public static func register(_ feature: ExperimentalFeatureHooks) {
        storage.lock.withLock {
            precondition(storage.claimed.contains(feature.id) && !storage.entries.contains { $0.id == feature.id })
            storage.entries.append(feature)
        }
    }
    /// IDs of the extensions compiled into this build, in registration order.
    public static var compiled: [String] { storage.lock.withLock { storage.claimed } }
    public static func enabled(_ id: String, paths: LauncherPaths) throws -> Bool {
        try StateStore.load(paths).settings.experimental?.enabled(id) ?? false
    }
    /// Turns a compiled extension on or off, keeping the rest of its settings.
    public static func setEnabled(_ id: String, _ enabled: Bool, paths: LauncherPaths) throws {
        precondition(compiled.contains(id))
        try StateStore.updateIfChanged(paths) { state in
            var settings = state.settings.experimental ?? ExperimentalSettings()
            settings.setEnabled(enabled, for: id)
            state.settings.experimental = settings
        }
    }
    public static func beforeLaunch(paths: LauncherPaths, instanceID: UUID, settings: ExperimentalSettings?) throws {
        guard let settings else { return }
        let features = storage.lock.withLock { storage.entries }
        for feature in features where settings.enabled(feature.id) {
            try feature.beforeLaunch(paths, instanceID, settings.own(feature.id))
        }
    }
    public static func visibleServers(_ servers: [ServerLibraryItem], settings: ExperimentalSettings?) throws -> [ServerLibraryItem] {
        guard let settings else { return servers }
        let features = storage.lock.withLock { storage.entries }.filter { settings.enabled($0.id) }
        return try servers.filter { server in
            for feature in features where try feature.hidesServer(server, settings.own(feature.id)) { return false }
            return true
        }
    }
}
