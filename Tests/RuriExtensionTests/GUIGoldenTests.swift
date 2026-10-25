import AppKit
import ApplicationServices
import Foundation
import Testing

/// Without compiled extensions, the sidebar, home page and settings page read
/// the same through Accessibility as upstream main. Runs only when
/// RURI_GUI_GOLDEN_APP names a built Ruri.app; `GUIGolden.json` was recorded
/// from an upstream main build with RURI_RECORD_GOLDEN=1. The app runs as a
/// copy with its own bundle identifier and an empty data folder, so neither
/// the preferences nor the data of an installed Ruri are touched.
@MainActor struct GUIGoldenTests {
    nonisolated static let manifest = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("GUIGolden.json")
    nonisolated static let identifier = "dev.ruri.launcher.extension-golden"

    @Test(.enabled(if: ProcessInfo.processInfo.environment["RURI_GUI_GOLDEN_APP"] != nil))
    func pagesMatchUpstream() async throws {
        try #require(AXIsProcessTrusted(), "the test needs Accessibility access")
        // The settings page shows the data folder, so its path is the same in every run.
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("ruri-gui-golden")
        try? FileManager.default.removeItem(at: work)
        try FileManager.default.createDirectory(at: work.appendingPathComponent("data"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let app = work.appendingPathComponent("Ruri.app")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: ProcessInfo.processInfo.environment["RURI_GUI_GOLDEN_APP"]!), to: app)
        try run("/usr/libexec/PlistBuddy", ["-c", "Set :CFBundleIdentifier \(Self.identifier)", app.appendingPathComponent("Contents/Info.plist").path])
        try run("/usr/bin/codesign", ["--force", "--sign", "-", app.path])
        try? run("/usr/bin/defaults", ["delete", Self.identifier])
        defer { try? run("/usr/bin/defaults", ["delete", Self.identifier]) }

        let running = Process()
        running.executableURL = app.appendingPathComponent("Contents/MacOS/Ruri")
        running.environment = ProcessInfo.processInfo.environment.merging(["RURI_DATA_DIR": work.appendingPathComponent("data").path]) { _, value in value }
        running.standardOutput = FileHandle.nullDevice
        running.standardError = FileHandle.nullDevice
        try running.run()
        defer {
            if running.isRunning { running.terminate(); running.waitUntilExit() }
        }
        let application = AXUIElementCreateApplication(running.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 5)

        var pages: [String: [String]] = [:]
        for page in ["home", "settings"] {
            let window = try await Self.wait("main window") { try Self.windows(application).first }
            let sidebar = try await Self.wait("sidebar") { try Self.find(window) { try Self.text($0, kAXRoleAttribute) == kAXOutlineRole } }
            let rows = try Self.children(sidebar).filter { try Self.text($0, kAXRoleAttribute) == kAXRowRole }
            // Rows follow the sidebar order: home first, settings last.
            let row = page == "home" ? rows.first! : rows.last!
            #expect(AXUIElementSetAttributeValue(row, kAXSelectedAttribute as CFString, kCFBooleanTrue) == .success)
            try await Task.sleep(for: .seconds(2))
            pages[page] = try Self.describe(Self.windows(application).first!).map { $0.replacingOccurrences(of: work.path, with: "<work>") }
        }
        if ProcessInfo.processInfo.environment["RURI_RECORD_GOLDEN"] == "1" {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(pages).write(to: Self.manifest)
            return
        }
        let expected = try JSONDecoder().decode([String: [String]].self, from: Data(contentsOf: Self.manifest))
        #expect(pages == expected)
    }

    private func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.executableLoad) }
    }

    /// An attribute's value, or nil when the element does not provide it.
    private static func attribute(_ element: AXUIElement, _ name: String) throws -> CFTypeRef? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        if status == .apiDisabled { throw CocoaError(.featureUnsupported) }
        return status == .success ? value : nil
    }
    private static func text(_ element: AXUIElement, _ name: String) throws -> String { try attribute(element, name) as? String ?? "" }
    private static func children(_ element: AXUIElement) throws -> [AXUIElement] { try attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] }
    private static func windows(_ application: AXUIElement) throws -> [AXUIElement] { try attribute(application, kAXWindowsAttribute) as? [AXUIElement] ?? [] }
    private static func find(_ element: AXUIElement, depth: Int = 0, _ match: (AXUIElement) throws -> Bool) throws -> AXUIElement? {
        if try match(element) { return element }
        guard depth < 40 else { return nil }
        for child in try children(element) { if let found = try find(child, depth: depth + 1, match) { return found } }
        return nil
    }
    private static func wait<T>(_ description: String, _ value: () throws -> T?) async throws -> T {
        for _ in 0..<60 {
            if let found = try value() { return found }
            try await Task.sleep(for: .milliseconds(500))
        }
        throw CocoaError(.fileReadUnknown, userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for the GUI golden \(description)"])
    }

    /// Role, subrole and the visible texts of every element, in tree order.
    private static func describe(_ window: AXUIElement) throws -> [String] {
        var lines: [String] = []
        func visit(_ element: AXUIElement, depth: Int) throws {
            let fields = try [kAXRoleAttribute, kAXSubroleAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute]
                .map { name -> String in
                    let value = try attribute(element, name)
                    if let string = value as? String { return string }
                    if let number = value as? NSNumber { return number.stringValue }
                    return ""
                }
            lines.append(String(repeating: " ", count: depth) + fields.joined(separator: " | "))
            guard depth < 40 else { return }
            for child in try children(element) { try visit(child, depth: depth + 1) }
        }
        try visit(window, depth: 0)
        return lines
    }
}
