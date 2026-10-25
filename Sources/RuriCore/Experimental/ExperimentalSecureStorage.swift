import RuriLocalization
import Foundation
import Security

/// Keychain items of one extension, under the service `dev.ruri.launcher.ext.<id>`.
/// Obtained from the extension's context, so an extension cannot name another
/// extension's service.
public struct ExperimentalSecureStorage: @unchecked Sendable {
    public let service: String
    /// A file keychain to use instead of the default search list; tests only.
    let keychain: SecKeychain?
    init(extension id: String, keychain: SecKeychain? = nil) {
        service = "dev.ruri.launcher.ext." + id
        self.keychain = keychain
    }

    public func read(_ account: String) throws -> Data? {
        var request = query(account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw Self.failure(status) }
        return data
    }

    public func write(_ data: Data, account: String) throws {
        let status = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        guard status == errSecItemNotFound else {
            guard status == errSecSuccess else { throw Self.failure(status) }
            return
        }
        var add: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account,
                                  kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                                  kSecAttrAccess as String: try Self.access(service)]
        if let keychain { add[kSecUseKeychain as String] = keychain }
        let created = SecItemAdd(add as CFDictionary, nil)
        guard created == errSecSuccess else { throw Self.failure(created) }
    }

    /// Removes the item; a missing item counts as removed.
    public func remove(_ account: String) throws {
        try KeychainItemDeletion.remove(service: service, account: account, keychains: keychain.map { [$0] })
    }

    /// Account names of this extension's items.
    public func accounts() throws -> [String] {
        var request: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                      kSecReturnAttributes as String: true, kSecMatchLimit as String: kSecMatchLimitAll]
        if let keychain { request[kSecMatchSearchList as String] = [keychain] }
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else { throw Self.failure(status) }
        return (result as? [[String: Any]] ?? []).compactMap { $0[kSecAttrAccount as String] as? String }.sorted()
    }

    private func query(_ account: String) -> [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        if let keychain { query[kSecMatchSearchList as String] = [keychain] }
        return query
    }

    /// The application and its bundled CLI are different executables, and the
    /// default access object lets only the creator delete an item. Trust both
    /// and grant Delete, so either one can remove what the other created.
    static func access(_ description: String) throws -> SecAccess {
        var paths: [String?] = [nil]
        if let application = RuriInstallation.application(), let cli = RuriInstallation.cliExecutable {
            paths = [application.path, cli.path]
        }
        let applications = try paths.map { path in
            var application: SecTrustedApplication?
            let status = SecTrustedApplicationCreateFromPath(path, &application)
            guard status == errSecSuccess, let application else { throw failure(status) }
            return application
        }
        var access: SecAccess?
        let created = SecAccessCreate(description as CFString, applications as CFArray, &access)
        guard created == errSecSuccess, let access else { throw failure(created) }
        guard let trusted = SecAccessCopyMatchingACLList(access, kSecACLAuthorizationDecrypt) as? [SecACL], trusted.count == 1 else {
            throw failure(errSecACLNotSimple)
        }
        let authorizations = SecACLCopyAuthorizations(trusted[0]) as? [String] ?? []
        let updated = SecACLUpdateAuthorizations(trusted[0], (authorizations + [kSecACLAuthorizationDelete as String]) as CFArray)
        guard updated == errSecSuccess else { throw failure(updated) }
        return access
    }

    private static func failure(_ status: OSStatus) -> RuriError { .message(Messages.CoreAuthentication.keychainAccessFailed(String(describing: status))) }
}
