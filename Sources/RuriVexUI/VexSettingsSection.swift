import SwiftUI
import RuriCore
import RuriVex
import RuriExtensionKit
import RuriLocalization

private enum VexLoginSheet: Identifiable {
    case add, login(VexServer)
    var id: String { switch self { case .add: "add"; case .login(let server): server.id } }
}

struct VexSettingsSection: View {
    @Environment(ExperimentalHost.self) private var host
    @Environment(VexPresentation.self) private var vex
    @State private var sheet: VexLoginSheet?
    @State private var renaming: VexServer?
    @State private var name = ""
    @State private var notice: String?
    private var settings: VexSettings { vex.settings }
    var body: some View {
        Section {
            Toggle(Messages.Vex.enabled.localized, isOn: Binding(get: { settings.enabled }, set: { enabled in
                save { $0.enabled = enabled }
            }))
            Text(Messages.Vex.description.localized).font(.caption).foregroundStyle(.secondary)
            if settings.enabled {
                Text(Messages.VexLogin.servers.localized).font(.headline)
                ForEach(settings.servers) { server in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(server.name).font(.headline)
                            Text(server.baseURL).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        let connection = vex.connections.first { $0.id == server.id }
                        VStack(alignment: .trailing) {
                            Text(connection?.statusText ?? Messages.VexLogin.notLoggedIn.localized).font(.caption)
                            if let notice = connection?.eventConnectionNotice {
                                Text(notice).font(.caption).foregroundStyle(.orange)
                            }
                        }
                        if connection?.status != .loggedIn {
                            Button(connection?.status == .expired ? Messages.VexLogin.loginAgain.localized : Messages.VexLogin.login.localized) { sheet = .login(server) }
                        }
                        Menu {
                            Button(Messages.VexLogin.testConnection.localized) { connection?.testConnection(paths: host.paths) }
                            Button(Messages.VexLogin.rename.localized) { name = server.name; renaming = server }
                            Button(Messages.VexLogin.makeDefault.localized) { save { $0.defaultServer = server.id } }
                            if let connection, !connection.projects.isEmpty {
                                Menu(Messages.VexLogin.defaultProject.localized) {
                                    ForEach(connection.projects) { project in
                                        Button(project.id) { save { settings in
                                            var updated = server; updated.defaultProject = project.id; try settings.save(updated)
                                        } }
                                    }
                                }
                            }
                            Button(Messages.VexLogin.logout.localized) { logout(server, remove: false) }.disabled(server.userID == nil)
                            Button(Messages.VexLogin.removeServer.localized, role: .destructive) { logout(server, remove: true) }
                        } label: { Image(systemName: "ellipsis") }
                    }
                }
                Button { sheet = .add } label: { Label(Messages.VexLogin.addServer.localized, systemImage: "plus") }
                if let notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
            }
        } header: { Text(Messages.Vex.experimental.localized) }
        .disabled(host.readOnly)
        .sheet(item: $sheet) { item in
            switch item {
            case .add:
                VexAddServerSheet { server in sheet = server.userID == nil ? .login(server) : nil }
            case .login(let server): VexLoginForm(server: server) { sheet = nil }
            }
        }
        .alert(Messages.VexLogin.rename.localized, isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField(Messages.Servers.name.localized, text: $name)
            Button(Messages.Servers.save.localized) {
                guard var server = renaming else { return }
                server.name = name
                save { try $0.save(server) }
                renaming = nil
            }
            Button(Messages.Common.cancel.localized, role: .cancel) { renaming = nil }
        }
    }
    private func save(_ change: (inout VexSettings) throws -> Void) {
        do { vex.settings = try VexSettings.update(paths: host.paths, change); try host.reload() }
        catch { host.report(VexAuthentication.message(for: error)) }
    }
    private func logout(_ server: VexServer, remove: Bool) {
        Task {
            do {
                let remote = try await VexAuthentication.logout(server, paths: host.paths, remove: remove)
                try host.reload()
                notice = remote.warning
            } catch { notice = VexAuthentication.message(for: error) }
        }
    }
}

