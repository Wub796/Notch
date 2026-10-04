#if DEBUG
import AppKit
import SwiftUI

/// In-process input reaches the actual SwiftUI editor/buttons without asking
/// for cross-app Accessibility access. Notes use an isolated defaults suite.
@MainActor
enum WorkflowCheck {
    static func run(state: NotchState, reportURL: URL?) {
        let suite = "NotchNativeWorkflowCheck-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { return }
        let notes = NotesManager(defaults: defaults)
        let savedTab = state.settings.lastTab
        let savedVolume = state.settings.volumeHUDEnabled
        let savedCapacity = state.settings.clipboardMaxCapacity
        let previousVolumeCallback = state.settings.onVolumeHUDSettingChanged
        let previousCapacityCallback = state.settings.onClipboardCapacityChanged
        var volumeChanges: [Bool] = []
        var capacityChanges: [Int] = []
        var checks: [(String, Bool)] = []
        state.settings.onVolumeHUDSettingChanged = { enabled in
            volumeChanges.append(enabled)
            previousVolumeCallback?(enabled)
        }
        state.settings.onClipboardCapacityChanged = { capacity in
            capacityChanges.append(capacity)
            previousCapacityCallback?(capacity)
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 265),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        let hosting = NSHostingView(rootView: NotesView(state: state, notes: notes))
        hosting.sizingOptions = []
        window.contentView = hosting
        window.setContentSize(NSSize(width: 580, height: 265))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let editor = editor(in: hosting) {
                window.makeFirstResponder(editor)
                editor.insertText("Native scratchpad check", replacementRange: NSRange(location: 0, length: 0))
                checks.append(("notes.editor-input", notes.text == "Native scratchpad check"))
                checks.append(("notes.pending-save", notes.hasUnsavedChanges))
            } else {
                checks.append(("notes.editor-found", false))
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                // The right-most header control is Clear, at the actual fixed
                // Notes surface size. A real mouse event exercises SwiftUI.
                click(window: window, point: NSPoint(x: 548, y: 242))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    checks.append(("notes.clear-button", notes.text.isEmpty && notes.canUndoClear))
                    checks.append(("notes.clear-persisted", defaults.string(forKey: "scratchpadText") == ""))
                    click(window: window, point: NSPoint(x: 448, y: 242))
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        checks.append(("notes.undo-button", notes.text == "Native scratchpad check" && !notes.canUndoClear))
                        checks.append(("notes.undo-persisted", defaults.string(forKey: "scratchpadText") == notes.text))
                        if let editor = editor(in: hosting) {
                            editor.insertText(" before closing", replacementRange: NSRange(location: notes.text.utf16.count, length: 0))
                        }
                        // Replacing the native surface triggers its actual
                        // onDisappear flush before the debounce can finish.
                        window.contentView = NSView(frame: hosting.frame)
                        checks.append(("notes.leave-flush", defaults.string(forKey: "scratchpadText") == "Native scratchpad check before closing"))
                        state.settings.volumeHUDEnabled = !savedVolume
                        state.settings.volumeHUDEnabled = savedVolume
                        checks.append(("settings.volume-immediate", volumeChanges == [!savedVolume, savedVolume]))
                        state.settings.clipboardMaxCapacity = 0
                        checks.append(("settings.capacity-clamped", state.settings.clipboardMaxCapacity == 1 && capacityChanges.last == 1))
                        state.settings.clipboardMaxCapacity = savedCapacity
                        state.settings.onVolumeHUDSettingChanged = previousVolumeCallback
                        state.settings.onClipboardCapacityChanged = previousCapacityCallback
                        state.settings.lastTab = savedTab
                        notes.flush()
                        window.close()
                        defaults.removePersistentDomain(forName: suite)
                        let report = checks.map { "\($0.0)=\($0.1)" }.joined(separator: "\n")
                            + "\nchecks.passed=\(checks.allSatisfy { $0.1 })\n"
                        print(report)
                        if let reportURL {
                            do { try report.write(to: reportURL, atomically: true, encoding: .utf8) }
                            catch { print("Workflow report failed: \(error)") }
                        }
                        NSApp.terminate(nil)
                    }
                }
            }
        }
    }

    private static func editor(in view: NSView) -> NSTextView? {
        if let text = view as? NSTextView, !text.isFieldEditor { return text }
        for child in view.subviews {
            if let editor = editor(in: child) { return editor }
        }
        return nil
    }

    private static func click(window: NSWindow, point: NSPoint) {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0
            ) else { continue }
            window.sendEvent(event)
        }
    }
}
#endif
