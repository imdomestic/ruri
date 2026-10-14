import RuriLocalization
import SwiftUI
import AppKit
import RuriCore

struct PreferencesView: View {
    @Environment(AppModel.self) private var model
    @Environment(SoftwareUpdater.self) private var updater
    @State private var showLaunchDefaults = false
    @State private var language = LocalizationContext.savedLanguage()
    /// The interface language is fixed for the process, so only a choice that
    /// differs from the one this launch started with needs a restart.
    private static let launchLanguage = LocalizationContext.savedLanguage()
    var body: some View {
        Form {
            // CHORUS: 后端地址与钥匙串凭据。
            ChorusSettingsView()
            appearance
            launchDefaults
            newInstances
            network
            CLISettingsSection()
            if updater.isAvailable { softwareUpdate }
            dataAndAbout
        }
        .formStyle(.grouped).scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(isPresented: $showLaunchDefaults) { DefaultLaunchSettingsView(settings: model.state.settings) }
        .onChange(of: language) { LocalizationContext.savePreference(language) }
        .onChange(of: model.state.settings.appearance) { model.save() }
        .onChange(of: model.state.settings.isolationPolicy) { model.save() }
        .onChange(of: model.state.settings.concurrentDownloads) { model.save(); Task { await model.applyNetworkSettings() } }
        .onChange(of: model.state.settings.downloadSource) { model.save(); Task { await model.applyNetworkSettings() } }
        .onChange(of: model.state.settings.microsoftClientID) { model.save() }
    }

    @ViewBuilder private var appearance: some View {
        @Bindable var model = model
        Section {
            Picker(Messages.AppPreferencesView.theme.localized, selection: $model.state.settings.appearance) {
                Text(Messages.Common.followSystem.localized).tag("system")
                Text(Messages.AppPreferencesView.light.localized).tag("light")
                Text(Messages.AppPreferencesView.dark.localized).tag("dark")
            }.disabled(model.readOnly)
            if LocalizationContext.supportedLanguages.count > 1 {
                Picker(selection: $language) {
                    Text(Messages.Common.followSystem.localized).tag(LocalizationContext.systemPreference)
                    ForEach(LocalizationContext.supportedLanguages, id: \.self) { identifier in
                        Text(Locale(identifier: identifier).localizedString(forIdentifier: identifier) ?? identifier).tag(identifier)
                    }
                } label: {
                    Text(Messages.Common.language.localized)
                    if language != Self.launchLanguage { Text(Messages.Common.languageRestart.localized) }
                }
            }
        } header: {
            Text(Messages.AppPreferencesView.appearance.localized)
        }
    }

    private var launchDefaults: some View {
        Section {
            SettingsActionRow(title: Messages.AppPreferencesView.globalGameSettings.localized,
                              detail: Messages.AppPreferencesView.globalGameSettingsDescription.localized,
                              button: Messages.AppPreferencesView.editDefaultLaunchSettings.localized) {
                showLaunchDefaults = true
            }
        }
    }

