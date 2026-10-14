import Foundation
import Security
import RuriLocalization

public struct ChorusSettings: Codable, Sendable {
    public static let defaultBaseURL = "http://encore.inner.imdomestic.com:8790"
    public var baseURL = defaultBaseURL
    public var instances: [String: UUID] = [:]
    public init() {}
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

public enum ChorusTokenStore {
    public static let service = "dev.ruri.launcher.chorus.api"
    private static func query(_ url: URL) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: url.absoluteString]
    }
    public static func save(_ input: String, baseURL: URL) throws {
        let token = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, token.utf8.count <= 16384, token.unicodeScalars.allSatisfy({ (0x21...0x7e).contains($0.value) }) else {
            throw RuriError.message(Messages.Chorus.invalidToken)
        }
        let value = [kSecValueData as String: Data(token.utf8)]
        let status = SecItemUpdate(query(baseURL) as CFDictionary, value as CFDictionary)
        if status == errSecItemNotFound {
            var add = query(baseURL).merging(value) { _, new in new }
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let created = SecItemAdd(add as CFDictionary, nil)
            guard created == errSecSuccess else { throw failure(created) }
        } else if status != errSecSuccess { throw failure(status) }
    }
    public static func load(baseURL: URL) throws -> String {
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
