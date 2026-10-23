import Foundation
import SwiftUI
import RuriCore
import RuriExtensionKit
import RuriLocalization
import RuriVex

extension ExperimentalHost {
    /// Whether Vex is on in the settings the application currently holds.
    var vexEnabled: Bool { settings(VexFeature.context).enabled }
}

@MainActor public final class VexUIProvider: ExperimentalUIProvider {
    private let context: ExperimentalExtensionContext
    private let presentation = VexPresentation()
    public init(context: ExperimentalExtensionContext) { self.context = context }
    public var id: String { context.id }
    public func pages(host: ExperimentalHost) -> [ExperimentalPage] {
        host.vexEnabled ? [.init(id: "vex.git", title: Messages.Vex.git.localized, symbol: "point.3.connected.trianglepath.dotted")] : []
    }
    public func page(_ id: String, host: ExperimentalHost) -> AnyView {
        AnyView(VexGitView().environment(host).environment(presentation))
    }
    public func settings(host: ExperimentalHost) -> AnyView {
        AnyView(VexSettingsSection().environment(host).environment(presentation))
    }
    public func servers(host: ExperimentalHost) -> AnyView {
        AnyView(Group {
            if host.vexEnabled { VexRoomsSection().environment(host).environment(presentation) }
        })
    }
    public func configure(host: ExperimentalHost) async {
        do { presentation.configure(settings: try VexSettings.load(paths: host.paths), paths: host.paths) }
        catch { presentation.stop(); host.report(VexAuthentication.message(for: error)) }
    }
    public func open(_ url: URL, host: ExperimentalHost) throws -> AnyView? {
        guard url.scheme?.lowercased() == "ruri", url.host?.lowercased() == "vex" else { return nil }
        guard host.vexEnabled else { throw RuriError.message(Messages.Vex.disabled) }
        let link = try VexPreviewLink(url)
        _ = try VexTransport.requireHTTPS(link.server)
        return AnyView(VexPreviewSheet(link: link).environment(host).environment(presentation))
    }
    public func stop() { presentation.stop() }
}
