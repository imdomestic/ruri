import Foundation
import RuriCommandKit
import RuriLocalization
import RuriFeatureRegistration

@main struct CLI {
    @MainActor static func main() async {
        CompiledExperimentalFeatures.register()
        if let status = LocalizationCommandLine.resourceCheck() { exit(status) }
        signal(SIGINT, SIG_IGN); signal(SIGTERM, SIG_IGN)
        let task = Task { await CLIApplication.run(Array(CommandLine.arguments.dropFirst())) }
        let interrupts = [SIGINT, SIGTERM].map { number in
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { task.cancel() }; source.resume(); return source
        }
        let status = await task.value
        withExtendedLifetime(interrupts) { exit(status) }
    }
}
