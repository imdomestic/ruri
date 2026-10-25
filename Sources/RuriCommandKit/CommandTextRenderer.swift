import Foundation
import RuriCore
import RuriLocalization

/// Text is a presentation of the public DTO, never a second execution path.
struct CommandTextRenderer {
    var request: CommandRequest?
    var usagePath: [String]? = nil
    var layout = TextLayout()
    /// The request's targets as they were before it ran, so a removed or
    /// renamed resource is still named as it was.
    var targetRows: [(String, String)]? = nil

    var path: [String] { request?.spec.path ?? [] }
    var style: TextStyle { layout.style }

    func result(_ value: Value) -> String {
        if let presenter = Self.presenter(path) ?? ExperimentalCommandRegistry.presenter(path) { return presenter.render(self, value).joined(separator: "\n") }
        // Without a known command, the shape of the value decides.
        if value["before"]["effective"] != .null, value["after"]["effective"] != .null { return configurationChange(value).joined(separator: "\n") }
        if value["scope"] != .null, value.object?["effective"] != nil { return configuration(value).joined(separator: "\n") }
        if case .array(let items) = value["items"] { return page(value, items: items).joined(separator: "\n") }
        var lines: [String] = [], data = value
        if value["dryRun"] == .bool(true) || value["changed"] != .null { lines.append(status(value)) }
        if var object = value.object {
            for key in ["dryRun", "warnings", "schemaVersion"] { object.removeValue(forKey: key) }
            data = .object(object)
        }
        return (lines + Self.details(data)).joined(separator: "\n")
    }

    /// Preview, unchanged or completed, styled so the outcome reads first.
    func status(_ value: Value) -> String {
        if value["dryRun"] == .bool(true) { return style.bold(Messages.CLIExperience.preview.localized) }
        if value["changed"] == .bool(false) { return style.bold(Messages.CLIExperience.unchanged.localized) }
        return style.good(Messages.CLIExperience.completed.localized)
    }

    // MARK: Errors

    /// What happened, the target it concerns and how to continue. Recovery
    /// items and preserved files always show; other details need --details.
    func error(_ value: Value) -> String {
        let code = Self.atom(value["code"])
        var lines = layout.prose(Messages.CLIExperience.errorHeadline(code, value["message"].string ?? "").localized, style.bad)
        if code == "INVALID_ARGUMENT", let path = usagePath ?? request?.spec.path {
            lines.append(Messages.CLIExperience.usageLine(CommandHelp.usage(path)).localized)
        }
        lines += layout.fields(targets(), indent: 2)
        var details = value["details"]
        if code == "AMBIGUOUS_TARGET", case .array(let candidates) = details {
            lines += layout.fields(candidates.map { ($0["shortID"].string ?? $0["id"].string ?? "", $0["name"].string ?? "") })
            details = .null
        }
        if var fields = details.object {
            if case .array(let items) = fields.removeValue(forKey: "recovery") ?? .null, !items.isEmpty {
                lines += layout.prose(Messages.CLIExperience.pendingRecovery.localized, style.bold)
                lines += TerminalText.columns(items.map { item in (item["kind"].string ?? "", Self.plain(item["explanation"] != .null ? item["explanation"] : item["status"])) }, width: layout.width)
            }
            var preserved: [String] = []
            for key in ["preservedFiles", "preservedCopy"] {
                switch fields.removeValue(forKey: key) ?? .null {
                case .string(let path): preserved.append(path)
                case .array(let paths): preserved += paths.compactMap(\.string)
                default: break
                }
            }
            if !preserved.isEmpty {
                lines += layout.prose(Messages.CLIExperience.preservedFiles.localized, style.bold)
                lines += preserved.map { "  " + $0 }
            }
            // The file in the way, or the one that could not be read.
            if let path = fields.removeValue(forKey: "path")?.string { lines += layout.fields([(Messages.CLIExperience.labelPath.localized, path)]) }
            if case .array(let files) = fields["files"] ?? .null, files.allSatisfy({ $0["fileID"] != .null }) {
                fields.removeValue(forKey: "files"); lines += manualFiles(.array(files))
            }
            if case .array = fields["checks"] ?? .null {
                lines += checks(.object(fields)); fields = [:]
            }
            details = fields.isEmpty ? .null : .object(fields)
        }
        // Diagnostics for support, and IDs the target line already names, wait for --details.
        var withheld = false
        if !layout.details, var fields = details.object {
            for key in ["messageID", "httpStatus", "host", "instanceID", "directoryID", "accountID", "sessionID"] where fields.removeValue(forKey: key) != nil { withheld = true }
            details = fields.isEmpty ? .null : .object(fields)
        }
        if case .array(let values) = details, values.allSatisfy({ $0.string != nil }) { lines.append("  " + values.compactMap(\.string).joined(separator: ", ")) }
        else if details != .null { lines += Self.details(details).map { "  " + $0 } }
        if value["retryable"] == .bool(true) { lines += layout.prose(Messages.CLIExperience.retryable.localized) }
        if case .array(let actions) = value["nextActions"] {
            for action in actions {
                if case .array(let command) = action["command"] { lines.append(Messages.CLIExperience.nextAction(self.command(command.compactMap(\.string))).localized) }
            }
        }
        if withheld { lines += layout.prose(Messages.CLIExperience.moreWithDetails.localized, style.dim) }
        return lines.joined(separator: "\n")
    }

