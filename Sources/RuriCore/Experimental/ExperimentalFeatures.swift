import Foundation

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
    public func value<T: Decodable>(_ id: String, as type: T.Type) throws -> T? {
        try values[id].map { try $0.decode(type) }
    }
    public mutating func set<T: Encodable>(_ value: T, for id: String) throws {
        values[id] = try .encode(value)
    }
    public func enabled(_ id: String) -> Bool { values[id]?["enabled"].bool == true }
}

public struct ExperimentalFeatureHooks: Sendable {
    public let id: String
    public let beforeLaunch: @Sendable (LauncherPaths, UUID, ExperimentalSettings) throws -> Void
    public let hidesServer: @Sendable (ServerLibraryItem, ExperimentalSettings) throws -> Bool
    public init(id: String,
                beforeLaunch: @escaping @Sendable (LauncherPaths, UUID, ExperimentalSettings) throws -> Void,
                hidesServer: @escaping @Sendable (ServerLibraryItem, ExperimentalSettings) throws -> Bool) {
        self.id = id; self.beforeLaunch = beforeLaunch; self.hidesServer = hidesServer
    }
}

public enum ExperimentalFeatures {
    private final class Storage: @unchecked Sendable {
        let lock = NSLock()
        var entries: [ExperimentalFeatureHooks] = []
    }
    private static let storage = Storage()
    public static func register(_ feature: ExperimentalFeatureHooks) {
        storage.lock.withLock {
            precondition(!storage.entries.contains { $0.id == feature.id })
            storage.entries.append(feature)
        }
    }
    public static func beforeLaunch(paths: LauncherPaths, instanceID: UUID, settings: ExperimentalSettings?) throws {
        guard let settings else { return }
        let features = storage.lock.withLock { storage.entries }
        for feature in features where settings.enabled(feature.id) {
            try feature.beforeLaunch(paths, instanceID, settings)
        }
    }
    public static func visibleServers(_ servers: [ServerLibraryItem], settings: ExperimentalSettings?) throws -> [ServerLibraryItem] {
        guard let settings else { return servers }
        let features = storage.lock.withLock { storage.entries }.filter { settings.enabled($0.id) }
        return try servers.filter { server in
            for feature in features where try feature.hidesServer(server, settings) { return false }
            return true
        }
    }
}
