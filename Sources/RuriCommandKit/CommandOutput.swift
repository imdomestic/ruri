import Foundation
import RuriCore
import RuriLocalization

public final class CommandOutput: @unchecked Sendable {
    public enum Format: String, Sendable { case text, json, ndjson }
    private let lock = NSLock()
    private let write: @Sendable (Data, Bool) -> Void
    private let format: Format
    private let quiet: Bool
    private let localization = LocalizationContext.current
    private var finished = false
    private var redactor = GameLogRedactor()
    private var request: CommandRequest?
    private var lastProgress: Value?
    private var lastProgressTime = Date.distantPast
    func setRequest(_ request: CommandRequest) { withOutputContext { self.request = request } }
    public init(format: Format, quiet: Bool = false, write: @escaping @Sendable (Data, Bool) -> Void = { data, error in
        try? (error ? FileHandle.standardError : FileHandle.standardOutput).write(contentsOf: data)
    }) { self.format = format; self.quiet = quiet; self.write = write }
    public func addSecrets(_ values: [String]) { withOutputContext { redactor.addSecrets(values) } }
    public func event(_ type: String, _ value: Value) {
        withOutputContext {
            guard !finished else { return }
            if format == .ndjson { emit(.object(["schemaVersion": .integer(1), "type": .string(type), "data": clean(value)])) }
            else if format == .text && type == "log" { write(Data((clean(value)["text"].string ?? "").utf8), false) }
            else if !quiet {
                if type == "progress" {
                    let stage = value["stage"] != .null ? value["stage"] : value["phase"]
                    let oldStage = lastProgress?["stage"] != nil && lastProgress?["stage"] != .null ? lastProgress?["stage"] : lastProgress?["phase"]
                    let complete = value["total"].int.map { $0 > 0 && (value["completed"].int ?? 0) >= $0 } ?? false
                    guard lastProgress == nil || stage != oldStage || (complete && value != lastProgress) || Date().timeIntervalSince(lastProgressTime) >= 1 else { return }
                    lastProgress = value; lastProgressTime = Date()
                }
                write(Data((CommandTextRenderer(request: request).event(type, clean(value)) + "\n").utf8), true)
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
                let renderer = CommandTextRenderer(request: request)
                let text = error != nil ? renderer.error(value["error"]) : renderer.result(clean(data))
                if !text.isEmpty { write(Data((text + (text.hasSuffix("\n") ? "" : "\n")).utf8), error != nil) }
                for warning in warnings {
                    var line = Data(Messages.CLIExperience.warning(redactor.redact(warning)).localized.utf8)
                    line.append(10)
                    write(line, true)
                }
            } else if format == .ndjson { emit(.object(["schemaVersion": .integer(1), "type": .string("result"), "data": value])) }
            else { emit(value) }
        }
    }
    package func help(_ text: String) { withOutputContext { write(Data((text + "\n").utf8), false) } }
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
