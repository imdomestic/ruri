import RuriLocalization
import Foundation
import AppKit
import RuriCore
import RuriExtensionKit

extension AppModel {
    func isInstanceInUse(_ id: UUID?) -> Bool {
        guard let id else { return false }
        return activeSessions[id] != nil || pendingDirectoryCopyIDs.contains(id) || GameRunLease.isHeld(paths: paths, instanceID: id)
    }
    func runningLabel(_ id: UUID) -> String? {
        if pendingInstanceMoveIDs.contains(id) || InstanceMoveGuard.hasPending(paths: paths, instanceID: id) { return Messages.AppAppModelGameMonitoring.pendingMove.localized }
        if pendingInstanceCopyIDs.contains(id) || InstanceCopyGuard.hasPending(paths: paths, instanceID: id) { return Messages.AppAppModelGameMonitoring.pendingCopy.localized }
        if pendingDirectoryCopyIDs.contains(id) || RunDirectoryCopyGuard.hasPending(paths: paths, instanceID: id) { return Messages.AppAppModelGameMonitoring.pendingDirectoryCopy.localized }
        guard let record = activeSessions[id] else {
            if customDirectoryErrors[id] != nil { return Messages.AppAppModelGameMonitoring.inaccessibleGameDirectory.localized }
            return directoryErrors[paths.directoryID(for: id)] == nil ? nil : Messages.AppAppModelGameMonitoring.inaccessibleFolder.localized
        }
        switch GameMonitorClient.activity(record) {
        case .orphaned: return Messages.AppAppModelGameMonitoring.monitoringDisconnected.localized
        case .uncertain: return Messages.AppAppModelGameMonitoring.statusNeedsConfirmation.localized
        case .inactive: return nil
        case .monitoring:
            if record.state.isFinished { return Messages.AppAppModelGameMonitoring.savingRecord.localized }
            if record.stage == .quitting { return Messages.AppAppModelGameMonitoring.waitingForExit.localized }
            if record.stage == .beforeCommand || record.stage == .afterCommand { return record.stage.title }
            if record.stage == .stopping { return Messages.AppAppModelGameMonitoring.terminatingProcess.localized }
            return record.gameIdentity == nil ? Messages.AppAppModelGameMonitoring.launching.localized : Messages.AppAppModelGameMonitoring.running.localized
        }
    }
    func returnToGame(_ id: UUID) {
        guard let record = activeSessions[id] ?? sessions.first(where: { $0.instanceID == id && !$0.state.isFinished && $0.gameIdentity?.isAlive == true }) else { return }
        guard let identity = record.gameIdentity, identity.isAlive,
              let application = NSRunningApplication(processIdentifier: identity.pid), !application.isTerminated else {
            showSession(record.id); return
        }
        if application.activate(options: [.activateAllWindows]) { try? GameMonitorClient.recordEvent(.gameActivationRequested, paths: paths, session: record) }
        else { report(Messages.AppAppModelGameMonitoring.gameWindowUnavailable, level: .warning) }
    }
    func requestGameQuit(_ instanceID: UUID) {
        guard let record = activeSessions[instanceID] else { return }
        sendGameControl(record, normal: true)
    }
    func confirmGameTermination(_ instanceID: UUID) {
        guard let record = activeSessions[instanceID], !record.state.isFinished, record.monitorIdentity?.isAlive == true else { return }
        if record.stage != .beforeCommand && record.stage != .afterCommand {
            let alert = NSAlert()
            alert.messageText = Messages.AppAppModelGameMonitoring.terminateGameProcess(record.instanceName).localized
            alert.informativeText = Messages.AppAppModelGameMonitoring.terminateWarning.localized
            alert.alertStyle = .warning
            alert.addButton(withTitle: Messages.Common.cancel.localized)
            alert.addButton(withTitle: Messages.AppAppModelGameMonitoring.terminateProcess.localized)
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        sendGameControl(record, normal: false)
    }
    private func sendGameControl(_ record: GameSession, normal: Bool) {
        let paths = paths
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    if normal { _ = try GameMonitorClient.requestNormalQuit(paths: paths, record: record) }
                    else { try GameMonitorClient.requestStop(paths: paths, record: record) }
                }.value
                if normal { report(Messages.AppAppModelGameMonitoring.normalExitRequested, sessionID: record.id) }
            } catch { report(error.localizedDescription, level: .error, sessionID: record.id) }
        }
    }
    func didRecoverSession(_ record: GameSession) async {
        publishSession(record)
        finishLaunchPresentation(record.id)
        if activeSessions[record.instanceID]?.id == record.id { activeSessions.removeValue(forKey: record.instanceID) }
        handledExits.insert(record.id)
        acknowledgeSession(record)
        report(record.title, sessionID: record.id)
    }
    func showSession(_ id: UUID? = nil) {
        guard let selected = id ?? activeSessions.values.max(by: { $0.createdAt < $1.createdAt })?.id ?? logsSessionID ?? sessions.first?.id else {
            showHistory(); openMainWindow?(); return
        }
        requestedLogSessionID = selected
        inspectedSession = sessions.first { $0.id == requestedLogSessionID }
        openMainWindow?(); showLogs = true
    }
    func inspectSession(_ record: GameSession) {
        requestedLogSessionID = record.id; inspectedSession = record
        openMainWindow?(); showLogs = true
    }
    func showHistory(instanceID: UUID? = nil) {
        historyInstanceID = instanceID; page = .history
    }
    func acknowledgeSession(_ record: GameSession) {
        guard state.instances.contains(where: { $0.id == record.instanceID }) else { return }
        do {
            try GameSessionReviewStore.mark(record, paths: paths)
            NSApp.dockTile.badgeLabel = sessions.contains(where: needsReview) ? "!" : nil
        } catch { report(Messages.AppAppModelGameMonitoring.acknowledgeSessionFailure(error.localizedDescription), level: .error) }
    }
    private func reviewed(_ record: GameSession) -> Bool {
        (try? GameSessionReviewStore.contains(record, paths: paths)) ?? false
    }
    private func needsReview(_ record: GameSession) -> Bool {
        needsReview(record, activity: GameMonitorClient.activity(record))
    }
    private func needsReview(_ record: GameSession, activity: GameMonitorClient.Activity) -> Bool {
        guard record.monitorIdentity != nil else { return false }
        let attention = record.needsAttention || (!record.state.isFinished && activity != .monitoring)
        return attention && !reviewed(record)
    }
    func recordClientEvent(_ event: GameMonitorClient.ClientEvent) {
        for record in activeSessions.values { try? GameMonitorClient.recordEvent(event, paths: paths, session: record) }
    }
    func startGameObservation() {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let watched = observationDirectories, processes = observedMonitorPIDs
                let observer = FileChangeObserver(directories: watched, processes: processes, fallbackSeconds: 30)
                defer { observer.cancel() }
                await refreshSessions(useCache: true); await pollGames()
                if watched != observationDirectories || processes != observedMonitorPIDs { continue }
                for await _ in observer.events {
                    guard !Task.isCancelled else { return }
                    await refreshSessions(useCache: true); await pollGames()
                    if watched != observationDirectories || processes != observedMonitorPIDs { break }
                }
            }
        }
    }
    private var observedMonitorPIDs: [Int32] { activeSessions.values.compactMap { $0.monitorIdentity?.pid }.sorted() }
    private var observationDirectories: [URL] {
        // Session updates arrive over IPC. Root changes discover new instances;
        // process-exit notifications and a slow fallback cover lost connections.
        [paths.root] + state.instances.map { paths.instance($0.id) }
    }
    private func synchronizeMonitorSubscriptions() {
        let desired = activeSessions.values.filter { ($0.controlEndpoint != nil || sessionSubscriptions[$0.id] != nil) && $0.monitorIdentity?.isAlive == true }
        let ids = Set(desired.map(\.id))
        for id in Array(sessionSubscriptions.keys) where !ids.contains(id) { sessionSubscriptions.removeValue(forKey: id)?.cancel() }
        for record in desired where record.controlEndpoint != nil && sessionSubscriptions[record.id] == nil {
            sessionSubscriptions[record.id] = Task { [weak self] in
                let observation = GameMonitorObservation(session: record)
                defer { observation.cancel() }
                do {
                    for try await update in observation.updates {
                        guard !Task.isCancelled, let self else { return }
                        if let snapshot = update.session { publishSession(snapshot); await pollGames() }
                    }
                } catch { /* Reconcile from durable state if the channel disappears. */ }
                guard !Task.isCancelled, let self else { return }
                // A helper may close its transport just before exiting. Avoid an
                // immediate reconnect loop during that small shutdown interval.
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                sessionSubscriptions.removeValue(forKey: record.id)
                await refreshSessions(useCache: true); await pollGames()
            }
        }
    }
    func pollGames() async {
        let previous = activeSessions
        let snapshot = sessions, snapshotIDs = Set(sessions.map(\.id))
        var active: [UUID: GameSession] = [:]
        var presentedAttention = false
        for candidate in snapshot where candidate.monitorIdentity != nil && (!candidate.state.isFinished || previous[candidate.instanceID]?.id == candidate.id || (!handledExits.contains(candidate.id) && candidate.needsAttention)) {
            var record = sessions.first(where: { $0.id == candidate.id }) ?? candidate
            var activity = GameMonitorClient.activity(record)
            if !record.state.isFinished && activity != .monitoring {
                let paths = paths, pending = record
                do {
                    let saved = try await Task.detached(priority: .utility) { try GameMonitorClient.reconcile(paths: paths, record: pending) }.value
                    publishSession(saved)
                    // A newer IPC update or recovery may have arrived while
                    // the database read yielded. Never restore an older state.
                    record = sessions.first(where: { $0.id == pending.id }) ?? saved
                    activity = GameMonitorClient.activity(record)
                } catch {
                    report(Messages.AppAppModelSessions.historyReadWarning(error.localizedDescription), level: .warning)
                    if active[record.instanceID] == nil { active[record.instanceID] = record }
                    continue // A failed read is not evidence of a game failure.
                }
            }
            // Use the same liveness observation throughout this decision. If
            // the helper exits now, the next observation reconciles it first.
            let review = needsReview(record, activity: activity)
            if activity == .inactive || record.state.isFinished || record.exit != nil { finishLaunchPresentation(record.id) }
            else { applyLaunchPresentation(record) }
            if activity != .inactive {
                if previous[record.instanceID]?.id != record.id { try? GameMonitorClient.recordEvent(.connected, paths: paths, session: record) }
                if active[record.instanceID] == nil { active[record.instanceID] = record }
                if logsSessionID == nil { logsSessionID = record.id }
            } else if previous[record.instanceID]?.id == record.id {
                if let exit = record.exit { lastGameExit = exit }
            }
            if review && !handledExits.contains(record.id) {
                handledExits.insert(record.id)
                NSApp.dockTile.badgeLabel = "!"
                let summary = record.state.isFinished ? record.title : activity == .uncertain ? Messages.AppAppModelGameMonitoring.statusUnconfirmed.localized : Messages.AppAppModelGameMonitoring.monitoringStopped.localized
                report(Messages.Common.labeledValue(record.instanceName, summary).localized, level: record.state == .failed ? .error : .warning, sessionID: record.id)
                if !presentedAttention {
                    if NSApp.isActive && NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) {
                        requestedLogSessionID = record.id; showLogs = true
                    }
                    presentedAttention = true
                }
            }
        }
        for (id, record) in activeSessions where !snapshotIDs.contains(record.id) { active[id] = record }
        // A recovery action may have completed while a log read yielded above.
        // Do not restore that action's older active snapshot into the UI.
        for (id, record) in active {
            if let latest = sessions.first(where: { $0.id == record.id }), latest != record {
                if GameMonitorClient.activity(latest) == .inactive { active.removeValue(forKey: id) }
                else { active[id] = latest }
            }
        }
        if activeSessions != active { activeSessions = active }
        synchronizeMonitorSubscriptions()
        await restorePlaytime()
    }
    private func applyLaunchPresentation(_ record: GameSession) {
        guard let presentation = launchPresentations[record.id], record.gameIdentity?.isAlive == true else { return }
        if record.host?.backend == .native && record.host?.windowReadyAt == nil { return }
        launchPresentations.removeValue(forKey: record.id)
        guard presentation.hideLauncher, !presentation.showLogs, !showLogs else { return }
        if !NSApp.isHidden {
            automaticallyHiddenSessions.insert(record.id)
            NSApp.hide(nil)
        } else if !automaticallyHiddenSessions.isEmpty {
            automaticallyHiddenSessions.insert(record.id)
        }
    }
    func finishLaunchPresentation(_ sessionID: UUID) {
        launchPresentations.removeValue(forKey: sessionID)
        guard automaticallyHiddenSessions.remove(sessionID) != nil, automaticallyHiddenSessions.isEmpty, NSApp.isHidden else { return }
        NSApp.unhide(nil)
        openMainWindow?()
    }
    private func restorePlaytime() async {
        var changed = false
        let paths = paths
        for id in state.instances.map(\.id) {
            let completed = Set(sessions.filter { $0.instanceID == id && $0.state.isFinished && $0.monitorIdentity?.isAlive != true }.map(\.id))
            guard restoredPlaytimeSessions[id] != completed else { continue }
            let ledger = await Task.detached(priority: .utility) {
                return try? GameHistoryStore.summary(paths: paths, instanceID: id)
            }.value
            guard let index = state.instances.firstIndex(where: { $0.id == id }) else { continue }
            restoredPlaytimeSessions[id] = completed
            if let ledger {
                if state.instances[index].playTime != ledger.seconds { state.instances[index].playTime = ledger.seconds; changed = true }
                if state.instances[index].lastPlayed != ledger.lastPlayed { state.instances[index].lastPlayed = ledger.lastPlayed; changed = true }
            }
        }
        if changed { save() }
    }
    func prepareToQuit() async {
        isQuitting = true
        ExperimentalUIRegistry.stop()
        bootTask?.cancel()
        operation?.cancel()
        await operation?.value
        monitorTask?.cancel()
        for task in sessionSubscriptions.values { task.cancel() }; sessionSubscriptions.removeAll()
        await journalWriteTask?.value
    }
}
