import Foundation
import RuriCore
import RuriLocalization

/// Text is a presentation of the public DTO, never a second execution path.
struct CommandTextRenderer {
    var request: CommandRequest?

    func result(_ value: Value) -> String {
        if request?.path == "session logs" { return value["text"].string ?? "" }
        if value["before"]["effective"] != .null, value["after"]["effective"] != .null { return configurationChange(value) }
        if value["scope"] != .null, value.object?["effective"] != nil { return configuration(value) }
        if case .array(let items) = value["items"] { return page(value, items: items) }
        if request?.path == "schema", case .array(let commands) = value["commands"], commands.allSatisfy({ $0["usage"].string != nil }) {
            return commands.map { ($0["usage"].string ?? "") + "  — " + ($0["summary"].string ?? "") }.joined(separator: "\n")
        }
        var lines: [String] = []
        if request?.spec.mutation == true || value["dryRun"] == .bool(true) {
            let status = value["dryRun"] == .bool(true) ? Messages.CLIExperience.preview.localized
                : value["changed"] == .bool(false) ? Messages.CLIExperience.unchanged.localized : Messages.CLIExperience.completed.localized
            lines.append(status + (request.map { ": " + $0.path } ?? ""))
        }
        var data = value
        if var object = value.object {
            for key in ["dryRun", "warnings", "schemaVersion"] { object.removeValue(forKey: key) }
            if request?.spec.path.first == "instance", !((request?.dryRun) ?? false), let instance = object["instance"]?.object {
                let keys = Set(["id", "name", "gameVersion", "installed", "components", "directoryID", "gameDirectory", "issue"])
                object["instance"] = .object(instance.filter { keys.contains($0.key) && $0.value != .null })
            }
            data = .object(object)
        }
        lines += Self.details(data)
        return lines.joined(separator: "\n")
    }

