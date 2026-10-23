import Foundation
import RuriLocalization
import Security

enum KeychainItemDeletion {
    // 文件 Keychain 的原生删除支持应用与内置 CLI 共享的凭据。
    // 删除前按服务和账号取得唯一条目，并验证引用类型。
    static func remove(service: String, account: String, keychains: [SecKeychain]? = nil) throws {
        if let keychains, keychains.isEmpty { throw failure(errSecParam) }
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        if let keychains { query[kSecMatchSearchList as String] = keychains }
        var result: CFTypeRef?
        let found = SecItemCopyMatching(query as CFDictionary, &result)
        if found == errSecItemNotFound { return }
        guard found == errSecSuccess else { throw failure(found) }
        guard let items = result as? [SecKeychainItem] else { throw failure(errSecDecode) }
        guard items.count == 1 else { throw failure(errSecDuplicateItem) }
        let item = items[0]
        guard CFGetTypeID(item) == SecKeychainItemGetTypeID() else { throw failure(errSecDecode) }
        let status = SecKeychainItemDelete(item)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw failure(status) }
    }

    private static func failure(_ status: OSStatus) -> RuriError {
        .message(Messages.CoreAuthentication.keychainAccessFailed(String(describing: status)))
    }
}
