import SwiftUI
import AppKit
import RuriCore
import RuriLocalization

struct ChorusRoomsSection: View {
    @Environment(ChorusPresentation.self) private var chorus
    @Environment(AppModel.self) private var model
    @State private var expanded = false
    var body: some View {
        Section(Messages.Chorus.title.localized) {
            ForEach(chorus.rooms.filter { $0.kind == "branch" }) { room in
                ChorusRoomRow(room: room).tag("chorus:" + room.id)
            }
            if let error = chorus.error {
                Text(error).font(.caption).foregroundStyle(.orange)
                Button(Messages.AppRuriApp.settings.localized) { model.page = .settings }
            }
            let temporary = chorus.rooms.filter { $0.kind != "branch" && ![.closed, .stopped].contains($0.state) }
            if !temporary.isEmpty {
                DisclosureGroup(Messages.Chorus.temporaryRooms.localized, isExpanded: $expanded) {
                    ForEach(temporary) { room in ChorusRoomRow(room: room).tag("chorus:" + room.id) }
                }
            }
        }
    }
}

private struct ChorusRoomRow: View {
    let room: ChorusRoom
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "server.rack").font(.title2).foregroundStyle(room.state == .ready ? .green : .secondary)
            VStack(alignment: .leading, spacing: 4) {
                HStack { Text(room.branch ?? room.id).fontWeight(.medium); Spacer(); ChorusStateBadge(state: room.state.rawValue) }
                Text([room.loader, String(room.sha.prefix(7))].joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                if room.behindHead { Text(Messages.Chorus.behindHead.localized).font(.caption).foregroundStyle(.orange) }
            }
        }.padding(.vertical, 4)
    }
}

struct ChorusStateBadge: View {
    let state: String
    static func title(_ state: String) -> String {
        switch state {
        case "stopped": Messages.Chorus.stateStopped.localized
        case "queued": Messages.Chorus.stateQueued.localized
        case "building": Messages.Chorus.stateBuilding.localized
        case "starting": Messages.Chorus.stateStarting.localized
        case "ready": Messages.Chorus.stateReady.localized
        case "stopping": Messages.Chorus.stateStopping.localized
        case "archiving": Messages.Chorus.stateArchiving.localized
        case "closed": Messages.Chorus.stateClosed.localized
        case "failed": Messages.Chorus.stateFailed.localized
        case "lost": Messages.Chorus.stateLost.localized
        default: Messages.Chorus.unbuilt.localized
        }
    }
    var body: some View {
        Text(Self.title(state)).font(.caption2).fontWeight(.medium).padding(.horizontal, 6).padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule()).foregroundStyle(color)
    }
    private var color: Color {
        switch state { case "ready": .green; case "failed", "lost": .red; case "building", "starting", "queued": .orange; default: .secondary }
    }
}

struct ChorusRoomDetail: View {
    @Environment(ChorusPresentation.self) private var chorus
    @Environment(AppModel.self) private var model
    let room: ChorusRoom
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 16) {
                    Image(systemName: "server.rack").font(.system(size: 42)).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(room.branch ?? room.id).font(.title).fontWeight(.semibold)
                        Text(room.host + ":" + String(room.port)).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    Spacer(); ChorusStateBadge(state: room.state.rawValue)
                }
                HStack {
                    Button(Messages.Servers.joinButton.localized) { chorus.join(room, model: model) }
                        .buttonStyle(.borderedProminent).disabled(chorus.joining || model.busy || room.label == "finished")
                    Button(Messages.Servers.copyAddress.localized) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(room.host + ":" + String(room.port), forType: .string)
                    }
                    Menu {
                        Button(Messages.Chorus.stop.localized) { chorus.change(room, action: "stop") }
                        Button(Messages.Chorus.restart.localized) { chorus.change(room, action: "restart") }
                        Button(Messages.Chorus.buildLog.localized) { chorus.showBuildLog(room.buildId) }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
                Picker(Messages.Chorus.testing.localized, selection: Binding(get: { room.label }, set: { chorus.setLabel(room, finished: $0 == "finished") })) {
                    Text(Messages.Chorus.testing.localized).tag("testing")
                    Text(Messages.Chorus.finished.localized).tag("finished")
                }.pickerStyle(.segmented)
                VStack(alignment: .leading, spacing: 8) {
                    Text(room.buildId).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                    Text(room.phase).foregroundStyle(.secondary)
                    if room.behindHead { Label(Messages.Chorus.behindHead.localized, systemImage: "arrow.triangle.branch").foregroundStyle(.orange) }
                    ForEach(room.players, id: \.uuid) { player in Label(player.name, systemImage: "person.fill") }
                    if let error = room.lastError { Text(error.message).foregroundStyle(.red).textSelection(.enabled) }
                }
            }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
