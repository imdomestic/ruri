import Foundation
import RuriLocalization

private final class ResourceBundleMarker {}

public enum VexLocalization {
    public static func register() { _ = registration }
    private static let registration: Void = {
        let bundle: Bundle?
        if let executable = Bundle.main.executableURL,
           let installed = LocalizationResources.installedBundle(executable: executable, mainResources: Bundle.main.resourceURL, name: "Ruri_RuriVex") {
            bundle = installed
        } else if Bundle(for: ResourceBundleMarker.self).bundleURL.pathExtension == "xctest" {
            bundle = Bundle.module
        } else { bundle = nil }
        LocalizationCatalogRegistry.register(table: "Vex", definitions: Messages.Vex.definitions, bundle: bundle)
        LocalizationCatalogRegistry.register(table: "VexDevices", definitions: Messages.VexDevices.definitions, bundle: bundle)
        LocalizationCatalogRegistry.register(table: "VexLogin", definitions: Messages.VexLogin.definitions, bundle: bundle)
        LocalizationCatalogRegistry.register(table: "VexRooms", definitions: Messages.VexRooms.definitions, bundle: bundle)
        LocalizationCatalogRegistry.register(table: "VexNetwork", definitions: Messages.VexNetwork.definitions, bundle: bundle)
    }()
}
