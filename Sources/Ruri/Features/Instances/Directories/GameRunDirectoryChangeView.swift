import RuriLocalization
import SwiftUI
import AppKit
import RuriCore

struct GameRunDirectoryChangeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let instance: GameInstance
    @State private var target: GameRunDirectory
    @State private var customDirectory: CustomRunDirectory?
    @State private var chosenURL: URL?
    @State private var selectionRequest = UUID()
    @State private var registering = false
    @State private var preview: GameRunDirectoryChangePreview?
    @State private var recovery: RunDirectoryCopyRecovery?
    @State private var copyFiles = false
    @State private var choiceFor: String?
    @State private var cancelling = false
    @State private var loading = false
    @State private var issue: String?
    @State private var registrationIssue: String?
    @State private var refresh = UUID()
    init(instance: GameInstance) {
        self.instance = instance
        _target = State(initialValue: (instance.runDirectory ?? .isolated) == .isolated ? .shared : .isolated)
        _customDirectory = State(initialValue: instance.customRunDirectory)
    }
    private var checking: Bool { loading || registering }
    private var needsFolder: Bool { target == .custom && customDirectory == nil }
    private var previewTaskID: String {
        "\(target.rawValue)\(customDirectory?.url.path ?? "")\(selectionRequest.uuidString)\(refresh.uuidString)"
    }
    private var destination: URL? {
        if target == .custom {
            return registering || registrationIssue != nil ? chosenURL ?? customDirectory?.url : customDirectory?.url
        }
        var changed = instance
        changed.runDirectory = target
        return model.paths.including(changed).game(instance.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            if let recovery {
                recoveryDetails(recovery)
            } else {
                directorySelection
                if let preview {
                    contentOptions(preview)
                }
            }
            if let issue = registrationIssue ?? issue {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(issue).font(.callout).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button(Messages.AppGameRunDirectoryChangeView.recheck.localized, action: recheck)
                        .fixedSize().disabled(checking || model.busy)
                }
            }
            footer
        }.padding(24).frame(width: 580).fixedSize(horizontal: false, vertical: true)
        .interactiveDismissDisabled(model.busy)
        .task(id: selectionRequest) {
            guard let chosenURL else { return }
            registering = true; registrationIssue = nil; issue = nil
            let paths = model.paths
            do {
                let selected = try await Task.detached(priority: .userInitiated) { try CustomRunDirectory.register(at: chosenURL, paths: paths) }.value
                try Task.checkCancellation(); customDirectory = selected; refresh = UUID()
            } catch { if !Task.isCancelled { preview = nil; registrationIssue = error.localizedDescription } }
            if !Task.isCancelled { registering = false }
        }
        .task(id: previewTaskID) {
            guard !registering else { loading = false; return }
            if preview?.targetMode != target || preview?.target != destination { preview = nil }
            issue = nil; registrationIssue = nil; loading = true
            do {
                let service = GameRunDirectoryChange(paths: model.paths)
                let pending = try await service.pendingCopy(instanceID: instance.id)
                try Task.checkCancellation()
                if let pending { recovery = pending }
                else {
                    recovery = nil
                    if needsFolder { preview = nil; copyFiles = false }
                    else {
                        let result = try await service.preview(instanceID: instance.id, target: target, customDirectory: customDirectory)
                        try Task.checkCancellation(); preview = result
                        let choice = target.rawValue + result.target.path
                        if choiceFor != choice { copyFiles = result.canCopyToTarget && result.sourceFileCount > 0; choiceFor = choice }
                        else if !result.canCopyToTarget { copyFiles = false }
                    }
                }
            } catch { if !Task.isCancelled { preview = nil; issue = error.localizedDescription } }
            if !Task.isCancelled { loading = false }
        }
        .onChange(of: model.paths.game(instance.id)) {
            if model.state.instances.first(where: { $0.id == instance.id })?.runDirectory == target,
               (target != .custom || model.state.instances.first(where: { $0.id == instance.id })?.customRunDirectory?.id == customDirectory?.id),
               !RunDirectoryCopyGuard.hasPending(paths: model.paths, instanceID: instance.id) { dismiss() }
        }
        .onChange(of: model.busy) { if !model.busy { cancelling = false; refresh = UUID() } }
    }
    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(recovery == nil ? Messages.AppGameRunDirectoryChangeView.changeRunDirectory.localized : Messages.AppGameRunDirectoryChangeView.recoverDirectoryCopy.localized)
                    .font(.title2.weight(.semibold))
                Text(recovery?.owner.instanceName ?? instance.name).font(.callout).foregroundStyle(.secondary)
                    .lineLimit(2).textSelection(.enabled)
            }
            Spacer(minLength: 0)
            if (preview != nil || recovery != nil) && issue == nil && registrationIssue == nil {
                Button(Messages.AppGameRunDirectoryChangeView.refreshPreview.localized, systemImage: "arrow.clockwise") { refresh = UUID() }
                    .labelStyle(.iconOnly).buttonStyle(.borderless)
                    .help(Messages.AppGameRunDirectoryChangeView.refreshPreview.localized)
                    .disabled(checking || model.busy)
            }
        }
    }

    private var directorySelection: some View {
        VStack(alignment: .leading, spacing: 8) {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Picker(Messages.AppGameRunDirectoryChangeView.directoryType.localized, selection: $target) {
                        Text(Messages.AppGameRunDirectoryChangeView.isolatedOption.localized).tag(GameRunDirectory.isolated)
                        Text(Messages.AppGameRunDirectoryChangeView.sharedOption.localized).tag(GameRunDirectory.shared)
                        Text(Messages.AppGameRunDirectoryChangeView.customOption.localized).tag(GameRunDirectory.custom)
                    }.pickerStyle(.menu).disabled(model.busy || registering)
                    Divider()
                    HStack(spacing: 12) {
                        Image(systemName: "folder").font(.title3).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            if let destination {
                                Text(destination.lastPathComponent).lineLimit(1).truncationMode(.middle)
                                Text(destination.path).font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(2).truncationMode(.middle).textSelection(.enabled).help(destination.path)
                            } else {
                                Text(Messages.AppGameRunDirectoryChangeView.noFolderSelected.localized).foregroundStyle(.secondary)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        if target == .custom {
                            Button(customDirectory == nil ? Messages.AppGameRunDirectoryChangeView.chooseFolder.localized : Messages.AppGameRunDirectoryChangeView.changeFolder.localized, action: chooseFolder)
                                .fixedSize().disabled(model.busy || registering)
                        } else if let destination {
                            revealButton(destination)
                        }
                    }
                }.padding(8)
            }
            Text(target.explanation).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func contentOptions(_ preview: GameRunDirectoryChangePreview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(Messages.AppGameRunDirectoryChangeView.contentHandling.localized).font(.headline)
                Picker(Messages.AppGameRunDirectoryChangeView.contentHandling.localized, selection: $copyFiles) {
                    Text(Messages.AppGameRunDirectoryChangeView.copyCurrentContentToEmptyTarget.localized).tag(true).disabled(!preview.canCopyToTarget)
                    Text(Messages.AppGameRunDirectoryChangeView.useExistingContent.localized).tag(false)
                }.pickerStyle(.radioGroup).labelsHidden().disabled(checking || model.busy)
                if let copyIssue = preview.copyIssue {
                    Text(copyIssue).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if !preview.canCopyToTarget {
                    Text(Messages.AppGameRunDirectoryChangeView.targetContainsFiles.localized).font(.caption).foregroundStyle(.secondary)
                }
                Text(copyFiles ? Messages.AppGameRunDirectoryChangeView.copyBeforeSwitching.localized : preview.targetFileCount == 0 ? Messages.AppGameRunDirectoryChangeView.emptyTargetDetails.localized : Messages.AppGameRunDirectoryChangeView.useExistingTargetDetails.localized)
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if !preview.otherInstances.isEmpty {
                    Text(Messages.AppGameRunDirectoryChangeView.sharedInstances(LocalizedFormat.list(preview.otherInstances)).localized)
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            DisclosureGroup(Messages.AppGameRunDirectoryChangeView.fileDetails.localized) {
                VStack(alignment: .leading, spacing: 12) {
                    location(Messages.AppGameRunDirectoryChangeView.sourceDirectory.localized, url: preview.source, files: preview.sourceFileCount, bytes: preview.sourceBytes)
                    Divider()
                    location(Messages.AppGameRunDirectoryChangeView.targetDirectory.localized, url: preview.target, files: preview.targetFileCount, bytes: preview.targetBytes)
                    if instance.repositoryVersionID != nil {
                        Text(Messages.AppGameRunDirectoryChangeView.gameFilesStayInPlace.localized).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(.top, 8)
            }.font(.callout)
        }
    }

    private func recoveryDetails(_ recovery: RunDirectoryCopyRecovery) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Label(recovery.committed ? Messages.AppGameRunDirectoryChangeView.copySubmittedAwaitingCleanup.localized : Messages.AppGameRunDirectoryChangeView.copyIncomplete.localized, systemImage: "arrow.counterclockwise.circle")
                    .font(.headline)
                Text(recovery.committed ? Messages.AppGameRunDirectoryChangeView.recoveryCleanupDetails.localized : Messages.AppGameRunDirectoryChangeView.recoveryPreservationDetails.localized)
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    location(Messages.AppGameRunDirectoryChangeView.sourceDirectory.localized, url: recovery.source)
                    Divider()
                    location(Messages.AppGameRunDirectoryChangeView.targetDirectory.localized, url: recovery.target)
                }.padding(8)
            }
            HStack {
                Text(Messages.AppGameRunDirectoryChangeView.copyStartedAt(LocalizedFormat.date(recovery.createdAt, date: .abbreviated, time: .shortened)).localized)
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(Messages.AppGameRunDirectoryChangeView.viewWorkspaceInFinder.localized) { NSWorkspace.shared.open(recovery.workspace) }
                    .disabled(model.busy)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if model.busy {
                ProgressView().controlSize(.small)
                Text(cancelling ? Messages.AppGameRunDirectoryChangeView.cancellingAndKeepingWorkCopy.localized : model.activeActivity?.progress.stage ?? Messages.AppGameRunDirectoryChangeView.processingDirectory.localized)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            } else if checking {
                ProgressView().controlSize(.small)
                Text(registering ? Messages.AppGameRunDirectoryChangeView.preparingSelectedDirectory.localized : Messages.AppGameRunDirectoryChangeView.checkingDirectoryFiles.localized)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
            Button(Messages.Common.cancel.localized) {
                if model.busy { cancelling = true; model.operation?.cancel() } else { dismiss() }
            }.keyboardShortcut(.cancelAction).disabled(cancelling || (model.busy && recovery != nil))
            if let recovery {
                Button(recovery.committed ? Messages.AppGameRunDirectoryChangeView.completeRecovery.localized : Messages.AppGameRunDirectoryChangeView.recoverAndKeepCopy.localized) { model.recoverGameRunDirectory(recovery) }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(model.busy || checking)
            } else {
                Button(copyFiles && preview != nil ? Messages.AppGameRunDirectoryChangeView.copyAndSwitch.localized : Messages.AppGameRunDirectoryChangeView.switchDirectory.localized) {
                    if let preview { model.changeGameRunDirectory(preview, copyFiles: copyFiles) }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(preview == nil || checking || model.busy || issue != nil || registrationIssue != nil)
            }
        }.fixedSize(horizontal: false, vertical: true)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.message = Messages.AppGameRunDirectoryChangeView.directoryPurpose.localized
        if panel.runModal() == .OK, let url = panel.url {
            preview = nil; issue = nil; registrationIssue = nil
            registering = true; chosenURL = url; selectionRequest = UUID()
        }
    }

    private func recheck() {
        if registrationIssue != nil {
            registrationIssue = nil; registering = true; selectionRequest = UUID()
        } else { refresh = UUID() }
    }

    private func location(_ title: String, url: URL, files: Int? = nil, bytes: Int64 = 0) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title).font(.callout).foregroundStyle(.secondary).frame(width: 56, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(url.path).font(.caption).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                if let files {
                    Text(Messages.AppGameRunDirectoryChangeView.fileCountAndSize(Int64(files), LocalizedFormat.bytes(bytes)).localized)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            revealButton(url)
        }
    }

    private func revealButton(_ url: URL) -> some View {
        Button(Messages.AppGameRunDirectoryChangeView.showInFinder.localized, systemImage: "arrow.up.forward.square") { NSWorkspace.shared.open(url) }
            .labelStyle(.iconOnly).buttonStyle(.borderless).help(Messages.AppGameRunDirectoryChangeView.showInFinder.localized)
            .disabled(model.busy || !FileManager.default.fileExists(atPath: url.path))
    }
}
