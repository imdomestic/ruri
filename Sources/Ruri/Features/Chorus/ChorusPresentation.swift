import Foundation
import Observation
import RuriCore
import RuriLocalization

@MainActor @Observable final class ChorusPresentation {
    var rooms: [ChorusRoom] = []
    var builds: [ChorusBuild] = []
    var meta: ChorusMeta?
    var error: String?
    var configurationRevision = UUID()
    var gitRevision = UUID()
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
            meta = try await configured.meta()
            for try await event in ChorusEventStream(client: configured).events() {
                switch event {
                case .sync(let sync): rooms = sync.rooms; builds = sync.builds
                case .room(let room): upsert(room)
                case .build(let build):
                    builds.removeAll { $0.id == build.id }; builds.append(build)
                case .git: gitRevision = UUID()
                case .ready, .failed: break
                }
            }
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    func upsert(_ room: ChorusRoom) {
        rooms.removeAll { $0.id == room.id }; rooms.append(room); rooms.sort { $0.id < $1.id }
    }
    func join(_ room: ChorusRoom, model: AppModel) {
        guard !joining, !model.busy else { return }
        guard model.activeAccount != nil else { model.showAccount = true; return }
        guard let client else { error = Messages.Chorus.tokenRequired.localized; return }
        joining = true; joinProgress = .init(room: room, local: Messages.Chorus.preparing.localized, unmanaged: []); joinError = nil
        joinTask = Task {
            defer { joining = false; joinTask = nil }
            do {
                let result = try await ChorusLaunchCoordinator(client: client, paths: model.basePaths).prepare(roomID: room.id) { [weak self] value in
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
        Task { do { upsert(try await client.changeRoom(room.id, action: action)) } catch { self.error = error.localizedDescription } }
    }
    func setLabel(_ room: ChorusRoom, finished: Bool) {
        guard let client else { return }
        Task { do { upsert(try await client.label(room.id, finished: finished)) } catch { self.error = error.localizedDescription } }
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
