import Foundation
import Testing
@testable import RuriLocalization

struct ExtensionCatalogTests {
    @Test func registeredTablesResolveThroughTheirOwnDefinitions() {
        LocalizationCatalogRegistry.register(table: "ExtensionSample", definitions: [
            "ExtensionSample:Sample.greeting": MessageDefinition("你好，%@", [.text]),
        ], bundle: nil)
        let context = LocalizationContext(language: "zh-Hans")
        let message = LocalizedMessage(key: "Sample.greeting", table: "ExtensionSample", fallback: "你好，%@", arguments: [.text("Ruri")])
        #expect(context.string(message) == "你好，Ruri")
        // Arguments that do not match the definition never reach a format string.
        let mismatched = LocalizedMessage(key: "Sample.greeting", table: "ExtensionSample", fallback: "unchanged", arguments: [.integer(1)])
        #expect(context.string(mismatched) == "unchanged")
        let unknown = LocalizedMessage(key: "Sample.missing", table: "ExtensionSample", fallback: "recorded", arguments: [])
        #expect(context.string(unknown) == "recorded")
        // A table without a bundle has no compiled strings to check.
        #expect(!LocalizationCatalogRegistry.resourcesAvailable())
    }
}
