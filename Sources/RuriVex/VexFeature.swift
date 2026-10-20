import RuriCore

public enum VexFeature {
    public static var hooks: ExperimentalFeatureHooks {
        VexLocalization.register()
        return ExperimentalFeatureHooks(id: "vex", beforeLaunch: { paths, instance, configuration in
            guard let settings = try configuration.value("vex", as: VexSettings.self) else { return }
            try VexServerPolicy.cleanBeforeLaunch(paths: paths, instanceID: instance, settings: settings)
        }, hidesServer: { item, configuration in
            guard let settings = try configuration.value("vex", as: VexSettings.self) else { return false }
            return VexServerPolicy(settings: settings).hides(item)
        })
    }
}
