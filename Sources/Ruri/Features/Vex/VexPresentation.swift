import Foundation
import Observation
import RuriCore
import RuriLocalization

struct VexConnectionIdentity: Equatable {
    let enabled: Bool
    let servers: [VexServer]
    init(settings: VexSettings?) {
        enabled = settings?.enabled ?? false
        servers = settings?.servers ?? []
    }
}

@MainActor @Observable final class VexProjectPresentation: Identifiable {
    nonisolated let id: String
    var project: VexProject
    var rooms: [VexRoom] = []
    var builds: [VexBuild] = []
    var branches: [VexBranch] = []
    var refreshID = UUID()
    let client: VexClient
    init(project: VexProject, client: VexClient) { id = project.id; self.project = project; self.client = client }
}

@MainActor @Observable final class VexServerConnection: Identifiable {
    enum Status { case loggedOut, loggedIn, unreachable, expired }
    nonisolated let id: String
    var server: VexServer
    var status: Status = .loggedOut
    var user: VexUser?
    var meta: VexMeta?
    var projects: [VexProjectPresentation] = []
    var nodes: [VexNode] = []
    var error: String?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var subscribers: [UUID: AsyncThrowingStream<VexEvent, Error>.Continuation] = [:]
    init(_ server: VexServer) { id = server.id; self.server = server }
    var statusText: String {
        switch status {
        case .loggedOut: Messages.VexLogin.notLoggedIn.localized
        case .loggedIn: Messages.VexLogin.loggedIn(user?.id ?? server.userID ?? "").localized
        case .unreachable: Messages.VexLogin.cannotConnect.localized
        case .expired: Messages.VexLogin.expired.localized
        }
    }
    func stop() {
        task?.cancel(); task = nil
        for subscriber in subscribers.values { subscriber.finish(throwing: CancellationError()) }
        subscribers = [:]
    }
    func events() -> AsyncThrowingStream<VexEvent, Error> {
        let id = UUID()
        let (stream, continuation) = AsyncThrowingStream<VexEvent, Error>.makeStream()
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in Task { @MainActor in self?.subscribers.removeValue(forKey: id) } }
        return stream
    }
    func start(paths: LauncherPaths) {
        stop()
        guard server.userID != nil else { status = .loggedOut; projects = []; user = nil; return }
        task = Task {
            var retry = 0
            while !Task.isCancelled {
                do {
                    let client = try server.client()
                    user = try await client.me()
                    meta = try await client.meta()
                    if let zone = meta?.zone { try VexSettings.remember(zone: zone, paths: paths) }
                    let available = try await client.projects()
                    var next: [VexProjectPresentation] = []
                    for project in available {
                        let current = try VexProjectPresentation(project: project, client: client.selecting(project: project.id))
                        current.branches = try await current.client.branches()
                        next.append(current)
                    }
                    try Task.checkCancellation()
                    projects = next
                    if user?.admin == true { nodes = try await client.nodes() }
                    status = .loggedIn; error = nil; retry = 0
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        group.addTask { [weak self] in
                            for try await event in VexEventStream(client: client).events() {
                                try Task.checkCancellation()
                                try await self?.receive(event)
                            }
                        }
                        group.addTask { [weak self] in
                            while !Task.isCancelled {
                                try await Task.sleep(for: .seconds(15))
                                try await self?.refreshSession(client, paths: paths)
                            }
                        }
                        defer { group.cancelAll() }
                        _ = try await group.next()
                    }
                } catch is CancellationError { return }
                catch {
                    if Task.isCancelled { return }
                    record(error)
                    if status == .expired {
                        for subscriber in subscribers.values { subscriber.finish(throwing: error) }
                        subscribers = [:]
                        return
                    }
                }
                do { try await Task.sleep(for: VexEventStream.retryDelay(attempt: retry)); retry += 1 }
                catch { return }
            }
        }
    }
    func record(_ failure: any Error) {
        error = VexAuthentication.message(for: failure)
        if let http = failure as? VexHTTPError, http.status == 401 { status = .expired }
        else if failure is URLError || ((failure as? VexHTTPError)?.status ?? 0) >= 500 { status = .unreachable }
    }
    private func refreshSession(_ client: VexClient, paths: LauncherPaths) async throws {
        user = try await client.me()
        let currentMeta = try await client.meta()
        if let zone = currentMeta.zone { try VexSettings.remember(zone: zone, paths: paths) }
        meta = currentMeta
        let available = try await client.projects()
        var next: [VexProjectPresentation] = []
        for project in available {
            if let existing = projects.first(where: { $0.id == project.id }) {
                existing.project = project
                next.append(existing)
            } else {
                let added = try VexProjectPresentation(project: project, client: client.selecting(project: project.id))
                added.rooms = try await added.client.rooms()
                added.builds = try await added.client.builds()
                added.branches = try await added.client.branches()
                next.append(added)
            }
        }
        projects = next
        nodes = user?.admin == true ? try await client.nodes() : []
    }
    private func receive(_ event: VexEvent) async throws {
        for subscriber in subscribers.values { subscriber.yield(event) }
        switch event {
        case .sync(let sync):
            for project in projects {
                project.rooms = sync.rooms.filter { $0.project == project.id }
                project.builds = sync.builds.filter { $0.project == project.id }
            }
        case .room(let room): if let project = projects.first(where: { $0.id == room.project }) { replace(room, in: &project.rooms) }
        case .build(let build): if let project = projects.first(where: { $0.id == build.project }) { replace(build, in: &project.builds) }
        case .ready, .failed: break
        case .git:
            for project in projects { project.branches = try await project.client.branches(); project.refreshID = UUID() }
        }
    }
    private func replace<T: Identifiable>(_ item: T, in values: inout [T]) {
        if let index = values.firstIndex(where: { $0.id == item.id }) { values[index] = item }
        else { values.append(item) }
    }
    func refresh(_ project: VexProjectPresentation? = nil) async {
        do {
            for item in project.map({ [$0] }) ?? projects {
                try await item.client.refreshGit()
                item.branches = try await item.client.branches()
                item.rooms = try await item.client.rooms()
                item.builds = try await item.client.builds()
                item.refreshID = UUID()
            }
            error = nil
        } catch { if !Task.isCancelled { record(error) } }
    }
    func testConnection(paths: LauncherPaths) async {
        do {
            meta = try await VexClient(baseURL: VexSettings.normalizedURL(server.baseURL)).meta()
            error = nil
            start(paths: paths)
        } catch { status = .unreachable; record(error) }
    }
}

