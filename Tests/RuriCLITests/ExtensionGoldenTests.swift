import CryptoKit
import Foundation
import Testing
@testable import RuriCommandKit

/// Without compiled extensions, discovery output is byte-for-byte the output
/// of upstream main. `ExtensionGolden.json` holds the SHA-256 and size of each
/// output, recorded from upstream main with RURI_RECORD_GOLDEN=1 (this file
/// added to an upstream checkout). Record it again only from upstream main.
@MainActor struct ExtensionGoldenTests {
    nonisolated static let cases: [(name: String, arguments: [String])] = [
        ("help", ["help"]), ("help-all", ["help", "--all"]), ("help-json", ["help", "--json"]),
        ("help-all-json", ["help", "--all", "--json"]), ("root-help", ["--help"]),
        ("schema", ["schema"]), ("schema-json", ["schema", "--json"]),
        ("schema-full", ["schema", "--full"]), ("schema-full-json", ["schema", "--full", "--json"]),
    ]
    nonisolated static let languages = ["en", "zh-Hans"]
    nonisolated static let manifest = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("ExtensionGolden.json")

    struct Entry: Codable, Equatable {
        let sha256: String
        let size: Int
    }

    private static func render(_ arguments: [String]) async -> Data {
        let output = CommandCapture()
        let status = await CLIApplication.run(arguments, write: output.write)
        return Data("exit=\(status)\n".utf8) + output.output + Data("\n--- stderr\n".utf8) + output.errors
    }
    private static func entry(_ data: Data) -> Entry {
        Entry(sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), size: data.count)
    }

    @Test func discoveryMatchesUpstream() async throws {
        var rendered: [String: Data] = [:]
        for (name, arguments) in Self.cases {
            for language in Self.languages {
                rendered["\(name).\(language)"] = await Self.render(arguments + ["--language", language])
            }
        }
        let actual = rendered.mapValues(Self.entry)
        if ProcessInfo.processInfo.environment["RURI_RECORD_GOLDEN"] == "1" {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(actual).write(to: Self.manifest)
            return
        }
        let expected = try JSONDecoder().decode([String: Entry].self, from: Data(contentsOf: Self.manifest))
        #expect(Set(expected.keys) == Set(actual.keys))
        for (key, entry) in actual.sorted(by: { $0.key < $1.key }) where expected[key] != entry {
            // Keep the differing output for comparison with upstream.
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("ruri-golden-\(key).txt")
            try rendered[key]!.write(to: file)
            Issue.record("\(key) differs from upstream main; output saved to \(file.path)")
        }
    }
}
