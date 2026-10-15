import Foundation
import AppKit
import RuriLocalization

/// Owns one launch attempt. Commands and optional services compose around the
/// game lifetime; they do not decide how much playtime gets credited.
@MainActor final class GameSessionCoordinator {
    private var plan: LaunchPlan
    private let recorder: MonitorSessionRecorder
    private let paths: any SessionPaths
    private var game: GameProcess?
    private var activityMonitor: GameActivityMonitor?
    private var stopPending = false
    private let checkpointInterval: DispatchTimeInterval
    private let checkpointLeeway: DispatchTimeInterval

    init(plan: LaunchPlan, recorder: MonitorSessionRecorder, paths: any SessionPaths, checkpointInterval: DispatchTimeInterval = .seconds(60), checkpointLeeway: DispatchTimeInterval = .seconds(10)) {
        self.plan = plan; self.recorder = recorder; self.paths = paths
        self.checkpointInterval = checkpointInterval; self.checkpointLeeway = checkpointLeeway
    }
    private var shouldStop: Bool { stopPending }

    func run() async throws -> Int32 {
        let transport = try MonitorServiceTransport(session: recorder.record) { [weak self] request in self?.control(request) ?? false }
        recorder.writer.onChange = { [weak transport] record in transport?.update(record) }
        recorder.onCapture = { [weak transport] capture in transport?.setCapture(capture) }
        defer { recorder.writer.onChange = nil; recorder.onCapture = nil; transport.close() }
        do {
            try recorder.setControlEndpoint(transport.endpoint)
            try plan.commands?.validate()
            let javaLease = try JavaRuntimeLease.shared(binary: plan.executable, paths: paths)
            defer { withExtendedLifetime(javaLease) {} }
            try checkCancellation()
            if let commands = plan.commands, commands.enabled, !commands.before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let result = await GameCommandRunner.run(commands.before, phase: .before, plan: plan, timeoutSeconds: commands.timeoutSeconds, recorder: recorder) { self.shouldStop }
                if !result.succeeded {
                    try recorder.fail(RuriError.message(result.summaryMessage), cancelled: result.cancelled)
                    return result.cancelled ? 130 : 1
                }
            }
            try checkCancellation()
            var skinServer: OfflineSkinServer?
            defer { skinServer?.stop() }
            if let skin = plan.offlineSkin {
                let server = try await OfflineSkinServer.start(skin)
                skinServer = server; plan = try server.applying(to: plan)
                try? recorder.writer.append(Messages.OfflineSkin.ready.localized)
                try? recorder.writer.append("[Ruri] \(plan.redactedCommand)")
            }
            try checkCancellation()
            let result = try await runGame()
            // The game result and clock are already saved. Evidence is captured
            // while the directory lease is still held, before user commands.
            await recorder.preserveEvidence(exit: result)
            if !result.stopRequested, let commands = plan.commands, commands.enabled, !commands.after.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                _ = await GameCommandRunner.run(commands.after, phase: .after, plan: plan, timeoutSeconds: commands.timeoutSeconds, exit: result, recorder: recorder) { self.shouldStop }
            }
            if result.succeeded, let cleanup = plan.chorusServerCleanup {
                try cleanup.clean(directory: plan.directory)
            }
            try recorder.finish(exit: result)
            return result.shellStatus
        } catch {
            if !recorder.record.state.isFinished { try? recorder.fail(error, cancelled: error is CancellationError) }
            throw error
        }
    }

    private func runGame() async throws -> GameExit {
        if recorder.record.stage != .starting { try recorder.writer.transition(.starting) }
        if let log = plan.quickPlayLog {
            let expected = try SessionFileSystem.safePath("quick-play/" + log.lastPathComponent, within: paths.instance(recorder.record.instanceID))
            guard log.isFileURL, log.pathExtension == "json", log.standardizedFileURL == expected.standardizedFileURL else { throw RuriError.message(Messages.Servers.invalidList) }
            try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        recorder.prepareGame(directory: plan.directory)
        let process = GameProcess(); game = process
        let capture = try recorder.makeOutputCapture(); recorder.retainOutput(capture)
        let activityFeed = GameActivityLogFeed()
        capture.observeActivity { activityFeed.receive($0) }
        try recorder.setNativeQuitSupported(plan.nativeQuitSupported == true)
        let checkpoint = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        checkpoint.schedule(deadline: .now() + checkpointInterval, repeating: checkpointInterval, leeway: checkpointLeeway)
        // The source runs on a utility queue. Keep its callback nonisolated;
        // only the task that saves the clock may inherit MainActor isolation.
        checkpoint.setEventHandler { @Sendable [weak self] in Task { @MainActor in self?.saveClock() } }
        checkpoint.resume()
        let center = NSWorkspace.shared.notificationCenter
        let notifications = [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.saveClock() }
            }
        }
        defer {
            checkpoint.cancel()
            for token in notifications { center.removeObserver(token) }
            game = nil; activityMonitor = nil
            capture.observeActivity(nil); activityFeed.finish()
            if let log = plan.quickPlayLog { try? FileManager.default.removeItem(at: log) }
        }
        var result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<GameExit, any Error>) in
            do {
                try process.start(plan: plan, capture: capture, sessionID: recorder.record.id, hostStatus: { [recorder] status in
                    try? recorder.setHostStatus(status)
                }) { result in continuation.resume(returning: result) }
                if let pid = process.processIdentifier {
                    try? recorder.started(processID: pid)
                    if let timing = process.timing {
                        let activity = GameActivityMonitor(recorder: recorder, logURL: plan.quickPlayLog, feed: activityFeed, initial: timing, sample: { process.timing })
                        activityMonitor = activity; activity.start()
                    }
                    saveClock()
                }
            } catch { continuation.resume(throwing: error) }
        }
        if let timing = process.timing { await activityMonitor?.finish(timing, maximumSeconds: result.playTime) }
        if result.succeeded && !result.stopRequested {
            let markers = ["Crash report saved to", "Could not save crash report to", "This crash report has been saved to:", "Unable to launch", "An exception was thrown, the game will display an error screen and halt."]
            let output = capture.snapshot(final: true, includeHead: true)
            if markers.contains(where: output.contains) || !GameCrashReport.find(in: plan.directory, exit: result).isEmpty { result.reportedFailure = true }
        }
        try? recorder.recordGameExit(result, timing: process.timing)
        return result
    }
    private func saveClock() {
        guard let game, game.isRunning, let timing = game.timing else { return }
        if let activityMonitor { activityMonitor.checkpoint(timing) } else { recorder.checkpoint(timing) }
    }
    private func checkCancellation() throws { if shouldStop { throw CancellationError() } }
    private func control(_ request: MonitorControlRequest) -> Bool {
        guard !recorder.record.state.isFinished else { return false }
        switch request.command {
        case .stop:
            stopPending = true
            if let game, game.isRunning { try? recorder.writer.transition(.stopping); game.stop() }
            return true
        case .quit:
            guard let game, game.isRunning, recorder.record.nativeQuitSupported == true else { return false }
            let accepted = game.requestNormalQuit()
            try? recorder.recordNormalQuit(requestID: request.id, requestedAt: Date(), accepted: accepted)
            return accepted
        default: return false
        }
    }
}
