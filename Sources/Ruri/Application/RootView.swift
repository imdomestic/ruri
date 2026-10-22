import RuriLocalization
import SwiftUI
import AppKit
import RuriCore
import RuriExtensionKit

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(CLISetupModel.onboardingSeenKey) private var cliSetupSeen = false
    @State private var columns = NavigationSplitViewVisibility.automatic
    @State private var sidebarWidth: CGFloat = 236
    @State private var collectionWidth: CGFloat = 280
    @State private var libraryNavigation = LibraryNavigationState()
    @State private var historyCache = GameHistoryView.Cache()
    @State private var serverNavigation = ServerNavigationState()
    /// Pinned servers on the home page keep their own status rounds.
    @State private var homeServers = ServerNavigationState()
    @State private var accountsNavigation = AccountsNavigationState()
    @State private var experimentalSheet: ExtensionSheet?
    private struct ExtensionSheet: Identifiable { let id = UUID(); let content: AnyView }
    private var hasCollectionColumn: Bool { model.page == .library || model.page == .accounts || model.page == .servers }
    private let collectionMinimumWidth: CGFloat = 280
    private let collectionToolbarWidth: CGFloat = 420
    private let collectionMaximumWidth: CGFloat = 560
    private var minimumWindowWidth: CGFloat {
        guard hasCollectionColumn, columns != .detailOnly else { return 760 }
        let visibleSidebarWidth: CGFloat = columns == .doubleColumn ? 0 : 210
        return max(visibleSidebarWidth + collectionMinimumWidth, collectionToolbarWidth) + 420 + 2
    }
    var body: some View {
        // Keep the same split view and column constraints when switching collections.
        ZStack {
            if hasCollectionColumn {
                NavigationSplitView(columnVisibility: $columns) {
                    RootSidebar(width: $sidebarWidth)
                } content: {
                    Group {
                        if model.page == .library {
                            LibraryView(column: .content, navigation: libraryNavigation)
                        } else if model.page == .servers {
                            ServersView(column: .content, navigation: serverNavigation)
                        } else {
                            AccountsView(column: .content, navigation: accountsNavigation)
                        }
                    }
                    .frame(minWidth: collectionMinimumWidth, maxWidth: .infinity)
                    .navigationSplitViewColumnWidth(
                        min: collectionMinimumWidth,
                        ideal: min(max(collectionWidth, collectionMinimumWidth), collectionMaximumWidth),
                        max: collectionMaximumWidth
                    )
                    .background {
                        CollectionColumnSizing(width: $collectionWidth, toolbarWidth: collectionToolbarWidth)
                    }
                } detail: {
                    Group {
                        if model.page == .library {
                            LibraryView(column: .detail, navigation: libraryNavigation)
                        } else if model.page == .servers {
                            ServersView(column: .detail, navigation: serverNavigation)
                        } else {
                            AccountsView(column: .detail, navigation: accountsNavigation)
                        }
                    }
                    .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                    .toolbarBackground(model.page == .library || model.page == .servers ? .hidden : .automatic, for: .windowToolbar)
                }
            } else {
                NavigationSplitView(columnVisibility: $columns) {
                    RootSidebar(width: $sidebarWidth)
                } detail: {
                    Group {
                        switch model.page {
                        case .experimental(let id, _, _): ExperimentalUIRegistry.page(id, host: model.experimentalHost)
                        case .home, .library, .accounts, .servers: HomeView(servers: homeServers)
                        case .discover: DiscoverView()
                        case .history: GameHistoryView(cache: historyCache, instanceID: model.historyInstanceID)
                        case .activity: LauncherLogView().id(model.logNavigationID)
                        case .java: JavaView()
                        case .settings: PreferencesView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .navigationTitle(model.page.title)
                    .toolbar { RootToolbar(model: model) }
                }
            }
        }
        .frame(minWidth: minimumWindowWidth, minHeight: 600)
        .onOpenURL { url in
            do {
                if let view = try ExperimentalUIRegistry.open(url, host: model.experimentalHost) {
                    model.openMainWindow?(); experimentalSheet = ExtensionSheet(content: view)
                }
            } catch { model.error = error.localizedDescription }
        }
        .sheet(item: $experimentalSheet) { $0.content }
        .task(id: model.state.settings.experimental) {
            await ExperimentalUIRegistry.configure(host: model.experimentalHost)
            // Leave a page whose extension was turned off.
            if case .experimental(let id, _, _) = model.page,
               !ExperimentalUIRegistry.pages(host: model.experimentalHost).contains(where: { $0.id == id }) {
                experimentalSheet = nil; model.page = .home
            }
        }
        .sheet(isPresented: Bindable(model).showCLISetup) { CLIOnboardingView() }
        .sheet(isPresented: Bindable(model).showCreate) { CreateInstanceView() }
        .sheet(isPresented: Binding(get: { model.showDirectories || model.showAddDirectory }, set: {
            if !$0 { model.showDirectories = false; model.showAddDirectory = false }
        })) {
            if model.showAddDirectory {
                AddMinecraftFolderView(cancel: { model.showAddDirectory = false }, completed: { _ in
                    model.showAddDirectory = false
                    if !model.showDirectories { model.page = .library }
                })
            } else { GameDirectoriesView() }
        }
        .sheet(isPresented: Bindable(model).showAccount) { AddAccountView() }
        .sheet(isPresented: Bindable(model).showLogs) { LogsView() }
        .sheet(item: Bindable(model).editingInstance) { instance in InstanceSettingsView(instance: instance) }
        .sheet(item: Bindable(model).contentPresentation) { presentation in
            InstanceContentView(instance: presentation.instance, kind: presentation.kind).id(presentation.id)
        }
        .sheet(item: Bindable(model).serverInstance) { instance in ServerManagerView(instance: instance) }
        .sheet(item: Bindable(model).worldInstance) { instance in WorldManagerView(instance: instance) }
        .sheet(item: Bindable(model).schematicInstance) { instance in SchematicManagerView(instance: instance) }
        .sheet(item: Bindable(model).importingInstance) { prepared in ImportInstanceView(prepared: prepared) }
        .sheet(item: Bindable(model).exportingInstance) { instance in ExportInstanceView(instance: instance) }
        .sheet(item: Bindable(model).copyingInstance) { instance in InstanceCopyView(instance: instance) }
        .sheet(item: Bindable(model).movingInstance) { instance in InstanceMoveView(instance: instance) }
        .alert(Messages.AppRootView.operationIncomplete.localized, isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button(Messages.AppRootView.ok.localized, role: .cancel) { model.error = nil } } message: { Text(model.error ?? "") }
        .task { await model.boot() }
        .task(id: canOfferCLISetup) {
            guard canOfferCLISetup else { return }
            // Let startup URL imports and window restoration take priority.
            do { try await Task.sleep(for: .milliseconds(700)) } catch { return }
            while canOfferCLISetup && !Task.isCancelled {
                // Native dialogs (including the updater) aren't represented in AppModel.
                if NSApp.mainWindow?.attachedSheet != nil || NSApp.modalWindow != nil {
                    do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                    continue
                }
                guard let service = try? CLIInstallation(), service.packageManager == nil,
                      FileManager.default.isExecutableFile(atPath: service.executable.path) else { return }
                cliSetupSeen = true
                if service.status()["installed"] != .bool(true) { model.showCLISetup = true }
                return
            }
        }
    }

    private var canOfferCLISetup: Bool {
        !cliSetupSeen && scenePhase == .active && model.page == .home && !model.busy && !model.readOnly
            && !model.isPresentingSheet && model.error == nil && model.pendingOpenURLs.isEmpty
    }
}

/// App-wide items at the trailing edge of the detail column's toolbar.
struct RootToolbar<Trailing: View>: ToolbarContent {
    let model: AppModel
    @ViewBuilder var trailing: Trailing
    var body: some ToolbarContent {
        // In the library's detail column nothing else fills the toolbar, so
        // without a spacer these items sit at its leading edge.
        if #available(macOS 26, *) { ToolbarSpacer(.flexible, placement: .primaryAction) }
        ToolbarItemGroup(placement: .primaryAction) {
            if let runningID = model.runningID {
                Button { model.showSession(model.activeSessions[runningID]?.id) } label: { Label(Messages.SessionUI.session.localized, systemImage: "gamecontroller") }
                    .help(Messages.AppRootView.viewRunningGameLogs.localized)
            }
            LauncherNotificationButton()
            // Explicit controls stay beside notifications; .searchable inserts its own spacer.
            trailing
        }
    }
}

extension RootToolbar where Trailing == EmptyView {
    init(model: AppModel) {
        self.model = model
        trailing = EmptyView()
    }
}

private struct RootSidebar: View {
    @Environment(AppModel.self) private var model
    @Binding var width: CGFloat
    var body: some View {
        @Bindable var model = model
        // Give the sidebar its own navigation scope. When the root switches
        // between two and three columns, the implicit scope can leave native
        // row emphasis tied to the selection from the sidebar's creation.
        NavigationStack {
            List(selection: $model.page) {
                Section { ForEach([Page.home, .library, .servers, .discover]) { page in sidebarRow(page) } }
                ForEach(ExperimentalUIRegistry.pages(host: model.experimentalHost)) { page in
                    Section { sidebarRow(.experimental(id: page.id, title: page.title, symbol: page.symbol)) }
                }
                Section(Messages.AppRootView.records.localized) { ForEach([Page.history, .activity]) { page in sidebarRow(page) } }
                Section(Messages.AppRootView.manage.localized) { ForEach([Page.accounts, .java, .settings]) { page in sidebarRow(page) } }
            }
            .listStyle(.sidebar)
            .controlSize(.large)
            .safeAreaInset(edge: .bottom, spacing: 0) { AccountSidebarFooter() }
        }
        // Constrain the actual sidebar as well as the split view's preferred width.
        .frame(minWidth: 210, idealWidth: width, maxWidth: 320)
        .navigationSplitViewColumnWidth(min: 210, ideal: width, max: 320)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { measuredWidth in
            if NSApp.currentEvent?.type == .leftMouseDragged,
               measuredWidth >= 210, abs(measuredWidth - width) > 1 {
                width = min(measuredWidth, 320)
            }
        }
    }
    private func sidebarRow(_ page: Page) -> some View {
        HStack {
            Label(page.title, systemImage: page.symbol)
            Spacer()
            if page == .activity, let task = model.activeActivity {
                LauncherTaskProgress(entry: task).controlSize(.mini)
            } else if page == .activity, model.journal.unreadCount > 0 {
                Text(model.journal.unreadCount, format: .number).font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 3).tag(page)
    }
}

/// The signed-in player, shown at the bottom of the sidebar like the account
/// entry in the App Store. The menu switches accounts without leaving the page.
private struct AccountSidebarFooter: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(spacing: 0) {
            Divider()
            Menu {
                Group {
                    if !model.state.accounts.isEmpty {
                        Picker(Messages.AppRootView.switchAccount.localized, selection: Binding(get: { model.state.activeAccountID }, set: { id in
                            guard id != model.state.activeAccountID else { return }
                            if let account = model.state.accounts.first(where: { $0.id == id }) { model.activateAccount(account) }
                        })) {
                            ForEach(model.state.accounts) { account in
                                Text(account.username).tag(Optional(account.id))
                            }
                        }.pickerStyle(.inline).labelsHidden()
                        Divider()
                    }
                    Button(Messages.AppRootView.addAccount.localized, systemImage: "person.badge.plus") { model.showAccount = true }
                    Button(Messages.AppRootView.manageAccounts.localized, systemImage: "person.2") { model.page = .accounts }
                }.labelStyle(.titleAndIcon)
            } label: {
                HStack(spacing: 10) {
                    if let account = model.activeAccount { AccountAvatar(account: account, size: 32) }
                    else {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 30)).symbolRenderingMode(.hierarchical).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.activeAccount?.username ?? Messages.AppRootView.notSignedIn.localized).font(.system(size: 13, weight: .semibold))
                        Text(model.activeAccount?.kindLabel ?? Messages.AppRootView.addAccountToLaunch.localized).font(.system(size: 11)).foregroundStyle(.secondary)
                    }.lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                }.padding(.horizontal, 12).padding(.vertical, 10).contentShape(Rectangle())
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
            .labelStyle(.titleAndIcon)
            .disabled(model.readOnly)
            .padding(.horizontal, 8).padding(.vertical, 8)
            .help(model.activeAccount == nil ? Messages.AppRootView.addAnotherAccount.localized : Messages.AppRootView.switchAccount.localized)
        }
    }
}
