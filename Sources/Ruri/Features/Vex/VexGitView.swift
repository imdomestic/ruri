import SwiftUI
import RuriCore
import RuriLocalization

struct VexGitView: View {
    @Environment(VexPresentation.self) private var vex
    @State private var login: VexServer?
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(vex.connections) { connection in
                    if !vex.hidesGroupTitles { Text(connection.server.name).font(.title2) }
                    if connection.status != .loggedIn {
                        Text(connection.statusText).foregroundStyle(.secondary)
                        if connection.status == .expired || connection.status == .loggedOut {
                            Button(Messages.VexLogin.loginAgain.localized) { login = connection.server }
                        }
                    }
                    if let notice = connection.eventConnectionNotice {
                        Text(notice).font(.caption).foregroundStyle(.orange)
                    }
                    if let error = connection.error { Text(error).foregroundStyle(.red) }
                    ForEach(connection.projects) { project in
                        if !vex.hidesGroupTitles { Text(project.id).font(.headline) }
                        VexGitProjectView(server: connection, project: project).disabled(connection.status != .loggedIn)
                    }
                }
            }.padding()
        }
        .sheet(item: $login) { server in VexLoginForm(server: server) { login = nil } }
    }
}

private struct VexGitProjectView: View {
    @Environment(AppModel.self) private var model
    @Environment(VexPresentation.self) private var vex
    let server: VexServerConnection
    let project: VexProjectPresentation
    @State private var branch = ""
    @State private var commits: [VexCommit] = []
    @State private var graph: [VexCommitGraph.Row] = []
    @State private var log = ""
    @State private var busy = false
    @State private var action: Task<Void, Never>?
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Picker(Messages.Vex.git.localized, selection: $branch) {
                    ForEach(project.branches) { Text($0.name).tag($0.name) }
                }
                Button { action?.cancel(); action = Task { await server.refresh(project); if !Task.isCancelled { await load() } } } label: { Image(systemName: "arrow.clockwise") }
                    .help(Messages.Servers.refresh.localized)
            }.padding()
            LazyVStack(alignment: .leading) {
                ForEach(commits) { commit in
                    HStack(spacing: 12) {
                        if let row = graph.first(where: { $0.sha == commit.sha }) {
                            VexCommitGraphView(row: row, columns: graph.map(\.width).max() ?? 1).frame(minHeight: 80)
                        }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(commit.subject).font(.headline)
                        ForEach(commit.refs, id: \.self) { Text($0).font(.caption).foregroundStyle(.tint) }
                        Text([server.server.name, project.id, String(commit.sha.prefix(12)), commit.author, commit.time].joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(project.project.loaders ?? [], id: \.self) { loader in
                            HStack {
                                Text(loader)
                                Button(Messages.Vex.buildOnly.localized) { build(commit, loader: loader) }
                                Button(Messages.Vex.startTemporary.localized) { create(commit, loader: loader) }
                                if let summary = summary(commit, loader: loader) {
                                    Text(VexStateTitle.title(summary.status.rawValue))
                                    Button(Messages.Vex.buildLog.localized) { showLog(summary.id) }
                                }
                            }
                        }
                    }.padding(.vertical, 5)
                    }
                }
                if !commits.isEmpty {
                    Button(Messages.Vex.loadMore.localized) { action?.cancel(); action = Task { await load(more: true) } }
                }
        }.disabled(busy)
            if !log.isEmpty { ScrollView { Text(log).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }.frame(maxHeight: 220) }
        }
        .task(id: project.refreshID) {
            if !project.branches.contains(where: { $0.name == branch }) { branch = project.project.defaultBranch ?? project.branches.first?.name ?? "" }
            await load()
        }
        .task(id: branch) { await load() }
        .onDisappear { action?.cancel() }
    }
    private func summary(_ commit: VexCommit, loader: String) -> VexBuildSummary? {
        if let build = project.builds.first(where: { $0.project == commit.project && $0.sha == commit.sha && $0.loader == loader }) {
            return .init(id: build.id, status: build.status)
        }
        return commit.builds[loader] ?? nil
    }
    private func load(more: Bool = false) async {
        guard !branch.isEmpty else { commits = []; return }
        let client = project.client
        do {
            let values = try await client.commits(branch: branch, before: more ? commits.last?.sha : nil)
            try Task.checkCancellation()
            if more { commits += values } else { commits = values }
            graph = try VexCommitGraph.layout(commits.map { .init(sha: $0.sha, parents: $0.parents) })
        } catch is CancellationError { }
        catch { server.record(error) }
    }
    private func build(_ commit: VexCommit, loader: String) {
        let client = project.client
        action = Task {
            busy = true; defer { busy = false }
            do { _ = try await client.createBuild(sha: commit.sha, loader: loader); await load() }
            catch { server.record(error) }
        }
    }
    private func create(_ commit: VexCommit, loader: String) {
        let client = project.client
        action = Task {
            busy = true; defer { busy = false }
            do { let room = try await client.createRoom(sha: commit.sha, loader: loader, branch: branch); vex.join(room, server: server, model: model) }
            catch { server.record(error) }
        }
    }
    private func showLog(_ id: String) {
        let client = project.client
        action = Task { do { log = try await client.log(build: id) } catch { if !Task.isCancelled { server.record(error) } } }
    }
}
