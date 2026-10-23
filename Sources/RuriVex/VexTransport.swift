import Foundation
import Darwin
import RuriCore
import RuriLocalization

public enum VexTransport {
    public static func isLoopback(_ host: String) -> Bool {
        if host.lowercased() == "localhost" { return true }
        let host = host.hasPrefix("[") && host.hasSuffix("]") ? String(host.dropFirst().dropLast()) : host
        var address = in_addr()
        if inet_pton(AF_INET, host, &address) == 1 { return UInt32(bigEndian: address.s_addr) >> 24 == 127 }
        var address6 = in6_addr(), loopback = in6addr_loopback
        guard inet_pton(AF_INET6, host, &address6) == 1 else { return false }
        return memcmp(&address6, &loopback, MemoryLayout<in6_addr>.size) == 0
    }
    public static func requireHTTPS(_ url: URL) throws -> URL {
        guard url.scheme == "https" else { throw RuriError.message(Messages.VexNetwork.httpsRequired) }
        return url
    }
}
