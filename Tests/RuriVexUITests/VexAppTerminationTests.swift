import AppKit
import Testing
import XCTest
@testable import RuriVexUI

@MainActor private func terminationTestWindow(preventsTermination: Bool = true) -> NSWindow {
    _ = NSApplication.shared
    let window = NSWindow(
        contentRect: NSRect(x: -10000, y: -10000, width: 120, height: 80),
        styleMask: .titled, backing: .buffered, defer: false
    )
    window.isReleasedWhenClosed = false
    window.preventsApplicationTerminationWhenModal = preventsTermination
    return window
}

@MainActor @Suite(.serialized) struct VexAppTerminationTests {
    @Test(arguments: [true, false])
    func restoresOriginalValueAfterRemovalAndInvalidation(original: Bool) throws {
        let window = terminationTestWindow(preventsTermination: original)
        defer { window.close() }
        let content = try #require(window.contentView)
        let binding = VexAppTerminationWindowView(frame: .zero)
        content.addSubview(binding)
        #expect(!window.preventsApplicationTerminationWhenModal)
        binding.refreshBinding()
        binding.removeFromSuperview()
        #expect(window.preventsApplicationTerminationWhenModal == original)

        content.addSubview(binding)
        #expect(!window.preventsApplicationTerminationWhenModal)
        binding.invalidate()
        #expect(window.preventsApplicationTerminationWhenModal == original)
        binding.refreshBinding()
        #expect(window.preventsApplicationTerminationWhenModal == original)
        binding.removeFromSuperview()
        #expect(window.preventsApplicationTerminationWhenModal == original)
    }

    @Test func restoresSharedWindowAfterLastBindingLeaves() throws {
        let window = terminationTestWindow()
        defer { window.close() }
        let content = try #require(window.contentView)
        let first = VexAppTerminationWindowView(frame: .zero)
        let second = VexAppTerminationWindowView(frame: .zero)
        content.addSubview(first)
        content.addSubview(second)
        #expect(!window.preventsApplicationTerminationWhenModal)
        first.removeFromSuperview()
        #expect(!window.preventsApplicationTerminationWhenModal)
        second.removeFromSuperview()
        #expect(window.preventsApplicationTerminationWhenModal)
    }

    @Test func movingBindingRestoresEachWindowIndependently() throws {
        let first = terminationTestWindow()
        let second = terminationTestWindow(preventsTermination: false)
        let unrelated = terminationTestWindow()
        defer { first.close(); second.close(); unrelated.close() }
        let binding = VexAppTerminationWindowView(frame: .zero)
        try #require(first.contentView).addSubview(binding)
        #expect(!first.preventsApplicationTerminationWhenModal)
        try #require(second.contentView).addSubview(binding)
        #expect(first.preventsApplicationTerminationWhenModal)
        #expect(!second.preventsApplicationTerminationWhenModal)
        #expect(unrelated.preventsApplicationTerminationWhenModal)
        binding.invalidate()
        #expect(!second.preventsApplicationTerminationWhenModal)
        try #require(unrelated.contentView).addSubview(binding)
        #expect(unrelated.preventsApplicationTerminationWhenModal)
        binding.removeFromSuperview()
    }

    @Test func hierarchyUpdatesPreserveTheOriginalWindowValue() throws {
        let window = terminationTestWindow()
        defer { window.close() }
        let content = try #require(window.contentView)
        let container = NSView(frame: .zero)
        content.addSubview(container)
        let binding = VexAppTerminationWindowView(frame: .zero)
        content.addSubview(binding)
        container.addSubview(binding)
        #expect(!window.preventsApplicationTerminationWhenModal)
        binding.refreshBinding()
        binding.removeFromSuperview()
        #expect(window.preventsApplicationTerminationWhenModal)
    }

