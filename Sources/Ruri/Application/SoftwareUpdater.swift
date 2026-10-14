import Foundation
import Observation

// CHORUS: 独立应用通过本地构建交付。
@MainActor @Observable final class SoftwareUpdater {
    let isAvailable = false
    let canCheckForUpdates = false
    let lastUpdateCheckDate: Date? = nil
    var automaticallyChecksForUpdates = false
    var automaticallyDownloadsUpdates = false
    var receivesPrereleases = false
    func checkForUpdates() {}
}
