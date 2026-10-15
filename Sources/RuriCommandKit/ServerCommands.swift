import Foundation
import RuriCore
import RuriLocalization

extension CLIApplication {
    @MainActor static func manageServer(_ request: CommandRequest) async throws -> Value {
        let (state, paths, _) = try await context(request)
        let action = request.spec.path.last!
        func address(_ raw: String) throws -> ServerAddress {
            do { return try ServerAddress(raw) } catch { throw OperationFailure("INVALID_ARGUMENT", error.localizedDescription) }
        }
        if action == "query" {
            let endpoint = try address(request.operand())
            do { return statusValue(try await ServerStatusClient.query(endpoint), address: endpoint) }
            catch is CancellationError { throw CancellationError() }
            catch { throw OperationFailure("NETWORK_ERROR", error.localizedDescription, retryable: true) }
        }
        if action == "list" {
            if let instance = request.string("instance") {
                let id = try uuid(instance); _ = try InstanceService(paths: paths).resolve(id: id)
                let snapshot = try ServerListManager(paths: paths, instanceID: id).snapshot()
                return request.page(snapshot.entries.filter { matchesServer($0.name, $0.address, request: request) }.map(serverEntryValue))
            }
            let library = try ServerLibrary.load(paths: paths, state: state)
            var result = request.page(library.items.filter { matchesServer($0.name, $0.address.authority, request: request) }.map { item in
                .object(["id": .string(item.id), "address": .string(item.address.authority), "name": .string(item.name), "favorite": .bool(item.preference?.favorite == true), "saved": .bool(item.preference?.saved == true),
                         "instanceIDs": .array(item.instanceIDs.map { .string($0.uuidString) }), "notes": .string(item.preference?.notes ?? ""), "preferredInstanceID": .text(item.preference?.preferredInstanceID?.uuidString)])
            }).object!
            result["warnings"] = .array(library.errors.sorted { $0.key.uuidString < $1.key.uuidString }.map { .string($0.key.uuidString + ": " + $0.value) })
            return .object(result)
        }
        if action == "favorite" || action == "preferences" || (action == "add" && request.string("instance") == nil) {
            let endpoint = try address(request.operand())
            var preference = state.servers?.first { $0.id == endpoint.key } ?? .init(address: endpoint)
            if action == "add" { preference.saved = true; preference.alias = request.string("name") ?? preference.alias }
            if action == "favorite" { preference.favorite = request.string("value") == "true" }
            if let saved = request.string("saved") { preference.saved = saved == "true" }
            if let alias = request.string("alias") { preference.alias = alias }
            if let notes = request.string("notes") { preference.notes = notes }
            if let target = request.string("preferred-instance") {
                preference.preferredInstanceID = target == "none" ? nil : try uuid(target)
                if let id = preference.preferredInstanceID { _ = try InstanceService(paths: paths).resolve(id: id) }
            }
            guard preference.alias.utf8.count <= 1024, preference.notes.utf8.count <= 16384 else { throw OperationFailure("INVALID_ARGUMENT", Messages.Servers.invalidList.localized) }
            if !request.dryRun { try ServerLibrary.save(preference, paths: paths) }
            return .object(["address": .string(endpoint.authority), "favorite": .bool(preference.favorite), "saved": .bool(preference.saved), "name": .string(preference.alias), "notes": .string(preference.notes), "preferredInstanceID": .text(preference.preferredInstanceID?.uuidString)])
        }
        let id = try uuid(action == "add" ? request.required("instance") : request.operand())
        _ = try InstanceService(paths: paths).resolve(id: id)
        let manager = ServerListManager(paths: paths, instanceID: id), snapshot = try manager.snapshot()
        let change: ServerListChange
        if action == "add" {
            let endpoint = try address(request.operand())
            change = .add(name: request.string("name") ?? endpoint.authority, address: endpoint, resourcePacks: request.string("resource-packs").flatMap(ServerResourcePacks.init(rawValue:)) ?? .ask)
        } else {
            guard let row = Int(try request.operand(1)), let entry = snapshot.entries.first(where: { $0.id == row }) else { throw OperationFailure("NOT_FOUND", Messages.Servers.notFound.localized) }
            switch action {
            case "edit": change = .edit(id: row, name: request.string("name") ?? entry.name, address: try address(request.string("address") ?? entry.address), resourcePacks: request.string("resource-packs").flatMap(ServerResourcePacks.init(rawValue:)) ?? entry.resourcePacks)
            case "remove": change = .remove(id: row)
            case "move":
                guard let target = Int(try request.operand(2)), snapshot.entries.indices.contains(target) else { throw OperationFailure("INVALID_ARGUMENT", Messages.Servers.notFound.localized) }
                change = .move(id: row, to: target)
            default: throw OperationFailure("INVALID_ARGUMENT", Messages.Servers.notFound.localized)
            }
        }
        let result = try manager.apply(change, to: snapshot, dryRun: request.dryRun)
        return .object(["instanceID": .string(id.uuidString), "revision": .string(result.revision), "items": .array(result.entries.map(serverEntryValue)), "dryRun": .bool(request.dryRun)])
    }
    private static func matchesServer(_ name: String, _ address: String, request: CommandRequest) -> Bool {
        guard let search = request.string("search"), !search.isEmpty else { return true }
        return name.localizedCaseInsensitiveContains(search) || address.localizedCaseInsensitiveContains(search)
    }
    static func serverEntryValue(_ entry: ServerEntry) -> Value {
        .object(["id": .integer(entry.id), "name": .string(entry.name), "address": .string(entry.address), "resourcePacks": .string(entry.resourcePacks.rawValue), "validAddress": .bool(entry.endpoint != nil)])
    }
    static func statusValue(_ status: ServerStatus, address: ServerAddress) -> Value {
        .object(["address": .string(address.authority), "description": .string(status.description), "version": .text(status.version), "protocolVersion": status.protocolVersion.map(Value.integer) ?? .null,
                 "online": status.online.map(Value.integer) ?? .null, "maximum": status.maximum.map(Value.integer) ?? .null, "latencyMilliseconds": status.latencyMilliseconds.map(Value.integer) ?? .null,
                 "playerSample": .array(status.playerSample.map(Value.string)), "queriedAt": .string(status.queriedAt.ISO8601Format())])
    }
}
