import SwiftUI
import AppKit
import Observation
import RuriCore
import RuriExtensionKit
import RuriLocalization

enum ServerScope: String, CaseIterable, Identifiable {
    case all, recent
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: Messages.Servers.allServers.localized
        case .recent: Messages.Servers.recent.localized
        }
    }
    var symbol: String {
        switch self {
        case .all: "server.rack"
        case .recent: "clock"
        }
    }
}

/// What the last status query says about a server. A response stays on
/// screen while it is being queried again, so rows don't flicker.
enum ServerReachability {
    case unknown, querying
    case online(ServerStatus)
    case offline(String)

    var status: ServerStatus? { if case .online(let status) = self { status } else { nil } }
    var summary: String {
        switch self {
        case .unknown: Messages.Servers.unknown.localized
        case .querying: Messages.Servers.querying.localized
        case .offline: Messages.Servers.offline.localized
        case .online(let status):
            [Messages.Servers.reachable.localized, status.latencyMilliseconds.map { Messages.Servers.milliseconds(Int64($0)).localized }]
                .compactMap { $0 }.joined(separator: " · ")
        }
    }
}

extension ServerStatus {
    /// Signal strength for a `cellularbars` symbol, graded like the game's ping bars.
    var signal: Double {
        guard let latencyMilliseconds else { return 1 }
        switch latencyMilliseconds {
        case ..<100: return 1
        case ..<200: return 0.75
        case ..<400: return 0.5
        default: return 0.25
        }
    }
    var playersLabel: String? {
        online.map { LocalizedFormat.number($0) + (maximum.map { " / " + LocalizedFormat.number($0) } ?? "") }
    }
}

extension AppModel {
    /// Opens the server center with the server selected and any filter cleared.
    func showServer(_ address: ServerAddress) {
        serverFocus = address.key
        page = .servers
    }
}

@MainActor @Observable final class ServerNavigationState {
    var search = ""
    var scope = ServerScope.all
    var instanceID: UUID?
    var selectedID: String?
    var pendingSelection: String?
    var snapshot: ServerLibrarySnapshot?
    var responses: [String: ServerStatus] = [:]
    var failures: [String: String] = [:]
    var querying = Set<String>()
    var refreshID = UUID()
    var queryID = UUID()
    var editor: ServerEditorRequest?
    var removeTarget: ServerLibraryItem?
    var joining = false
    @ObservationIgnored private var lastRound: (key: String, date: Date)?

    var filtering: Bool { scope != .all || instanceID != nil }

    func load(paths: LauncherPaths, state: PersistentState) async {
        let result = await Task.detached(priority: .utility) { ServerLibrary.load(paths: paths, state: state) }.value
        guard !Task.isCancelled else { return }
        snapshot = result
        if let key = pendingSelection, result.items.contains(where: { $0.id == key }) { selectedID = key; pendingSelection = nil }
    }
    func refresh(_ addresses: [ServerAddress]) async {
        let generation = UUID(); queryID = generation
        querying = Set(addresses.map(\.key))
        defer { if queryID == generation { querying = [] } }
        await withTaskGroup(of: (String, ServerStatus?, String?).self) { group in
            var pending = addresses.makeIterator()
            func enqueue(_ address: ServerAddress) {
                group.addTask {
                    do { return (address.key, try await ServerStatusClient.query(address), nil) }
                    catch { return (address.key, nil, error.localizedDescription) }
                }
            }
            for _ in 0..<4 { if let address = pending.next() { enqueue(address) } }
            while let (key, response, error) = await group.next() {
                guard !Task.isCancelled, queryID == generation else { group.cancelAll(); return }
                querying.remove(key)
                record(key, response: response, error: error)
                if let address = pending.next() { enqueue(address) }
            }
        }
    }
    /// Queries the list every minute. A new list or a manual refresh (a new
    /// key) starts at once; otherwise the next round waits until the last
    /// finished one is a minute old, so pausing and resuming doesn't re-query.
    func monitor(_ addresses: [ServerAddress], key: String) async {
        repeat {
            if let lastRound, lastRound.key == key {
                let wait = 60 - Date().timeIntervalSince(lastRound.date)
                if wait > 0 { do { try await Task.sleep(for: .seconds(wait)) } catch { return } }
            }
            await refresh(addresses)
            guard !Task.isCancelled else { return }
            lastRound = (key, Date())
        } while !Task.isCancelled
    }
    /// Queries one server again without restarting the rest of the list.
    func refresh(_ address: ServerAddress) async {
        let key = address.key
        guard !querying.contains(key) else { return }
        querying.insert(key)
        defer { querying.remove(key) }
        do { record(key, response: try await ServerStatusClient.query(address), error: nil) }
        catch is CancellationError {}
        catch { record(key, response: nil, error: error.localizedDescription) }
    }
    private func record(_ key: String, response: ServerStatus?, error: String?) {
        if let response {
            responses[key] = response; failures[key] = nil
            if responses.count > 256, let oldest = responses.min(by: { $0.value.queriedAt < $1.value.queriedAt })?.key { responses[oldest] = nil }
        } else { failures[key] = error }
    }
    func reachability(_ key: String) -> ServerReachability {
        if let error = failures[key] { return .offline(error) }
        if let response = responses[key] { return .online(response) }
        return querying.contains(key) ? .querying : .unknown
    }

