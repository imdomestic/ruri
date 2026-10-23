import Foundation
import RuriLocalization

private final class ResourceBundleMarker {}

enum VexCLILocalization {
    static func register() { _ = registration }
    private static let registration: Void = {
        let bundle: Bundle?
        if let executable = Bundle.main.executableURL,
           let installed = LocalizationResources.installedBundle(executable: executable, mainResources: Bundle.main.resourceURL, name: "Ruri_RuriVexCLI") {
            bundle = installed
        } else if Bundle(for: ResourceBundleMarker.self).bundleURL.pathExtension == "xctest" {
            bundle = Bundle.module
        } else { bundle = nil }
        LocalizationCatalogRegistry.register(table: "VexCLI", definitions: Messages.VexCLI.definitions, bundle: bundle)
    }()
}
