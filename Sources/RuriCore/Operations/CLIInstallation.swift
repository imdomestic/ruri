import RuriLocalization
import Foundation

public enum RuriInstallation {
    public static func application(executable: URL? = Bundle.main.executableURL) -> URL? {
        guard let executable else { return nil }
        var parent = executable.resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<6 {
            // CHORUS: 仅识别独立应用。
            if parent.pathExtension == "app", let bundle = Bundle(url: parent), bundle.bundleIdentifier == "dev.ruri.launcher.chorus" { return parent }
            parent.deleteLastPathComponent()
        }
        return nil
    }
    public static var info: [String: Any] { application().flatMap { Bundle(url: $0)?.infoDictionary } ?? Bundle.main.infoDictionary ?? [:] }
    public static var cliExecutable: URL? {
        if let app = application() { return app.appendingPathComponent("Contents/Helpers/ruri-cli") }
        return Bundle.main.executableURL?.resolvingSymlinksInPath().deletingLastPathComponent().appendingPathComponent("ruri-cli")
    }
    public static func resourceBundle(_ name: String) -> Bundle? {
        if let app = application(), let bundle = Bundle(url: app.appendingPathComponent("Contents/Resources/\(name).bundle")) { return bundle }
        guard let binary = Bundle.main.executableURL?.resolvingSymlinksInPath() else { return nil }
        return Bundle(url: binary.deletingLastPathComponent().appendingPathComponent("\(name).bundle"))
    }
}