    /// The instance a join uses unless the player picks another: the one set
    /// in the server's settings, then the last one played on it, then one
    /// that already lists it, then the instance featured on the home page.
    func defaultInstance(for item: ServerLibraryItem, model: AppModel) -> GameInstance? {
        let instances = model.state.instances
        let candidates = [item.preference?.preferredInstanceID, snapshot?.history[item.id]?.lastInstanceID, item.instanceIDs.first, model.selected?.id]
        return candidates.lazy.compactMap { id in id.flatMap { id in instances.first { $0.id == id } } }.first
    }

    func toggleFavorite(_ item: ServerLibraryItem, model: AppModel) {
        do {
            var preference = item.preference ?? .init(address: item.address)
            preference.favorite.toggle()
            model.acceptState(try ServerLibrary.save(preference, paths: model.basePaths))
            refreshID = UUID()
        } catch { model.error = error.localizedDescription }
    }

    func remove(_ item: ServerLibraryItem, model: AppModel) {
        do {
            model.acceptState(try ServerLibrary.remove(item.address, paths: model.basePaths))
            refreshID = UUID()
        } catch { model.error = error.localizedDescription }
    }

    /// Adds the server to the instance's multiplayer list when it isn't there
    /// yet, so the game shows it afterwards, then launches straight into it.
    func join(_ item: ServerLibraryItem, with instance: GameInstance, model: AppModel) {
        guard !joining else { return }
        if model.activeSessions[instance.id] != nil { model.returnToGame(instance.id); return }
        guard !model.busy, !model.readOnly, !model.isInstanceInUse(instance.id) else { return }
        joining = true
        Task {
            defer { joining = false }
            do {
                let paths = model.paths, name = item.name, address = item.address, id = instance.id
                try await Task.detached(priority: .userInitiated) {
                    let manager = ServerListManager(paths: paths, instanceID: id), list = try manager.snapshot()
                    if !list.entries.contains(where: { $0.endpoint?.key == address.key }) { try manager.apply(.add(name: name, address: address, resourcePacks: .ask), to: list) }
                }.value
                refreshID = UUID()
                model.launch(instance, server: item.address)
            } catch { model.error = error.localizedDescription }
        }
    }
}

