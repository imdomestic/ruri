import Foundation
import RuriCore
import Security
import RuriLocalization

public struct VexSettings: Codable, Equatable, Sendable {
    public var enabled = false
    public var servers: [VexServer] = []
    public var defaultServer: String?
    public var knownZones: [String] = []
    public var instances: [String: UUID] = [:]
    public init() {}
    private enum CodingKeys: String, CodingKey { case enabled, servers, defaultServer, knownZones, instances }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        servers = try values.decodeIfPresent([VexServer].self, forKey: .servers) ?? []
        defaultServer = try values.decodeIfPresent(String.self, forKey: .defaultServer)
        knownZones = try values.decodeIfPresent([String].self, forKey: .knownZones) ?? []
        instances = try values.decodeIfPresent([String: UUID].self, forKey: .instances) ?? [:]
    }

    public static func load(paths: LauncherPaths) throws -> Self {
        try ExperimentalConfigurationStore(paths: paths, feature: "vex").load(as: Self.self) ?? Self()
    }
    @discardableResult public static func update(paths: LauncherPaths, _ action: (inout Self) throws -> Void) throws -> Self {
        try ExperimentalConfigurationStore(paths: paths, feature: "vex").update(default: Self(), action)
    }
    public static func normalizedURL(_ value: String) throws -> URL {
        let url = try canonicalURL(value)
        guard url.scheme == "https" || VexTransport.isLoopback(url.host!) else { throw RuriError.message(Messages.VexNetwork.httpsRequired) }
        return url
    }
    static func canonicalURL(_ value: String) throws -> URL {
        guard var parts = URLComponents(string: value), ["http", "https"].contains(parts.scheme?.lowercased()),
              parts.host?.isEmpty == false, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil, parts.path.isEmpty || parts.path == "/" else {
            throw RuriError.message(Messages.Vex.invalidURL)
        }
        parts.scheme = parts.scheme?.lowercased()
        parts.host = parts.host?.lowercased()
        if (parts.scheme == "http" && parts.port == 80) || (parts.scheme == "https" && parts.port == 443) { parts.port = nil }
        parts.path = ""
        guard let url = parts.url else { throw RuriError.message(Messages.Vex.invalidURL) }
        return url
    }
    public func server(named selection: String? = nil) throws -> VexServer {
        guard enabled else { throw RuriError.message(Messages.Vex.disabled) }
        if let selection {
            guard let server = servers.first(where: { $0.name == selection || $0.id == selection }) else {
                throw RuriError.message(Messages.VexLogin.chooseServer(servers.map(\.name).joined(separator: ", ")))
            }
            return server
        }
        if let defaultServer, let server = servers.first(where: { $0.id == defaultServer }) { return server }
        if servers.count == 1 { return servers[0] }
        throw RuriError.message(Messages.VexLogin.chooseServer(servers.map(\.name).joined(separator: ", ")))
    }
    public mutating func save(_ server: VexServer) throws {
        guard !server.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !servers.contains(where: { $0.id != server.id && $0.name == server.name }) else {
            throw RuriError.message(Messages.VexLogin.duplicateName)
        }
        if let index = servers.firstIndex(where: { $0.id == server.id }) { servers[index] = server }
        else { servers.append(server) }
        if defaultServer == nil, servers.count == 1 { defaultServer = server.id }
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
            if status == errSecItemNotFound { throw RuriError.message(Messages.VexLogin.notLoggedIn) }
            guard status == errSecSuccess, let data = result as? Data, let token = String(data: data, encoding: .utf8) else { throw failure(status) }
            return token
        }
    }
    public static func invalidate(baseURL: URL) { cache.invalidate(baseURL: baseURL) }
    public static func remove(baseURL: URL) throws {
        let url = try VexSettings.canonicalURL(baseURL.absoluteString)
        var request = query(url)
        request[kSecReturnRef as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitAll
        var result: CFTypeRef?
        let found = SecItemCopyMatching(request as CFDictionary, &result)
        if found == errSecItemNotFound {
            cache.invalidate(baseURL: url)
            return
        }
        guard found == errSecSuccess else { throw failure(found) }
        guard let items = result as? [SecKeychainItem], items.count == 1 else { throw failure(errSecDuplicateItem) }
        let status = SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecMatchItemList as String: items,
        ] as CFDictionary)
        guard status == errSecSuccess else { throw failure(status) }
        cache.invalidate(baseURL: url)
    }
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
