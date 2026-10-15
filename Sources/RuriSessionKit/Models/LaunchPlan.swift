import RuriLocalization
import Foundation

public struct LaunchPlan: Codable, Sendable {
    package init(executable: URL, arguments: [String], directory: URL, environment: [String: String], nativeQuitSupported: Bool? = nil, memory: LaunchMemory? = nil, tuning: JVMTuning? = nil, customEnvironmentNames: [String]? = nil, commands: LaunchCommands? = nil, wrapper: [String]? = nil, offlineSkin: OfflineSkinLaunch? = nil, debugLogging: Bool? = nil, host: GameHostPlan? = nil, quickPlayLog: URL? = nil, destination: LaunchDestination? = nil) {
        self.executable = executable
        self.arguments = arguments
        self.directory = directory
        self.environment = environment
        self.nativeQuitSupported = nativeQuitSupported
        self.memory = memory
        self.tuning = tuning
        self.customEnvironmentNames = customEnvironmentNames
        self.commands = commands
        self.wrapper = wrapper
        self.offlineSkin = offlineSkin
        self.debugLogging = debugLogging
        self.host = host
        self.quickPlayLog = quickPlayLog
        self.destination = destination
    }

    public let executable: URL
    public var arguments: [String]
    public let directory: URL
    public let environment: [String: String]
    public var nativeQuitSupported: Bool?
    public var memory: LaunchMemory?
    public var tuning: JVMTuning? = nil
    public var customEnvironmentNames: [String]?
    public var commands: LaunchCommands?
    public var wrapper: [String]?
    public var offlineSkin: OfflineSkinLaunch? = nil
    public var debugLogging: Bool? = nil
    public var host: GameHostPlan? = nil
    public var quickPlayLog: URL? = nil
    public var destination: LaunchDestination? = nil
    public var chorusServerCleanup: ChorusServerCleanupPlan? = nil
    package var processExecutable: URL { wrapper?.first.map { URL(fileURLWithPath: $0) } ?? executable }
    package var processArguments: [String] { wrapper?.isEmpty == false ? Array(wrapper!.dropFirst()) + [executable.path] + arguments : arguments }
    public var environmentRedactions: [String] { (customEnvironmentNames ?? []).compactMap { environment[$0] }.filter { $0.count > 3 } }
    public var redactedCommand: String {
        var redactNext = false
        return ([processExecutable.path] + processArguments).map { value in
            if redactNext { redactNext = false; return "<redacted>" }
            if ["--accessToken", "--clientId", "--xuid", "--session", "--userProperties"].contains(value) { redactNext = true }
            if value.hasPrefix("-Dauthlibinjector.yggdrasil.prefetched=") { return "-Dauthlibinjector.yggdrasil.prefetched=<metadata>" }
            return value.contains(" ") ? "\"\(value)\"" : value
        }.joined(separator: " ")
    }
}
