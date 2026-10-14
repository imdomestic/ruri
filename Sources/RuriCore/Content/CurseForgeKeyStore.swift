import RuriLocalization
import Foundation
import Security

public enum CurseForgeKeyStore {
    // CHORUS: 独立服务凭据。
    private static var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "dev.ruri.launcher.chorus.services", kSecAttrAccount as String: "curseforge"] }
    public static var hasBundledKey: Bool { bundledKey() != nil }
    public static func isConfigured() -> Bool { hasCustomKey() || hasBundledKey }
    public static func hasCustomKey() -> Bool {
        var query = query; query[kSecReturnAttributes as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess
    }
    public static func load() throws -> String {
        try resolve(bundledKey: bundledKey(), customKey: loadCustomKey)
    }
    // A user override takes precedence. Keychain errors must not silently switch
    // identities; only an absent override falls back to the application key.
    static func resolve(bundledKey: String?, customKey: () throws -> String?) throws -> String {
        guard let input = try customKey() ?? bundledKey else { throw RuriError.message(Messages.CoreCurseForge.apiKeyMissing) }
        return try validated(input)
    }
    static func bundledKey(in bundle: Bundle = RuriInstallation.application().flatMap(Bundle.init(url:)) ?? .main) -> String? {
        guard let url = bundle.url(forResource: "RuriServices", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String],
              let key = info["CurseForgeAPIKey"] else { return nil }
        return try? validated(key)
    }
    private static func loadCustomKey() throws -> String? {
        var query = query; query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let key = String(data: data, encoding: .utf8) else {
            throw RuriError.message(Messages.CoreCurseForge.apiKeyReadFailed(String(describing: status)))
        }
        return key
    }
    static func validated(_ input: String) throws -> String {
        let key = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key.unicodeScalars.allSatisfy({ (0x21...0x7E).contains($0.value) }) else {
            throw RuriError.message(Messages.CoreCurseForge.invalidApiKey)
        }
        return key
    }
    public static func save(_ input: String) throws {
        let key = try validated(input)
        let value = [kSecValueData as String: Data(key.utf8)]
        let status = SecItemUpdate(query as CFDictionary, value as CFDictionary)
        if status == errSecItemNotFound {
            var add = query.merging(value) { _, new in new }; add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(add as CFDictionary, nil)
            guard added == errSecSuccess else { throw RuriError.message(Messages.CoreCurseForge.apiKeySaveFailed(String(describing: added))) }
        } else if status != errSecSuccess { throw RuriError.message(Messages.CoreCurseForge.apiKeySaveFailed(String(describing: status))) }
    }
    public static func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw RuriError.message(Messages.CoreCurseForge.apiKeyRemoveFailed(String(describing: status))) }
    }
}
