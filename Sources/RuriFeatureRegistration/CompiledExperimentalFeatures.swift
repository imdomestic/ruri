import RuriCore
import RuriCommandKit
import RuriExtensionKit
#if RURI_VEX_ENABLED
import RuriVex
import RuriVexUI
import RuriVexCLI
#endif

@MainActor public enum CompiledExperimentalFeatures {
    public static func register() { _ = registration }
    private static let registration: Void = {
        #if RURI_VEX_ENABLED
        register(VexFeature.hooks, ui: VexUIProvider(), cli: VexCLIProvider())
        #endif
    }()
    private static func register(_ hooks: ExperimentalFeatureHooks, ui: any ExperimentalUIProvider, cli: any ExperimentalCommandProvider) {
        ExperimentalFeatures.register(hooks)
        ExperimentalUIRegistry.register(ui)
        ExperimentalCommandRegistry.register(cli)
    }
}
