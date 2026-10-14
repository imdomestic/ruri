import SwiftUI
import RuriLocalization

struct RoomStartingSheet: View {
    @Environment(ChorusPresentation.self) private var chorus
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(chorus.joinProgress?.room.id ?? Messages.Chorus.title.localized).font(.title2).fontWeight(.semibold)
            if let value = chorus.joinProgress {
                HStack { ChorusStateBadge(state: value.room.state.rawValue); Text(value.room.phase) }
                Text(value.local).foregroundStyle(.secondary)
                if !value.unmanaged.isEmpty { Text(Messages.Chorus.unmanagedMods(value.unmanaged.joined(separator: ", ")).localized).foregroundStyle(.orange) }
                if chorus.joining { ProgressView().controlSize(.small) }
            }
            if let error = chorus.joinError { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                if let build = chorus.joinProgress?.room.buildId { Button(Messages.Chorus.buildLog.localized) { chorus.showBuildLog(build) } }
                Spacer()
                Button(Messages.Common.cancel.localized) { chorus.cancelJoin() }.keyboardShortcut(.cancelAction)
            }
        }.padding(24).frame(width: 510)
            .sheet(isPresented: Binding(get: { chorus.log != nil }, set: { if !$0 { chorus.log = nil } })) { ChorusBuildLogSheet().environment(chorus) }
    }
}

struct ChorusBuildLogSheet: View {
    @Environment(ChorusPresentation.self) private var chorus
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(Messages.Chorus.buildLog.localized).font(.headline)
                Spacer()
                Button(Messages.AppRootView.ok.localized) { chorus.log = nil }.keyboardShortcut(.cancelAction)
            }
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 12) {
                    if let error = chorus.logBuild?.lastError {
                        Text(error.code + ": " + error.message).foregroundStyle(.red)
                    }
                    Text(chorus.log ?? "")
                }.font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(20).frame(width: 760, height: 480)
    }
}
