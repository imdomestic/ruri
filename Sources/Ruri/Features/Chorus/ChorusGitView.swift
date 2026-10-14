import SwiftUI
import RuriCore
import RuriLocalization

struct ChorusGitView: View {
    @Environment(AppModel.self) private var model
    @Environment(ChorusPresentation.self) private var chorus
    @State private var branches: [ChorusBranch] = []
    @State private var branch: String?
    @State private var commits: [ChorusCommit] = []
    @State private var graph: [ChorusCommitGraph.Row] = []
    @State private var selected: String?
    @State private var loader = "fabric"
    @State private var hasMore = false
    @State private var loading = false
    @State private var acting = false
    @State private var error: String?
    @State private var historyRequest = UUID()

    private var selectedCommit: ChorusCommit? { commits.first { $0.sha == selected } }
    private var columns: Int { graph.map(\.width).max() ?? 1 }
    private var loaders: [String] { chorus.meta?.loaders ?? ["fabric"] }

    var body: some View {
        HSplitView {
            List(selection: $branch) {
                ForEach(branches) { value in
                    Label(value.name, systemImage: "arrow.triangle.branch").tag(value.name)
                }
            }.listStyle(.sidebar).frame(minWidth: 130, idealWidth: 180, maxWidth: 280)
            VStack(spacing: 0) {
                if let error { Text(error).foregroundStyle(.red).textSelection(.enabled).padding() }
                if let error = chorus.error { Text(error).foregroundStyle(.red).textSelection(.enabled).padding() }
                if loading && commits.isEmpty { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
                else { history }
                if let commit = selectedCommit {
                    Divider()
                    details(commit).padding()
                }
            }.frame(minWidth: 400, maxWidth: .infinity)
        }
        .task(id: chorus.configurationRevision) { await refreshBranches() }
        .task(id: branch) { await loadHistory(append: false) }
        .task(id: chorus.gitRevision) {
            await refreshBranches()
            await loadHistory(append: false)
        }
    }

    private var history: some View {
        ScrollView([.vertical, .horizontal]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(zip(commits, graph)), id: \.0.sha) { commit, row in
                    HStack(spacing: 12) {
                        CommitGraphView(row: row, columns: columns)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(String(commit.sha.prefix(8))).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                                Text(commit.subject).lineLimit(1)
                                ForEach(commit.refs, id: \.self) { Text($0).font(.caption).foregroundStyle(.tint) }
                            }
                            HStack(spacing: 8) {
                                Text(commit.author).font(.caption).foregroundStyle(.secondary)
                                Text(commit.time).font(.caption).foregroundStyle(.secondary)
                                ForEach(loaders, id: \.self) { value in status(commit, loader: value) }
                            }
                        }
                        Spacer(minLength: 12)
                    }.frame(minWidth: 600, minHeight: 66, maxHeight: 66)
                        .padding(.horizontal, 10)
                        .background(selected == commit.sha ? Color.accentColor.opacity(0.12) : .clear)
                        .contentShape(Rectangle())
                        .onTapGesture { selected = commit.sha }
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(selected == commit.sha ? [.isSelected, .isButton] : .isButton)
                        .accessibilityAction { selected = commit.sha }
                }
                if hasMore {
                    Button(Messages.Chorus.loadMore.localized) { Task { await loadHistory(append: true) } }
                        .disabled(loading).padding()
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func build(_ commit: ChorusCommit, loader: String) -> ChorusBuildSummary? {
        if let current = chorus.builds.first(where: { $0.sha == commit.sha && $0.loader == loader }) {
            return .init(id: current.id, status: current.status)
        }
        return commit.builds[loader] ?? nil
    }

    @ViewBuilder private func status(_ commit: ChorusCommit, loader: String) -> some View {
        let value = build(commit, loader: loader)
        let symbol = switch value?.status {
        case .none: "circle.dashed"
        case .queued: "clock"
        case .building: "hammer"
        case .ready: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        }
        Button {
            if let value { chorus.showBuildLog(value.id) }
        } label: {
            Label(loader, systemImage: symbol)
                .foregroundStyle(value?.status == .failed ? Color.red : value?.status == .ready ? Color.green : Color.secondary)
        }.buttonStyle(.plain).font(.caption).disabled(value == nil)
            .help(ChorusStateBadge.title(value?.status.rawValue ?? ""))
    }

    private func details(_ commit: ChorusCommit) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(commit.subject).font(.headline)
            Text(commit.sha).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            HStack {
                Picker(Messages.AppCreateInstanceView.loader.localized, selection: $loader) { ForEach(loaders, id: \.self) { Text($0).tag($0) } }.labelsHidden().frame(width: 130)
                Button(Messages.Chorus.buildOnly.localized) { perform(commit, launch: false) }
                Button(Messages.Chorus.startTemporary.localized) { perform(commit, launch: true) }.buttonStyle(.borderedProminent)
                if let build = build(commit, loader: loader) {
                    Button(Messages.Chorus.buildLog.localized) { chorus.showBuildLog(build.id) }
                }
                if acting { ProgressView().controlSize(.small) }
            }.disabled(acting || chorus.joining || model.busy || branch == nil)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func refreshBranches() async {
        do {
            let client = try ChorusSettings.load(paths: model.basePaths).client()
            let values = try await client.branches()
            try Task.checkCancellation()
            branches = values
            if branch == nil || !values.contains(where: { $0.name == branch }) { branch = values.first?.name }
            if !loaders.contains(loader), let first = loaders.first { loader = first }
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }

    private func loadHistory(append: Bool) async {
        guard let branch else { commits = []; graph = []; return }
        if append && loading { return }
        let request = UUID(); historyRequest = request; loading = true; error = nil
        if !append { commits = []; graph = []; hasMore = false }
        defer { if historyRequest == request { loading = false } }
        do {
            let client = try ChorusSettings.load(paths: model.basePaths).client()
            let page = try await client.commits(branch: branch, before: append ? commits.last?.sha : nil)
            try Task.checkCancellation()
            guard historyRequest == request else { return }
            let combined = append ? commits + page : page
            let rows = try ChorusCommitGraph.layout(combined.map { .init(sha: $0.sha, parents: $0.parents) })
            commits = combined; graph = rows; hasMore = page.count == 50
            if !commits.contains(where: { $0.sha == selected }) { selected = commits.first?.sha }
        } catch is CancellationError {} catch { if historyRequest == request { self.error = error.localizedDescription } }
    }

    private func perform(_ commit: ChorusCommit, launch: Bool) {
        guard let branch, let client = chorus.client else { return }
        if launch && model.activeAccount == nil { model.showAccount = true; return }
        acting = true; error = nil
        Task {
            defer { acting = false }
            do {
                if launch {
                    let room = try await client.createRoom(sha: commit.sha, loader: loader, branch: branch)
                    chorus.upsert(room)
                    chorus.join(room, model: model)
                } else {
                    let value = try await client.createBuild(sha: commit.sha, loader: loader)
                    chorus.builds.removeAll { $0.id == value.id }; chorus.builds.append(value)
                }
            } catch { self.error = error.localizedDescription }
        }
    }
}
