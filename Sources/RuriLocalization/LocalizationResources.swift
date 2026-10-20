import Foundation

private final class ResourceBundleMarker {}

public enum LocalizationResources {
    public static let bundleName = "Ruri_RuriLocalization"
    public static let languages = SupportedLocalizations.languages

    public static let bundle: Bundle? = {
        if let executable = Bundle.main.executableURL,
           let installed = installedBundle(executable: executable, mainResources: Bundle.main.resourceURL) { return installed }
        let container = Bundle(for: ResourceBundleMarker.self)
        if let directory = container.resourceURL,
           let embedded = Bundle(url: directory.appendingPathComponent(bundleName + ".bundle")) { return embedded }
        // Test runners place resources outside the runner's own bundle. Only
        // tests may use the generated accessor's absolute build-path fallback.
        if container.bundleURL.pathExtension == "xctest" {
            return Bundle.module
        }
        return nil
    }()

    public static func installedBundle(executable: URL, mainResources: URL?, name: String = bundleName) -> Bundle? {
        let parent = executable.resolvingSymlinksInPath().deletingLastPathComponent()
        var candidates = [mainResources, parent].compactMap { $0 }
        if ["Helpers", "MacOS"].contains(parent.lastPathComponent), parent.deletingLastPathComponent().lastPathComponent == "Contents" {
            candidates.insert(parent.deletingLastPathComponent().appendingPathComponent("Resources"), at: 0)
        }
        return candidates.lazy.compactMap { Bundle(url: $0.appendingPathComponent(name + ".bundle")) }.first
    }
}
