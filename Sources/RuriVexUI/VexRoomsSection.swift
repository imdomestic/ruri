import SwiftUI
import AppKit
import RuriCore
import RuriVex
import RuriExtensionKit
import RuriLocalization

struct VexRoomsSection: View {
    @Environment(ExperimentalHost.self) private var host
    @Environment(VexPresentation.self) private var vex
    @State private var selected: Selection?
    @State private var login: VexServer?
    private struct Selection: Identifiable {
        let server: VexServerConnection
        let room: VexRoom
        var id: String { server.id + "/" + room.project + "/" + room.id }
    }
    var body: some View {
        Section {
            ForEach(vex.connections) { connection in
                if !vex.hidesGroupTitles { Text(connection.server.name).font(.headline) }
                if connection.status != .loggedIn {
                    Text(connection.statusText).font(.caption).foregroundStyle(.secondary)
                    if connection.status == .expired || connection.status == .loggedOut {
                        Button(Messages.VexLogin.loginAgain.localized) { login = connection.server }
                    }
                }
                if let notice = connection.eventConnectionNotice {
                    Text(notice).font(.caption).foregroundStyle(.orange)
                }
                ForEach(connection.nodes.filter(\.hasLowDiskSpace)) { node in
                    if let bytes = node.rootFreeBytes {
                        Label(Messages.VexRooms.lowDiskSpace(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .binary)).localized,
                              systemImage: "externaldrive.badge.exclamationmark").font(.caption).foregroundStyle(.orange)
                    }
                }
                if let error = connection.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                ForEach(connection.projects) { project in
                    if !vex.hidesGroupTitles { Text(project.id).font(.subheadline) }
                    ForEach(project.rooms.filter { $0.kind == "branch" }) { room in row(room, server: connection) }
                    DisclosureGroup(Messages.VexRooms.temporaryRooms.localized) {
                        ForEach(project.rooms.filter { $0.kind != "branch" && ![.closed, .stopped].contains($0.state) }) { room in row(room, server: connection) }
                    }
                    DisclosureGroup(Messages.Vex.recentlyClosed.localized) {
                        ForEach(VexServerPolicy.recentlyClosed(project.rooms)) { room in row(room, server: connection) }
                    }
                }.disabled(connection.status != .loggedIn)
            }
            VexJoinProgressView()
        } header: {
            HStack {
                Text(Messages.Vex.title.localized)
                Spacer()
                Button { Task { await withTaskGroup(of: Void.self) { group in
                    for connection in vex.connections { group.addTask { await connection.refresh() } }
                } } } label: { Image(systemName: "arrow.clockwise") }
                    .help(Messages.Servers.refresh.localized).disabled(vex.connections.isEmpty)
            }
        }
        .sheet(item: $selected) { value in VexRoomDetail(server: value.server, initial: value.room).frame(minWidth: 560, minHeight: 400) }
        .sheet(item: $login) { server in VexLoginForm(server: server) { login = nil } }
    }
    private func row(_ room: VexRoom, server: VexServerConnection) -> some View {
        Button { selected = Selection(server: server, room: room) } label: {
            VStack(alignment: .leading) {
                Text(room.project + " / " + room.id).font(.headline)
                Text([VexStateTitle.title(room.state.rawValue), room.phase, room.host + ":" + String(room.port)].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                if room.behindHead { Text(Messages.VexRooms.behindHead.localized).font(.caption).foregroundStyle(.orange) }
            }
        }.buttonStyle(.plain).disabled(vex.progress != nil || host.readOnly)
    }
}

enum VexStateTitle {
    static func title(_ value: String) -> String {
        switch value {
        case "stopped": Messages.VexRooms.stopped.localized
        case "queued": Messages.VexRooms.queued.localized
        case "building": Messages.VexRooms.building.localized
        case "starting": Messages.VexRooms.starting.localized
        case "ready": Messages.VexRooms.ready.localized
        case "stopping": Messages.VexRooms.stopping.localized
        case "archiving": Messages.VexRooms.archiving.localized
        case "closed": Messages.VexRooms.closed.localized
        case "failed": Messages.VexRooms.failed.localized
        case "lost": Messages.VexRooms.lost.localized
        default: value
        }
    }
}

private struct VexRoomDetail: View {
    @Environment(ExperimentalHost.self) private var host
    @Environment(VexPresentation.self) private var vex
    @Environment(\.dismiss) private var dismiss
    let server: VexServerConnection
    let initial: VexRoom
    @State private var action: Task<Void, Never>?
    @State private var busy = false
    @State private var log = ""
    private var project: VexProjectPresentation? { server.projects.first { $0.id == initial.project } }
    private var room: VexRoom { project?.rooms.first { $0.id == initial.id } ?? initial }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(server.server.name + " / " + room.project + " / " + room.id).font(.title)
                Text(room.host + ":" + String(room.port)).textSelection(.enabled)
                Text(VexStateTitle.title(room.state.rawValue))
                HStack {
                    Button(room.state == .closed ? Messages.VexRooms.reopen.localized : Messages.Servers.joinButton.localized) {
                        vex.join(room, server: server, host: host); dismiss()
                    }.disabled(vex.progress != nil || host.busy || (room.label == "finished" && room.state != .closed))
                    Button(Messages.Servers.copyAddress.localized) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(room.host + ":" + String(room.port), forType: .string)
                    }
                    Menu {
                        Button(Messages.VexRooms.stop.localized) { change("stop") }
                        Button(Messages.VexRooms.restart.localized) { change("restart") }
                        Button(Messages.Vex.buildLog.localized) { showLog() }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
                Picker(Messages.VexRooms.testing.localized, selection: Binding(get: { room.label }, set: { label($0 == "finished") })) {
                    Text(Messages.VexRooms.testing.localized).tag("testing")
                    Text(Messages.VexRooms.finished.localized).tag("finished")
                }.pickerStyle(.segmented)
                Text(room.buildId).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                Text(room.phase).foregroundStyle(.secondary)
                if room.behindHead { Text(Messages.VexRooms.behindHead.localized).foregroundStyle(.orange) }
                ForEach(room.players, id: \.uuid) { player in Label(player.name, systemImage: "person.fill") }
                if let error = room.lastError { Text(error.message).foregroundStyle(.red) }
                if let error = server.error { Text(error).foregroundStyle(.red) }
                if !log.isEmpty { Text(log).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
                Button(Messages.Common.done.localized) { dismiss() }
            }.padding(24).disabled(busy || host.readOnly)
        }.onDisappear { action?.cancel() }
    }
    private func change(_ name: String) {
        guard let project else { return }
        let client = project.client
        action = Task {
            busy = true; defer { busy = false }
            do { _ = try await client.changeRoom(room.id, action: name); await server.refresh(project) }
            catch { if !Task.isCancelled { server.record(error) } }
        }
    }
    private func label(_ finished: Bool) {
        guard let project else { return }
        let client = project.client
        action = Task {
            busy = true; defer { busy = false }
            do { _ = try await client.label(room.id, finished: finished); await server.refresh(project) }
            catch { if !Task.isCancelled { server.record(error) } }
        }
    }
    private func showLog() {
        guard let client = project?.client else { return }
        action = Task {
            do { log = try await client.log(build: room.buildId) }
            catch { if !Task.isCancelled { server.record(error) } }
        }
    }
}