/// Servers from every instance's multiplayer list and the ones the player
/// saved in Ruri, as a master–detail page like the library.
struct ServersView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appearsActive) private var appearsActive
    let column: NavigationSplitViewColumn
    @Bindable var navigation: ServerNavigationState
    private var filteredLibrary: Result<[ServerLibraryItem], any Error> {
        Result { try ExperimentalFeatures.visibleServers(navigation.snapshot?.items ?? [], settings: model.state.settings.experimental) }
    }
    private var items: [ServerLibraryItem] {
        switch filteredLibrary { case .success(let items): items; case .failure: [] }
    }
    private var filtered: [ServerLibraryItem] {
        let history = navigation.snapshot?.history ?? [:]
        return items.filter { item in
            (navigation.scope != .recent || history[item.id] != nil) &&
            (navigation.instanceID.map { (item.instanceIDs + item.playedInstanceIDs).contains($0) } ?? true) &&
            (navigation.search.isEmpty || item.name.localizedCaseInsensitiveContains(navigation.search) || item.address.authority.localizedCaseInsensitiveContains(navigation.search))
        }.sorted { first, second in
            if navigation.scope == .recent { return (history[first.id]?.lastPlayed ?? .distantPast) > (history[second.id]?.lastPlayed ?? .distantPast) }
            return first.name.localizedStandardCompare(second.name) == .orderedAscending
        }
    }
    private var current: ServerLibraryItem? { filtered.first { $0.id == navigation.selectedID } ?? filtered.first }
    private var statusKey: String { items.map(\.id).joined(separator: "|") + navigation.refreshID.uuidString }

    var body: some View {
        if column == .content { contentColumn }
        else {
            detailColumn
                .sheet(item: $navigation.editor) { request in
                    ServerEditorSheet(request: request) { address in
                        if request.entry == nil && request.item == nil { navigation.scope = .all; navigation.instanceID = nil; navigation.search = "" }
                        navigation.pendingSelection = address.key; navigation.refreshID = UUID()
                    }
                }
                .toolbar { RootToolbar(model: model) }
                .confirmationDialog(Messages.Servers.removeFromLibraryConfirm.localized, isPresented: Binding(get: { navigation.removeTarget != nil }, set: { if !$0 { navigation.removeTarget = nil } }), titleVisibility: .visible) {
                    Button(Messages.Servers.removeFromLibrary.localized, role: .destructive) {
                        if let target = navigation.removeTarget { navigation.remove(target, model: model) }
                        navigation.removeTarget = nil
                    }
                } message: { Text(Messages.Servers.removeFromLibraryDetail.localized) }
        }
    }

    // MARK: Content column

    private var contentColumn: some View {
        list
            .topScrollBar {
                VStack(spacing: 16) {
                    ServerFilterMenu(navigation: navigation)
                    NativeSearchField(text: $navigation.search, prompt: Messages.Servers.search.localized)
                }
                .padding(.horizontal, 10).padding(.top, 6).padding(.bottom, 12)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { listErrors }
            .navigationTitle(Messages.Servers.page.localized)
            .navigationSubtitle(countLabel)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { navigation.refreshID = UUID() } label: { Label(Messages.Servers.refresh.localized, systemImage: "arrow.clockwise") }
                        .help(Messages.Servers.refreshStatus.localized)
                        .keyboardShortcut("r", modifiers: .command)
                    Button { navigation.editor = .init(instanceID: navigation.instanceID) } label: { Label(Messages.Servers.add.localized, systemImage: "plus") }
                        .help(Messages.Servers.add.localized)
                        .disabled(model.readOnly || model.busy)
                }
            }
            .task(id: "\(model.state.revision?.uuidString ?? "")/\(navigation.refreshID)/\(model.historyRevision)") {
                let paths = model.paths, state = model.state
                let observer = FileChangeObserver(directories: state.instances.map { paths.game($0.id) }, fallbackSeconds: 15)
                defer { observer.cancel() }
                await navigation.load(paths: paths, state: state)
                for await _ in observer.events {
                    guard !Task.isCancelled else { break }
                    await navigation.load(paths: paths, state: state)
                }
            }
            // Status belongs to the whole library, so typing in the search
            // field or switching filters doesn't start the queries over.
            // Queries pause while the window is in the background or
            // minimized, such as while the game is running.
            .task(id: "\(statusKey)|\(appearsActive)") {
                guard appearsActive else { return }
                await navigation.monitor(items.map(\.address), key: statusKey)
            }
            .onChange(of: filtered.map(\.id), initial: true) { _, ids in
                if navigation.selectedID.map(ids.contains) != true { navigation.selectedID = ids.first }
            }
            .onChange(of: model.serverFocus, initial: true) { _, key in
                guard let key else { return }
                navigation.search = ""; navigation.scope = .all; navigation.instanceID = nil
                if items.contains(where: { $0.id == key }) { navigation.selectedID = key } else { navigation.pendingSelection = key }
                model.serverFocus = nil
            }
    }

    private var countLabel: String {
        guard navigation.snapshot != nil, !items.isEmpty else { return "" }
        guard navigation.filtering || !navigation.search.isEmpty else { return Messages.Servers.serverCount(Int64(items.count)).localized }
        return Messages.Servers.filteredServerCount(Int64(filtered.count), Int64(items.count)).localized
    }

    /// Pinned servers get their own section only when there is something else
    /// to set them apart from. Double-clicking a row joins the server.
    private var list: some View {
        List(selection: $navigation.selectedID) {
            ForEach(ExperimentalUIRegistry.providers, id: \.id) { $0.servers(host: model.experimentalHost) }
            if case .failure(let error) = filteredLibrary { Text(error.localizedDescription).foregroundStyle(.red) }
            let pinned = navigation.scope == .all ? filtered.filter { $0.preference?.favorite == true } : []
            if pinned.isEmpty || pinned.count == filtered.count {
                rows(filtered)
            } else {
                Section(Messages.Servers.favorites.localized) { rows(pinned) }
                Section(Messages.Servers.otherServers.localized) { rows(filtered.filter { $0.preference?.favorite != true }) }
            }
        }
        .listStyle(.inset)
        // The list starts empty while the library loads. Give AppKit the
        // two-line row height up front so its initial 24-point estimate
        // doesn't clip asynchronously inserted rows until the next layout.
        .environment(\.defaultMinListRowHeight, 48)
        .scrollContentBackground(.hidden)
        .overlay {
            if navigation.snapshot == nil { DelayedProgressView() }
            else if filtered.isEmpty && !navigation.search.isEmpty { ContentUnavailableView.search(text: navigation.search) }
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if let item = item(ids) { ServerContextActions(item: item, navigation: navigation).labelStyle(.titleAndIcon) }
        } primaryAction: { ids in
            guard let item = item(ids), let instance = navigation.defaultInstance(for: item, model: model) else { return }
            navigation.join(item, with: instance, model: model)
        }
    }

    private func rows(_ items: [ServerLibraryItem]) -> some View {
        ForEach(items) { item in
            ServerRow(item: item, reachability: navigation.reachability(item.id)).tag(item.id)
        }
    }

    private func item(_ ids: Set<String>) -> ServerLibraryItem? {
        ids.first.flatMap { id in items.first { $0.id == id } }
    }

    @ViewBuilder private var listErrors: some View {
        if let errors = navigation.snapshot?.errors, !errors.isEmpty {
            Label(Messages.Servers.listErrors.localized, systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .help(errors.values.sorted().joined(separator: "\n"))
        }
    }

    // MARK: Detail column

    private var detailColumn: some View {
        Group {
            if navigation.snapshot == nil {
                DelayedProgressView()
            } else if items.isEmpty {
                ContentUnavailableView {
                    Label(Messages.Servers.empty.localized, systemImage: "server.rack")
                } description: {
                    Text(Messages.Servers.emptyDescription.localized)
                } actions: {
                    Button(Messages.Servers.add.localized) { navigation.editor = .init() }
                        .buttonStyle(.borderedProminent).disabled(model.readOnly || model.busy)
                }
            } else if let item = current {
                ServerDetailView(item: item, navigation: navigation).id(item.id)
            } else if !navigation.search.isEmpty {
                ContentUnavailableView.search(text: navigation.search)
            } else {
                ContentUnavailableView {
                    Label(Messages.Servers.noMatches.localized, systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text(Messages.Servers.noMatchesDescription.localized)
                } actions: {
                    Button(Messages.Servers.showAll.localized) { navigation.scope = .all; navigation.instanceID = nil }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.canvas(for: colorScheme))
    }
}

// MARK: - List pieces

private struct ServerRow: View {
    let item: ServerLibraryItem
    let reachability: ServerReachability
    var body: some View {
        HStack(spacing: 10) {
            ServerIcon(data: reachability.status?.icon ?? item.icon, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.body.weight(.medium)).lineLimit(1)
                Text(item.address.authority).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if let players = reachability.status?.online {
                HStack(spacing: 3) {
                    Image(systemName: "person.fill").font(.system(size: 9))
                    Text(LocalizedFormat.number(players)).monospacedDigit()
                }
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Messages.Servers.players.localized)
                .accessibilityValue(LocalizedFormat.number(players))
            }
            ServerSignal(reachability: reachability)
        }
        .padding(.vertical, 4)
        .help(item.name)
    }
}

/// Signal bars for a reachable server, a crossed-out network for one that
/// didn't answer, and a spinner while the first answer is on its way.
struct ServerSignal: View {
    let reachability: ServerReachability
    var body: some View {
        Group {
            switch reachability {
            case .querying:
                ProgressView().controlSize(.mini)
            case .unknown:
                Image(systemName: "cellularbars", variableValue: 0).foregroundStyle(.tertiary)
            case .online(let status):
                Image(systemName: "cellularbars", variableValue: status.signal).foregroundStyle(.secondary)
            case .offline(let error):
                Image(systemName: "network.slash").foregroundStyle(.red).help(error)
            }
        }
        .font(.system(size: 12, weight: .medium))
        .frame(width: 18, height: 16)
        .accessibilityElement()
        .accessibilityLabel(reachability.summary)
    }
}

/// The scope and instance filters as one full-width pull-down that matches
/// the search field under it, like the folder menu over the library.
private struct ServerFilterMenu: View {
    @Environment(AppModel.self) private var model
    @Bindable var navigation: ServerNavigationState
    @State private var hovering = false
    private var title: String {
        let instance = navigation.instanceID.flatMap { id in model.state.instances.first { $0.id == id }?.name }
        return [navigation.scope.title, instance].compactMap { $0 }.joined(separator: " · ")
    }
    var body: some View {
        Menu {
            Picker(Messages.Servers.filter.localized, selection: $navigation.scope) {
                ForEach(ServerScope.allCases) { scope in Label(scope.title, systemImage: scope.symbol).tag(scope) }
            }.pickerStyle(.inline).labelsHidden()
            if !model.state.instances.isEmpty {
                Section(Messages.Servers.instanceName.localized) {
                    Picker(Messages.Servers.instanceName.localized, selection: $navigation.instanceID) {
                        Text(Messages.Servers.allInstances.localized).tag(nil as UUID?)
                        ForEach(model.state.instances) { instance in Text(instance.name).tag(Optional(instance.id)) }
                    }.pickerStyle(.inline).labelsHidden()
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: navigation.filtering ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .foregroundStyle(navigation.filtering ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
                Text(title).lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10).frame(height: 24)
            .background(.primary.opacity(hovering ? 0.10 : 0.06), in: Capsule())
            .contentShape(Capsule())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        .labelStyle(.titleAndIcon)
        .onHover { hovering = $0 }
        .help(Messages.Servers.filter.localized)
    }
}

struct ServerContextActions: View {
    @Environment(AppModel.self) private var model
    let item: ServerLibraryItem
    let navigation: ServerNavigationState
    var body: some View {
        if let instance = navigation.defaultInstance(for: item, model: model) {
            Button(Messages.Servers.joinButton.localized + " · " + instance.name, systemImage: "play.fill") { navigation.join(item, with: instance, model: model) }
                .disabled(navigation.joining || (model.activeSessions[instance.id] == nil && (model.busy || model.readOnly || model.isInstanceInUse(instance.id))))
            Divider()
        }
        let pinned = item.preference?.favorite == true
        Button(pinned ? Messages.Servers.unfavorite.localized : Messages.Servers.favorite.localized, systemImage: pinned ? "pin.slash" : "pin") {
            navigation.toggleFavorite(item, model: model)
        }.disabled(model.readOnly)
        Button(Messages.Servers.globalSettings.localized, systemImage: "slider.horizontal.3") {
            navigation.editor = .init(item: item, status: navigation.responses[item.id])
        }.disabled(model.readOnly)
        Divider()
        Button(Messages.Servers.copyAddress.localized, systemImage: "doc.on.doc") { copyServerAddress(item.address) }
        Button(Messages.Servers.refreshStatus.localized, systemImage: "arrow.clockwise") { Task { await navigation.refresh(item.address) } }
            .disabled(navigation.querying.contains(item.id))
        if item.preference?.saved == true {
            Divider()
            Button(Messages.Servers.removeFromLibrary.localized, systemImage: "trash", role: .destructive) { navigation.removeTarget = item }
                .disabled(model.readOnly)
        }
    }
}

func copyServerAddress(_ address: ServerAddress) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(address.authority, forType: .string)
}

/// The server's own 64-pixel favicon, drawn crisply, or a neutral tile.
struct ServerIcon: View {
    let data: Data?
    var size: CGFloat = 64
    private var image: NSImage? { data.flatMap(ServerStatus.validatedIcon).flatMap(NSImage.init(data:)) }
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.none).scaledToFill()
            } else {
                Image(systemName: "server.rack")
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.quaternary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay { shape.strokeBorder(.primary.opacity(0.08), lineWidth: 1) }
        .accessibilityHidden(true)
    }
}