public struct CLIInstallation: Sendable {
    public static let defaultBinDirectory = URL(fileURLWithPath: "/usr/local/bin", isDirectory: true)
    public let executable: URL
    public let binDirectory: URL
    private let homeDirectory: URL
    private let migrateLegacyLink: Bool
    // CHORUS: 保留原应用的命令与安装凭据。
    public var link: URL { binDirectory.appendingPathComponent("ruri-chorus") }
    private var receipt: URL { binDirectory.appendingPathComponent(".ruri-chorus-cli-install.json") }
    private var lockFile: URL { binDirectory.appendingPathComponent(".ruri-chorus-cli-install.lock") }
    public init(executable: URL? = RuriInstallation.cliExecutable, binDirectory: URL? = nil,
                homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) throws {
        guard let executable else { throw OperationFailure("CLI_UNAVAILABLE", Messages.CLIInterface.bundledCliNotFound.localized) }
        self.executable = executable.resolvingSymlinksInPath()
        self.binDirectory = (binDirectory ?? Self.defaultBinDirectory).standardizedFileURL
        self.homeDirectory = homeDirectory
        self.migrateLegacyLink = binDirectory == nil
    }
    private var destination: String? { try? FileManager.default.destinationOfSymbolicLink(atPath: link.path) }
    private var exists: Bool { FileManager.default.fileExists(atPath: link.path) || destination != nil }
    private var owned: Bool {
        guard let destination else { return false }
        if destination == executable.path { return true }
        guard let data = try? Data(contentsOf: receipt), let prior = try? JSONDecoder().decode(String.self, from: data) else { return false }
        return destination == prior
    }
    private var legacy: CLIInstallation? {
        guard migrateLegacyLink else { return nil }
        let prior = try? CLIInstallation(executable: executable, binDirectory: homeDirectory.appendingPathComponent(".local/bin"), homeDirectory: homeDirectory)
        return prior?.owned == true ? prior : nil
    }
    private var needsAuthorization: Bool {
        let fm = FileManager.default
        var parent = binDirectory
        while !fm.fileExists(atPath: parent.path), parent.path != "/" { parent.deleteLastPathComponent() }
        return !fm.isWritableFile(atPath: parent.path) || (fm.fileExists(atPath: lockFile.path) && !fm.isWritableFile(atPath: lockFile.path))
    }
    public func status(environment: [String: String] = ProcessInfo.processInfo.environment) -> OperationValue {
        let installed = owned && destination == executable.path && FileManager.default.isExecutableFile(atPath: executable.path)
        return .object(["executable": .string(executable.path), "link": .string(link.path), "target": .text(destination),
                 "installed": .bool(installed), "owned": .bool(owned), "legacyLink": .text(legacy?.link.path),
                 "requiresAuthorization": .bool(!installed && needsAuthorization),
                 "onPath": .bool((environment["PATH"] ?? "").split(separator: ":").contains { URL(fileURLWithPath: String($0)).standardizedFileURL == binDirectory })])
    }
    private func validateOwnership() throws {
        if exists && !owned { throw OperationFailure("PATH_CONFLICT", Messages.CLIInterface.cliLinkNotOwnedByRuri.localized, details: .object(["path": .string(link.path)])) }
    }
    private func requireWriteAccess() throws {
        guard !needsAuthorization else {
            throw OperationFailure("AUTHORIZATION_REQUIRED", Messages.CLISetup.authorizationRequired.localized, details: .object(["path": .string(link.path), "installationMethod": .string("appSettings")]))
        }
    }
    public func install(dryRun: Bool = false) throws -> OperationValue {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw OperationFailure("CLI_UNAVAILABLE", Messages.CLIInterface.cliExecutableNotFound.localized) }
        try validateOwnership()
        let needsLink = destination != executable.path, oldLink = legacy
        if dryRun { return .object(["dryRun": .bool(true), "changed": .bool(needsLink || oldLink != nil), "status": status()]) }
        var changed = false
        // A current installation needs no privileged write. In particular, a
        // normal user can query or repeat an administrator-owned installation.
        if needsLink {
            try requireWriteAccess()
            let lease = try OperationLease.acquire(directory: binDirectory, name: lockFile.lastPathComponent)
            defer { withExtendedLifetime(lease) {} }
            try validateOwnership()
            if destination != executable.path {
                let temporary = binDirectory.appendingPathComponent(".ruri-link-\(UUID())")
                defer { try? FileManager.default.removeItem(at: temporary) }
                try FileManager.default.createSymbolicLink(atPath: temporary.path, withDestinationPath: executable.path)
                guard rename(temporary.path, link.path) == 0 else { throw OperationFailure("IO_ERROR", Messages.CLIInterface.cliLinkInstallFailed.localized) }
                try JSONEncoder().encode(executable.path).write(to: receipt, options: .atomic)
                changed = true
            }
        }
        if let oldLink { _ = try oldLink.uninstall(); changed = true }
        return .object(["changed": .bool(changed), "status": status()])
    }
    public func uninstall(dryRun: Bool = false) throws -> OperationValue {
        try validateOwnership()
        let oldLink = legacy, wasInstalled = exists
        if dryRun { return .object(["changed": .bool(wasInstalled || oldLink != nil), "dryRun": .bool(true), "status": status()]) }
        if wasInstalled {
            try requireWriteAccess()
            let lease = try OperationLease.acquire(directory: binDirectory, name: lockFile.lastPathComponent)
            defer { withExtendedLifetime(lease) {} }
            guard owned else { throw OperationFailure("PATH_CONFLICT", Messages.CLIInterface.cliLinkChangedDuringUninstall.localized) }
            try FileManager.default.removeItem(at: link)
            if FileManager.default.fileExists(atPath: receipt.path) { try FileManager.default.removeItem(at: receipt) }
        }
        if let oldLink { _ = try oldLink.uninstall() }
        return .object(["changed": .bool(wasInstalled || oldLink != nil), "status": status()])
    }
    /// After the GUI's privileged worker exits, remove only this user's old
    /// Ruri-owned link. The administrator worker has a different home directory.
    public func removeLegacyLink() throws { if let legacy { _ = try legacy.uninstall() } }

    public enum Action: String, Sendable { case install, uninstall }
    public func authorizationCommand(_ action: Action) -> String {
        ([executable.path, "cli", action.rawValue, "--bin-dir", binDirectory.path, "--json", "--quiet", "--language", LocalizationContext.current.language] + (action == .uninstall ? ["--yes"] : []))
            .map(Self.shellQuote).joined(separator: " ")
    }
    public func authorizationScript(_ action: Action) -> String {
        let prompt = action == .install ? Messages.CLISetup.authorizeInstall.localized : Messages.CLISetup.authorizeUninstall.localized
        return """
        try
            return do shell script \(Self.appleScriptString(authorizationCommand(action) + " 2>&1 || true")) with administrator privileges with prompt \(Self.appleScriptString(prompt))
        on error number -128
            return "__RURI_AUTH_CANCELLED__"
        end try
        """
    }
    public static func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    public static func appleScriptString(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r").replacingOccurrences(of: "\n", with: "\\n") + "\""
    }
}
