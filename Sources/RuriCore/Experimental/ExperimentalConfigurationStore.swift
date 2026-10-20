import Foundation

public struct ExperimentalConfigurationStore: Sendable {
    public let paths: LauncherPaths
    public let feature: String
    public init(paths: LauncherPaths, feature: String) {
        precondition(!feature.isEmpty)
        self.paths = paths
        self.feature = feature
    }
    public func load<Value: Decodable>(as type: Value.Type) throws -> Value? {
        try StateStore.load(paths).settings.experimental?.value(feature, as: type)
    }
    @discardableResult public func update<Value: Codable>(default value: Value, _ action: (inout Value) throws -> Void) throws -> Value {
        let state = try StateStore.updateIfChanged(paths) { state in
            var current = try state.settings.experimental?.value(feature, as: Value.self) ?? value
            try action(&current)
            if state.settings.experimental == nil { state.settings.experimental = ExperimentalSettings() }
            try state.settings.experimental?.set(current, for: feature)
        }
        return try state.settings.experimental!.value(feature, as: Value.self)!
    }
}
