import Foundation
import RuriLocalization

public struct VexServerPolicy: Sendable {
    public let settings: VexSettings
    public init(settings: VexSettings) { self.settings = settings }
    public func contains(_ address: ServerAddress) -> Bool {
        settings.knownZones.contains { address.host == $0 || address.host.hasSuffix("." + $0) }
    }
    public func hides(_ item: ServerLibraryItem) -> Bool {
        guard settings.enabled else { return false }
        if contains(item.address) { return true }
        let preferred = item.preference?.preferredInstanceID.map { [$0] } ?? []
        let associated = Set(item.instanceIDs + item.playedInstanceIDs + preferred)
        return !associated.isEmpty && associated.isSubset(of: Set(settings.instances.values))
    }
    // 调用方持有 GameRunLease，限定在带有 Vex 实例标记的游戏目录内。
    public static func cleanBeforeLaunch(paths: LauncherPaths, instanceID: UUID, settings: VexSettings) throws {
        guard settings.enabled, settings.instances.values.contains(instanceID) else { return }
        let marker = try LauncherPaths.safePath("vex-instance.json", within: paths.instance(instanceID))
        let value = try JSONDecoder().decode(VexInstanceManager.Marker.self, from: Data(contentsOf: marker))
        guard settings.instances[value.key] == instanceID else { throw RuriError.message(Messages.Vex.invalidResponse) }
        let snapshot = try ServerListManager(paths: paths, instanceID: instanceID).snapshot()
        guard let original = snapshot.original else { return }
        var document = snapshot.document
        let policy = Self(settings: settings)
        document.entries.removeAll { fields in
            guard fields.first(where: { $0.name == "hidden" })?.value.integer.map({ $0 != 0 }) == true,
                  let address = fields.first(where: { $0.name == "ip" })?.value.string,
                  let endpoint = try? ServerAddress(address) else { return false }
            return policy.contains(endpoint)
        }
        guard document.entries.count != snapshot.document.entries.count else { return }
        let file = try LauncherPaths.safePath("servers.dat", within: paths.game(instanceID))
        guard paths.game(instanceID).standardizedFileURL.resolvingSymlinksInPath() == snapshot.directory,
              try RunDirectoryCopyGuard.read(file, limit: 8 * 1024 * 1024) == original else {
            throw RuriError.message(Messages.Servers.listChanged)
        }
        let backup = try LauncherPaths.safePath("servers.dat.ruri-backup", within: paths.game(instanceID))
        try original.write(to: backup, options: .atomic)
        try document.encoded().write(to: file, options: .atomic)
    }
    public static func recentlyClosed(_ rooms: [VexRoom], now: Date = Date()) -> [VexRoom] {
        let oldest = now.addingTimeInterval(-7 * 24 * 60 * 60)
        return rooms.filter { room in
            guard ["commit", "world"].contains(room.kind), room.state == .closed, let timestamp = room.closedAt,
                  let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: timestamp.contains(".")).parse(timestamp) else { return false }
            return date >= oldest && date <= now
        }.sorted { ($0.closedAt ?? "") > ($1.closedAt ?? "") }.prefix(10).map { $0 }
    }
}
