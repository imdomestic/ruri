import Foundation
import Security
import Testing
@testable import RuriCore
@testable import RuriVex

struct VexTokenStorageTests {
    @Test func dryRunReadsLegacyWithoutWritingOrCaching() throws {
        let keychain = try VexTestKeychain()
        defer { keychain.remove() }
        let url = try #require(URL(string: "https://legacy.example"))
        let first = UUID().uuidString, second = UUID().uuidString
        let sessions = VexSessionStorage(storage: keychain.storage, legacy: keychain.legacy)
        try keychain.addLegacy(Data(first.utf8), for: url)

        #expect(try sessions.load(baseURL: url, migrateLegacy: false) == first)
        #expect(try keychain.storage.accounts().isEmpty)
        #expect(try keychain.legacy.read(url) == Data(first.utf8))
        try keychain.legacy.remove(url)
        try keychain.addLegacy(Data(second.utf8), for: url)
        #expect(try sessions.load(baseURL: url, migrateLegacy: false) == second)
        #expect(try keychain.storage.accounts().isEmpty)
        #expect(try keychain.legacy.read(url) == Data(second.utf8))

        #expect(try sessions.load(baseURL: url) == second)
        #expect(try keychain.storage.read(url.absoluteString) == Data(second.utf8))
        #expect(try keychain.legacy.read(url) == nil)
    }

    @Test func dryRunPrefersCurrentAndLeavesBothItemsUnchanged() throws {
        let keychain = try VexTestKeychain()
        defer { keychain.remove() }
        let url = try #require(URL(string: "https://current.example"))
        let current = UUID().uuidString, legacy = UUID().uuidString, updated = UUID().uuidString
        let sessions = VexSessionStorage(storage: keychain.storage, legacy: keychain.legacy)
        try keychain.storage.write(Data(current.utf8), account: url.absoluteString)
        try keychain.addLegacy(Data(legacy.utf8), for: url)

        #expect(try sessions.load(baseURL: url, migrateLegacy: false) == current)
        #expect(try keychain.storage.read(url.absoluteString) == Data(current.utf8))
        #expect(try keychain.legacy.read(url) == Data(legacy.utf8))
        try keychain.storage.write(Data(updated.utf8), account: url.absoluteString)
        #expect(try sessions.load(baseURL: url) == updated)
        #expect(try keychain.storage.read(url.absoluteString) == Data(updated.utf8))
        #expect(try keychain.legacy.read(url) == nil)
    }

    @Test func migrationResumesWhenCurrentItemAlreadyExists() throws {
        let keychain = try VexTestKeychain()
        defer { keychain.remove() }
        let url = try #require(URL(string: "https://resuming.example"))
        let otherURL = try #require(URL(string: "https://other.example"))
        let token = UUID().uuidString, otherToken = UUID().uuidString
        let otherStorage = ExperimentalSecureStorage(extension: "other", keychain: keychain.file)
        let sessions = VexSessionStorage(storage: keychain.storage, legacy: keychain.legacy)
        try keychain.addLegacy(Data(token.utf8), for: url)
        // 保留写入新条目后、删除旧条目前的实际 Keychain 状态。
        try keychain.storage.write(Data(token.utf8), account: url.absoluteString)
        try keychain.addLegacy(Data(otherToken.utf8), for: otherURL)
        try otherStorage.write(Data(otherToken.utf8), account: url.absoluteString)

        #expect(try sessions.load(baseURL: url) == token)
        #expect(try keychain.storage.read(url.absoluteString) == Data(token.utf8))
        #expect(try keychain.legacy.read(url) == nil)
        #expect(try keychain.legacy.read(otherURL) == Data(otherToken.utf8))
        #expect(try otherStorage.read(url.absoluteString) == Data(otherToken.utf8))
        #expect(try sessions.load(baseURL: url) == token)
    }

