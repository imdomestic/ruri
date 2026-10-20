import Foundation
import RuriCore
import RuriLocalization

public struct VexDeviceAuthorization: Decodable, Sendable {
    public let handle: String
    public let userCode: String
    public let verificationUri: URL
    public let expiresAt: String
    public let interval: Int
    public var verificationURL: URL { verificationUri }
    public func deadline() throws -> Date {
        guard !handle.isEmpty, !userCode.isEmpty, (1...60).contains(interval) else { throw RuriError.message(Messages.Vex.invalidResponse) }
        for url in [verificationUri] {
            guard url.scheme == "https", url.host != nil, url.user == nil, url.password == nil, url.fragment == nil else {
                throw RuriError.message(Messages.Vex.invalidURL)
            }
        }
        return try Date.ISO8601FormatStyle(includingFractionalSeconds: expiresAt.contains(".")).parse(expiresAt)
    }
}

public enum VexDevicePoll: Sendable {
    case pending(interval: Int)
    case authorized(VexLoginResult)
}

extension VexClient {
    public func beginDevice() async throws -> VexDeviceAuthorization {
        let body = try JSONEncoder().encode([String: String]())
        let value = try JSONDecoder().decode(VexDeviceAuthorization.self, from: await data("/v2/auth/device", method: "POST", body: body))
        guard try value.deadline() > Date() else { throw RuriError.message(Messages.VexDevices.expired) }
        return value
    }
    public func pollDevice(handle: String, client: String) async throws -> VexDevicePoll {
        let body = try JSONEncoder().encode(["handle": handle, "client": client])
        let (bytes, response) = try await session.data(for: request("/v2/auth/device/poll", method: "POST", body: body))
        try validate(response, data: bytes)
        guard let http = response as? HTTPURLResponse else { throw RuriError.message(Messages.Vex.invalidResponse) }
        if http.statusCode == 202 {
            struct Pending: Decodable { let status: String; let interval: Int }
            let value = try JSONDecoder().decode(Pending.self, from: bytes)
            guard value.status == "pending", (1...60).contains(value.interval) else { throw RuriError.message(Messages.Vex.invalidResponse) }
            return .pending(interval: value.interval)
        }
        guard http.statusCode == 200 else { throw RuriError.message(Messages.Vex.invalidResponse) }
        return .authorized(try JSONDecoder().decode(VexLoginResult.self, from: bytes))
    }
}

extension VexAuthentication {
    public static func beginGitHub(_ server: VexServer) async throws -> VexDeviceAuthorization {
        let client = try VexClient(baseURL: VexSettings.normalizedURL(server.baseURL))
        guard try await client.meta().auth.methods.contains("github") else { throw RuriError.message(Messages.VexDevices.unavailable) }
        return try await client.beginDevice()
    }
    public static func finishGitHub(_ server: VexServer, authorization: VexDeviceAuthorization) async throws -> VexServer {
        let client = try VexClient(baseURL: VexSettings.normalizedURL(server.baseURL))
        let deadline = try authorization.deadline()
        var interval = authorization.interval
        while true {
            try Task.checkCancellation()
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { throw RuriError.message(Messages.VexDevices.expired) }
            try await Task.sleep(for: .seconds(min(Double(interval), remaining)))
            guard deadline > Date() else { throw RuriError.message(Messages.VexDevices.expired) }
            switch try await client.pollDevice(handle: authorization.handle, client: clientName) {
            case .pending(let seconds): interval = seconds
            case .authorized(let result):
                try Task.checkCancellation()
                return try recordLogin(result, server: server)
            }
        }
    }
}
