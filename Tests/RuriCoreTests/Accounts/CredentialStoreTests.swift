import Foundation
import Security
import Testing
@testable import RuriCore

struct CredentialStoreTests {
    @Test(arguments: ["dev.ruri.launcher.microsoft", "dev.ruri.launcher.external", "dev.ruri.launcher.login-flow"])
    func deletionKeepsOtherAccountsAndServices(service: String) throws {
        let keychain = try TemporaryKeychain()
        defer { keychain.close() }
        let account = UUID().uuidString, otherAccount = UUID().uuidString
        let otherService = service + ".other"
        try keychain.add(service: service, account: account)
        try keychain.add(service: service, account: otherAccount)
        try keychain.add(service: otherService, account: account)

        try KeychainItemDeletion.remove(service: service, account: account, keychains: [keychain.file])

        #expect(try !keychain.contains(service: service, account: account))
        #expect(try keychain.contains(service: service, account: otherAccount))
        #expect(try keychain.contains(service: otherService, account: account))
    }

    @Test func missingItemsAndRepeatedDeletionSucceed() throws {
        let keychain = try TemporaryKeychain()
        defer { keychain.close() }
        let service = UUID().uuidString, account = UUID().uuidString
        try KeychainItemDeletion.remove(service: service, account: account, keychains: [keychain.file])
        try keychain.add(service: service, account: account)
        try KeychainItemDeletion.remove(service: service, account: account, keychains: [keychain.file])
        try KeychainItemDeletion.remove(service: service, account: account, keychains: [keychain.file])
        #expect(try !keychain.contains(service: service, account: account))
    }

    @Test func emptySearchListIsRejected() throws {
        let keychain = try TemporaryKeychain()
        defer { keychain.close() }
        let service = UUID().uuidString, account = UUID().uuidString
        try keychain.add(service: service, account: account)
        #expect(throws: RuriError.self) {
            try KeychainItemDeletion.remove(service: service, account: account, keychains: [])
        }
        #expect(try keychain.contains(service: service, account: account))
    }

    @Test func duplicateMatchesRemainInBothKeychains() throws {
        let first = try TemporaryKeychain(), second = try TemporaryKeychain()
        defer { first.close(); second.close() }
        let service = UUID().uuidString, account = UUID().uuidString
        try first.add(service: service, account: account)
        try second.add(service: service, account: account)

        #expect(throws: RuriError.self) {
            try KeychainItemDeletion.remove(service: service, account: account, keychains: [first.file, second.file])
        }
        #expect(try first.contains(service: service, account: account))
        #expect(try second.contains(service: service, account: account))

        try KeychainItemDeletion.remove(service: service, account: account, keychains: [first.file])
        #expect(try !first.contains(service: service, account: account))
        #expect(try second.contains(service: service, account: account))
    }

    @Test func deletesAnItemCreatedByAnotherProcess() throws {
        let keychain = try TemporaryKeychain()
        defer { keychain.close() }
        let service = UUID().uuidString, account = UUID().uuidString
        let creator = Process()
        creator.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        // security creates a real item; the password data is used only for deletion in this isolated keychain.
        creator.arguments = ["add-generic-password", "-a", account, "-s", service, "-X", "010203", keychain.path.path]
        creator.standardOutput = FileHandle.nullDevice
        creator.standardError = FileHandle.nullDevice
        try creator.run()
        creator.waitUntilExit()
        try #require(creator.terminationStatus == 0)
        #expect(try keychain.contains(service: service, account: account))

        try KeychainItemDeletion.remove(service: service, account: account, keychains: [keychain.file])

        #expect(try !keychain.contains(service: service, account: account))
    }
}

private struct TemporaryKeychain {
    let directory: URL
    let path: URL
    let file: SecKeychain

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("ruri-keychain-deletion-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        path = directory.appendingPathComponent("test.keychain-db")
        var keychain: SecKeychain?
        let password = UUID().uuidString
        try #require(SecKeychainCreate(path.path, UInt32(password.utf8.count), password, false, nil, &keychain) == errSecSuccess)
        file = try #require(keychain)
    }

    func close() {
        #expect(SecKeychainDelete(file) == errSecSuccess)
        do { try FileManager.default.removeItem(at: directory) }
        catch { Issue.record(error) }
    }

    func add(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data([1, 2, 3]),
            kSecUseKeychain as String: file
        ]
        try #require(SecItemAdd(query as CFDictionary, nil) == errSecSuccess)
    }

    func contains(service: String, account: String) throws -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchSearchList as String: [file],
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return false }
        try #require(status == errSecSuccess)
        return true
    }
}