    @Test func missingSessionCanBeReadAfterItAppears() throws {
        let keychain = try VexTestKeychain()
        defer { keychain.remove() }
        let url = try #require(URL(string: "https://missing.example"))
        let token = UUID().uuidString
        let sessions = VexSessionStorage(storage: keychain.storage, legacy: keychain.legacy)

        #expect(throws: (any Error).self) { try sessions.load(baseURL: url, migrateLegacy: false) }
        #expect(throws: (any Error).self) { try sessions.load(baseURL: url) }
        #expect(try keychain.storage.accounts().isEmpty)
        #expect(try keychain.legacy.read(url) == nil)
        try keychain.addLegacy(Data(token.utf8), for: url)
        #expect(try sessions.load(baseURL: url) == token)
        #expect(try keychain.storage.read(url.absoluteString) == Data(token.utf8))
        #expect(try keychain.legacy.read(url) == nil)
    }

    @Test func invalidLegacyDataFailsBeforeWritingAndCanBeRetried() throws {
        let keychain = try VexTestKeychain()
        defer { keychain.remove() }
        let url = try #require(URL(string: "https://invalid.example"))
        let invalid = Data([0xff]), token = UUID().uuidString
        let sessions = VexSessionStorage(storage: keychain.storage, legacy: keychain.legacy)
        try keychain.addLegacy(invalid, for: url)

        #expect(throws: (any Error).self) { try sessions.load(baseURL: url, migrateLegacy: false) }
        #expect(throws: (any Error).self) { try sessions.load(baseURL: url) }
        #expect(try keychain.storage.accounts().isEmpty)
        #expect(try keychain.legacy.read(url) == invalid)
        try keychain.legacy.remove(url)
        try keychain.addLegacy(Data(token.utf8), for: url)
        #expect(try sessions.load(baseURL: url) == token)
        #expect(try keychain.storage.read(url.absoluteString) == Data(token.utf8))
        #expect(try keychain.legacy.read(url) == nil)
    }

    @Test func saveAndRemoveUpdateTheSessionCacheAndBothServices() throws {
        let keychain = try VexTestKeychain()
        defer { keychain.remove() }
        let url = try #require(URL(string: "https://saved.example"))
        let token = UUID().uuidString, updated = UUID().uuidString
        let sessions = VexSessionStorage(storage: keychain.storage, legacy: keychain.legacy)
        try sessions.save(token, baseURL: url)
        #expect(try sessions.load(baseURL: url) == token)
        try keychain.addLegacy(Data(token.utf8), for: url)
        try sessions.save(updated, baseURL: url)
        #expect(try sessions.load(baseURL: url) == updated)
        #expect(try keychain.storage.read(url.absoluteString) == Data(updated.utf8))
        #expect(try keychain.legacy.read(url) == nil)
        try keychain.addLegacy(Data(token.utf8), for: url)

        try sessions.remove(baseURL: url)
        #expect(try keychain.storage.read(url.absoluteString) == nil)
        #expect(try keychain.legacy.read(url) == nil)
        #expect(throws: (any Error).self) { try sessions.load(baseURL: url) }
    }
}

private struct VexTestKeychain {
    let directory: URL
    let file: SecKeychain
    let storage: ExperimentalSecureStorage
    let legacy: VexLegacyTokenStore

    init() throws {
        // 独立 Keychain 只保存本测试产生的数据，路径位于仓库忽略的工作目录。
        directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".work/vex-keychain-tests/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var keychain: SecKeychain?
        let password = UUID().uuidString
        try #require(SecKeychainCreate(directory.appendingPathComponent("test.keychain-db").path,
                                      UInt32(password.utf8.count), password, false, nil, &keychain) == errSecSuccess)
        file = try #require(keychain)
        storage = ExperimentalSecureStorage(extension: "vex", keychain: file)
        legacy = VexLegacyTokenStore(keychain: file)
    }

    func addLegacy(_ data: Data, for url: URL) throws {
        let request: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                      kSecAttrService as String: VexLegacyTokenStore.service,
                                      kSecAttrAccount as String: url.absoluteString,
                                      kSecValueData as String: data,
                                      kSecUseKeychain as String: file,
                                      kSecAttrAccess as String: try ExperimentalSecureStorage.access(VexLegacyTokenStore.service)]
        try #require(SecItemAdd(request as CFDictionary, nil) == errSecSuccess)
    }

    func remove() {
        #expect(SecKeychainDelete(file) == errSecSuccess)
        #expect(throws: Never.self) { try FileManager.default.removeItem(at: directory) }
    }
}
