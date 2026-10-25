import Foundation

/// Reads and writes one extension's opaque settings in the launcher state.
/// Obtained from the extension's context; other extensions' values stay as they are.
public struct ExperimentalConfigurationStore: Sendable {
    public let paths: LauncherPaths
    public let feature: String
    init(paths: LauncherPaths, feature: String) {
        self.paths = paths
        self.feature = feature
    }
    public func load<Value: Decodable>(as type: Value.Type) throws -> Value? {
        try StateStore.load(paths).settings.experimental?.own(feature).decode(type)
    }
    @discardableResult public func update<Value: Codable>(default value: Value, _ action: (inout Value) throws -> Void) throws -> Value {
        let state = try StateStore.updateIfChanged(paths) { state in
            var current = try state.settings.experimental?.own(feature).decode(Value.self) ?? value
            try action(&current)
            if state.settings.experimental == nil { state.settings.experimental = ExperimentalSettings() }
            try state.settings.experimental?.set(current, for: feature)
        }
        return try state.settings.experimental!.own(feature).decode(Value.self)!
    }
}
