import Foundation
import Testing
@testable import RuriCommandKit

@MainActor struct HelpCommandTests {
    @Test func rootAndNestedHelpPreserveTheRequestedCommandContext() async throws {
        let cases: [([String], String)] = [
            ([], "ruri-chorus"), (["--help"], "ruri-chorus"), (["-h"], "ruri-chorus"), (["help"], "ruri-chorus"),
            (["--help", "app"], "ruri-chorus app"), (["app", "--help"], "ruri-chorus app"),
            (["-h", "app"], "ruri-chorus app"), (["--quiet", "--help", "app"], "ruri-chorus app"),
            (["help", "app"], "ruri-chorus app"), (["app"], "ruri-chorus app"),
            (["app", "language"], "ruri-chorus app language"),
            (["help", "app", "language"], "ruri-chorus app language"),
            (["--help", "world", "backup", "restore"], "ruri-chorus world backup restore"),
            (["world", "backup", "restore", "-h"], "ruri-chorus world backup restore")
        ]
        for (arguments, command) in cases {
            let output = CommandCapture()
            #expect(await CLIApplication.run(arguments, write: output.write) == 0)
            let help = String(decoding: output.output, as: UTF8.self)
            #expect(help.contains("USAGE: " + command + " "), "\(arguments): \(help)")
            #expect(!help.contains("USAGE: help "))
            #expect(output.errors.isEmpty)
        }
    }
    @Test func everyPublicCommandShowsItsOwnOptionsWithoutExecuting() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let state = root.appendingPathComponent("state.json"), original = Data("invalid state".utf8)
        try original.write(to: state)
        for spec in CommandRegistry.commands + ChorusGroup.specs {
            let output = CommandCapture()
            let status = await CLIApplication.run(["--data-dir", root.path] + spec.path + ["--help"], write: output.write)
            let help = String(decoding: output.output, as: UTF8.self)
            #expect(status == 0, "\(spec.path): \(help)")
            #expect(help.contains("USAGE: ruri-chorus " + spec.path.joined(separator: " ") + " "))
            for option in spec.options { #expect(help.contains("--" + option.name), "\(spec.path): \(option.name)") }
            #expect(help.contains("--json"))
            #expect(output.errors.isEmpty)
        }
        #expect(try Data(contentsOf: state) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["state.json"])
    }
    @Test func terminatorKeepsHelpLikeOperandsLiteral() async throws {
        let output = CommandCapture()
        #expect(await CLIApplication.run(["schema", "--json", "--", "--help"], write: output.write) == 1)
        #expect(try output.value["error"]["code"].string == "NOT_FOUND")
    }
}
