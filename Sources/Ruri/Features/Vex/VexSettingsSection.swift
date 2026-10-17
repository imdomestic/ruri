import SwiftUI
import RuriCore
import RuriLocalization

private enum VexLoginSheet: Identifiable {
    case add, login(VexServer)
    var id: String { switch self { case .add: "add"; case .login(let server): server.id } }
}

struct VexSettingsSection: View {
    @Environment(AppModel.self) private var model
    @Environment(VexPresentation.self) private var vex
    @State private var sheet: VexLoginSheet?
    @State private var renaming: VexServer?
    @State private var name = ""
    @State private var notice: String?
    private var settings: VexSettings { model.state.settings.experimental?.vex ?? VexSettings() }
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
                            Button(Messages.VexLogin.testConnection.localized) { Task { await connection?.testConnection(paths: model.paths) } }
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
        .disabled(model.readOnly)
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
        do { try VexSettings.update(paths: model.paths, change); model.acceptState(try StateStore.load(model.paths)) }
        catch { model.error = VexAuthentication.message(for: error) }
    }
    private func logout(_ server: VexServer, remove: Bool) {
        Task {
            do {
                let remote = try await VexAuthentication.logout(server, paths: model.paths, remove: remove)
                model.acceptState(try StateStore.load(model.paths))
                notice = remote.warning
            } catch { notice = VexAuthentication.message(for: error) }
        }
    }
}

private struct VexAddServerSheet: View {
    @Environment(AppModel.self) private var model
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
                let server = try await VexAuthentication.add(address, paths: model.paths)
                address = ""
                model.acceptState(try StateStore.load(model.paths))
                added(server)
            } catch { self.error = VexAuthentication.message(for: error) }
        }
    }
}

struct VexLoginForm: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let server: VexServer
    let completed: () -> Void
    @State private var meta: VexMeta?
    @State private var invite = ""
    @State private var error: String?
    @State private var busy = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(server.name).font(.title2)
            Text(server.baseURL).font(.caption).foregroundStyle(.secondary)
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
            do { meta = try await VexClient(baseURL: VexSettings.normalizedURL(server.baseURL)).meta() }
            catch { self.error = VexAuthentication.message(for: error) }
        }
    }
    private func login() {
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                let server = try await VexAuthentication.login(server, invite: invite)
                invite = ""
                try VexSettings.update(paths: model.paths) { try $0.save(server) }
                model.acceptState(try StateStore.load(model.paths))
                completed()
            } catch { self.error = VexAuthentication.message(for: error) }
        }
    }
}
