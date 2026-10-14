import ArgumentParser
import Foundation
import Testing
import RuriCore
@testable import RuriCommandKit

struct TextOutputTests {
    private func request(_ args: [String]) throws -> CommandRequest {
        try #require(try RuriCommand.parseAsRoot(args) as? any ExecutableCommand).request
    }
    private func text(_ capture: CommandCapture, error: Bool = false) -> String {
        String(decoding: error ? capture.errors : capture.output, as: UTF8.self)
    }
    @MainActor @Test func configurationRoundTripShowsDiffInheritanceAndNoOpWithoutSnapshots() async throws {
        let paths = LauncherPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: paths.root) }
        var instance = GameInstance(name: "Fixture", gameVersion: "1.21.1")
        instance.launchOverrides = .init()
        try StateStore.update(paths) { $0.instances = [instance] }
        let scope = "instance:\(instance.id)"
        let set = ["config", "set", "window.width", "1440", "--scope", scope, "--data-dir", paths.root.path]
        let original = try Data(contentsOf: paths.state), preview = CommandCapture()
        #expect(await CLIApplication.run(set + ["--dry-run"], write: preview.write) == 0)
        #expect(try Data(contentsOf: paths.state) == original)
        #expect(text(preview).contains("1280 → 1440"))
        #expect(text(preview).contains("defaults → instance"))
        #expect(!text(preview).contains("before"))
        #expect(!text(preview).contains("java"))
        let saved = CommandCapture()
        #expect(await CLIApplication.run(set, write: saved.write) == 0)
        #expect(text(saved).contains(try #require(StateStore.load(paths).revision).uuidString))
        let noOp = CommandCapture()
        #expect(await CLIApplication.run(set, write: noOp.write) == 0)
        #expect(!text(noOp).contains(" → "))
        let inherited = CommandCapture()
        #expect(await CLIApplication.run(["config", "inherit", "window", "--scope", scope, "--data-dir", paths.root.path], write: inherited.write) == 0)
        #expect(text(inherited).contains("instance → defaults"))
        let read = CommandCapture()
        #expect(await CLIApplication.run(["config", "get", "memory", "--scope", scope, "--data-dir", paths.root.path], write: read.write) == 0)
        #expect(text(read).contains("memory.initialMB"))
        #expect(text(read).contains("null"))
        #expect(text(read).contains("defaults"))
    }
    @Test func listsPreserveIDsProblemsAndActionablePagination() throws {
        let output = CommandCapture(), sink = CommandOutput(format: .text, write: output.write)
        sink.setRequest(try request(["instance", "list", "--limit", "1", "--name", "Two words", "--data-dir", "/tmp/ruri fixture"]))
        let id = UUID().uuidString
        sink.result(.object(["items": .array([.object([
            "id": .string(id), "name": .string("Two words"), "gameVersion": .string("1.21.1"),
            "installed": .bool(false), "issue": .string("Needs repair"), "iconGlyph": .null
        ])]), "offset": .integer(3), "total": .integer(8), "hasMore": .bool(true),
        "issues": .array([.object(["directory": .string("/missing"), "error": .string("Access denied")])])]))
        let rendered = text(output)
        #expect(rendered.contains(id))
        #expect(rendered.contains("Needs repair"))
        #expect(rendered.contains("Access denied"))
        #expect(rendered.contains("--name 'Two words'"))
        #expect(rendered.contains("ruri-chorus instance list"))
        #expect(rendered.contains("--data-dir '/tmp/ruri fixture' --offset 4"))
        #expect(!rendered.contains("\"items\""))
    }
    @Test func errorsKeepRecoveryDetailsAndRedactEveryChannel() {
        let output = CommandCapture(), sink = CommandOutput(format: .text, write: output.write)
        sink.addSecrets(["fixture-secret"])
        sink.result(error: .init("RECOVERY_REQUIRED", "Failed fixture-secret", retryable: true,
            nextActions: [.init(["recovery", "apply", "content", "fixture id", "--yes"])],
            details: .object(["candidates": .array([.object(["id": .string("first-id"), "name": .string("fixture-secret")])]), "recoveryID": .string("recovery-id")])),
            warnings: ["Warning fixture-secret"])
        let rendered = text(output, error: true)
        #expect(output.output.isEmpty)
        #expect(rendered.contains("RECOVERY_REQUIRED"))
        #expect(rendered.contains("first-id"))
        #expect(rendered.contains("recovery-id"))
        #expect(rendered.contains("ruri-chorus recovery apply content 'fixture id' --yes"))
        #expect(!rendered.contains("fixture-secret"))
    }
    @Test func logsAreRawAndProgressIsCoalescedOnlyForText() throws {
        let logs = CommandCapture(), logSink = CommandOutput(format: .text, write: logs.write)
        logSink.setRequest(try request(["session", "logs", UUID().uuidString, UUID().uuidString]))
        logSink.result(.object(["sessionID": .string("id"), "text": .string("line one\nline two\n"), "bounded": .bool(true)]))
        #expect(text(logs) == "line one\nline two\n")
        let progress = CommandCapture(), sink = CommandOutput(format: .text, write: progress.write)
        let events = (0...100).map { Value.object(["stage": .string("download"), "completed": .integer($0), "total": .integer(100)]) }
        for event in events { sink.event("progress", event) }
        #expect(text(progress, error: true).contains("download 0/100"))
        #expect(text(progress, error: true).contains("download 100/100"))
        #expect(text(progress, error: true).split(separator: "\n").count <= 3)
        let stream = CommandCapture(), streamSink = CommandOutput(format: .ndjson, write: stream.write)
        for event in events { streamSink.event("progress", event) }
        streamSink.result(.object(["id": .string("result")]))
        #expect(text(stream).split(separator: "\n").count == 102)
    }
    @Test func textDistinguishesNullEmptyAndControlCharacters() {
        #expect(CommandTextRenderer.atom(.null) == "null")
        #expect(CommandTextRenderer.atom(.string("")) == "\"\"")
        #expect(CommandTextRenderer.atom(.string("null")) == "\"null\"")
        #expect(CommandTextRenderer.atom(.string("name\nsecond")) == "\"name\\nsecond\"")
        #expect(!CommandTextRenderer.atom(.string("\u{1b}[31m")).contains("\u{1b}"))
    }
    @MainActor @Test func JSONKeepsTheFullContractWhileDefaultIsText() async throws {
        let paths = LauncherPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let args = ["config", "get", "--scope", "defaults", "--data-dir", paths.root.path]
        let readable = CommandCapture(), machine = CommandCapture()
        #expect(await CLIApplication.run(args, write: readable.write) == 0)
        #expect(await CLIApplication.run(args + ["--json"], write: machine.write) == 0)
        #expect(!text(readable).contains("\"effective\""))
        #expect(try machine.value["data"]["effective"]["java"] != .null)
        #expect(try machine.value["data"]["explicit"] != .null)
        #expect(try machine.value["schemaVersion"] == .integer(1))
        #expect(text(machine).split(separator: "\n").count == 1)
    }
}
