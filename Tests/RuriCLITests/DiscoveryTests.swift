import Foundation
import Testing
@testable import RuriCommandKit

@MainActor struct DiscoveryTests {
    @Test func completeCheatSheetIsBoundedAndContainsEverySignature() async throws {
        let output = CommandCapture()
        #expect(await CLIApplication.run(["help", "--all"], write: output.write) == 0)
        let text = String(decoding: output.output, as: UTF8.self)
        for spec in CommandRegistry.commands + ChorusGroup.specs { #expect(text.contains(CommandHelp.signature(spec))) }
        #expect(output.output.count < 35_000)
        #expect(!text.contains("resultSchema"))
        #expect(text.components(separatedBy: "--data-dir").count == 2)
    }
    @Test func groupedHelpIncludesNestedCommandsOptionsEnumsAndExamples() async throws {
        let output = CommandCapture()
        #expect(await CLIApplication.run(["help", "instance"], write: output.write) == 0)
        let text = String(decoding: output.output, as: UTF8.self)
        for spec in CommandRegistry.commands where spec.path.first == "instance" {
            #expect(text.contains(CommandHelp.signature(spec)))
            for option in spec.options { #expect(text.contains("--" + option.name)) }
            for example in spec.examples { #expect(text.contains(example)) }
        }
        #expect(!text.contains("ruri-chorus account add-offline"))
        let config = CommandCapture()
        #expect(await CLIApplication.run(["help", "config"], write: config.write) == 0)
        #expect(String(decoding: config.output, as: UTF8.self).contains("memory.maximumMB: integer (512…131072)"))
    }
    @Test func schemaIndexAndLeafExcludeUnrelatedDefinitions() async throws {
        let index = CommandCapture()
        #expect(await CLIApplication.run(["schema", "--json"], write: index.write) == 0)
        #expect(index.output.count < 40_000)
        #expect(try index.value["data"]["patchSchemas"] == .null)
        #expect(!String(decoding: index.output, as: UTF8.self).contains("resultSchema"))
        let leaf = CommandCapture()
        #expect(await CLIApplication.run(["schema", "instance", "list", "--json"], write: leaf.write) == 0)
        #expect(leaf.output.count < 5_000)
        #expect(try leaf.value["data"]["configuration"] == .null)
        #expect(try leaf.value["data"]["patchSchemas"] == .null)
    }
    @Test func schemaCanSelectOnlyInputOutputAndPatchScope() async throws {
        let output = CommandCapture()
        #expect(await CLIApplication.run(["schema", "config", "apply", "--input", "--scope", "instance", "--json"], write: output.write) == 0)
        let data = try output.value["data"]
        #expect(data["patchSchemas"]["app"] == .null)
        #expect(data["patchSchemas"]["defaults"] == .null)
        #expect(data["patchSchemas"]["instance"] != .null)
        #expect(!String(decoding: output.output, as: UTF8.self).contains("resultSchema"))
        let result = CommandCapture()
        #expect(await CLIApplication.run(["schema", "config", "apply", "--output-schema", "--json"], write: result.write) == 0)
        #expect(try result.value["data"]["patchSchemas"] == .null)
        #expect(!String(decoding: result.output, as: UTF8.self).contains("inputSchema"))
        for args in [["schema", "--input"], ["schema", "instance", "list", "--scope", "app"], ["schema", "config", "get", "--scope", "app", "--output-schema"], ["help", "missing"], ["help", "--output", "missing"]] {
            let invalid = CommandCapture()
            #expect(await CLIApplication.run(args + ["--json"], write: invalid.write) == 2)
        }
    }
}
