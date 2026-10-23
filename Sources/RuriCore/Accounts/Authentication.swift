import RuriLocalization
import Foundation
import Security
import LocalAuthentication

public struct AccountCredentials: Codable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    public var clientID: String
}

public enum CredentialStore {
    private static let service = "dev.ruri.launcher.microsoft"
    private static let externalService = "dev.ruri.launcher.external"
    public static func save(_ credentials: AccountCredentials, for id: UUID) throws {
        try saveData(JSONEncoder().encode(credentials), for: id, service: service)
    }
    public static func load(for id: UUID) throws -> AccountCredentials {
        try JSONDecoder().decode(AccountCredentials.self, from: loadData(for: id, service: service))
    }
    public static func remove(for id: UUID) throws { try removeData(for: id, service: service) }
    public static func saveExternal(_ credentials: ExternalAccountCredentials, for id: UUID) throws {
        try saveData(JSONEncoder().encode(credentials), for: id, service: externalService)
    }
    public static func loadExternal(for id: UUID) throws -> ExternalAccountCredentials {
        try JSONDecoder().decode(ExternalAccountCredentials.self, from: loadData(for: id, service: externalService))
    }
    public static func removeExternal(for id: UUID) throws { try removeData(for: id, service: externalService) }
    /// Read metadata only and never prompt for Keychain access during a check.
    public static func availability(for id: UUID, kind: Account.Kind) -> String {
        if kind == .offline { return "notRequired" }
        let context = LAContext(); context.interactionNotAllowed = true
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: kind == .microsoft ? service : externalService,
            kSecAttrAccount as String: id.uuidString, kSecReturnAttributes as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context]
        var result: CFTypeRef?
        switch SecItemCopyMatching(query as CFDictionary, &result) {
        case errSecSuccess: return "available"
        case errSecItemNotFound: return "missing"
        default: return "unavailable"
        }
    }
    static func saveFlow(_ data: Data, for id: UUID) throws { try saveData(data, for: id, service: "dev.ruri.launcher.login-flow") }
    static func loadFlow(for id: UUID) throws -> Data { try loadData(for: id, service: "dev.ruri.launcher.login-flow") }
    static func removeFlow(for id: UUID) throws { try removeData(for: id, service: "dev.ruri.launcher.login-flow") }
    static func flowIDs() throws -> [UUID] {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "dev.ruri.launcher.login-flow", kSecReturnAttributes as String: true, kSecMatchLimit as String: kSecMatchLimitAll]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else { throw failure(status) }
        return (result as? [[String: Any]] ?? []).compactMap { ($0[kSecAttrAccount as String] as? String).flatMap(UUID.init(uuidString:)) }
    }
    private static func saveData(_ data: Data, for id: UUID, service: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: id.uuidString]
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecItemNotFound {
            var add = query; add[kSecValueData as String] = data; add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let status = SecItemAdd(add as CFDictionary, nil)
            guard status == errSecSuccess else { throw failure(status) }
        } else if update != errSecSuccess { throw failure(update) }
    }
    private static func loadData(for id: UUID, service: String) throws -> Data {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: id.uuidString, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { throw failure(status) }
        return data
    }
    private static func removeData(for id: UUID, service: String) throws {
        try KeychainItemDeletion.remove(service: service, account: id.uuidString)
    }
    private static func failure(_ status: OSStatus) -> RuriError { .message(Messages.CoreAuthentication.keychainAccessFailed(String(describing: status))) }
}

public struct DeviceCode: Codable, Sendable {
    public let device_code: String
    public let user_code: String
    public let verification_uri: URL
    public let expires_in: Int
    public let interval: Int?
}