    @ViewBuilder private var newInstances: some View {
        Section {
            Picker(Messages.AppPreferencesView.newInstanceIsolation.localized, selection: Binding(get: { model.state.settings.isolationPolicy ?? .always }, set: { model.state.settings.isolationPolicy = $0 })) {
                ForEach(GameIsolationPolicy.allCases) { Text($0.title).tag($0) }
            }.disabled(model.readOnly)
        } header: {
            Text(Messages.AppPreferencesView.newInstances.localized)
        } footer: {
            Text(Messages.AppPreferencesView.newInstanceIsolationDetails.localized).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var dataAndAbout: some View {
        Section(Messages.AppPreferencesView.data.localized) {
            HStack {
                Text(Messages.AppPreferencesView.instanceFolders.localized)
                Spacer()
                Button(Messages.AppPreferencesView.manageInstanceFolders.localized, systemImage: "folder.badge.gearshape") { model.showDirectories = true }
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(Messages.AppPreferencesView.dataDirectory.localized)
                    Spacer()
                    Button(Messages.AppPreferencesView.showInFinder.localized, systemImage: "folder") {
                        do { try model.paths.prepare(); NSWorkspace.shared.open(model.paths.root) }
                        catch { model.error = error.localizedDescription }
                    }.help(Messages.AppPreferencesView.openDataDirectory.localized)
                }
                Text(model.paths.root.path).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }.multilineTextAlignment(.leading).padding(.vertical, 3)
            DownloadCacheRow()
        }
        Section {
            LabeledContent(Messages.AppPreferencesView.version.localized, value: BuildConfiguration().version)
        } header: {
            Text(Messages.AppPreferencesView.aboutRuri.localized)
        } footer: {
            Text(Messages.AppPreferencesView.aboutRuriDescription.localized).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var softwareUpdate: some View {
        @Bindable var updater = updater
        Section {
            Toggle(Messages.AppPreferencesView.automaticallyCheckForUpdates.localized, isOn: $updater.automaticallyChecksForUpdates)
            Toggle(Messages.AppPreferencesView.automaticallyInstallUpdates.localized, isOn: $updater.automaticallyDownloadsUpdates)
                .disabled(!updater.automaticallyChecksForUpdates)
            Toggle(Messages.AppPreferencesView.receivePrereleaseUpdates.localized, isOn: $updater.receivesPrereleases)
            SettingsActionRow(title: Messages.AppPreferencesView.checkForUpdates.localized,
                              detail: updater.lastUpdateCheckDate.map { Messages.AppPreferencesView.lastUpdateCheck($0.formatted(.relative(presentation: .named))).localized }
                                  ?? Messages.AppPreferencesView.neverCheckedForUpdates.localized,
                              button: Messages.AppRuriApp.checkForUpdates.localized) {
                updater.checkForUpdates()
            }.disabled(!updater.canCheckForUpdates)
        } header: {
            Text(Messages.AppPreferencesView.softwareUpdate.localized)
        } footer: {
            Text(Messages.AppPreferencesView.softwareUpdateDetails.localized).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var network: some View {
        @Bindable var model = model
        Section {
            Picker(Messages.AppPreferencesView.downloadSource.localized, selection: Binding(get: { model.state.settings.downloadSource ?? .automatic }, set: { model.state.settings.downloadSource = $0 })) {
                ForEach(DownloadSource.allCases) { Text($0.title).tag($0) }
            }.disabled(model.readOnly)
            Stepper(value: $model.state.settings.concurrentDownloads, in: 1...16) {
                HStack {
                    Text(Messages.AppPreferencesView.parallelDownloadsLabel.localized)
                    Spacer()
                    Text(model.state.settings.concurrentDownloads, format: .number).monospacedDigit()
                }
            }.disabled(model.readOnly)
        } header: {
            Text(Messages.AppPreferencesView.downloadsAndNetwork.localized)
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(Messages.AppPreferencesView.automaticMirrorDetails.localized)
                Link(Messages.AppPreferencesView.bmclapiMirror.localized, destination: AppLinks.bmclapiDocumentation)
            }.fixedSize(horizontal: false, vertical: true)
        }
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(Messages.AppPreferencesView.customClientID.localized)
                TextField(Messages.AppPreferencesView.customClientID.localized, text: $model.state.settings.microsoftClientID,
                          prompt: Text(BuildConfiguration().microsoftClientID.isEmpty ? Messages.AppPreferencesView.enterClientID.localized : Messages.AppPreferencesView.useBuiltInClientID.localized))
                    .labelsHidden().textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
                    .multilineTextAlignment(.leading).autocorrectionDisabled().disabled(model.readOnly)
                    .accessibilityLabel(Messages.AppPreferencesView.customClientID.localized)
            }.padding(.vertical, 3)
        } header: {
            Text(Messages.AppPreferencesView.microsoftLogin.localized)
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if !BuildConfiguration().microsoftClientID.isEmpty { Text(Messages.AppPreferencesView.microsoftLoginDetails.localized) }
                Text(Messages.AppPreferencesView.customClientIDDetails.localized)
                Link(Messages.AppPreferencesView.microsoftRegistrationDocs.localized, destination: AppLinks.microsoftRegistration)
            }.fixedSize(horizontal: false, vertical: true)
        }
        CurseForgeSettingsSection()
    }

}
