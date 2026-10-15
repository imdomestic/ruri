import Foundation
import CryptoKit
import RuriLocalization

public enum ServerResourcePacks: String, Codable, CaseIterable, Sendable {
    case ask, always, never
    public var title: String { switch self { case .ask: Messages.Servers.ask.localized; case .always: Messages.Servers.always.localized; case .never: Messages.Servers.never.localized } }
}

public struct ServerEntry: Identifiable, Equatable, Sendable {
    /// Row identity is valid only in the snapshot it came from; duplicates are preserved.
    public let id: Int
    public let name: String
    public let address: String
    public let resourcePacks: ServerResourcePacks
    public let icon: Data?
    public var hidden: Bool = false
    public var endpoint: ServerAddress? { try? ServerAddress(address) }
}

public struct ServerListSnapshot: Sendable {
    public let directory: URL
    public let entries: [ServerEntry]
    public let revision: String
    let original: Data?
    let document: ServerNBTDocument
}

public enum ServerListChange: Sendable {
    case add(name: String, address: ServerAddress, resourcePacks: ServerResourcePacks)
    case edit(id: Int, name: String, address: ServerAddress, resourcePacks: ServerResourcePacks)
    case remove(id: Int)
    case move(id: Int, to: Int)
}

public struct ServerListManager: Sendable {
    public let paths: LauncherPaths
    public let instanceID: UUID
    public init(paths: LauncherPaths, instanceID: UUID) { self.paths = paths; self.instanceID = instanceID }
    public func snapshot() throws -> ServerListSnapshot {
        try InstanceLocationLease.requireCurrentDirectory(paths: paths, instanceID: instanceID)
        try paths.validateBinding(InstanceService(paths: paths).resolve(id: instanceID))
        try paths.validateInstanceLocation(instanceID)
        try RunDirectoryCopyGuard.requireAvailable(paths: paths, instanceID: instanceID)
        let directory = paths.game(instanceID).standardizedFileURL.resolvingSymlinksInPath()
        let data = try read()
        let document = try data.map(NBTReader.serverDocument) ?? ServerNBTDocument.empty()
        let entries = document.entries.enumerated().map { index, fields in
            func value(_ name: String) -> NBTValue? { fields.first { $0.name == name }?.value }
            let resource = fields.first { $0.name == "acceptTextures" && $0.type == 1 }?.value.integer
            let icon = value("icon")?.string.flatMap { $0.utf8.count <= 1_048_576 ? Data(base64Encoded: $0) : nil }
            return ServerEntry(id: index, name: value("name")?.string ?? "", address: value("ip")?.string ?? "",
                               resourcePacks: resource.map { $0 == 0 ? .never : .always } ?? .ask, icon: icon,
                               hidden: value("hidden")?.integer.map { $0 != 0 } ?? false)
        }
        let revision = data.map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() } ?? "missing"
        return .init(directory: directory, entries: entries, revision: revision, original: data, document: document)
    }
    @discardableResult public func apply(_ change: ServerListChange, to snapshot: ServerListSnapshot, dryRun: Bool = false) throws -> ServerListSnapshot {
        // This lease covers all instances sharing a game directory, as well as
        // directory relocation. Never race the game's in-memory server list.
        let lease = try dryRun ? nil : GameRunLease.acquire(paths: paths, instanceID: instanceID)
        try paths.validateBinding(InstanceService(paths: paths).resolve(id: instanceID))
        defer { withExtendedLifetime(lease) {} }
        guard paths.game(instanceID).standardizedFileURL.resolvingSymlinksInPath().path == snapshot.directory.path,
              try read() == snapshot.original else { throw RuriError.message(Messages.Servers.listChanged) }
        var document = snapshot.document
        func fields(_ name: String, _ address: ServerAddress, _ packs: ServerResourcePacks, original: [ServerNBTDocument.Field]) throws -> [ServerNBTDocument.Field] {
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name.utf8.count <= 1024 else { throw RuriError.message(Messages.Servers.invalidName) }
            let previousAddress = original.first { $0.name == "ip" }?.value.string.flatMap { try? ServerAddress($0) }
            var replaced: Set<String> = ["name", "ip", "acceptTextures"]
            if previousAddress?.key != address.key { replaced.insert("icon") }
            var result = original.filter { !replaced.contains($0.name) }
            result += [try ServerNBTDocument.string("name", name), try ServerNBTDocument.string("ip", address.authority)]
            if packs != .ask { result.append(try ServerNBTDocument.byte("acceptTextures", packs == .always ? 1 : 0)) }
            return result
        }
        func require(_ id: Int) throws { guard document.entries.indices.contains(id) else { throw RuriError.message(Messages.Servers.notFound) } }
        switch change {
        case let .add(name, address, packs): document.entries.append(try fields(name, address, packs, original: []))
        case let .edit(id, name, address, packs):
            try require(id); document.entries[id] = try fields(name, address, packs, original: document.entries[id])
        case let .remove(id): try require(id); document.entries.remove(at: id)
        case let .move(id, target):
            try require(id); try require(target)
            let row = document.entries.remove(at: id); document.entries.insert(row, at: target)
        }
        try write(document, replacing: snapshot, dryRun: dryRun)
        return try self.snapshot()
    }
    // 调用方 GameSessionRecorder 在整个准备期间持有实例启动租约。
    func chorusCleanupPlanDuringPreparation(policy: ChorusServerPolicy, state: PersistentState) throws -> ChorusServerCleanupPlan? {
        guard policy.managedInstanceIDs.contains(instanceID) else { return nil }
        let directory = paths.game(instanceID).standardizedFileURL.resolvingSymlinksInPath().path
        for instance in state.instances where !policy.managedInstanceIDs.contains(instance.id) {
            guard paths.game(instance.id).standardizedFileURL.resolvingSymlinksInPath().path != directory else {
                throw RuriError.message(Messages.Chorus.sharedDirectory)
            }
        }
        let snapshot = try snapshot()
        return try ChorusServerCleanupPlan(zones: policy.zones, directory: snapshot.directory)
    }
    private func write(_ document: ServerNBTDocument, replacing snapshot: ServerListSnapshot, dryRun: Bool) throws {
        guard paths.game(instanceID).standardizedFileURL.resolvingSymlinksInPath().path == snapshot.directory.path,
              try read() == snapshot.original else { throw RuriError.message(Messages.Servers.listChanged) }
        let updated = try document.encoded()
        if !dryRun {
            try FileManager.default.createDirectory(at: paths.game(instanceID), withIntermediateDirectories: true)
            let file = try LauncherPaths.safePath("servers.dat", within: paths.game(instanceID))
            if let original = snapshot.original {
                let backup = try LauncherPaths.safePath("servers.dat.ruri-backup", within: paths.game(instanceID))
                try original.write(to: backup, options: .atomic)
            }
            guard try read() == snapshot.original else { throw RuriError.message(Messages.Servers.listChanged) }
            try updated.write(to: file, options: .atomic)
        }
    }
    private func read() throws -> Data? {
        let file = try LauncherPaths.safePath("servers.dat", within: paths.game(instanceID))
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try RunDirectoryCopyGuard.read(file, limit: 8 * 1024 * 1024)
    }
}