public actor MicrosoftAuth {
    private let clientID: String
    private let session: URLSession
    public init(clientID: String, session: URLSession = .shared) { self.clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines); self.session = session }
    public func begin() async throws -> DeviceCode {
        guard UUID(uuidString: clientID) != nil else { throw RuriError.message(Messages.CoreAuthentication.microsoftClientIDRequired) }
        let (data, status) = try await form(AuthenticationEndpoints.deviceCode, values: ["client_id": clientID, "scope": AuthenticationEndpoints.scope])
        guard status == 200 else { throw RuriError.message(Messages.CoreAuthentication.microsoftDeviceLoginRejected(String(describing: status))) }
        return try JSONDecoder().decode(DeviceCode.self, from: data)
    }
    private struct OAuthToken: Decodable, Sendable {
        let access_token: String?; let refresh_token: String?; let error: String?
    }
    public func finish(_ code: DeviceCode, expiresAt: Date? = nil) async throws -> (Account, AccountCredentials) {
        let deadline = expiresAt ?? Date().addingTimeInterval(TimeInterval(code.expires_in))
        var interval = max(code.interval ?? 5, 1)
        while Date() < deadline {
            try await Task.sleep(for: .seconds(interval)); try Task.checkCancellation()
            let (data, status) = try await form(AuthenticationEndpoints.token, values: ["client_id": clientID, "grant_type": "urn:ietf:params:oauth:grant-type:device_code", "device_code": code.device_code])
            let token = try JSONDecoder().decode(OAuthToken.self, from: data)
            if token.error == "authorization_pending" { continue }
            if token.error == "slow_down" { interval += 5; continue }
            if token.error == "expired_token" { throw RuriError.message(Messages.CoreAuthentication.deviceLoginCodeExpired) }
            guard status == 200, token.error == nil, let access = token.access_token, let refresh = token.refresh_token else {
                throw RuriError.message(token.error == "authorization_declined" ? Messages.CoreAuthentication.loginCancelled : Messages.CoreAuthentication.microsoftLoginExpiredOrFailed)
            }
            return try await exchange(access: access, refresh: refresh)
        }
        throw RuriError.message(Messages.CoreAuthentication.deviceLoginCodeExpired)
    }
    public func refresh(_ credentials: AccountCredentials, account: Account) async throws -> (Account, AccountCredentials) {
        let (data, status) = try await form(AuthenticationEndpoints.token, values: ["client_id": credentials.clientID, "grant_type": "refresh_token", "refresh_token": credentials.refreshToken, "scope": AuthenticationEndpoints.scope])
        let token = try JSONDecoder().decode(OAuthToken.self, from: data)
        guard status == 200, let access = token.access_token else { throw RuriError.message(Messages.CoreAuthentication.microsoftLoginInvalid) }
        var (updated, secrets) = try await exchange(access: access, refresh: token.refresh_token ?? credentials.refreshToken)
        updated = try account.reauthenticated(with: updated); secrets.clientID = credentials.clientID
        return (updated, secrets)
    }
    private func form(_ endpoint: URL, values: [String: String]) async throws -> (Data, Int) {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"; request.timeoutInterval = 45
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        request.httpBody = Data(values.sorted(by: { $0.key < $1.key }).map { key, value in "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }.joined(separator: "&").utf8)
        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
    private func post<T: Decodable>(_ type: T.Type, url: URL, body: [String: Any]) async throws -> T {
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let code = json["XErr"] as? Int64 {
            let explanation: LocalizedMessage
            switch code {
            case 2148916233: explanation = Messages.CoreAuthentication.xboxProfileMissing
            case 2148916235: explanation = Messages.CoreAuthentication.xboxLiveUnavailableInRegion
            case 2148916236, 2148916237: explanation = Messages.CoreAuthentication.xboxAgeVerificationRequired
            case 2148916238: explanation = Messages.CoreAuthentication.childAccountFamilyApprovalRequired
            default: explanation = Messages.CoreAuthentication.xboxLoginFailed(String(describing: code))
            }
            throw RuriError.message(explanation)
        }
        guard (200..<300).contains(status) else { throw RuriError.message(Messages.CoreAuthentication.minecraftServiceLoginFailed(String(describing: url.host ?? Messages.CoreAuthentication.authenticationService.localized), String(describing: status))) }
        return try JSONDecoder().decode(type, from: data)
    }
    private func exchange(access: String, refresh: String) async throws -> (Account, AccountCredentials) {
        struct Xbox: Decodable { struct Claims: Decodable { let xui: [[String: String]] }; let Token: String; let DisplayClaims: Claims }
        struct Minecraft: Decodable { let access_token: String; let expires_in: Int }
        struct Entitlements: Decodable, Sendable { struct Item: Decodable, Sendable { let name: String }; let items: [Item] }
        struct Profile: Decodable, Sendable { let id: String; let name: String }
        let xbox = try await post(Xbox.self, url: AuthenticationEndpoints.xboxAuthenticate, body: ["Properties": ["AuthMethod": "RPS", "SiteName": AuthenticationEndpoints.xboxSite, "RpsTicket": "d=\(access)"], "RelyingParty": AuthenticationEndpoints.xboxRelyingParty, "TokenType": "JWT"])
        let xsts = try await post(Xbox.self, url: AuthenticationEndpoints.xstsAuthorize, body: ["Properties": ["SandboxId": "RETAIL", "UserTokens": [xbox.Token]], "RelyingParty": AuthenticationEndpoints.minecraftRelyingParty, "TokenType": "JWT"])
        guard let uhs = xsts.DisplayClaims.xui.first?["uhs"], uhs == xbox.DisplayClaims.xui.first?["uhs"] else { throw RuriError.message(Messages.CoreAuthentication.xboxIdentityValidationFailed) }
        let minecraft = try await post(Minecraft.self, url: AuthenticationEndpoints.minecraftLogin, body: ["identityToken": "XBL3.0 x=\(uhs);\(xsts.Token)"])
        var request = URLRequest(url: AuthenticationEndpoints.entitlements)
        request.setValue("Bearer \(minecraft.access_token)", forHTTPHeaderField: "Authorization")
        // Complete the mcstore check, then verify the Java profile. An empty
        // store list alone does not rule out access.
        _ = try await HTTPClient(session: session).data(for: request)
        request.url = AuthenticationEndpoints.profile
        let profile: Profile
        do {
            profile = try JSONDecoder().decode(Profile.self, from: await HTTPClient(session: session).data(for: request))
        } catch let error as RuriError where error.httpStatusCode == 404 {
            request.url = AuthenticationEndpoints.license
            let license = try JSONDecoder().decode(Entitlements.self, from: await HTTPClient(session: session).data(for: request))
            guard license.items.contains(where: { $0.name == "game_minecraft" }) else {
                throw RuriError.message(Messages.CoreAuthentication.minecraftJavaEntitlementMissing)
            }
            throw RuriError.message(Messages.CoreAuthentication.minecraftJavaProfileMissing)
        }
        return (Account(username: profile.name, uuid: profile.id, kind: .microsoft), AccountCredentials(accessToken: minecraft.access_token, refreshToken: refresh, expiresAt: Date().addingTimeInterval(TimeInterval(minecraft.expires_in)), clientID: clientID))
    }
}
