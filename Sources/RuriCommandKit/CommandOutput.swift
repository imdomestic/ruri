import Foundation
import RuriCore
import RuriLocalization

package final class CommandOutput: @unchecked Sendable {
    enum Format: String, Sendable { case text, json, ndjson }
    private let lock = NSLock()
    private let write: @Sendable (Data, Bool) -> Void
    private let format: Format
    private let quiet: Bool
    private let details: Bool
    private let color: String?
    private let localization = LocalizationContext.current
    private var finished = false
    private var redactor = GameLogRedactor()
    private var request: CommandRequest?
    private var usagePath: [String]?
    let terminal: TerminalProfile
    private var progress = Progress()
    private let clock: @Sendable () -> Date

    /// Text progress on stderr: rewritten in place on a terminal, otherwise
    /// printed at each new stage, at completion and at most every 10 seconds.
    private struct Progress {
        var stage: String?
        var stageStarted = Date.distantPast
        var lastWrite = Date.distantPast
        var lineShown = false
    }

    private var targets: [(String, String)]?

    /// Text names the request's targets as they are now, before it can rename
    /// or remove them.
    func setRequest(_ request: CommandRequest) {
        withOutputContext {
            self.request = request
            targets = format == .text ? CommandTextRenderer.targets(of: request, details: details) : nil
        }
    }
    /// The command whose usage an argument error shows.
    func setUsage(_ path: [String]) { withOutputContext { usagePath = path } }
    init(format: Format, quiet: Bool = false, details: Bool = false, color: String? = nil, write: @escaping @Sendable (Data, Bool) -> Void = { data, error in
        try? (error ? FileHandle.standardError : FileHandle.standardOutput).write(contentsOf: data)
    }, terminal: TerminalProfile = .pipe, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.format = format; self.quiet = quiet; self.details = details; self.color = color; self.write = write; self.terminal = terminal; self.clock = clock
    }
    public func addSecrets(_ values: [String]) { withOutputContext { redactor.addSecrets(values) } }
    public func event(_ type: String, _ value: Value) {
        withOutputContext {
            guard !finished else { return }
            if format == .ndjson { emit(.object(["schemaVersion": .integer(1), "type": .string(type), "data": clean(value)])) }
            else if format == .text && type == "log" { clearProgress(); write(Data((clean(value)["text"].string ?? "").utf8), false) }
            else if format == .text && !quiet {
                if type == "progress" || type == "session" { showProgress(type, clean(value)); return }
                // The result reports what other events announce.
                if type == "instanceCreated" { return }
                clearProgress()
                write(Data((renderer(terminal.error).event(type, clean(value)) + "\n").utf8), true)
            }
        }
    }
    /// 等待用户操作的提示始终可见，JSON 的最终结果继续独占 stdout。
    package func interaction(_ type: String, _ value: Value) {
        withOutputContext {
            guard !finished else { return }
            let type = redactor.redact(type), value = clean(value)
            if format == .ndjson {
                emit(.object(["schemaVersion": .integer(1), "type": .string(type), "data": value]))
            } else {
                clearProgress()
                write(Data((renderer(terminal.error).event(type, value) + "\n").utf8), true)
            }
        }
    }
    public func progress(_ progress: InstallProgress) { event("progress", .object(["stage": .string(progress.stage), "completed": .integer(progress.completed), "total": .integer(progress.total)])) }
    public func result(_ data: Value = .null, error: OperationFailure? = nil, warnings: [String] = []) {
        withOutputContext {
            guard !finished else { return }; finished = true
            let value: Value = .object(["schemaVersion": .integer(1), "ok": .bool(error == nil), "data": clean(data),
                "warnings": .array(warnings.map { .string(redactor.redact($0)) }), "error": error.flatMap { try? Value.encode($0) }.map(clean) ?? .null])
            if format == .text {
                clearProgress()
                let text = error != nil ? renderer(terminal.error).error(value["error"]) : renderer(terminal.output).result(clean(data))
                if !text.isEmpty { write(Data((text + (text.hasSuffix("\n") ? "" : "\n")).utf8), error != nil) }
                let style = renderer(terminal.error).style
                for warning in warnings {
                    var line = Data(style.warning(Messages.CLIExperience.warning(redactor.redact(warning)).localized).utf8)
                    line.append(10)
                    write(line, true)
                }
            } else if format == .ndjson { emit(.object(["schemaVersion": .integer(1), "type": .string("result"), "data": value])) }
            else { emit(value) }
        }
    }
    func help(_ text: String) { withOutputContext { write(Data((text + "\n").utf8), false) } }

    private func renderer(_ stream: TerminalProfile.Stream) -> CommandTextRenderer {
        CommandTextRenderer(request: request, usagePath: usagePath,
                            layout: .init(width: stream.width, style: .init(colors: terminal.colors(stream, mode: color)), details: details), targetRows: targets)
    }

    private func showProgress(_ type: String, _ value: Value) {
        let now = clock(), stage = CommandTextRenderer.progressStage(type, value)
        let changed = stage != progress.stage
        if changed { progress.stage = stage; progress.stageStarted = now }
        let complete = value["total"].int.map { $0 > 0 && (value["completed"].int ?? 0) >= $0 } ?? false
            || value["totalBytes"].int.map { $0 > 0 && (value["bytesCopied"].int ?? value["receivedBytes"].int ?? 0) >= $0 } ?? false
        let interval: TimeInterval = terminal.error.isTerminal ? 0.1 : 10
        guard changed || complete || now.timeIntervalSince(progress.lastWrite) >= interval else { return }
        progress.lastWrite = now
        let line = renderer(terminal.error).progress(type, value, elapsed: now.timeIntervalSince(progress.stageStarted))
        if terminal.error.isTerminal {
            // One line, rewritten in place; it must not wrap or it cannot be cleared.
            write(Data(("\r\u{1B}[2K" + TerminalText.truncate(line, to: max(1, terminal.error.width - 1))).utf8), true)
            progress.lineShown = true
        } else {
            write(Data((line + "\n").utf8), true)
        }
    }

    /// Removes the in-place progress line before anything else is written.
    private func clearProgress() {
        guard progress.lineShown else { return }
        write(Data("\r\u{1B}[2K".utf8), true)
        progress.lineShown = false
    }

    private func clean(_ value: Value) -> Value {
        switch value {
        case .string(let s): .string(redactor.redact(s))
        case .array(let values): .array(values.map(clean))
        case .object(let values): .object(values.mapValues(clean))
        default: value
        }
    }
    private func withOutputContext(_ body: () -> Void) {
        lock.withLock { LocalizationContext.$current.withValue(localization, operation: body) }
    }
    private func emit(_ value: Value) {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        if var data = try? encoder.encode(value) { data.append(10); write(data, false) }
    }
}
