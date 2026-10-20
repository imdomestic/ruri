import Foundation
import Observation
#if canImport(Sparkle)
import Sparkle

/// Sparkle updates from the per-architecture appcast that the Appcast workflow
/// publishes to GitHub Pages. Items from GitHub pre-releases carry the
/// `prerelease` channel and are offered only after opting in.
@MainActor @Observable final class SoftwareUpdater: NSObject, SPUUpdaterDelegate {
    private static let prereleaseChannel = "prerelease"
    private static let prereleasePreferenceKey = "RuriReceivePrereleaseUpdates"
    #if arch(arm64)
    private static let feedName = "appcast-arm64.xml"
    #else
    private static let feedName = "appcast-x86_64.xml"
    #endif
    private static let feed = (Bundle.main.object(forInfoDictionaryKey: "RuriAppcastBaseURL") as? String)
        .flatMap(URL.init(string:))?.appendingPathComponent(feedName).absoluteString

    /// Builds run outside a packaged bundle, and ad hoc signed packages, have
    /// no update key or feed: Sparkle would report a startup error for them,
    /// and contributor builds must not replace themselves with official releases.
    let isAvailable = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") != nil && SoftwareUpdater.feed != nil
    private(set) var canCheckForUpdates = false
    private(set) var lastUpdateCheckDate: Date?
    var automaticallyChecksForUpdates = false {
        didSet { controller.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates }
    }
    var automaticallyDownloadsUpdates = false {
        didSet { controller.updater.automaticallyDownloadsUpdates = automaticallyDownloadsUpdates }
    }
    var receivesPrereleases = UserDefaults.standard.bool(forKey: SoftwareUpdater.prereleasePreferenceKey) {
        didSet { UserDefaults.standard.set(receivesPrereleases, forKey: Self.prereleasePreferenceKey) }
    }
    @ObservationIgnored private var controller: SPUStandardUpdaterController!
    @ObservationIgnored private var observation: NSKeyValueObservation?

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        guard isAvailable else { return }
        controller.startUpdater()
        let updater = controller.updater
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
        lastUpdateCheckDate = updater.lastUpdateCheckDate
        observation = updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            MainActor.assumeIsolated { self?.canCheckForUpdates = updater.canCheckForUpdates }
        }
    }

    func checkForUpdates() { controller.checkForUpdates(nil) }

    func feedURLString(for updater: SPUUpdater) -> String? { Self.feed }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        receivesPrereleases ? [Self.prereleaseChannel] : []
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        lastUpdateCheckDate = updater.lastUpdateCheckDate
    }
}
#else
@MainActor @Observable final class SoftwareUpdater {
    let isAvailable = false
    let canCheckForUpdates = false
    let lastUpdateCheckDate: Date? = nil
    var automaticallyChecksForUpdates = false
    var automaticallyDownloadsUpdates = false
    var receivesPrereleases = false
    func checkForUpdates() {}
}
#endif
