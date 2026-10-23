import RuriCore
import RuriCommandKit
import RuriExtensionKit
#if RURI_VEX_ENABLED
import RuriVex
import RuriVexUI
import RuriVexCLI
#endif

/// Registers the extensions compiled into this build. Each extension is listed
/// here behind its own build condition; without any, the application and the
/// command line behave exactly as they do without extension support.
@MainActor public enum CompiledExperimentalFeatures {
    public static func register() { _ = registration }
    private static let registration: Void = {
        #if RURI_VEX_ENABLED
        install("vex") { context in
            (VexFeature.hooks(context), VexUIProvider(context: context), VexCLIProvider(context: context))
        }
        #endif
    }()

    /// Claims the extension's ID and registers what it contributes.
    package static func install(_ id: String, _ make: (ExperimentalExtensionContext) -> (hooks: ExperimentalFeatureHooks, ui: any ExperimentalUIProvider, cli: any ExperimentalCommandProvider)) {
        let context = ExperimentalFeatures.claim(id)
        let parts = make(context)
        ExperimentalFeatures.register(parts.hooks)
        ExperimentalUIRegistry.register(parts.ui)
        ExperimentalCommandRegistry.register(parts.cli)
    }
}
