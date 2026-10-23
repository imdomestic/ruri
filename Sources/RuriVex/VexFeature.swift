import Foundation
import RuriCore

/// Vex's registration with the host, which hands over Vex's context once.
public enum VexFeature {
    private final class Storage: @unchecked Sendable {
        let lock = NSLock()
        var context: ExperimentalExtensionContext?
    }
    private static let storage = Storage()
    /// The context of the registered extension; the build's registration sets it before any Vex code runs.
    public static var context: ExperimentalExtensionContext {
        // Reaching Vex code before CompiledExperimentalFeatures.register() is a programming error.
        guard let context = storage.lock.withLock({ storage.context }) else { preconditionFailure() }
        return context
    }
    public static func hooks(_ context: ExperimentalExtensionContext) -> ExperimentalFeatureHooks {
        storage.lock.withLock {
            precondition(storage.context == nil)
            storage.context = context
        }
        VexLocalization.register()
        return ExperimentalFeatureHooks(id: context.id, beforeLaunch: { paths, instance, settings in
            guard let settings = try settings.decode(VexSettings.self) else { return }
            try VexServerPolicy.cleanBeforeLaunch(paths: paths, instanceID: instance, settings: settings)
        }, hidesServer: { item, settings in
            guard let settings = try settings.decode(VexSettings.self) else { return false }
            return VexServerPolicy(settings: settings).hides(item)
        })
    }
}
