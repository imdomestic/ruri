import AppKit
import SwiftUI

extension View {
    @ViewBuilder func vexAllowsAppTermination() -> some View {
        if #available(macOS 15.4, *) {
            presentationPreventsAppTermination(false)
        } else {
            background(VexAppTerminationWindowBinding().frame(width: 0, height: 0))
        }
    }
}

private struct VexAppTerminationWindowBinding: NSViewRepresentable {
    func makeNSView(context: Context) -> VexAppTerminationWindowView {
        VexAppTerminationWindowView(frame: .zero)
    }

    func updateNSView(_ view: VexAppTerminationWindowView, context: Context) {
        view.refreshBinding()
    }

    static func dismantleNSView(_ view: VexAppTerminationWindowView, coordinator: ()) {
        view.invalidate()
    }
}

@MainActor final class VexAppTerminationWindowView: NSView {
    private final class Attachments: NSObject {
        let originalValue: Bool
        var owners: Set<ObjectIdentifier> = []

        init(originalValue: Bool) { self.originalValue = originalValue }
    }

    private static let attachments = NSMapTable<NSWindow, Attachments>(
        keyOptions: [.weakMemory, .objectPointerPersonality], valueOptions: .strongMemory
    )
    private weak var boundWindow: NSWindow?
    private var keyObserver: (any NSObjectProtocol)?
    private var active = true

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if boundWindow !== newWindow { unbind() }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshBinding()
    }

    func refreshBinding() {
        guard active else { return }
        if boundWindow !== window {
            unbind()
            guard let window else { return }
            let state = Self.attachments.object(forKey: window) ?? Attachments(
                originalValue: window.preventsApplicationTerminationWhenModal
            )
            state.owners.insert(ObjectIdentifier(self))
            Self.attachments.setObject(state, forKey: window)
            boundWindow = window
            keyObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshBinding() }
            }
        }
        if let boundWindow, boundWindow.preventsApplicationTerminationWhenModal {
            boundWindow.preventsApplicationTerminationWhenModal = false
        }
    }

    func invalidate() {
        active = false
        unbind()
    }

    private func unbind() {
        if let keyObserver {
            NotificationCenter.default.removeObserver(keyObserver)
            self.keyObserver = nil
        }
        guard let boundWindow else { return }
        let state = Self.attachments.object(forKey: boundWindow)!
        precondition(state.owners.remove(ObjectIdentifier(self)) != nil)
        if state.owners.isEmpty {
            boundWindow.preventsApplicationTerminationWhenModal = state.originalValue
            Self.attachments.removeObject(forKey: boundWindow)
        }
        self.boundWindow = nil
    }
}
