import Foundation
import RuriCore
import RuriLocalization

public struct VexHTTPError: Error, LocalizedError, Sendable {
    public let status: Int
    public let api: VexAPIError?
    public var errorDescription: String? { api?.message ?? Messages.Vex.httpFailure(String(status)).localized }
}

public struct VexClient: Sendable {
    public let baseURL: URL
    public let project: String
    private let token: String?
    let session: URLSession
    public init(baseURL: URL, token: String? = nil, project: String = "") throws {
        self.baseURL = try VexSettings.normalizedURL(baseURL.absoluteString)
        if let token {
            guard !token.isEmpty, !token.contains("\r"), !token.contains("\n") else { throw RuriError.message(Messages.Vex.invalidToken) }
        }
        guard project.isEmpty || Self.validProject(project) else { throw RuriError.message(Messages.Vex.projectRequired) }
        self.project = project
        self.token = token
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 3600
        configuration.urlCache = nil
        session = URLSession(configuration: configuration, delegate: VexRedirectPolicy(baseURL: self.baseURL), delegateQueue: nil)
    }
    public static func validProject(_ value: String) -> Bool {
        value.range(of: "^[a-z][a-z0-9-]{0,22}$", options: .regularExpression) != nil && !value.hasSuffix("-") && !value.contains("--")
    }
    public func projectPath(_ suffix: String) throws -> String {
        guard Self.validProject(project), suffix.hasPrefix("/") else { throw RuriError.message(Messages.Vex.projectRequired) }
        return "/v2/projects/" + project + suffix
    }
    public func request(_ path: String, method: String = "GET", body: Data? = nil, query: [URLQueryItem] = []) throws -> URLRequest {
        guard let resolved = URL(string: path, relativeTo: baseURL)?.absoluteURL,
              resolved.scheme == baseURL.scheme, resolved.host == baseURL.host, resolved.port == baseURL.port,
              resolved.user == nil, resolved.password == nil, resolved.fragment == nil,
              resolved.path.hasPrefix("/v2/") else { throw RuriError.message(Messages.Vex.invalidURL) }
        var parts = URLComponents(url: resolved, resolvingAgainstBaseURL: false)!
        if !query.isEmpty { parts.queryItems = query }
        var request = URLRequest(url: parts.url!)
        request.httpMethod = method
        request.httpBody = body
        if let token { request.setValue(["Bearer", token].joined(separator: " "), forHTTPHeaderField: "Authorization") }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return request
    }
    static func component(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_~.")))!
    }
    func validate(_ response: URLResponse, data: Data = Data()) throws {
        guard let http = response as? HTTPURLResponse else { throw RuriError.message(Messages.Vex.invalidResponse) }
        guard (200...299).contains(http.statusCode) else {
            struct Envelope: Decodable { let error: VexAPIError }
            let decoded = try? JSONDecoder().decode(Envelope.self, from: data)
            throw VexHTTPError(status: http.statusCode, api: decoded?.error)
        }
    }
    public func data(_ path: String, method: String = "GET", body: Data? = nil, query: [URLQueryItem] = []) async throws -> Data {
        let (data, response) = try await session.data(for: request(path, method: method, body: body, query: query))
        try validate(response, data: data)
        return data
    }
    public func get<T: Decodable & Sendable>(_ type: T.Type, _ path: String, query: [URLQueryItem] = []) async throws -> T {
        try JSONDecoder().decode(type, from: await data(path, query: query))
    }
    public func projects() async throws -> [VexProject] { try await get([VexProject].self, "/v2/projects") }
    public func selecting(project: String) throws -> Self { try Self(baseURL: baseURL, token: token, project: project) }
    public func redeem(code: String, client: String) async throws -> VexLoginResult {
        try JSONDecoder().decode(VexLoginResult.self, from: await data("/v2/auth/invites/redeem", method: "POST", body: JSONEncoder().encode(["code": code, "client": client])))
    }
    public func logout() async throws { _ = try await data("/v2/auth/logout", method: "POST") }
    public func me() async throws -> VexUser { try await get(VexUser.self, "/v2/me") }
    public func meta() async throws -> VexMeta { try await get(VexMeta.self, "/v2/meta") }
    public func nodes() async throws -> [VexNode] { try await get([VexNode].self, "/v2/nodes") }
    public func rooms() async throws -> [VexRoom] { try await get([VexRoom].self, projectPath("/rooms")) }
    public func builds() async throws -> [VexBuild] { try await get([VexBuild].self, projectPath("/builds")) }
    public func branches() async throws -> [VexBranch] { try await get([VexBranch].self, projectPath("/branches")) }
    public func pulls() async throws -> [VexPull] { try await get([VexPull].self, projectPath("/pulls")) }
    public func room(_ id: String) async throws -> VexRoom { try await get(VexRoom.self, projectPath("/rooms/" + Self.component(id))) }
    public func build(_ id: String) async throws -> VexBuild { try await get(VexBuild.self, projectPath("/builds/" + Self.component(id))) }
    public func refreshGit() async throws { _ = try await data(projectPath("/git/refresh"), method: "POST") }
    public func start(_ id: String) async throws -> VexStartResult {
        try JSONDecoder().decode(VexStartResult.self, from: await data(projectPath("/rooms/" + Self.component(id) + "/start"), method: "POST"))
    }
    public func reopen(_ id: String) async throws -> VexStartResult {
        try await prepareReopen(id)
        try Task.checkCancellation()
        return try await start(id)
    }
    func prepareReopen(_ id: String) async throws {
        let room = try await room(id)
        try Task.checkCancellation()
        if room.state == .closed, room.label == "finished" { _ = try await label(id, finished: false) }
    }
    public func label(_ id: String, finished: Bool) async throws -> VexRoom {
        let body = try JSONEncoder().encode(["label": finished ? "finished" : "testing"])
        return try JSONDecoder().decode(VexRoom.self, from: await data(projectPath("/rooms/" + Self.component(id)), method: "PATCH", body: body))
    }
    public func cancel(room: String, lease: String) async throws {
        _ = try await data(projectPath("/rooms/" + Self.component(room) + "/leases/" + Self.component(lease)), method: "DELETE")
    }
    public func changeRoom(_ id: String, action: String) async throws -> VexRoom {
        guard ["stop", "restart"].contains(action) else { throw RuriError.message(Messages.Vex.invalidResponse) }
        return try JSONDecoder().decode(VexRoom.self, from: await data(projectPath("/rooms/" + Self.component(id) + "/" + action), method: "POST"))
    }
    public func log(build id: String) async throws -> String { String(decoding: try await data(projectPath("/builds/" + Self.component(id) + "/log")), as: UTF8.self) }
    public func commits(branch: String, before: String? = nil) async throws -> [VexCommit] {
        var query = [URLQueryItem(name: "branch", value: branch), URLQueryItem(name: "limit", value: "50")]
        if let before { query.append(.init(name: "before", value: before)) }
        return try await get([VexCommit].self, projectPath("/commits"), query: query)
    }
    public func createBuild(sha: String, loader: String, force: Bool = false) async throws -> VexBuild {
        struct Request: Encodable { let sha: String; let loader: String; let force: Bool }
        return try JSONDecoder().decode(VexBuild.self, from: await data(projectPath("/builds"), method: "POST", body: JSONEncoder().encode(Request(sha: sha, loader: loader, force: force))))
    }
    public func createRoom(sha: String, loader: String, branch: String) async throws -> VexRoom {
        let body = try JSONEncoder().encode(["kind": "commit", "sha": sha, "loader": loader, "seed": "branch:" + branch])
        return try JSONDecoder().decode(VexRoom.self, from: await data(projectPath("/rooms"), method: "POST", body: body))
    }
}

private final class VexRedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
    let baseURL: URL
    init(baseURL: URL) { self.baseURL = baseURL }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        guard let url = request.url, url.scheme == baseURL.scheme, url.host == baseURL.host, url.port == baseURL.port,
              url.user == nil, url.password == nil, url.path.hasPrefix("/v2/") else { completionHandler(nil); return }
        completionHandler(request)
    }
}
