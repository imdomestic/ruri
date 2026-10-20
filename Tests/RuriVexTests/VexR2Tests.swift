import Foundation
import Testing
@testable import RuriCore
@testable import RuriVex

struct VexR2Tests {
    @Test func deviceErrorsHaveActionableLocalizedMessages() {
        for (code, expected) in [("expired_token", "授权已超时，请重新登录。"),
                                 ("access_denied", "已在 GitHub 上拒绝授权。"),
                                 ("account_not_linked", "这个 GitHub 账号尚未加入该服务器，请联系管理员。")] {
            let error = VexHTTPError(status: 401, api: .init(code: code, message: code, details: nil))
            #expect(VexAuthentication.message(for: error) == expected)
        }
    }
    @Test func transportRequiresHTTPSOutsideLoopbackAndGUIRequiresHTTPS() throws {
        for address in ["http://localhost:8792", "http://127.0.0.1:8792", "http://127.2.3.4", "http://[::1]:8792"] {
            let url = try VexSettings.normalizedURL(address)
            #expect(throws: (any Error).self) { try VexTransport.requireHTTPS(url) }
        }
        for address in ["http://vex.example", "http://100.64.0.43", "http://127.0.0.1.example", "http://[::ffff:127.0.0.1]"] {
            #expect(throws: (any Error).self) { try VexSettings.normalizedURL(address) }
        }
        #expect(try VexTransport.requireHTTPS(VexSettings.normalizedURL("https://vex.example")).absoluteString == "https://vex.example")
    }
    @Test func legacyCredentialIdentityCanBeRemovedWithoutPermittingHTTPTransport() throws {
        let stored = "HTTP://VEX.EXAMPLE:80/"
        #expect(try VexSettings.canonicalURL(stored).absoluteString == "http://vex.example")
        #expect(throws: (any Error).self) { try VexSettings.normalizedURL(stored) }
        for malformed in ["http://user:password@vex.example", "http://vex.example?token=input", "http://vex.example/i/input"] {
            #expect(throws: (any Error).self) { try VexSettings.canonicalURL(malformed) }
        }
    }
    @Test func previewLinkUsesOnlyExplicitTargetAndNormalizesServer() throws {
        var parts = URLComponents()
        parts.scheme = "ruri"; parts.host = "vex"
        parts.queryItems = [.init(name: "server", value: "HTTPS://VEX.EXAMPLE:443/"), .init(name: "project", value: "example"), .init(name: "room", value: "c932eab71-fabric")]
        let link = try VexPreviewLink(#require(parts.url))
        #expect(link.server.absoluteString == "https://vex.example")
        #expect(link.project == "example")
        #expect(link.room == "c932eab71-fabric")
        for extra in [URLQueryItem(name: "server", value: "https://other.example"), .init(name: "token", value: "test-input")] {
            var invalid = parts
            invalid.queryItems?.append(extra)
            #expect(throws: (any Error).self) { try VexPreviewLink(#require(invalid.url)) }
        }
        for address in ["https://user:password@vex.example", "https://vex.example?token=input", "https://vex.example#fragment"] {
            var invalid = parts
            invalid.queryItems?[0] = .init(name: "server", value: address)
            #expect(throws: (any Error).self) { try VexPreviewLink(#require(invalid.url)) }
        }
        for raw in ["ruri://user@vex?server=https://vex.example&project=example&room=main-fabric",
                    "ruri://vex?server=https://vex.example&project=example&room=main-fabric#fragment",
                    "ruri://vex?server=https://vex.example&project=bad--project&room=main-fabric",
                    "ruri://vex?server=https://vex.example&project=example&room=../room"] {
            #expect(throws: (any Error).self) { try VexPreviewLink(#require(URL(string: raw))) }
        }
    }

    @Test func deviceAuthorizationValidatesLinksIntervalAndExpiryFormat() throws {
        let deadline = "2026-10-18T12:00:00Z"
        let authorization = VexDeviceAuthorization(handle: "device-input", userCode: "ABCD-EFGH", verificationUri: URL(string: "https://github.com/login/device")!,
                                                  expiresAt: deadline, interval: 5)
        #expect(try authorization.deadline() == Date.ISO8601FormatStyle().parse(deadline))
        #expect(authorization.verificationURL == authorization.verificationUri)
        for raw in ["http://github.com/login/device", "https://user@github.com/login/device", "https://github.com/login/device#secret"] {
            let invalid = VexDeviceAuthorization(handle: "device-input", userCode: "ABCD-EFGH", verificationUri: URL(string: raw)!,
                                                 expiresAt: deadline, interval: 5)
            #expect(throws: (any Error).self) { try invalid.deadline() }
        }
        for interval in [0, 61] {
            let invalid = VexDeviceAuthorization(handle: "device-input", userCode: "ABCD-EFGH", verificationUri: authorization.verificationUri,
                                                 expiresAt: deadline, interval: interval)
            #expect(throws: (any Error).self) { try invalid.deadline() }
        }
    }

    @Test func clientFingerprintIgnoresFileNamesOrderDuplicatesAndServerAgent() throws {
        func file(_ name: String, digest: String, side: String = "both") -> VexBuild.File {
            .init(name: name, sha1: String(repeating: "a", count: 40), sha256: String(repeating: "b", count: 64),
                  sha512: digest, size: 20, side: side, url: "/v2/projects/example/builds/fabric-test/files/" + name)
        }
        func build(_ files: [VexBuild.File], version: String = "0.19.5") -> VexBuild {
            .init(project: "example", id: "fabric-test", sha: "test", loader: "fabric", status: .ready, attempt: 1,
                  queuedAt: "2026-10-18T00:00:00Z", startedAt: nil, finishedAt: nil, minecraft: "26.3", loaderVersion: version,
                  java: 25, builtAt: nil, durationSec: nil, modIds: [], files: files, log: "", lastError: nil)
        }
        let a = String(repeating: "1", count: 128), b = String(repeating: "2", count: 128)
        let original = build([file("one.jar", digest: a), file("two.jar", digest: b)])
        #expect(try VexMRPack.computedFingerprint(original) == "e6913c10065a3d1efd42dec55173b7cf8373a9299f438b601611b45ab128d3a9")
        let reordered = build([file("second.jar", digest: b), file("first.jar", digest: a), file("duplicate.jar", digest: a), file("agent.jar", digest: b, side: "server")])
        #expect(try VexMRPack.computedFingerprint(original) == VexMRPack.computedFingerprint(reordered))
        #expect(try VexMRPack.computedFingerprint(original) != VexMRPack.computedFingerprint(build(original.files, version: "0.19.6")))
        var accepted = original
        accepted.clientFingerprint = try VexMRPack.computedFingerprint(original)
        #expect(try VexMRPack.fingerprint(accepted) == accepted.clientFingerprint)
        accepted.clientFingerprint = String(repeating: "0", count: 64)
        #expect(throws: (any Error).self) { try VexMRPack.fingerprint(accepted) }
        #expect(throws: (any Error).self) { try VexMRPack.computedFingerprint(build(original.files, version: "\"unsafe")) }
    }
}
