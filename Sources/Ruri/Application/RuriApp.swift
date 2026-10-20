import RuriLocalization
import SwiftUI
import AppKit
import RuriCore
import RuriFeatureRegistration

@main struct RuriApp: App {
    @State private var model: AppModel
    @State private var updater = SoftwareUpdater()
    @NSApplicationDelegateAdaptor(RuriLifecycle.self) private var lifecycle
    init() {
        CompiledExperimentalFeatures.register()
        if let status = LocalizationCommandLine.resourceCheck() { exit(status) }
        _model = State(initialValue: AppModel())
    }
    var body: some Scene {
        Window("Ruri", id: "main") {
            MainWindowContent(model: model, updater: updater, lifecycle: lifecycle)
        }
        .defaultSize(width: 1140, height: 780)
        .commands {
            if updater.isAvailable {
                CommandGroup(after: .appInfo) {
                    Button(Messages.AppRuriApp.checkForUpdates.localized) { updater.checkForUpdates() }.disabled(!updater.canCheckForUpdates)
                }
            }
            CommandGroup(replacing: .newItem) {
                Button(Messages.AppRuriApp.showMainWindow.localized) { model.openMainWindow?() }.keyboardShortcut("0")
                Divider()
                Button(Messages.AppRuriApp.newInstance.localized) { model.openMainWindow?(); model.showCreate = true }.keyboardShortcut("n").disabled(model.busy || model.showCLISetup)
                Button(Messages.AppRuriApp.importInstance.localized) { model.openMainWindow?(); model.chooseInstanceImport() }.keyboardShortcut("i").disabled(model.busy || model.showCLISetup)
                Button(Messages.AppRuriApp.addGameFolder.localized) { model.openMainWindow?(); model.chooseMinecraftDirectory() }.keyboardShortcut("i", modifiers: [.command, .shift]).disabled(model.busy || model.showCLISetup)
                Divider()
                Button(Messages.SessionUI.launcherActivity.localized) { model.openMainWindow?(); model.showLauncherLog() }.keyboardShortcut("l", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .appSettings) {
                Button(Messages.AppRuriApp.settings.localized) { model.openMainWindow?(); model.page = .settings }.keyboardShortcut(",")
            }
            CommandMenu(Messages.AppRuriApp.gameMenu.localized) {
                Button(Messages.AppRuriApp.launchSelectedInstance.localized) { if let instance = model.selected { model.launch(instance) } }.keyboardShortcut("r").disabled(model.selected == nil || model.busy || model.isInstanceInUse(model.selected?.id))
                ForEach(model.activeSessions.values.sorted { $0.createdAt < $1.createdAt }) { record in
                    Button(Messages.AppRuriApp.returnToInstance(record.instanceName).localized) { model.returnToGame(record.instanceID) }
                    if record.nativeQuitSupported == true {
                        Button(Messages.AppRuriApp.requestExit(record.instanceName).localized) { model.requestGameQuit(record.instanceID) }.disabled(record.state.isFinished || record.gameIdentity?.isAlive != true || record.monitorIdentity?.isAlive != true)
                    }
                    Button(Messages.AppRuriApp.terminateInstance(record.instanceName).localized) { model.confirmGameTermination(record.instanceID) }.disabled(record.state.isFinished || record.monitorIdentity?.isAlive != true)
                }
                Button(Messages.SessionUI.session.localized) { model.showSession() }.keyboardShortcut("l")
                Button(Messages.SessionUI.history.localized) { model.openMainWindow?(); model.showHistory() }.keyboardShortcut("y")
                Divider()
                Button(Messages.AppRuriApp.revealInstance.localized) { if let instance = model.selected { model.reveal(instance) } }.keyboardShortcut("o", modifiers: [.command, .shift]).disabled(model.selected == nil)
            }
        }
    }
}

private struct MainWindowContent: View {
    @Environment(\.openWindow) private var openWindow
    let model: AppModel
    let updater: SoftwareUpdater
    let lifecycle: RuriLifecycle
    var body: some View {
        RootView().environment(model).environment(updater)
            .environment(\.locale, LocalizationContext.current.formatLocale)
            .environment(\.layoutDirection, Locale.Language(identifier: LocalizationContext.current.language).characterDirection == .rightToLeft ? .rightToLeft : .leftToRight)
            .onChange(of: model.state.settings.appearance, initial: true) { _, preference in
                // Let AppKit propagate one appearance to windows, native controls,
                // and SwiftUI. A presentation-level color scheme can leave them
                // out of sync when switching back from dark to light.
                NSApp.appearance = switch preference {
                case "light": NSAppearance(named: .aqua)
                case "dark": NSAppearance(named: .darkAqua)
                default: nil
                }
            }
            .onAppear {
                lifecycle.model = model
                let action = openWindow
                model.openMainWindow = { action(id: "main"); NSApp.activate() }
            }
            .onOpenURL { url in
                if ["mrpack", "zip"].contains(url.pathExtension.lowercased()) {
                    model.pendingOpenURLs.append(url); model.openMainWindow?()
                }
            }
            .task(id: model.pendingOpenURLs.first) {
                guard model.pendingOpenURLs.first != nil else { return }
                while model.busy || model.isPresentingSheet || model.error != nil {
                    do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
                }
                guard !Task.isCancelled, let url = model.pendingOpenURLs.first else { return }
                model.pendingOpenURLs.removeFirst(); model.importPack(url)
            }
    }
}

@MainActor final class RuriLifecycle: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { model?.recordClientEvent(.windowClosed); return false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { model?.recordClientEvent(.windowReopened); model?.openMainWindow?() }
        return true
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model?.recordClientEvent(.quitRequested)
        guard let model else { return .terminateNow }
        if !model.isQuitting {
            Task { await model.prepareToQuit(); sender.reply(toApplicationShouldTerminate: true) }
        }
        return .terminateLater
    }
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let show = NSMenuItem(title: Messages.AppRuriApp.showRuri.localized, action: #selector(showMain(_:)), keyEquivalent: "")
        show.target = self; menu.addItem(show)
        for record in model?.activeSessions.values.sorted(by: { $0.createdAt < $1.createdAt }) ?? [] where record.gameIdentity?.isAlive == true {
            let item = NSMenuItem(title: Messages.AppRuriApp.returnToInstance(record.instanceName).localized, action: #selector(returnGame(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = record.instanceID.uuidString; menu.addItem(item)
        }
        return menu
    }
    @objc private func showMain(_ sender: NSMenuItem) { model?.openMainWindow?() }
    @objc private func returnGame(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String, let id = UUID(uuidString: value) else { return }
        model?.returnToGame(id)
    }
}