private struct VexAddServerSheet: View {
    @Environment(ExperimentalHost.self) private var host
    @Environment(\.dismiss) private var dismiss
    let added: (VexServer) -> Void
    @State private var address = ""
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(Messages.VexLogin.addServer.localized).font(.title2)
            TextField(Messages.VexLogin.addressOrInvite.localized, text: $address).onSubmit { add() }
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Button(Messages.Common.cancel.localized) { dismiss() }
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Button(Messages.Servers.add.localized) { add() }.disabled(address.isEmpty || busy)
            }
        }.padding(24).frame(width: 480)
    }
    private func add() {
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                _ = try VexTransport.requireHTTPS(VexServerInput(address).baseURL)
                let server = try await VexAuthentication.add(address, paths: host.paths)
                address = ""
                try host.reload()
                added(server)
            } catch { self.error = VexAuthentication.message(for: error) }
        }
    }
}

struct VexLoginForm: View {
    @Environment(ExperimentalHost.self) private var host
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let server: VexServer
    let completed: () -> Void
    @State private var meta: VexMeta?
    @State private var invite = ""
    @State private var error: String?
    @State private var busy = false
    @State private var authorization: VexDeviceAuthorization?
    @State private var authentication: Task<Void, Never>?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(server.name).font(.title2)
            Text(server.baseURL).font(.caption).foregroundStyle(.secondary)
            if meta?.auth.methods.contains("github") == true {
                Button(Messages.VexDevices.github.localized) { github() }.disabled(busy)
            }
            if let authorization {
                Text(authorization.userCode).font(.title.monospaced()).textSelection(.enabled)
                HStack {
                    Button(Messages.AppAddAccountView.copyCode.localized) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(authorization.userCode, forType: .string)
                    }
                    Button(Messages.VexDevices.openBrowser.localized) { openURL(authorization.verificationURL) }
                }
                Text(Messages.VexDevices.waiting.localized).font(.caption)
            }
            if meta?.auth.methods.contains("invite") == true {
                TextField(Messages.VexLogin.invite.localized, text: $invite).onSubmit { login() }
                Text(Messages.VexLogin.inviteHelp.localized).font(.caption).foregroundStyle(.secondary)
                Button(Messages.VexLogin.login.localized) { login() }.disabled(invite.isEmpty || busy)
            }
            if let error { Text(error).foregroundStyle(.red) }
            if busy || meta == nil && error == nil { ProgressView().controlSize(.small) }
            Button(Messages.Common.cancel.localized) { dismiss() }
        }.padding(24).frame(width: 480)
        .task {
            do {
                guard host.configuration?.enabled("vex") == true else { throw CancellationError() }
                meta = try await VexClient(baseURL: VexTransport.requireHTTPS(VexSettings.normalizedURL(server.baseURL))).meta()
            }
            catch is CancellationError { }
            catch { self.error = VexAuthentication.message(for: error) }
        }
        .onDisappear { authentication?.cancel() }
        .onChange(of: host.configuration?.enabled("vex")) {
            if host.configuration?.enabled("vex") != true { authentication?.cancel(); dismiss() }
        }
    }
    private func login() {
        guard !busy, host.configuration?.enabled("vex") == true else { return }
        busy = true; error = nil; authorization = nil
        authentication = Task {
            defer { busy = false }
            do {
                let server = try await VexAuthentication.login(server, invite: invite)
                invite = ""
                try finished(server)
            } catch is CancellationError { }
            catch { self.error = VexAuthentication.message(for: error) }
        }
    }
    private func github() {
        guard !busy, host.configuration?.enabled("vex") == true else { return }
        busy = true; error = nil; authorization = nil
        authentication = Task {
            defer { busy = false; authorization = nil }
            do {
                let authorization = try await VexAuthentication.beginGitHub(server)
                self.authorization = authorization
                try finished(await VexAuthentication.finishGitHub(server, authorization: authorization))
            } catch is CancellationError { }
            catch { self.error = VexAuthentication.message(for: error) }
        }
    }
    private func finished(_ server: VexServer) throws {
        try Task.checkCancellation()
        try VexSettings.update(paths: host.paths) { try $0.save(server) }
        try host.reload()
        completed()
    }
}
