import Foundation
import Observation
import RuriCore
import RuriLocalization

@MainActor @Observable final class ChorusPresentation {
    var rooms: [ChorusRoom] = []
    var builds: [ChorusBuild] = []
    var meta: ChorusMeta?
    var nodes: [ChorusNode] = []
    var recentlyClosed: [ChorusRoom] = []
    var refreshing = false
    var error: String?
    var configurationRevision = UUID()
    var gitRevision = UUID()
    var serverLibraryRevision = UUID()
    var joinProgress: ChorusJoinProgress?
    var joinError: String?
    var joining = false
    var log: String?
    var logBuild: ChorusBuild?
    @ObservationIgnored var client: ChorusClient?
    @ObservationIgnored private var joinTask: Task<Void, Never>?

    func observe(paths: LauncherPaths) async {
        error = nil
        do {
            let configured = try ChorusSettings.load(paths: paths).client()
            client = configured
            try acceptMeta(await configured.meta(), paths: paths)
            nodes = try await configured.nodes()
            let polling = Task {
                do {
                    while !Task.isCancelled {
                        try await Task.sleep(for: .seconds(60))
                        nodes = try await configured.nodes()
                        recentlyClosed = try ChorusServerPolicy.recentlyClosed(rooms)
                    }
                } catch is CancellationError {} catch { self.error = error.localizedDescription }
            }
            defer { polling.cancel() }
            for try await event in ChorusEventStream(client: configured).events() {
                switch event {
                case .sync(let sync): try acceptRooms(sync.rooms); builds = sync.builds
                case .room(let room): try upsert(room)
                case .build(let build):
                    builds.removeAll { $0.id == build.id }; builds.append(build)
                case .git: gitRevision = UUID()
                case .ready, .failed: break
                }
            }
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    private func acceptMeta(_ value: ChorusMeta, paths: LauncherPaths) throws {
        try ChorusSettings.remember(zone: value.zone, paths: paths)
        meta = value
        serverLibraryRevision = UUID()
    }
    private func acceptRooms(_ values: [ChorusRoom]) throws {
        let closed = try ChorusServerPolicy.recentlyClosed(values)
        rooms = values.sorted { $0.id < $1.id }
        recentlyClosed = closed
    }
    func upsert(_ room: ChorusRoom) throws {
        try acceptRooms(rooms.filter { $0.id != room.id } + [room])
    }
    func refresh(paths: LauncherPaths) async {
        guard !refreshing, let client else { return }
        refreshing = true; error = nil
        defer { refreshing = false }
        do {
            try await client.refreshGit()
            async let newMeta = client.meta()
            async let newRooms = client.rooms()
            async let newBuilds = client.builds()
            async let newNodes = client.nodes()
            let values = try await (newMeta, newRooms, newBuilds, newNodes)
            try Task.checkCancellation()
            try acceptMeta(values.0, paths: paths)
            try acceptRooms(values.1)
            builds = values.2; nodes = values.3
            gitRevision = UUID()
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    func join(_ room: ChorusRoom, model: AppModel) {
        guard !joining, !model.busy else { return }
        guard model.activeAccount != nil else { model.showAccount = true; return }
        guard let client else { error = Messages.Chorus.tokenRequired.localized; return }
        joining = true; joinProgress = .init(room: room, local: Messages.Chorus.preparing.localized, unmanaged: []); joinError = nil
        joinTask = Task {
            defer { joining = false; joinTask = nil }
            do {
                let result = try await ChorusLaunchCoordinator(client: client, paths: model.basePaths).prepare(roomID: room.id, reopeningClosedRoom: room.state == .closed) { [weak self] value in
                    await MainActor.run { self?.joinProgress = value }
                }
                try Task.checkCancellation()
                model.acceptState(try StateStore.load(model.basePaths))
                if !result.prepared.unmanagedMods.isEmpty {
                    model.report(Messages.Chorus.unmanagedMods(result.prepared.unmanagedMods.joined(separator: ", ")), level: .warning)
                }
                let address = try ServerAddress(result.room.host + ":" + String(result.room.port))
                joinProgress = nil
                model.launch(result.prepared.instance, server: address)
            } catch is CancellationError { joinProgress = nil }
            catch { joinError = error.localizedDescription }
        }
    }
    func cancelJoin() { joinTask?.cancel(); if joinTask == nil { joinProgress = nil; joinError = nil } }
    func change(_ room: ChorusRoom, action: String) {
        guard let client else { return }
        Task { do { try upsert(await client.changeRoom(room.id, action: action)) } catch { self.error = error.localizedDescription } }
    }
    func setLabel(_ room: ChorusRoom, finished: Bool) {
        guard let client else { return }
        Task { do { try upsert(await client.label(room.id, finished: finished)) } catch { self.error = error.localizedDescription } }
    }
    func showBuildLog(_ id: String) {
        guard let client else { return }
        Task {
            do {
                let build = try await client.build(id)
                let text = try await client.log(build: id)
                logBuild = build
                log = text
            } catch { self.error = error.localizedDescription }
        }
    }
}
