import Foundation
import Testing
import RuriCore
@testable import RuriCommandKit

struct CommandInteractionTests {
    private let prompt: Value = .object([
        "instructions": .string("Open the authorization page and enter the code."),
        "userCode": .string("ABCD-EFGH"),
        "verificationURL": .string("https://example.com/authorize")
    ])

    @Test func textAndJSONShowRequiredInteractionOnStandardError() {
        for format in [CommandOutput.Format.text, .json] {
            for quiet in [false, true] {
                let capture = CommandCapture(), output = CommandOutput(format: format, quiet: quiet, write: capture.write)
                output.interaction("authorization", prompt)
                let text = String(decoding: capture.errors, as: UTF8.self)
                #expect(capture.output.isEmpty)
                #expect(text.hasPrefix("authorization:\n"))
                #expect(text.contains("Open the authorization page and enter the code."))
                #expect(text.contains("ABCD-EFGH"))
                #expect(text.contains("https://example.com/authorize"))
                #expect(text.hasSuffix("\n"))
            }
        }
    }

    @Test func JSONKeepsOneFinalDocumentOnStandardOutput() throws {
        let capture = CommandCapture(), output = CommandOutput(format: .json, quiet: true, write: capture.write)
        output.event("notice", .string("Ordinary event"))
        #expect(capture.output.isEmpty && capture.errors.isEmpty)
        output.interaction("authorization", prompt)
        #expect(capture.output.isEmpty)
        output.result(.object(["authorized": .bool(true)]))
        let value = try JSONDecoder().decode(Value.self, from: capture.output)
        #expect(value["schemaVersion"] == .integer(1))
        #expect(value["ok"] == .bool(true))
        #expect(value["data"]["authorized"] == .bool(true))
        #expect(!String(decoding: capture.output, as: UTF8.self).contains("ABCD-EFGH"))
    }

    @Test func NDJSONEmitsStructuredInteractionAndFinalResult() throws {
        for quiet in [false, true] {
            let capture = CommandCapture(), output = CommandOutput(format: .ndjson, quiet: quiet, color: "always", write: capture.write)
            output.interaction("authorization", prompt)
            output.result(.object(["authorized": .bool(true)]))
            let lines = capture.output.split(separator: 10)
            #expect(lines.count == 2)
            let interaction = try JSONDecoder().decode(Value.self, from: Data(try #require(lines.first)))
            let result = try JSONDecoder().decode(Value.self, from: Data(try #require(lines.last)))
            #expect(interaction == .object(["schemaVersion": .integer(1), "type": .string("authorization"), "data": prompt]))
            #expect(result["type"] == .string("result"))
            #expect(result["data"]["ok"] == .bool(true))
            #expect(capture.errors.isEmpty)
        }
    }

    @Test func quietKeepsOrdinaryTextEventsSilent() {
        let capture = CommandCapture(), output = CommandOutput(format: .text, quiet: true, write: capture.write)
        output.event("notice", .string("Ordinary event"))
        #expect(capture.output.isEmpty && capture.errors.isEmpty)
        output.interaction("authorization", prompt)
        #expect(!capture.errors.isEmpty && capture.output.isEmpty)
    }

    @Test func interactionsAfterCompletionDoNotWrite() {
        for format in [CommandOutput.Format.text, .json, .ndjson] {
            let capture = CommandCapture(), output = CommandOutput(format: format, write: capture.write)
            output.result(.object(["authorized": .bool(true)]))
            let stdout = capture.output, stderr = capture.errors
            output.interaction("authorization", prompt)
            #expect(capture.output == stdout)
            #expect(capture.errors == stderr)
        }
    }

    @Test func interactionRedactsTheTypeAndNestedValues() throws {
        for format in [CommandOutput.Format.text, .json, .ndjson] {
            let capture = CommandCapture(), output = CommandOutput(format: format, write: capture.write)
            output.addSecrets(["private-interaction-value"])
            output.interaction("authorization-private-interaction-value", .object([
                "message": .string("private-interaction-value"),
                "nested": .object(["items": .array([.string("private-interaction-value"), .string("Authorization: Bearer bearer-value")])]),
                "url": .string("https://example.com/authorize?token=query-value")
            ]))
            let text = String(decoding: capture.output + capture.errors, as: UTF8.self)
            #expect(!text.contains("private-interaction-value"))
            #expect(!text.contains("bearer-value"))
            #expect(!text.contains("query-value"))
            #expect(text.contains("<redacted>"))
            if format == .ndjson {
                let value = try JSONDecoder().decode(Value.self, from: capture.output)
                #expect(value["type"] == .string("authorization-<redacted>"))
                #expect(value["data"]["nested"]["items"] == .array([.string("<redacted>"), .string("Authorization: Bearer <redacted>")]))
            }
        }
    }

    @Test func interactionClearsTheTerminalProgressLine() {
        let capture = CommandCapture(), stream = TerminalProfile.Stream(isTerminal: true, width: 80)
        let output = CommandOutput(format: .text, write: capture.write,
                                   terminal: .init(output: stream, error: stream, environment: [:]))
        output.event("progress", .object(["stage": .string("Preparing"), "completed": .integer(1), "total": .integer(2)]))
        let progress = String(decoding: capture.errors, as: UTF8.self)
        #expect(progress.hasPrefix("\r\u{1B}[2K"))
        output.interaction("authorization", prompt)
        #expect(String(decoding: capture.errors, as: UTF8.self).hasPrefix(progress + "\r\u{1B}[2Kauthorization:\n"))
        #expect(capture.output.isEmpty)
    }
}
