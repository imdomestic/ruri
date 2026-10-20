import RuriLocalization
enum Page: Hashable, Identifiable {
    case experimental(id: String, title: String, symbol: String)
    case home, library, servers, discover, history, activity, accounts, java, settings
    var id: String { if case .experimental(let id, _, _) = self { return id }; return String(describing: self) }
    var title: String { switch self { case .experimental(_, let title, _): title; case .servers: Messages.Servers.page.localized; case .home: Messages.AppPage.home.localized; case .library: Messages.AppPage.library.localized; case .discover: Messages.AppPage.discover.localized; case .history: Messages.SessionUI.history.localized; case .activity: Messages.SessionUI.launcherActivity.localized; case .accounts: Messages.AppPage.accounts.localized; case .java: "Java"; case .settings: Messages.AppPage.settings.localized } }
    var symbol: String { switch self { case .experimental(_, _, let symbol): symbol; case .servers: "server.rack"; case .home: "house"; case .library: "square.grid.2x2"; case .discover: "safari"; case .history: "clock.arrow.circlepath"; case .activity: "list.bullet.rectangle"; case .accounts: "person.crop.circle"; case .java: "cup.and.saucer"; case .settings: "gearshape" } }
}
