import RuriLocalization
enum Page: String, CaseIterable, Identifiable {
    // MARK: Vex (experimental)
    case vexGit
    case home, library, servers, discover, history, activity, accounts, java, settings
    var id: String { rawValue }
    var title: String { switch self { case .vexGit: Messages.Vex.git.localized; case .servers: Messages.Servers.page.localized; case .home: Messages.AppPage.home.localized; case .library: Messages.AppPage.library.localized; case .discover: Messages.AppPage.discover.localized; case .history: Messages.SessionUI.history.localized; case .activity: Messages.SessionUI.launcherActivity.localized; case .accounts: Messages.AppPage.accounts.localized; case .java: "Java"; case .settings: Messages.AppPage.settings.localized } }
    var symbol: String { switch self { case .vexGit: "arrow.triangle.branch"; case .servers: "server.rack"; case .home: "house"; case .library: "square.grid.2x2"; case .discover: "safari"; case .history: "clock.arrow.circlepath"; case .activity: "list.bullet.rectangle"; case .accounts: "person.crop.circle"; case .java: "cup.and.saucer"; case .settings: "gearshape" } }
}
