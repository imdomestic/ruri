import ArgumentParser
import Foundation
import Testing
@testable import RuriCommandKit
import RuriCore

struct SchemaContractTests {
    @Test func everyDescriptorMatchesTheTypedParser() throws {
        for spec in CommandRegistry.commands + ChorusGroup.specs {
            var arguments = spec.path + spec.operands.map { _ in "fixture" }
            for option in spec.options {
                arguments.append("--" + option.name)
                if option.type != "bool" {
                    arguments.append(option.values.first ?? (option.type == "int" ? "1" : "fixture"))
                }
            }
            arguments += ["--json", "--data-dir", "/tmp/ruri-schema-test"]
            let command = try #require(try RuriCommand.parseAsRoot(arguments) as? any ExecutableCommand)
            #expect(command.request.spec.path == spec.path)
            try command.request.validate()
            let descriptor = try Value.encode(spec)
            let input = descriptor["inputSchema"]["properties"]["options"]["properties"]
            #expect(Set(input.object!.keys) == Set(spec.options.map(\.name) + ["json", "output", "data-dir", "language", "quiet"]))
            #expect(descriptor["resultSchema"]["properties"]["schemaVersion"]["const"] == .integer(1))
            #expect(descriptor["resultSchema"]["properties"]["error"]["anyOf"] != .null)
            if spec.operands.isEmpty { #expect(descriptor["inputSchema"]["properties"]["operands"]["prefixItems"] == .null) }
        }
    }
    @MainActor @Test func configurationSchemaDescribesPatchFieldsAndInheritance() async throws {
        let output = CommandCapture()
        #expect(await CLIApplication.run(["schema", "config", "apply", "--json"], write: output.write) == 0)
        let data = try output.value["data"]
        let patches = data["patchSchemas"]
        #expect(patches["app"]["properties"]["set"]["properties"]["concurrentDownloads"]["maximum"] == .integer(16))
        #expect(patches["instance"]["properties"]["set"]["properties"]["memory"]["properties"]["mode"]["enum"] == .array([.string("automatic"), .string("manual")]))
        #expect(patches["defaults"]["properties"]["inherit"]["maxItems"] == .integer(0))
        #expect(patches["instance"]["properties"]["inherit"]["items"]["enum"] != .null)
        #expect(patches["instance"]["additionalProperties"] == .bool(false))
    }
    @Test func outputTerminatesOnceAndRedactsDiagnostics() throws {
        let output = CommandCapture(), sink = CommandOutput(format: .ndjson, write: output.write)
        sink.addSecrets(["fixture-private-token"])
        sink.event("progress", .object(["message": .string("fixture-private-token")]))
        sink.result(error: .init("FIXTURE", "fixture-private-token"))
        sink.event("late", .null); sink.result(.bool(true))
        let text = String(decoding: output.output, as: UTF8.self)
        #expect(!text.contains("fixture-private-token"))
        #expect(text.split(separator: "\n").count == 2)
        let final = try JSONDecoder().decode(Value.self, from: Data(text.split(separator: "\n").last!.utf8))
        #expect(final["type"] == .string("result"))
        #expect(final["data"]["ok"] == .bool(false))
    }
}
