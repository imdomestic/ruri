import Foundation

public struct AppSettings: Codable, Equatable, Sendable {
    public var concurrentDownloads = 8
    public var microsoftClientID = ""
    public var effectiveMicrosoftClientID: String {
        BuildConfiguration().microsoftClientID(override: microsoftClientID)
    }
    public var showSnapshots = false
    public var defaultMemorySettings: MemorySettings?
    public var appearance = "system"
    public var downloadSource: DownloadSource?
    public var isolationPolicy: GameIsolationPolicy?
    public var defaultJava: JavaSelection?
    public var javaLocations: [JavaLocation]?
    public var defaultJVMTuning: JVMTuningMode?
    public var defaultJVMArguments: String?
    public var defaultGameArguments: String?
    public var defaultWindow: GameWindowSize?
    public var defaultLaunchPresentation: LaunchPresentation?
    public var defaultEnvironment: String?
    public var defaultLaunchCommands: LaunchCommands?
    public var defaultMacOSGameSettings: MacOSGameSettings?
    public var experimental: ExperimentalSettings?
    public init() {}
}
