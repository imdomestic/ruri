import Foundation
import RuriLocalization

public struct ChorusServerPolicy: Sendable {
    public static let legacyZone = "100-64-0-43.sslip.io"
    public let zones: Set<String>
    public let managedInstanceIDs: Set<UUID>

    public init(settings: ChorusSettings) throws {
        zones = try ChorusServerCleanupPlan.normalizedZones(settings.knownZones + [Self.legacyZone])
        managedInstanceIDs = Set(settings.instances.values)
    }

    public func contains(_ address: ServerAddress) -> Bool {
        ChorusServerCleanupPlan.contains(address, zones: zones)
    }

    public func hides(_ item: ServerLibraryItem) -> Bool {
        if contains(item.address) { return true }
        let preferred = item.preference?.preferredInstanceID.map { [$0] } ?? []
        let associated = Set(item.instanceIDs + item.playedInstanceIDs + preferred)
        return !associated.isEmpty && associated.isSubset(of: managedInstanceIDs)
    }

    public static func recentlyClosed(_ rooms: [ChorusRoom], now: Date = Date()) throws -> [ChorusRoom] {
        let oldest = now.addingTimeInterval(-7 * 24 * 60 * 60)
        var candidates: [(ChorusRoom, Date)] = []
        for room in rooms where ["commit", "asset"].contains(room.kind) && room.state == .closed {
            guard let value = room.closedAt else { continue }
            let date = try Date.ISO8601FormatStyle(includingFractionalSeconds: value.contains(".")).parse(value)
            if date >= oldest && date <= now { candidates.append((room, date)) }
        }
        return candidates.sorted { $0.1 == $1.1 ? $0.0.id < $1.0.id : $0.1 > $1.1 }.prefix(10).map(\.0)
    }
}
