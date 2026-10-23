import Foundation
import RuriCore
import RuriLocalization

public struct VexPreviewLink: Identifiable, Equatable, Sendable {
    public let server: URL
    public let project: String
    public let room: String
    public var id: String { server.absoluteString + "/" + project + "/" + room }
    public init(_ url: URL) throws {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "ruri", parts.host == "vex", parts.path.isEmpty,
              parts.port == nil, parts.user == nil, parts.password == nil, parts.fragment == nil,
              let items = parts.queryItems, items.count == 3,
              Set(items.map(\.name)) == ["server", "project", "room"],
              let address = items.first(where: { $0.name == "server" })?.value,
              let project = items.first(where: { $0.name == "project" })?.value,
              let room = items.first(where: { $0.name == "room" })?.value,
              VexClient.validProject(project),
              room.range(of: "^[a-z0-9][a-z0-9-]{0,62}$", options: .regularExpression) != nil else {
            throw RuriError.message(Messages.VexDevices.invalidLink)
        }
        server = try VexSettings.normalizedURL(address)
        self.project = project
        self.room = room
    }
}