    func targets() -> [(String, String)] { targetRows ?? Self.targets(of: request, details: layout.details) }

    /// The resolved targets of a request, by name and short ID.
    static func targets(of request: CommandRequest?, details: Bool) -> [(String, String)] {
        guard let request else { return [] }
        let catalog = TargetCatalog(paths: CLIApplication.basePaths(request))
        var rows: [(String, String)] = []
        func add(_ label: String, _ value: String, _ kind: TargetIndex.Kind, instance: UUID? = nil) {
            guard let id = UUID(uuidString: value), let index = try? catalog.index(kind, instance: instance),
                  let entry = index.entries.first(where: { $0.id == id }) else { return }
            rows.append((label, reference(entry, in: index, details: details)))
        }
        var instance: UUID?
        for (index, parameter) in request.spec.operands.enumerated() {
            guard let value = request.operands[safe: index] else { continue }
            switch parameter.role {
            case .instance: add(Messages.CLIExperience.labelInstance.localized, value, .instance); instance = UUID(uuidString: value)
            case .directory: add(Messages.CLIExperience.labelDirectory.localized, value, .directory)
            case .account: add(Messages.CLIExperience.labelAccount.localized, value, .account)
            case .session: add(Messages.CLIExperience.labelSession.localized, value, .session, instance: instance)
            case .recoveryTarget where request.operands.first == "repository-import": add(Messages.CLIExperience.labelDirectory.localized, value, .directory)
            case .recoveryTarget: add(Messages.CLIExperience.labelInstance.localized, value, .instance)
            default: break
            }
        }
        for parameter in request.spec.options {
            guard let value = request.string(parameter.name) else { continue }
            switch parameter.role {
            case .instance, .preferredInstance: add(Messages.CLIExperience.labelInstance.localized, value, .instance)
            case .directory: add(Messages.CLIExperience.labelDirectory.localized, value, .directory)
            case .account: add(Messages.CLIExperience.labelAccount.localized, value, .account)
            case .scope where value.hasPrefix("instance:"): add(Messages.CLIExperience.labelInstance.localized, String(value.dropFirst(9)), .instance)
            default: break
            }
        }
        return rows
    }

    /// A name with its short ID, or the full ID with --details.
    static func reference(_ entry: TargetEntry, in index: TargetIndex, details: Bool) -> String {
        let id = details ? entry.id.uuidString : index.shortID(entry.id)
        if index.kind == .directory && entry.id == GameDirectory.defaultID { return "default" + (details ? " (" + id + ")" : "") }
        return entry.name.map { $0 + " (" + id + ")" } ?? id
    }

    /// A command to copy: shell-quoted, for text output, and reaching the same
    /// data directory as this one.
    func command(_ words: [String]) -> String {
        var result: [String] = [], index = 0
        while index < words.count {
            let word = words[index]; index += 1
            if word == "--json" { continue }
            if word == "--output" { index += 1; continue }
            if word.hasPrefix("--output=") { continue }
            result.append(word)
        }
        if result.first != "help", !result.contains("--data-dir"), let directory = request?.common.dataDir { result += ["--data-dir", directory] }
        return Self.shell(["ruri"] + result)
    }

    func event(_ type: String, _ value: Value) -> String {
        ([type + ":"] + Self.details(value)).joined(separator: "\n")
    }

