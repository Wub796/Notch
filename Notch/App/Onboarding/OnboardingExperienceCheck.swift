#if DEBUG
import AppKit
import SwiftUI

@MainActor
enum OnboardingExperienceCheck {
    static func run(state: NotchState, reportURL: URL?) {
        let savedTab = state.settings.lastTab
        let savedMode = state.mode
        let savedPin = state.isPinned
        var checks: [(String, Bool)] = []
        var didFinish = false
        var observedStep: OnboardingStep?
        var observedSteps: [OnboardingStep] = []
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 620),
            styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false
        )
        window.titleVisibility = .hidden
        var flow = OnboardingView(state: state) { didFinish = true }
        flow.onStepObserved = { observedStep = $0; observedSteps.append($0) }
        let hosting = NSHostingView(rootView: flow)
        hosting.frame = NSRect(x: 0, y: 0, width: 460, height: 620)
        hosting.sizingOptions = []
        window.contentView = hosting
        window.setContentSize(NSSize(width: 460, height: 620))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.7))
            checks.append(("onboarding.welcome-visible", observedStep == .welcome))
            capture(hosting, named: "welcome", reportURL: reportURL)
            // Continue twice in one turn: only the first event may advance.
            click(window, NSPoint(x: 250, y: 42))
            click(window, NSPoint(x: 250, y: 42))
            try? await Task.sleep(for: .seconds(0.45))
            checks.append(("onboarding.double-click-single-step", observedStep == .ask(.calendar)))
            checks.append(("onboarding.single-navigation", observedSteps == [.welcome, .ask(.calendar)]))
            checks.append(("onboarding.no-accidental-request", !IntegrationPermissions.shared.pending.contains(.calendar)))
            capture(hosting, named: "permission", reportURL: reportURL)
            click(window, NSPoint(x: 39, y: 97))
            try? await Task.sleep(for: .seconds(0.45))
            checks.append(("onboarding.back", observedStep == .welcome))
            click(window, NSPoint(x: 250, y: 42))
            try? await Task.sleep(for: .seconds(0.45))
            // Skip all remaining asks; never raise a real system prompt.
            if let skip = NSEvent.keyEvent(with: .keyDown, location: .zero,
                                           modifierFlags: [.command, .shift],
                                           timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: window.windowNumber, context: nil,
                                           characters: "S", charactersIgnoringModifiers: "s",
                                           isARepeat: false, keyCode: 1) {
                _ = window.performKeyEquivalent(with: skip)
            }
            try? await Task.sleep(for: .seconds(0.5))
            checks.append(("onboarding.skip-rest", observedStep == .ready))
            capture(hosting, named: "ready", reportURL: reportURL)
            click(window, NSPoint(x: 250, y: 42))
            try? await Task.sleep(for: .seconds(0.4))
            checks.append(("onboarding.finish", didFinish))
            window.close()

            state.collapse()
            state.tab = .home
            state.hoverChanged(true)
            state.handleTap() // Fast explicit click is never discarded as hover.
            try? await Task.sleep(for: .seconds(0.12))
            checks.append(("notch.click-pins", state.mode == .expanded && state.isPinned))
            state.hoverChanged(false)
            try? await Task.sleep(for: .seconds(0.8))
            checks.append(("notch.pin-survives-pointer-exit", state.mode == .expanded && state.isPinned))
            state.showToast("First", symbol: "checkmark")
            let first = state.toast?.id
            state.showToast("Second", symbol: "checkmark")
            checks.append(("notch.feedback-replaced", first != state.toast?.id && state.toast?.message == "Second"))
            // Real Escape event is delivered to the native panel's responder chain.
            let panel = NotchPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200), state: state)
            panel.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
            panel.makeKeyAndOrderFront(nil)
            if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                           timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: panel.windowNumber, context: nil,
                                           characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                                           isARepeat: false, keyCode: 53) {
                panel.sendEvent(event)
            }
            try? await Task.sleep(for: .seconds(0.1))
            checks.append(("notch.escape-closes", state.mode == .collapsed && !state.isPinned))
            checks.append(("notch.close-clears-feedback", state.toast == nil))
            panel.close()
            state.settings.lastTab = savedTab
            state.tab = NotchTab(rawValue: savedTab) ?? .home
            if savedMode == .expanded { state.expand() }
            state.isPinned = savedPin
            let report = checks.map { "\($0.0)=\($0.1)" }.joined(separator: "\n")
                + "\nreduce-motion=\(NotchAnimations.prefersReducedMotion)\n"
                + "checks.passed=\(checks.allSatisfy { $0.1 })\n"
            print(report)
            if let reportURL {
                do { try report.write(to: reportURL, atomically: true, encoding: .utf8) }
                catch { print("Experience report failed: \(error)") }
            }
            NSApp.terminate(nil)
        }
    }

    private static func capture(_ view: NSView, named name: String, reportURL: URL?) {
        guard CommandLine.arguments.contains("--debug-experience-capture"), let reportURL else { return }
        let folder = reportURL.deletingPathExtension().appendingPathExtension("images")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
            try png.write(to: folder.appendingPathComponent(name + ".png"))
        } catch { print("Experience capture failed: \(error)") }
    }

    private static func click(_ window: NSWindow, _ point: NSPoint) {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                                timestamp: ProcessInfo.processInfo.systemUptime,
                                                windowNumber: window.windowNumber, context: nil,
                                                eventNumber: 0, clickCount: 1,
                                                pressure: type == .leftMouseDown ? 1 : 0) else { continue }
            window.sendEvent(event)
        }
    }

}
#endif
