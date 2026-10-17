import Foundation
import Security
import RuriLocalization

public struct ExperimentalSettings: Codable, Equatable, Sendable {
    public var vex: VexSettings?
    public init(vex: VexSettings? = nil) { self.vex = vex }
}

public struct VexSettings: Codable, Equatable, Sendable {
    public var enabled = false
    public var baseURL = ""
    public var project = ""
    public var knownZones: [String] = []
    public var instances: [String: UUID] = [:]
    public init() {}

    public static func load(paths: LauncherPaths) throws -> Self {
        try StateStore.load(paths).settings.experimental?.vex ?? Self()
    }
    @discardableResult public static func update(paths: LauncherPaths, _ action: (inout Self) throws -> Void) throws -> Self {
        let state = try StateStore.updateIfChanged(paths) { state in
            var settings = state.settings.experimental?.vex ?? Self()
            try action(&settings)
            if state.settings.experimental == nil { state.settings.experimental = ExperimentalSettings() }
            state.settings.experimental?.vex = settings
        }
        return state.settings.experimental!.vex!
    }
    public static func normalizedURL(_ value: String) throws -> URL {
        guard var parts = URLComponents(string: value), ["http", "https"].contains(parts.scheme),
              parts.host?.isEmpty == false, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil, parts.path.isEmpty || parts.path == "/" else {
            throw RuriError.message(Messages.Vex.invalidURL)
        }
        parts.path = ""
        guard let url = parts.url else { throw RuriError.message(Messages.Vex.invalidURL) }
        return url
    }
    public func client(project selection: String? = nil) throws -> VexClient {
        guard enabled else { throw RuriError.message(Messages.Vex.disabled) }
        let url = try Self.normalizedURL(baseURL)
        return try VexClient(baseURL: url, token: VexTokenStore.load(baseURL: url), project: selection ?? project)
    }
    public static func remember(zone: String, paths: LauncherPaths) throws {
        let zone = try ServerAddress(zone).host
        try update(paths: paths) { settings in
            settings.knownZones = Array(Set(settings.knownZones + [zone])).sorted()
        }
    }
}

public enum VexTokenStore {
    public static let service = "dev.ruri.launcher.vex.api"
    private static let cache = VexTokenCache()
    private static func query(_ url: URL) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: url.absoluteString]
    }
    public static func save(_ input: String, baseURL: URL) throws {
        let url = try VexSettings.normalizedURL(baseURL.absoluteString)
        let token = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, token.utf8.count <= 16384, token.unicodeScalars.allSatisfy({ (0x21...0x7e).contains($0.value) }) else {
            throw RuriError.message(Messages.Vex.invalidToken)
        }
        try cache.save(token, baseURL: url) {
            let value = [kSecValueData as String: Data(token.utf8)]
            let status = SecItemUpdate(query(url) as CFDictionary, value as CFDictionary)
            if status == errSecItemNotFound {
                var add = query(url).merging(value) { _, new in new }
                add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                let created = SecItemAdd(add as CFDictionary, nil)
                guard created == errSecSuccess else { throw failure(created) }
            } else if status != errSecSuccess { throw failure(status) }
        }
    }
    public static func load(baseURL: URL) throws -> String {
        let url = try VexSettings.normalizedURL(baseURL.absoluteString)
        return try cache.load(baseURL: url) {
            var request = query(url)
            request[kSecReturnData as String] = true
            request[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            let status = SecItemCopyMatching(request as CFDictionary, &result)
            if status == errSecItemNotFound { throw RuriError.message(Messages.Vex.tokenRequired) }
            guard status == errSecSuccess, let data = result as? Data, let token = String(data: data, encoding: .utf8) else { throw failure(status) }
            return token
        }
    }
    public static func invalidate(baseURL: URL) { cache.invalidate(baseURL: baseURL) }
    private static func failure(_ status: OSStatus) -> RuriError { .message(Messages.CoreAuthentication.keychainAccessFailed(String(status))) }
}

final class VexTokenCache: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [URL: Result<String, any Error>] = [:]
    func load(baseURL: URL, read: () throws -> String) throws -> String {
        try lock.withLock {
            if let value = values[baseURL] { return try value.get() }
            let value = Result(catching: read)
            values[baseURL] = value
            return try value.get()
        }
    }
    func save(_ value: String, baseURL: URL, write: () throws -> Void) throws {
        try lock.withLock { try write(); values[baseURL] = .success(value) }
    }
    func invalidate(baseURL: URL) { lock.withLock { _ = values.removeValue(forKey: baseURL) } }
}
