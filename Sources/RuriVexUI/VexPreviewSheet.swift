import SwiftUI
import RuriCore
import RuriVex
import RuriExtensionKit
import RuriLocalization

struct VexPreviewSheet: View {
    @Environment(ExperimentalHost.self) private var host
    @Environment(VexPresentation.self) private var vex
    @Environment(\.dismiss) private var dismiss
    let link: VexPreviewLink
    @State private var login: VexServer?
    @State private var operation: Task<Void, Never>?
    @State private var busy = false
    @State private var error: String?
    private var server: VexServer? {
        vex.settings.servers.first { $0.baseURL == link.server.absoluteString }
    }
    private var connection: VexServerConnection? { vex.connections.first { $0.id == server?.id } }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(Messages.VexDevices.preview.localized).font(.title2)
            Text(server?.name ?? link.server.host ?? link.server.absoluteString).font(.headline)
            Text(link.server.absoluteString).textSelection(.enabled)
            LabeledContent(Messages.Vex.project.localized, value: link.project)
            Text(link.room).font(.headline).textSelection(.enabled)
            if server == nil { Text(Messages.VexDevices.unknownServer.localized).font(.caption) }
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Button(Messages.Common.cancel.localized) { operation?.cancel(); dismiss() }
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                if connection?.status == .loggedIn {
                    Button(Messages.VexDevices.join.localized) { join() }.disabled(busy)
                } else {
                    Button(server == nil ? Messages.VexLogin.addServer.localized : Messages.VexLogin.login.localized) { authenticate() }.disabled(busy)
                }
            }
        }.padding(24).frame(width: 480)
        .sheet(item: $login) { server in VexLoginForm(server: server) { login = nil } }
        .onDisappear { operation?.cancel() }
    }
    private func authenticate() {
        guard !busy, host.configuration?.enabled("vex") == true else { return }
        if let server { login = server; return }
        busy = true; error = nil
        operation = Task {
            defer { busy = false }
            do {
                _ = try VexTransport.requireHTTPS(link.server)
                let server = try await VexAuthentication.add(link.server.absoluteString, paths: host.paths)
                try Task.checkCancellation()
                try host.reload()
                login = server
            } catch is CancellationError { }
            catch { self.error = VexAuthentication.message(for: error) }
        }
    }
    private func join() {
        guard !busy, host.configuration?.enabled("vex") == true,
              let connection, connection.status == .loggedIn else { return }
        busy = true; error = nil
        operation = Task {
            defer { busy = false }
            do {
                guard let project = connection.projects.first(where: { $0.id == link.project }) else { throw RuriError.message(Messages.Vex.invalidResponse) }
                let room = try await project.client.room(link.room)
                try Task.checkCancellation()
                vex.join(room, server: connection, host: host)
                dismiss()
            } catch is CancellationError { }
            catch { self.error = VexAuthentication.message(for: error) }
        }
    }
}