    /// One progress line: the stage, then real counts or bytes when the total
    /// is known, or the time spent in the stage when it is not.
    func progress(_ type: String, _ value: Value, elapsed: TimeInterval) -> String {
        var parts = [Self.progressStage(type, value)]
        let done = value["bytesCopied"].int ?? value["receivedBytes"].int
        if let total = value["totalBytes"].int, total > 0 {
            let fraction = (Double(min(done ?? 0, total)) / Double(total)).formatted(.percent.precision(.fractionLength(0)).locale(TextFormat.locale))
            parts.append(Messages.CLIExperience.progressOf(TextFormat.bytes(Int64(done ?? 0)), TextFormat.bytes(Int64(total)), fraction).localized)
        } else if let done {
            parts.append(TextFormat.bytes(Int64(done)))
        } else if let total = value["total"].int, total > 0 {
            parts.append("\(value["completed"].int ?? 0)/\(total)")
        }
        if value["total"].int ?? 0 <= 0, value["totalBytes"].int ?? 0 <= 0, elapsed >= 1 { parts.append(TextFormat.duration(elapsed)) }
        return parts.joined(separator: " ")
    }

    static func progressStage(_ type: String, _ value: Value) -> String {
        if type == "session" {
            let stage = value["stage"].string ?? ""
            return GameSession.Stage(rawValue: stage)?.title ?? stage
        }
        if let stage = value["stage"].string { return stage }
        switch value["phase"].string {
        case "verifying"?: return Messages.CLIExperience.progressVerifying.localized
        case "copying"?: return Messages.CLIExperience.progressCopying.localized
        case "publishing"?: return Messages.CLIExperience.progressPublishing.localized
        case "committed"?: return Messages.CLIExperience.progressFinishing.localized
        case "retiring"?, "deleting"?: return Messages.CLIExperience.progressCleaning.localized
        case "recovering"?, "rollingBack"?: return Messages.CLIExperience.progressRecovering.localized
        case let phase?: return phase
        case nil: return value["receivedBytes"] != .null ? Messages.CLIExperience.progressDownloading.localized : Messages.CLIExperience.progressWorking.localized
        }
    }

    // MARK: Lists

    /// Rows, the problems they have, the pages around them and an explanation
    /// when there are none. Problems stay visible however compact the table is.
    func page(_ value: Value, items: [Value], columns: [ListColumn]? = nil, problems: [(String, String)] = []) -> [String] {
        guard !items.isEmpty else { return empty(value) }
        var lines: [String]
        if let columns {
            let table = layout.table(columns, items)
            lines = table.lines
            if table.hidden { lines += layout.paragraph(Messages.CLIExperience.hiddenColumns.localized).map(style.dim) }
            if !problems.isEmpty { lines += [""] + layout.prose(Messages.CLIExperience.needsAttention.localized, style.warning) + layout.fields(problems) }
        } else if items.allSatisfy({ $0.object != nil }) {
            // Without fixed columns, each field is one, in name order.
            let keys = Set(items.flatMap { Self.flatten($0).keys }).sorted()
            let table = layout.table(keys.enumerated().map { position, key in
                ListColumn(header: key, priority: position) { Self.atom(ConfigurationService.get($0, key)) }
            }, items)
            lines = table.lines
            if table.hidden { lines += layout.paragraph(Messages.CLIExperience.fullDetails.localized).map(style.dim) }
        } else { lines = items.flatMap { Self.details($0) } }
        lines += pageFooter(value, count: items.count)
        let extra = value.object?.filter { !["items", "offset", "total", "providerTotal", "hasMore", "warnings"].contains($0.key) } ?? [:]
        if !extra.isEmpty { lines += Self.details(.object(extra)) }
        return lines
    }

    /// The range shown, the total when known and the command for the next page.
    func pageFooter(_ value: Value, count: Int) -> [String] {
        let offset = value["offset"].int ?? 0, more = value["hasMore"] == .bool(true)
        var lines: [String] = []
        if let total = value["total"].int {
            lines += layout.paragraph(offset == 0 && !more ? Messages.CLIExperience.total(Int64(total)).localized
                : Messages.CLIExperience.pageRange(String(offset + 1), String(offset + count), String(total)).localized)
        } else if offset > 0 || more {
            lines += layout.paragraph(Messages.CLIExperience.pageRangeOpen(String(offset + 1), String(offset + count)).localized)
        }
        if more { lines.append(Messages.CLIExperience.nextPage(command(repeating(offset: offset + count))).localized) }
        return lines.map(style.dim)
    }

