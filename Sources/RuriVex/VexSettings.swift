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
        try VexFeature.context.configuration(paths).load(as: Self.self) ?? Self()
    }
    @discardableResult public static func update(paths: LauncherPaths, _ action: (inout Self) throws -> Void) throws -> Self {
        try VexFeature.context.configuration(paths).update(default: Self(), action)
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

/// Sessions per server URL, in the extension's secure storage
/// (`dev.ruri.launcher.ext.vex`, account = server URL).
public enum VexTokenStore {
    private static let cache = VexTokenCache()
    private static var sessions: VexSessionStorage { VexSessionStorage(storage: VexFeature.context.secureStorage, cache: cache) }
    public static func save(_ input: String, baseURL: URL) throws {
        try sessions.save(input, baseURL: baseURL)
    }
    public static func load(baseURL: URL, migrateLegacy: Bool = true) throws -> String {
        try sessions.load(baseURL: baseURL, migrateLegacy: migrateLegacy)
    }
    public static func invalidate(baseURL: URL) { cache.invalidate(baseURL: baseURL) }
    public static func remove(baseURL: URL) throws {
        try sessions.remove(baseURL: baseURL)
    }
}

struct VexSessionStorage: Sendable {
    private let storage: ExperimentalSecureStorage
    private let legacy: VexLegacyTokenStore
    private let cache: VexTokenCache

    init(storage: ExperimentalSecureStorage, legacy: VexLegacyTokenStore = .init(), cache: VexTokenCache = .init()) {
        self.storage = storage
        self.legacy = legacy
        self.cache = cache
    }

    func save(_ input: String, baseURL: URL) throws {
        let url = try VexSettings.normalizedURL(baseURL.absoluteString)
        let token = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, token.utf8.count <= 16384, token.unicodeScalars.allSatisfy({ (0x21...0x7e).contains($0.value) }) else {
            throw RuriError.message(Messages.Vex.invalidToken)
        }
        try cache.save(token, baseURL: url) {
            try storage.write(Data(token.utf8), account: url.absoluteString)
            try legacy.remove(url)
        }
    }
    func load(baseURL: URL, migrateLegacy: Bool = true) throws -> String {
        let url = try VexSettings.normalizedURL(baseURL.absoluteString)
        func read() throws -> String {
            let current = try storage.read(url.absoluteString)
            let data = try current ?? legacy.read(url)
            guard let data else { throw RuriError.message(Messages.VexLogin.notLoggedIn) }
            guard let token = String(data: data, encoding: .utf8) else { throw RuriError.message(Messages.Vex.invalidToken) }
            if migrateLegacy {
                if current == nil { try storage.write(data, account: url.absoluteString) }
                // 新条目已经存在时仍清理旧条目，使中断的迁移能够继续。
                try legacy.remove(url)
            }
            return token
        }
        // dry-run 不缓存读取结果，后续正式操作仍会完成迁移。
        if !migrateLegacy { return try read() }
        return try cache.load(baseURL: url, read: read)
    }
    func remove(baseURL: URL) throws {
        let url = try VexSettings.canonicalURL(baseURL.absoluteString)
        try cache.remove(baseURL: url) {
            try storage.remove(url.absoluteString)
            try legacy.remove(url)
        }
    }
}

/// Items of the service earlier builds used, `dev.ruri.launcher.vex.api`.
struct VexLegacyTokenStore: @unchecked Sendable {
    static let service = "dev.ruri.launcher.vex.api"
    private let keychain: SecKeychain?

    init(keychain: SecKeychain? = nil) { self.keychain = keychain }

    private func query(_ url: URL) -> [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.service, kSecAttrAccount as String: url.absoluteString]
        if let keychain { query[kSecMatchSearchList as String] = [keychain] }
        return query
    }
    func read(_ url: URL) throws -> Data? {
        var request = query(url)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw failure(status) }
        return data
    }
    func remove(_ url: URL) throws {
        var request = query(url)
        request[kSecReturnRef as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitAll
        var result: CFTypeRef?
        let found = SecItemCopyMatching(request as CFDictionary, &result)
        if found == errSecItemNotFound { return }
        guard found == errSecSuccess else { throw failure(found) }
        guard let items = result as? [SecKeychainItem], items.count == 1 else { throw failure(errSecDuplicateItem) }
        var delete: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecMatchItemList as String: items]
        if let keychain { delete[kSecMatchSearchList as String] = [keychain] }
        let status = SecItemDelete(delete as CFDictionary)
        guard status == errSecSuccess else { throw failure(status) }
    }
    private func failure(_ status: OSStatus) -> RuriError { .message(Messages.CoreAuthentication.keychainAccessFailed(String(status))) }
}

final class VexTokenCache: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [URL: String] = [:]
    func load(baseURL: URL, read: () throws -> String) throws -> String {
        try lock.withLock {
            if let value = values[baseURL] { return value }
            let value = try read()
            values[baseURL] = value
            return value
        }
    }
    func save(_ value: String, baseURL: URL, write: () throws -> Void) throws {
        try lock.withLock {
            values.removeValue(forKey: baseURL)
            try write()
            values[baseURL] = value
        }
    }
    func remove(baseURL: URL, remove: () throws -> Void) throws {
        try lock.withLock {
            values.removeValue(forKey: baseURL)
            try remove()
        }
    }
    func invalidate(baseURL: URL) { lock.withLock { _ = values.removeValue(forKey: baseURL) } }
}
