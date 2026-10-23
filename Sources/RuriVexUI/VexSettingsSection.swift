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
    @Environment(VexPresentation.self) private var vex
    @Environment(\.dismiss) private var dismiss
    let added: (VexServer) -> Void
    @State private var address = ""
    @State private var busy = false
    @State private var error: String?
    @State private var authenticationOwner = UUID()
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(Messages.VexLogin.addServer.localized).font(.title2)
            TextField(Messages.VexLogin.addressOrInvite.localized, text: $address).onSubmit { add() }
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Button(Messages.Common.cancel.localized) { cancelAuthentication(); dismiss() }
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Button(Messages.Servers.add.localized) { add() }.disabled(address.isEmpty || busy)
            }
        }.padding(24).frame(width: 480)
        .onDisappear { cancelAuthentication() }
        .onChange(of: host.vexEnabled) {
            if !host.vexEnabled { cancelAuthentication(); dismiss() }
        }
    }
    private func add() {
        guard !busy, host.vexEnabled else { return }
        let started = vex.startAuthentication(owner: authenticationOwner) { id in
            defer {
                if vex.ownsAuthentication(owner: authenticationOwner, operation: id) { busy = false }
            }
            do {
                _ = try VexTransport.requireHTTPS(VexServerInput(address).baseURL)
                let server = try await VexAuthentication.add(address, paths: host.paths)
                try Task.checkCancellation()
                guard host.vexEnabled, vex.ownsAuthentication(owner: authenticationOwner, operation: id) else { throw CancellationError() }
                address = ""
                try host.reload()
                added(server)
            } catch is CancellationError { }
            catch {
                guard !Task.isCancelled, vex.ownsAuthentication(owner: authenticationOwner, operation: id) else { return }
                self.error = VexAuthentication.message(for: error)
            }
        }
        if started { busy = true; error = nil }
    }
    private func cancelAuthentication() {
        vex.cancelAuthentication(owner: authenticationOwner)
        busy = false
    }
}

struct VexLoginForm: View {
    @Environment(ExperimentalHost.self) private var host
    @Environment(VexPresentation.self) private var vex
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let server: VexServer
    let completed: () -> Void
    @State private var meta: VexMeta?
    @State private var invite = ""
    @State private var error: String?
    @State private var busy = false
    @State private var authorization: VexDeviceAuthorization?
    @State private var authenticationOwner = UUID()
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
            Button(Messages.Common.cancel.localized) { cancelAuthentication(); dismiss() }
        }.padding(24).frame(width: 480)
        .task {
            authenticate { id in
                let meta = try await VexClient(baseURL: VexTransport.requireHTTPS(VexSettings.normalizedURL(server.baseURL))).meta()
                try checkAuthentication(id)
                self.meta = meta
            }
        }
        .onDisappear { cancelAuthentication() }
        .onChange(of: host.vexEnabled) {
            if !host.vexEnabled { cancelAuthentication(); dismiss() }
        }
    }
    private func authenticate(_ operation: @escaping @MainActor (UUID) async throws -> Void) {
        guard !busy, host.vexEnabled else { return }
        let started = vex.startAuthentication(owner: authenticationOwner) { id in
            defer {
                if vex.ownsAuthentication(owner: authenticationOwner, operation: id) {
                    busy = false; authorization = nil
                }
            }
            do { try await operation(id) }
            catch is CancellationError { }
            catch {
                guard !Task.isCancelled, vex.ownsAuthentication(owner: authenticationOwner, operation: id) else { return }
                self.error = VexAuthentication.message(for: error)
            }
        }
        if started { busy = true; error = nil; authorization = nil }
    }
    private func cancelAuthentication() {
        vex.cancelAuthentication(owner: authenticationOwner)
        busy = false; authorization = nil
    }
    private func checkAuthentication(_ id: UUID) throws {
        try Task.checkCancellation()
        guard host.vexEnabled, vex.ownsAuthentication(owner: authenticationOwner, operation: id) else {
            throw CancellationError()
        }
    }
    private func login() {
        authenticate { id in
            let server = try await VexAuthentication.login(server, invite: invite)
            try checkAuthentication(id)
            invite = ""
            try finished(server, operation: id)
        }
    }
    private func github() {
        authenticate { id in
            let authorization = try await VexAuthentication.beginGitHub(server)
            try checkAuthentication(id)
            self.authorization = authorization
            let server = try await VexAuthentication.finishGitHub(server, authorization: authorization)
            try finished(server, operation: id)
        }
    }
    private func finished(_ server: VexServer, operation: UUID) throws {
        try checkAuthentication(operation)
        try VexSettings.update(paths: host.paths) { try $0.save(server) }
        try host.reload()
        completed()
    }
}
