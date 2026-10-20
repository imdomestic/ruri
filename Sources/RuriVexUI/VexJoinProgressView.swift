import SwiftUI
import RuriLocalization

struct VexJoinProgressView: View {
    @Environment(VexPresentation.self) private var vex
    var body: some View {
        if let progress = vex.progress {
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(progress.local)
                Text(progress.room.phase).font(.caption)
                Button(Messages.Common.cancel.localized) { vex.cancelJoin() }
            }
        }
    }
}
