import Foundation
import Observation
import RuriCore
import RuriVex
import RuriExtensionKit
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
    var pulls: [VexPull] = []
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
    var eventConnection: VexEventConnectionStatus.State = .idle
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let probe = VexOperation()
    @ObservationIgnored private var eventConnectionID = UUID()
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
        probe.cancel()
        task?.cancel(); task = nil
        eventConnectionID = UUID(); eventConnection = .idle
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
        let connectionID = eventConnectionID
        task = Task {
            var retry = 0
            while !Task.isCancelled {
                do {
                    _ = try VexTransport.requireHTTPS(VexSettings.normalizedURL(server.baseURL))
                    let client = try server.client()
                    user = try await client.me()
                    meta = try await client.meta()
                    if let zone = meta?.zone { try VexSettings.remember(zone: zone, paths: paths) }
                    let available = try await client.projects()
                    var next: [VexProjectPresentation] = []
                    for project in available {
                        let current = try VexProjectPresentation(project: project, client: client.selecting(project: project.id))
                        current.branches = try await current.client.branches()
                        current.pulls = try await current.client.pulls()
                        next.append(current)
                    }
                    try Task.checkCancellation()
                    projects = next
                    if user?.admin == true { nodes = try await client.nodes() }
                    status = .loggedIn; error = nil; retry = 0
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        group.addTask { [weak self] in
                            for try await event in VexEventStream(client: client).events(connectionChanged: { [weak self] state in
                                await self?.updateEventConnection(state, id: connectionID)
                            }) {
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
    private func updateEventConnection(_ state: VexEventConnectionStatus.State, id: UUID) {
        guard eventConnectionID == id else { return }
        eventConnection = state
    }
    var eventConnectionNotice: String? { status == .loggedIn ? eventConnection.message?.localized : nil }
    func record(_ failure: any Error) {
        guard !(failure is CancellationError), (failure as? URLError)?.code != .cancelled else { return }
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
                existing.pulls = try await existing.client.pulls()
                next.append(existing)
            } else {
                let added = try VexProjectPresentation(project: project, client: client.selecting(project: project.id))
                added.rooms = try await added.client.rooms()
                added.builds = try await added.client.builds()
                added.branches = try await added.client.branches()
                added.pulls = try await added.client.pulls()
                next.append(added)
            }
        }
        projects = next
        nodes = user?.admin == true ? try await client.nodes() : []
        if status == .unreachable { status = .loggedIn; error = nil }
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
            for project in projects {
                project.branches = try await project.client.branches()
                project.pulls = try await project.client.pulls()
                project.refreshID = UUID()
            }
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
                item.pulls = try await item.client.pulls()
                item.rooms = try await item.client.rooms()
                item.builds = try await item.client.builds()
                item.refreshID = UUID()
            }
            error = nil
        } catch { if !Task.isCancelled { record(error) } }
    }
    func testConnection(paths: LauncherPaths) {
        probe.cancel()
        probe.start { id in
            do {
                let value = try await VexClient(baseURL: VexTransport.requireHTTPS(VexSettings.normalizedURL(self.server.baseURL))).meta()
                try Task.checkCancellation()
                guard self.probe.owns(id) else { return }
                self.meta = value
                self.error = nil
                self.probe.finish(id)
                self.start(paths: paths)
            } catch is CancellationError { }
            catch {
                guard self.probe.owns(id) else { return }
                self.status = .unreachable
                self.record(error)
            }
        }
    }
}

@MainActor @Observable final class VexPresentation {
    var settings = VexSettings()
    var connections: [VexServerConnection] = []
    var progress: VexJoinProgress?
    var joiningServer: String?
    @ObservationIgnored private let joining = VexOperation()
    @ObservationIgnored private let authentication = VexOperation()
    @ObservationIgnored private var authenticationOwner: UUID?
    @ObservationIgnored private var acceptsAuthentication = false
    var hidesGroupTitles: Bool { connections.count == 1 && connections.first?.projects.count == 1 }
    func stop() {
        acceptsAuthentication = false
        authenticationOwner = nil
        authentication.cancel()
        joining.cancel()
        for connection in connections { connection.stop() }
        connections = []; progress = nil; joiningServer = nil
    }
    func configure(settings: VexSettings, paths: LauncherPaths) {
        self.settings = settings
        guard settings.enabled else { stop(); return }
        acceptsAuthentication = true
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
    @discardableResult
    func startAuthentication(owner: UUID, _ operation: @escaping @MainActor (UUID) async -> Void) -> Bool {
        guard acceptsAuthentication, settings.enabled else { return false }
        if authenticationOwner != owner {
            authenticationOwner = nil
            authentication.cancel()
        }
        guard !authentication.isRunning else { return false }
        authenticationOwner = owner
        return authentication.start { id in
            await operation(id)
            if self.ownsAuthentication(owner: owner, operation: id) { self.authenticationOwner = nil }
        }
    }
    func ownsAuthentication(owner: UUID, operation: UUID) -> Bool {
        acceptsAuthentication && settings.enabled && authenticationOwner == owner && authentication.owns(operation)
    }
    func cancelAuthentication(owner: UUID) {
        guard authenticationOwner == owner else { return }
        authenticationOwner = nil
        authentication.cancel()
    }
    func join(_ room: VexRoom, server: VexServerConnection, host: ExperimentalHost) {
        guard !joining.isRunning, let project = server.projects.first(where: { $0.id == room.project }) else { return }
        guard host.accountAvailable else { host.openAccount(); return }
        joiningServer = server.id
        let events = server.events()
        joining.start { id in
            defer {
                if self.joining.owns(id) { self.progress = nil; self.joiningServer = nil }
            }
            do {
                let result = try await VexLaunchCoordinator(client: project.client, paths: host.paths)
                    .prepare(roomID: room.id, events: events) { value in
                        await MainActor.run { if self.joining.owns(id) { self.progress = value } }
                    }
                try Task.checkCancellation()
                guard self.joining.owns(id), host.vexEnabled else { throw CancellationError() }
                let address = try ServerAddress(result.room.host + ":" + String(result.room.port))
                _ = try await host.start(instanceID: result.prepared.instance.id, address: address)
            } catch is CancellationError { }
            catch { if self.joining.owns(id) { server.record(error) } }
        }
    }
    func cancelJoin() {
        joining.cancel()
        progress = nil
        joiningServer = nil
    }
}
