import Foundation
import RuriCore
import RuriLocalization

public struct VexServer: Codable, Identifiable, Equatable, Sendable {
    public var id: String { baseURL }
    public let baseURL: String
    public var name: String
    public var defaultProject: String?
    public var userID: String?
    public var sessionRevision: UUID?
    public init(baseURL: URL, name: String) throws {
        self.baseURL = try VexSettings.normalizedURL(baseURL.absoluteString).absoluteString
        self.name = name
    }
    public func client(project: String = "") throws -> VexClient {
        guard userID != nil else { throw RuriError.message(Messages.VexLogin.notLoggedIn) }
        let url = try VexSettings.normalizedURL(baseURL)
        return try VexClient(baseURL: url, token: VexTokenStore.load(baseURL: url), project: project)
    }
    public func resolveProject(_ selection: String?, available: [VexProject]) throws -> VexProject {
        if let selection = selection ?? defaultProject {
            guard let project = available.first(where: { $0.id == selection }) else {
                throw RuriError.message(Messages.VexLogin.chooseProject(available.map(\.id).joined(separator: ", ")))
            }
            return project
        }
        if available.count == 1 { return available[0] }
        throw RuriError.message(Messages.VexLogin.chooseProject(available.map(\.id).joined(separator: ", ")))
    }
}

public struct VexServerInput: Equatable, Sendable {
    public let baseURL: URL
    public let invite: String?
    public init(_ input: String) throws {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = value.contains("://") ? value : "https://" + value
        guard var parts = URLComponents(string: address), parts.query == nil, parts.fragment == nil else {
            throw RuriError.message(Messages.Vex.invalidURL)
        }
        let components = parts.path.split(separator: "/", omittingEmptySubsequences: true)
        if components.count == 2, components[0] == "i", !parts.path.hasSuffix("/") {
            invite = try Self.code(String(components[1]))
            parts.path = ""
        } else {
            guard parts.path.isEmpty || parts.path == "/" else { throw RuriError.message(Messages.Vex.invalidURL) }
            invite = nil
        }
        guard let url = parts.url else { throw RuriError.message(Messages.Vex.invalidURL) }
        baseURL = try VexSettings.normalizedURL(url.absoluteString)
    }
    public static func code(_ input: String) throws -> String {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            .replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "O", with: "0")
            .replacingOccurrences(of: "I", with: "1").replacingOccurrences(of: "L", with: "1")
        guard value.count == 8, value.allSatisfy({ "0123456789ABCDEFGHJKMNPQRSTVWXYZ".contains($0) }) else {
            throw RuriError.message(Messages.VexLogin.inviteInvalid)
        }
        return value
    }
    public static func invite(_ input: String, for server: URL) throws -> String {
        if input.contains("://") {
            let parsed = try Self(input)
            guard parsed.baseURL == server, let code = parsed.invite else { throw RuriError.message(Messages.VexLogin.inviteInvalid) }
            return code
        }
        return try code(input)
    }
}

public enum VexLogoutOutcome: Sendable {
    case revoked, localOnly, serviceAccount
    public var remoteRevoked: Bool { self == .revoked }
    public var warning: String? { self == .localOnly ? Messages.VexLogin.localLogout.localized : nil }
}

public enum VexAuthentication {
    public static var clientName: String { Messages.VexLogin.clientName(Host.current().localizedName ?? ProcessInfo.processInfo.hostName).localized }
    public static func add(_ input: String, name: String? = nil, paths: LauncherPaths) async throws -> VexServer {
        var settings = try VexSettings.load(paths: paths)
        guard settings.enabled else { throw RuriError.message(Messages.Vex.disabled) }
        let parsed = try VexServerInput(input)
        let client = try VexClient(baseURL: parsed.baseURL)
        let meta = try await client.meta()
        var server = try VexServer(baseURL: parsed.baseURL, name: name ?? meta.name)
        if let existing = settings.servers.first(where: { $0.id == server.id }) { server = existing }
        if let name { server.name = name }
        try settings.save(server)
        if let invite = parsed.invite { server = try await login(server, invite: invite) }
        try VexSettings.update(paths: paths) { try $0.save(server) }
        return server
    }
    public static func login(_ server: VexServer, invite: String) async throws -> VexServer {
        let url = try VexSettings.normalizedURL(server.baseURL)
        let code = try VexServerInput.invite(invite, for: url)
        let result = try await VexClient(baseURL: url).redeem(code: code, client: clientName)
        return try recordLogin(result, server: server)
    }
    static func recordLogin(_ result: VexLoginResult, server: VexServer) throws -> VexServer {
        let url = try VexSettings.normalizedURL(server.baseURL)
        try VexTokenStore.save(result.token, baseURL: url)
        var updated = server
        updated.userID = result.user.id
        updated.sessionRevision = UUID()
        return updated
    }
    public static func serviceLogin(_ server: VexServer, token: String) async throws -> VexServer {
        let url = try VexSettings.normalizedURL(server.baseURL)
        let user = try await VexClient(baseURL: url, token: token).me()
        try VexTokenStore.save(token, baseURL: url)
        var updated = server
        updated.userID = user.id
        updated.sessionRevision = UUID()
        return updated
    }
    public static func logout(_ server: VexServer, paths: LauncherPaths, remove: Bool = false) async throws -> VexLogoutOutcome {
        var outcome = VexLogoutOutcome.revoked
        if server.userID != nil {
            do { try await server.client().logout() }
            catch let error as VexHTTPError where error.status == 401 { }
            catch let error as VexHTTPError where error.status == 409 { outcome = .serviceAccount }
            catch { outcome = .localOnly }
        }
        try VexTokenStore.remove(baseURL: VexSettings.canonicalURL(server.baseURL))
        try VexSettings.update(paths: paths) { settings in
            if remove {
                settings.servers.removeAll { $0.id == server.id }
                if settings.defaultServer == server.id { settings.defaultServer = settings.servers.count == 1 ? settings.servers[0].id : nil }
            } else if let index = settings.servers.firstIndex(where: { $0.id == server.id }) {
                settings.servers[index].userID = nil
                settings.servers[index].sessionRevision = UUID()
            }
        }
        return outcome
    }
    public static func message(for error: any Error) -> String {
        if let http = error as? VexHTTPError {
            if http.api?.code == "invite_invalid" { return Messages.VexLogin.inviteInvalid.localized }
            if http.api?.code == "expired_token" { return Messages.VexDevices.expired.localized }
            if http.api?.code == "access_denied" { return Messages.VexDevices.denied.localized }
            if http.api?.code == "account_not_linked" { return Messages.VexDevices.notLinked.localized }
            if http.api?.code == "provider_unavailable" { return Messages.VexDevices.unavailable.localized }
            if http.status == 401 { return Messages.VexLogin.expired.localized }
            if http.status == 429 { return Messages.VexLogin.rateLimited.localized }
        }
        if error is URLError { return Messages.VexLogin.cannotConnect.localized }
        return error.localizedDescription
    }
}
