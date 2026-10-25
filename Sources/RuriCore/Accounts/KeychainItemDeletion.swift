import Foundation
import RuriLocalization
import Security

enum KeychainItemDeletion {
    // Native file-keychain deletion supports credentials shared by the app and its bundled CLI.
    // Find exactly one item by service and account, and validate its reference before deleting it.
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