    func error(_ value: Value) -> String {
        var lines = [Self.atom(value["code"]) + ": " + (value["message"].string ?? "")]
        if value["details"] != .null { lines += Self.details(value["details"]) }
        if value["retryable"] == .bool(true) { lines.append(Messages.CLIExperience.retryable.localized) }
        if case .array(let actions) = value["nextActions"] {
            for action in actions {
                if case .array(let command) = action["command"] {
                    lines.append(Messages.CLIExperience.nextAction(Self.shell(["ruri-chorus"] + command.compactMap(\.string))).localized)
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    func event(_ type: String, _ value: Value) -> String {
        if type == "progress", let stage = value["stage"].string ?? value["phase"].string {
            let counter = value["total"].int.map { " \(value["completed"].int ?? 0)/\($0)" } ?? ""
            let remaining = value.object?.filter { !["stage", "phase", "completed", "total"].contains($0.key) } ?? [:]
            return ([stage + counter] + Self.details(.object(remaining))).joined(separator: " ")
        }
        return ([type + ":"] + Self.details(value)).joined(separator: "\n")
    }

    private func configuration(_ value: Value) -> String {
        let prefix = value["key"].string ?? ""
        let rows = Self.flatten(value["effective"], prefix: prefix).sorted { $0.key < $1.key }.map { key, field in
            let group = String(key.split(separator: ".").first ?? "")
            let source = value["source"].string ?? value["sources"][group].string ?? ""
            return [key, Self.atom(field), source]
        }
        return (["scope: " + Self.atom(value["scope"]), "revision: " + Self.atom(value["revision"])]
                + [Self.table(headers: ["field", "value", "source"], rows: rows)]).joined(separator: "\n")
    }

    private func configurationChange(_ value: Value) -> String {
        let before = value["before"], after = value["after"], changed = value["changed"] == .bool(true)
        let preview = value["dryRun"] == .bool(true)
        let status = changed ? (preview ? Messages.CLIExperience.configPreview.localized : Messages.CLIExperience.configUpdated.localized)
            : (preview ? Messages.CLIExperience.previewMessage(Messages.CLIExperience.configUnchanged.localized).localized : Messages.CLIExperience.configUnchanged.localized)
        var lines = [status, "scope: " + Self.atom(after["scope"])]
        let oldFields = Self.flatten(before["effective"]), newFields = Self.flatten(after["effective"])
        var differences: [String] = []
        for key in Set(oldFields.keys).union(newFields.keys).sorted() where oldFields[key] != newFields[key] {
            differences.append(key + ": " + Self.atom(oldFields[key] ?? .null) + " → " + Self.atom(newFields[key] ?? .null))
        }
        for key in Set(before["sources"].object?.keys.map { $0 } ?? []).union(after["sources"].object?.keys.map { $0 } ?? []).sorted()
            where before["sources"][key] != after["sources"][key] {
            differences.append(key + ".source: " + Self.atom(before["sources"][key]) + " → " + Self.atom(after["sources"][key]))
        }
        if changed && differences.isEmpty { differences.append(Messages.CLIExperience.hiddenChanges.localized) }
        lines += differences
        lines.append("revision: " + Self.atom(after["revision"]))
        return lines.joined(separator: "\n")
    }

    private func page(_ value: Value, items: [Value]) -> String {
        var lines: [String] = []
        if items.isEmpty { lines.append(Messages.CLIExperience.empty.localized) }
        else if items.allSatisfy({ $0.object != nil }) {
            let available = Set(items.flatMap { Self.flatten($0).keys })
            var keys = columns.filter { available.contains($0) }
            if keys.isEmpty { keys = available.sorted() }
            // Problems must remain visible even when a resource has a compact column set.
            for key in available.sorted() where ["issue", "error", "failure", "warning", "warnings", "nextAction", "nextActions"].contains(key.split(separator: ".").last.map(String.init) ?? "") && !keys.contains(key) {
                if items.contains(where: { let field = ConfigurationService.get($0, key); return field != .null && field != .array([]) && field != .string("") }) { keys.append(key) }
            }
            lines.append(Self.table(headers: keys, rows: items.map { item in keys.map { Self.atom(ConfigurationService.get(item, $0)) } }))
            if !available.isSubset(of: Set(keys)) { lines.append(Messages.CLIExperience.fullDetails.localized) }
        } else { lines += items.flatMap { Self.details($0) } }
        let offset = value["offset"].int ?? 0
        lines.append(Messages.CLIExperience.page(Int64(items.count), Int64(offset)).localized)
        if let total = value["total"].int { lines.append(Messages.CLIExperience.total(Int64(total)).localized) }
        if value["hasMore"] == .bool(true) {
            var command = ["ruri-chorus"] + (request?.spec.path ?? []) + (request?.operands ?? [])
            if let request {
                for key in request.options.keys.sorted() where !["offset", "all"].contains(key) {
                    switch request.options[key]! {
                    case .null, .bool(false): break
                    case .bool(true): command.append("--" + key)
                    case .array(let values):
                        for field in values { command += ["--" + key, field.string ?? Self.atom(field)] }
                    case let field: command += ["--" + key, field.string ?? Self.atom(field)]
                    }
                }
                if let directory = request.common.dataDir { command += ["--data-dir", directory] }
            }
            command += ["--offset", String(offset + items.count)]
            lines.append(Messages.CLIExperience.more(Self.shell(command)).localized)
        }
        let extra = value.object?.filter { !["items", "offset", "total", "hasMore", "warnings"].contains($0.key) } ?? [:]
        lines += Self.details(.object(extra))
        return lines.joined(separator: "\n")
    }

    private var columns: [String] {
        switch request?.spec.path.first {
        case "instance":
            if request?.spec.path.last == "versions" { return ["id", "version", "type", "releaseTime", "loader"] }
            return ["id", "name", "gameVersion", "components", "installed", "favorite"]
        case "account": return ["id", "username", "kind", "server"]
        case "directory": return ["id", "name", "path", "layout", "available", "detached", "gameVersion"]
        case "java": return ["id", "managedID", "path", "runtime.version", "version", "runtime.architecture", "architecture", "source"]
        case "catalog": return ["id", "provider", "title", "name", "number", "type", "gameVersions", "loaders", "channel"]
        case "content": return ["filename", "title", "version", "enabled", "kind"]
        case "server": return ["id", "name", "address", "resourcePacks", "favorite", "instanceIDs", "online", "maximum", "latencyMilliseconds", "description"]
        case "world": return ["id", "folder", "name", "world", "worldName", "version", "lastPlayed", "createdAt", "bytes"]
        case "datapack": return ["id", "title", "name", "number", "enabled", "description"]
        case "schematic": return ["path", "directory", "bytes", "modifiedAt"]
        case "session": return ["id", "instanceID", "instanceName", "state", "activity", "gameExitCode"]
        case "recovery": return ["kind", "target", "transaction", "status", "nextAction"]
        default: return []
        }
    }

    static func flatten(_ value: Value, prefix: String = "") -> [String: Value] {
        guard let fields = value.object, !fields.isEmpty else { return [prefix: value] }
        return fields.reduce(into: [:]) { result, pair in
            result.merge(flatten(pair.value, prefix: prefix.isEmpty ? pair.key : prefix + "." + pair.key)) { _, new in new }
        }
    }

    static func details(_ value: Value, prefix: String = "") -> [String] {
        switch value {
        case .object(let fields):
            return fields.keys.sorted().flatMap { key in
                details(fields[key]!, prefix: prefix.isEmpty ? key : prefix + "." + key)
            }
        case .array(let values) where !values.isEmpty && values.allSatisfy({ $0.object != nil }):
            let flattened = values.map { flatten($0) }
            let keys = Set(flattened.flatMap(\.keys)).sorted()
            return (prefix.isEmpty ? [] : [prefix + ":"]) + [table(headers: keys, rows: flattened.map { item in keys.map { atom(item[$0] ?? .null) } })]
        case .array(let values) where values.contains(where: { if case .array = $0 { true } else { $0.object != nil } }):
            return values.enumerated().flatMap { index, item in details(item, prefix: prefix + "[\(index)]") }
        default: return [(prefix.isEmpty ? "" : prefix + ": ") + atom(value)]
        }
    }

    /// Escape control characters, while preserving complete IDs and paths.
    static func atom(_ value: Value) -> String {
        switch value {
        case .null: return "null"
        case .bool(let flag): return flag ? "true" : "false"
        case .number(let number): return value.int.map(String.init) ?? String(number)
        case .string(let string):
            if string.isEmpty || ["null", "true", "false"].contains(string) || Double(string) != nil || string.contains(where: { $0.isWhitespace || $0 == "\"" || $0 == "\\" }) || string.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
                let encoder = JSONEncoder(); encoder.outputFormatting = [.withoutEscapingSlashes]
                return (try? String(decoding: encoder.encode(string), as: UTF8.self)) ?? string
            }
            return string
        case .array(let values): return "[" + values.map(atom).joined(separator: ", ") + "]"
        case .object(let fields): return fields.keys.sorted().map { $0 + "=" + atom(fields[$0]!) }.joined(separator: "; ")
        }
    }

    static func shell(_ arguments: [String]) -> String {
        arguments.map { argument in
            !argument.isEmpty && argument.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./:@%+=,-").contains($0) }
                ? argument : CLIInstallation.shellQuote(argument)
        }.joined(separator: " ")
    }

    static func table(headers: [String], rows: [[String]]) -> String {
        guard !headers.isEmpty else { return "" }
        let widths = headers.indices.map { index in min(48, ([headers] + rows).map { displayWidth($0[index]) }.max() ?? 0) }
        return ([headers] + rows).map { row in
            row.enumerated().map { index, cell in
                cell + (index == headers.count - 1 ? "" : String(repeating: " ", count: max(0, widths[index] - displayWidth(cell)) + 2))
            }.joined()
        }.joined(separator: "\n")
    }

    private static func displayWidth(_ text: String) -> Int {
        text.reduce(0) { width, character in
            let wide = character.unicodeScalars.contains { (0x2E80...0xA4CF).contains($0.value) || (0xAC00...0xD7AF).contains($0.value) || (0xF900...0xFAFF).contains($0.value) || $0.properties.isEmojiPresentation }
            return width + (wide ? 2 : 1)
        }
    }
}