    /// This command with its filters, for another page or without paging.
    private func repeating(offset: Int?, filters: Bool = true) -> [String] {
        guard let request else { return [] }
        var command = request.spec.path + request.operands
        for key in request.options.keys.sorted() where !["offset", "all"].contains(key) && (filters || key == "limit") {
            switch request.options[key]! {
            case .null, .bool(false): break
            case .bool(true): command.append("--" + key)
            case .array(let values): for field in values { command += ["--" + key, field.string ?? Self.atom(field)] }
            case let field: command += ["--" + key, field.string ?? Self.atom(field)]
            }
        }
        return command + (offset.map { ["--offset", String($0)] } ?? [])
    }

    private var filtered: Bool {
        request?.options.contains { !["limit", "offset", "all"].contains($0.key) && $0.value != .bool(false) && $0.value != .null } ?? false
    }

    /// No results: past the last page, nothing matching the filters, or nothing at all.
    private func empty(_ value: Value) -> [String] {
        if let total = value["total"].int, total > 0 {
            return layout.prose(Messages.CLIExperience.pagePastEnd(String(total)).localized) + [Messages.CLIExperience.nextAction(command(repeating(offset: nil))).localized]
        }
        if filtered {
            return layout.prose(Messages.CLIExperience.emptyFiltered.localized) + [Messages.CLIExperience.withoutFilters(command(repeating(offset: nil, filters: false))).localized]
        }
        return layout.prose(Messages.CLIExperience.empty.localized) + (emptyHints[path].map { [Messages.CLIExperience.nextAction(command($0)).localized] } ?? [])
    }

    /// Where to start when a resource has nothing yet.
    private var emptyHints: [[String]: [String]] {
        [["instance", "list"]: ["instance", "create", "--help"], ["account", "list"]: ["account", "login", "start", "--help"],
         ["java", "list"]: ["java", "available"], ["server", "list"]: ["server", "add", "--help"]]
    }

    // MARK: Configuration

    func configurationFields(_ value: Value) -> [String] {
        guard case .array(let fields) = value["fields"] else { return [] }
        var lines: [String] = []
        for (scope, title) in [("app", Messages.CLIExperience.fieldScopeApp.localized), ("defaults", Messages.CLIExperience.fieldScopeLaunch.localized)] {
            let rows = fields.filter { field in (try? field["scopes"].decode([String].self))?.contains(scope) == true }
            guard !rows.isEmpty else { continue }
            if !lines.isEmpty { lines.append("") }
            lines.append(style.bold(title))
            lines += TerminalText.columns(rows.map { field in (field["name"].string ?? "", Self.fieldDescription(field)) }, maximumLabel: 30, width: layout.width)
        }
        if fields.contains(where: { $0["group"] != .null }) {
            let groups = Array(Set(fields.compactMap { $0["group"].string })).sorted()
            lines += [""] + TerminalText.wrap(Messages.CLIExperience.fieldInheritance(groups.joined(separator: ", ")).localized, width: layout.width)
        }
        return lines
    }

    static func fieldDescription(_ field: Value) -> String {
        let values = (try? field["values"].decode([String].self)) ?? []
        var parts: [String]
        switch field["type"].string {
        case "integer":
            var text = Messages.CLIExperience.fieldTypeInteger.localized
            if let minimum = field["minimum"].int, let maximum = field["maximum"].int { text += " \(minimum)–\(maximum)" }
            parts = [text]
        case "boolean": parts = [Messages.CLIExperience.fieldTypeBoolean.localized]
        default: parts = [values.isEmpty ? Messages.CLIExperience.fieldTypeText.localized : values.joined(separator: " | ")]
        }
        switch field["unit"].string {
        case "MB": parts.append("MB")
        case "seconds": parts.append(Messages.CLIExperience.unitSeconds.localized)
        case "pixels": parts.append(Messages.CLIExperience.unitPixels.localized)
        default: break
        }
        var text = parts.joined(separator: " ")
        if field["nullable"] == .bool(true) { text = Messages.CLIExperience.fieldNullable(text).localized }
        if field["sensitive"] == .bool(true) { text = Messages.CLIExperience.fieldSensitive(text).localized }
        return text
    }

    /// app, defaults or the instance's name.
    func scopeTitle(_ scope: Value) -> String {
        let scope = scope.string ?? ""
        switch scope {
        case "app": return Messages.CLIExperience.scopeApp.localized
        case "defaults": return Messages.CLIExperience.scopeDefaults.localized
        default:
            let id = String(scope.dropFirst("instance:".count))
            let name = request.flatMap { try? TargetCatalog(paths: CLIApplication.basePaths($0)).index(.instance) }.flatMap { index in
                index.entries.first { $0.id.uuidString == id }.map { Self.reference($0, in: index, details: layout.details) }
            }
            return Messages.CLIExperience.scopeInstance(name ?? id).localized
        }
    }

