import Foundation

public enum LocalizationCommandLine {
    /// Global options precede the subcommand so game/command arguments keep
    /// their original meaning. Unsupported languages use normal fallback.
    public struct InvalidLanguageOption: LocalizedError, Sendable {
        public var errorDescription: String? { Messages.Common.invalidLanguageOption.localized }
    }
    public static func takeLanguage(from arguments: inout [String]) throws -> String? {
        guard let first = arguments.first else { return nil }
        if first.hasPrefix("--language=") {
            let value = String(first.dropFirst("--language=".count))
            guard !value.isEmpty else { throw InvalidLanguageOption() }
            arguments.removeFirst(); return value
        }
        if first == "--language", arguments.count > 1, !arguments[1].hasPrefix("--") {
            arguments.removeFirst(); return arguments.removeFirst()
        }
        if first == "--language" { throw InvalidLanguageOption() }
        return nil
    }

    /// A read-only packaging probe shared by all three executable entry points.
    /// It executes before loading launcher state, accounts or game services.
    public static func resourceCheck(arguments: [String] = Array(CommandLine.arguments.dropFirst())) -> Int32? {
        guard arguments == ["--localization-check"] else { return nil }
        guard LocalizationCatalogRegistry.resourcesAvailable(), let bundle = LocalizationResources.bundle,
              let name = bundle.localizations.first(where: { $0.caseInsensitiveCompare(LocalizationContext.baseLanguage) == .orderedSame }),
              let path = bundle.path(forResource: name, ofType: "lproj"), let localized = Bundle(path: path),
              localized.localizedString(forKey: "Common.localizationCheck", value: "MISSING", table: "Common") != "MISSING" else { return 2 }
        let report: [String: Any] = ["bundle": bundle.bundleURL.path, "languages": bundle.localizations.sorted(),
                                     "message": Messages.Common.localizationCheck.localized]
        guard let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return 2 }
        print(text)
        return 0
    }
}
