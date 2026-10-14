import Foundation
import RuriLocalization

public struct ChorusHTTPError: Error, LocalizedError, Sendable {
    public let status: Int
    public let api: ChorusAPIError?
    public var errorDescription: String? { api?.message ?? Messages.Chorus.httpFailure(String(status)).localized }
}

public struct ChorusClient: Sendable {
    public let baseURL: URL
    private let token: String
    let session: URLSession
    public init(baseURL: URL, token: String) throws {
        self.baseURL = try ChorusSettings.normalizedURL(baseURL.absoluteString)
        guard !token.isEmpty, !token.contains("\r"), !token.contains("\n") else { throw RuriError.message(Messages.Chorus.invalidToken) }
        self.token = token
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 3600
        configuration.urlCache = nil
        self.session = URLSession(configuration: configuration, delegate: ChorusRedirectPolicy(baseURL: self.baseURL), delegateQueue: nil)
    }
    public func request(_ path: String, method: String = "GET", body: Data? = nil, query: [URLQueryItem] = []) throws -> URLRequest {
        guard let resolved = URL(string: path, relativeTo: baseURL)?.absoluteURL,
              resolved.scheme == baseURL.scheme, resolved.host == baseURL.host, resolved.port == baseURL.port,
              resolved.user == nil, resolved.password == nil, resolved.fragment == nil,
              resolved.path.hasPrefix("/v1/") else { throw RuriError.message(Messages.Chorus.invalidURL) }
        var parts = URLComponents(url: resolved, resolvingAgainstBaseURL: false)!
        if !query.isEmpty { parts.queryItems = query }
        var request = URLRequest(url: parts.url!)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return request
    }
    static func component(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_~.")))!
    }
    func validate(_ response: URLResponse, data: Data = Data()) throws {
        guard let http = response as? HTTPURLResponse else { throw RuriError.message(Messages.Chorus.invalidResponse) }
        guard (200...299).contains(http.statusCode) else {
            struct Envelope: Decodable { let error: ChorusAPIError }
            let decoded = try? JSONDecoder().decode(Envelope.self, from: data)
            throw ChorusHTTPError(status: http.statusCode, api: decoded?.error)
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
    public func rooms() async throws -> [ChorusRoom] { try await get([ChorusRoom].self, "/v1/rooms") }
    public func builds() async throws -> [ChorusBuild] { try await get([ChorusBuild].self, "/v1/builds") }
    public func branches() async throws -> [ChorusBranch] { try await get([ChorusBranch].self, "/v1/branches") }
    public func meta() async throws -> ChorusMeta { try await get(ChorusMeta.self, "/v1/meta") }
    public func room(_ id: String) async throws -> ChorusRoom { try await get(ChorusRoom.self, "/v1/rooms/" + Self.component(id)) }
    public func build(_ id: String) async throws -> ChorusBuild { try await get(ChorusBuild.self, "/v1/builds/" + Self.component(id)) }
    public func start(_ id: String) async throws -> ChorusStartResult {
        try JSONDecoder().decode(ChorusStartResult.self, from: await data("/v1/rooms/" + Self.component(id) + "/start", method: "POST"))
    }
    public func cancel(room: String, lease: String) async throws {
        _ = try await data("/v1/rooms/" + Self.component(room) + "/leases/" + Self.component(lease), method: "DELETE")
    }
    public func changeRoom(_ id: String, action: String) async throws -> ChorusRoom {
        guard ["stop", "restart"].contains(action) else { throw RuriError.message(Messages.Chorus.invalidResponse) }
        return try JSONDecoder().decode(ChorusRoom.self, from: await data("/v1/rooms/" + Self.component(id) + "/" + action, method: "POST"))
    }
    public func label(_ id: String, finished: Bool) async throws -> ChorusRoom {
        let body = try JSONEncoder().encode(["label": finished ? "finished" : "testing"])
        return try JSONDecoder().decode(ChorusRoom.self, from: await data("/v1/rooms/" + Self.component(id), method: "PATCH", body: body))
    }
    public func log(build id: String) async throws -> String {
        String(decoding: try await data("/v1/builds/" + Self.component(id) + "/log"), as: UTF8.self)
    }
    public func commits(branch: String, before: String? = nil) async throws -> [ChorusCommit] {
        var query = [URLQueryItem(name: "branch", value: branch), URLQueryItem(name: "limit", value: "50")]
        if let before { query.append(.init(name: "before", value: before)) }
        return try await get([ChorusCommit].self, "/v1/commits", query: query)
    }
    public func createBuild(sha: String, loader: String, force: Bool = false) async throws -> ChorusBuild {
        struct Request: Encodable { let sha: String; let loader: String; let force: Bool }
        return try JSONDecoder().decode(ChorusBuild.self, from: await data("/v1/builds", method: "POST", body: JSONEncoder().encode(Request(sha: sha, loader: loader, force: force))))
    }
    public func createRoom(sha: String, loader: String, branch: String) async throws -> ChorusRoom {
        let body = try JSONEncoder().encode(["kind": "commit", "sha": sha, "loader": loader, "seed": "branch:" + branch])
        return try JSONDecoder().decode(ChorusRoom.self, from: await data("/v1/rooms", method: "POST", body: body))
    }
}

private final class ChorusRedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
    let baseURL: URL
    init(baseURL: URL) { self.baseURL = baseURL }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        guard let url = request.url, url.scheme == baseURL.scheme, url.host == baseURL.host, url.port == baseURL.port,
              url.user == nil, url.password == nil, url.path.hasPrefix("/v1/") else { completionHandler(nil); return }
        completionHandler(request)
    }
}