@MainActor @Observable final class VexPresentation {
    var connections: [VexServerConnection] = []
    var progress: VexJoinProgress?
    var joiningServer: String?
    @ObservationIgnored private var joining: Task<Void, Never>?
    var hidesGroupTitles: Bool { connections.count == 1 && connections.first?.projects.count == 1 }
    func stop() {
        joining?.cancel(); joining = nil
        for connection in connections { connection.stop() }
        connections = []; progress = nil; joiningServer = nil
    }
    func configure(settings: VexSettings, paths: LauncherPaths) {
        guard settings.enabled else { stop(); return }
        for previous in connections where !settings.servers.contains(where: { $0.id == previous.id }) { previous.stop() }
        connections = settings.servers.map { server in
            if let current = connections.first(where: { $0.id == server.id }) {
                let changed = current.server.sessionRevision != server.sessionRevision || current.server.userID != server.userID
                current.server = server
                if changed {
                    if let url = URL(string: server.baseURL) { VexTokenStore.invalidate(baseURL: url) }
                    current.start(paths: paths)
                }
                return current
            }
            let connection = VexServerConnection(server)
            connection.start(paths: paths)
            return connection
        }
    }
    func join(_ room: VexRoom, server: VexServerConnection, model: AppModel) {
        guard joining == nil, let project = server.projects.first(where: { $0.id == room.project }) else { return }
        guard model.activeAccount != nil else { model.showAccount = true; return }
        joiningServer = server.id
        let events = server.events()
        joining = Task {
            defer { joining = nil; progress = nil; joiningServer = nil }
            do {
                let result = try await VexLaunchCoordinator(client: project.client, paths: model.paths)
                    .prepare(roomID: room.id, events: events) { value in await MainActor.run { self.progress = value } }
                try Task.checkCancellation()
                guard model.state.settings.experimental?.vex?.enabled == true else { throw CancellationError() }
                let address = try ServerAddress(result.room.host + ":" + String(result.room.port))
                _ = try await LaunchService(paths: model.paths).start(instanceID: result.prepared.instance.id, destination: .server(address))
            } catch is CancellationError { }
            catch { server.record(error) }
        }
    }
    func cancelJoin() { joining?.cancel() }
}