    @Test func bindingDoesNotRetainReleasedWindow() throws {
        let binding = VexAppTerminationWindowView(frame: .zero)
        weak var releasedWindow: NSWindow?
        try autoreleasepool {
            let window = terminationTestWindow()
            releasedWindow = window
            try #require(window.contentView).addSubview(binding)
            #expect(!window.preventsApplicationTerminationWhenModal)
            window.close()
        }
        #expect(releasedWindow == nil)
        #expect(binding.window == nil)

        let replacement = terminationTestWindow()
        defer { replacement.close() }
        try #require(replacement.contentView).addSubview(binding)
        #expect(!replacement.preventsApplicationTerminationWhenModal)
        binding.removeFromSuperview()
        #expect(replacement.preventsApplicationTerminationWhenModal)
    }
}

// AppKit 应用激活使用 XCTest 的同步主线程宿主。
@MainActor final class VexAppTerminationTestsApplication: XCTestCase {
    private func waitForAppKit(_ condition: () -> Bool) {
        let application = NSApplication.shared
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline {
            autoreleasepool {
                if let event = application.nextEvent(
                    matching: .any,
                    until: min(deadline, Date().addingTimeInterval(0.01)),
                    inMode: .default,
                    dequeue: true
                ) {
                    application.sendEvent(event)
                }
                application.updateWindows()
            }
        }
    }

    private func recordAppKitState(_ phase: String, window: NSWindow) {
        let application = NSApplication.shared
        let running = NSRunningApplication.current
        let state: [String: Any] = [
            "recordType": "vex-appkit-window", "phase": phase,
            "pid": ProcessInfo.processInfo.processIdentifier,
            "applicationPolicy": application.activationPolicy().rawValue,
            "applicationActive": application.isActive,
            "applicationRunning": application.isRunning,
            "runningApplicationPolicy": running.activationPolicy.rawValue,
            "runningApplicationActive": running.isActive,
            "finishedLaunching": running.isFinishedLaunching,
            "windowVisible": window.isVisible,
            "windowCanBecomeKey": window.canBecomeKey,
            "windowKey": window.isKeyWindow,
            "preventsTermination": window.preventsApplicationTerminationWhenModal,
        ]
        var data = try! JSONSerialization.data(withJSONObject: state, options: .sortedKeys)
        data.append(10)
        FileHandle.standardError.write(data)
    }

    func testKeyNotificationReappliesOnlyAnActiveBinding() throws {
        let application = NSApplication.shared
        let originalPolicy = application.activationPolicy()
        let window = terminationTestWindow()
        defer {
            recordAppKitState("cleanup", window: window)
            window.orderOut(nil)
            window.close()
            XCTAssertTrue(application.setActivationPolicy(originalPolicy))
            waitForAppKit { !application.isActive && !NSRunningApplication.current.isActive }
            XCTAssertFalse(application.isActive)
            XCTAssertFalse(NSRunningApplication.current.isActive)
            recordAppKitState("restored", window: window)
        }
        let policyChanged = application.setActivationPolicy(.regular)
        XCTAssertTrue(policyChanged)
        guard policyChanged else { return }
        let binding = VexAppTerminationWindowView(frame: .zero)
        try XCTUnwrap(window.contentView).addSubview(binding)
        window.preventsApplicationTerminationWhenModal = true
        window.center()
        window.makeKeyAndOrderFront(nil)
        // SwiftPM 测试宿主需要完成 AppKit 启动并处理真实窗口事件。
        application.finishLaunching()
        recordAppKitState("shown", window: window)
        application.activate(ignoringOtherApps: true)
        waitForAppKit { application.isActive && window.isKeyWindow }
        recordAppKitState("activation", window: window)
        XCTAssertTrue(application.isActive)
        XCTAssertTrue(window.isKeyWindow)
        guard application.isActive, window.isKeyWindow else { return }
        XCTAssertFalse(window.preventsApplicationTerminationWhenModal)

        window.orderOut(nil)
        waitForAppKit { !window.isKeyWindow }
        XCTAssertFalse(window.isKeyWindow)
        guard !window.isKeyWindow else { return }
        binding.invalidate()
        XCTAssertTrue(window.preventsApplicationTerminationWhenModal)
        window.makeKeyAndOrderFront(nil)
        waitForAppKit { window.isKeyWindow }
        XCTAssertTrue(window.isKeyWindow)
        guard window.isKeyWindow else { return }
        XCTAssertTrue(window.preventsApplicationTerminationWhenModal)
        binding.removeFromSuperview()
    }
}
