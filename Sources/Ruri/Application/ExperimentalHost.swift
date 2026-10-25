import RuriCore
import RuriExtensionKit

extension AppModel {
    func makeExperimentalHost() -> ExperimentalHost {
        ExperimentalHost(paths: { [unowned self] in self.paths }, configuration: { [unowned self] in self.state.settings.experimental },
                         accountAvailable: { [unowned self] in self.activeAccount != nil }, readOnly: { [unowned self] in self.readOnly }, busy: { [unowned self] in self.busy },
                         reload: { [unowned self] in self.acceptState(try StateStore.load(self.paths)) },
                         openAccount: { [unowned self] in self.showAccount = true }, error: { [unowned self] in self.error = $0 })
    }
}
