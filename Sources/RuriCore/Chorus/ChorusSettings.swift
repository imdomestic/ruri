import Foundation
import Security
import RuriLocalization

public struct ChorusSettings: Codable, Sendable {
    public static let defaultBaseURL = "http://encore.inner.imdomestic.com:8790"
    public var baseURL = defaultBaseURL
    public var instances: [String: UUID] = [:]
    public var knownZones: [String] = [ChorusServerPolicy.legacyZone]
    public init() {}
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        baseURL = try values.decode(String.self, forKey: .baseURL)
        instances = try values.decode([String: UUID].self, forKey: .instances)
        knownZones = try values.decodeIfPresent([String].self, forKey: .knownZones) ?? [ChorusServerPolicy.legacyZone]
    }
    @discardableResult public static func remember(zone: String, paths: LauncherPaths) throws -> Self {
        let normalized = try ServerAddress(zone).host
        let settings = try load(paths: paths)
        if settings.knownZones.contains(normalized) { return settings }
        return try update(paths: paths) { settings in
            settings.knownZones = Array(Set(settings.knownZones + [normalized, ChorusServerPolicy.legacyZone])).sorted()
        }
    }
    public static func load(paths: LauncherPaths) throws -> Self {
        let file = paths.root.appendingPathComponent("chorus.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return Self() }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: file))
    }
    @discardableResult public static func update(paths: LauncherPaths, _ action: (inout Self) throws -> Void) throws -> Self {
        try paths.prepare()
        let lease = try OperationLease.acquire(directory: paths.root, name: ".chorus-settings.lock")
        defer { withExtendedLifetime(lease) {} }
        var current = try load(paths: paths)
        try action(&current)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(current).write(to: paths.root.appendingPathComponent("chorus.json"), options: .atomic)
        return current
    }
    @discardableResult public static func configure(paths: LauncherPaths, baseURL: String, token: String? = nil) throws -> Self {
        let url = try normalizedURL(baseURL)
        return try update(paths: paths) { settings in
            if let token {
                try ChorusTokenStore.save(token, baseURL: url)
            } else {
                ChorusTokenStore.invalidate(baseURL: url)
            }
            settings.baseURL = url.absoluteString
        }
    }
    public static func normalizedURL(_ value: String) throws -> URL {
        guard var parts = URLComponents(string: value), ["http", "https"].contains(parts.scheme),
              parts.host?.isEmpty == false, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil, parts.path.isEmpty || parts.path == "/" else {
            throw RuriError.message(Messages.Chorus.invalidURL)
        }
        parts.path = ""
        guard let url = parts.url else { throw RuriError.message(Messages.Chorus.invalidURL) }
        return url
    }
    public func client() throws -> ChorusClient {
        let url = try Self.normalizedURL(baseURL)
        return try ChorusClient(baseURL: url, token: ChorusTokenStore.load(baseURL: url))
    }
}

final class ChorusTokenCache: @unchecked Sendable {
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
        try lock.withLock {
            try write()
            values[baseURL] = .success(value)
        }
    }

    func invalidate(baseURL: URL) {
        lock.withLock { _ = values.removeValue(forKey: baseURL) }
    }
}

public enum ChorusTokenStore {
    public static let service = "dev.ruri.launcher.chorus.api"
    private static let cache = ChorusTokenCache()
    private static func query(_ url: URL) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: url.absoluteString]
    }
    public static func save(_ input: String, baseURL: URL) throws {
        let url = try ChorusSettings.normalizedURL(baseURL.absoluteString)
        let token = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, token.utf8.count <= 16384, token.unicodeScalars.allSatisfy({ (0x21...0x7e).contains($0.value) }) else {
            throw RuriError.message(Messages.Chorus.invalidToken)
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
        let url = try ChorusSettings.normalizedURL(baseURL.absoluteString)
        return try cache.load(baseURL: url) { try read(baseURL: url) }
    }
    static func invalidate(baseURL: URL) { cache.invalidate(baseURL: baseURL) }
    private static func read(baseURL: URL) throws -> String {
        var request = query(baseURL)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { throw RuriError.message(Messages.Chorus.tokenRequired) }
        guard status == errSecSuccess, let data = result as? Data, let token = String(data: data, encoding: .utf8) else { throw failure(status) }
        return token
    }
    private static func failure(_ status: OSStatus) -> RuriError { .message(Messages.CoreAuthentication.keychainAccessFailed(String(status))) }
}