    /// Fields with their effective value and where it comes from.
    func configuration(_ value: Value) -> [String] {
        let prefix = value["key"].string ?? ""
        let rows = Self.flatten(value["effective"], prefix: prefix).sorted { $0.key < $1.key }.map { key, field -> Value in
            let group = String(key.split(separator: ".").first ?? "")
            let source = value["source"].string ?? value["sources"][group].string ?? ""
            return .object(["field": .string(key), "value": .string(Self.atom(field)), "source": .string(source)])
        }
        var lines = layout.prose(Messages.CLIExperience.configurationOf(scopeTitle(value["scope"])).localized, style.bold)
        let columns = [ListColumn(header: Messages.CLIExperience.columnField.localized) { $0["field"].string ?? "" },
                       ListColumn(header: Messages.CLIExperience.columnValue.localized) { $0["value"].string ?? "" },
                       ListColumn(header: Messages.CLIExperience.columnSource.localized, priority: 1) { $0["source"].string ?? "" }]
        lines += layout.table(columns, rows).lines
        if layout.details { lines += layout.fields([(Messages.CLIExperience.labelRevision.localized, Self.atom(value["revision"]))], indent: 0) }
        return lines
    }

    /// The outcome first, then each changed field as before → after.
    func configurationChange(_ value: Value) -> [String] {
        let before = value["before"], after = value["after"], changed = value["changed"] == .bool(true)
        let preview = value["dryRun"] == .bool(true), scope = scopeTitle(after["scope"])
        let status = changed ? (preview ? Messages.CLIExperience.configPreviewOf(scope).localized : Messages.CLIExperience.configUpdatedOf(scope).localized)
            : preview ? Messages.CLIExperience.previewMessage(Messages.CLIExperience.configUnchangedOf(scope).localized).localized : Messages.CLIExperience.configUnchangedOf(scope).localized
        var lines = layout.prose(status, changed && !preview ? style.good : style.bold)
        let oldFields = Self.flatten(before["effective"]), newFields = Self.flatten(after["effective"])
        var differences: [(String, String)] = []
        for key in Set(oldFields.keys).union(newFields.keys).sorted() where oldFields[key] != newFields[key] {
            differences.append((key, Self.atom(oldFields[key] ?? .null) + " → " + Self.atom(newFields[key] ?? .null)))
        }
        for key in Set(before["sources"].object?.keys.map { $0 } ?? []).union(after["sources"].object?.keys.map { $0 } ?? []).sorted()
            where before["sources"][key] != after["sources"][key] {
            differences.append((Messages.CLIExperience.sourceOf(key).localized, Self.atom(before["sources"][key]) + " → " + Self.atom(after["sources"][key])))
        }
        if changed && differences.isEmpty { lines += layout.prose(Messages.CLIExperience.hiddenChanges.localized) }
        lines += layout.fields(differences)
        if layout.details { lines += layout.fields([(Messages.CLIExperience.labelRevision.localized, Self.atom(after["revision"]))]) }
        if preview && changed, let request {
            var words = request.spec.path + request.operands
            for key in request.options.keys.sorted() where key != "dry-run" {
                if case .string(let text) = request.options[key]! { words += ["--" + key, text] }
            }
            lines.append(Messages.CLIExperience.applyWith(command(words)).localized)
        }
        return lines
    }

    // MARK: Values

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

    /// Text that is read rather than parsed: control characters escaped, but
    /// spaces and quotes kept, so names and messages read naturally.
    static func plain(_ value: Value) -> String {
        guard let string = value.string else { return value == .null ? "" : atom(value) }
        guard string.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return string }
        return atom(value)
    }

    static func shell(_ arguments: [String]) -> String {
        arguments.map { argument in
            !argument.isEmpty && argument.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./:@%+=,-").contains($0) }
                ? argument : CLIInstallation.shellQuote(argument)
        }.joined(separator: " ")
    }

    static func table(headers: [String], rows: [[String]]) -> String {
        guard !headers.isEmpty else { return "" }
        let widths = headers.indices.map { index in min(48, ([headers] + rows).map { TerminalText.width($0[index]) }.max() ?? 0) }
        return ([headers] + rows).map { row in
            row.enumerated().map { index, cell in
                cell + (index == headers.count - 1 ? "" : String(repeating: " ", count: max(0, widths[index] - TerminalText.width(cell)) + 2))
            }.joined()
        }.joined(separator: "\n")
    }
}
