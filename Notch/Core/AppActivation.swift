import AppKit
import ApplicationServices

/// Bringing another app forward — properly.
///
/// `NSRunningApplication.activate()` raises the *process*, which is only half
/// of what a click on an album cover means. A window the user minimized stays
/// in the Dock, and an app whose window was closed just gets its menu bar and
/// nothing else; both read as a cover that does nothing. This does the same
/// three things a Dock click does:
///
///   1. unhide and activate, for an app that is hidden or behind others;
///   2. lift any miniaturized window out of the Dock through the Accessibility
///      API — the same trust the HUD's media-key tap already asks for, and the
///      only way another process can see a window that is in the Dock;
///   3. when there is no window at all, send the reopen event a Dock click
///      sends, so the player puts its main window back up.
enum AppActivation {

    /// Raises the app with this bundle identifier, launching it if it is not
    /// running at all.
    static func bringForward(bundleID: String) {
        guard !bundleID.isEmpty else { return }
        guard let running = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID).first
        else {
            open(bundleID)
            return
        }
        bringForward(running)
    }

    /// The same, for a caller that knows the process rather than the bundle.
    static func bringForward(pid: pid_t) {
        guard let running = NSRunningApplication(processIdentifier: pid) else { return }
        bringForward(running)
    }

    private static func bringForward(_ running: NSRunningApplication) {
        if running.isHidden { running.unhide() }
        running.activate()

        let pid = running.processIdentifier
        let bundleID = running.bundleIdentifier ?? ""

        // Off the main thread: every Accessibility call is a synchronous round
        // trip to the other app, and this one runs on a click.
        DispatchQueue.global(qos: .userInitiated).async {
            guard !raiseWindows(of: pid) else { return }
            // Nothing was there to raise. Either the window was closed, or
            // Accessibility is not granted and this cannot tell — and in both
            // cases the reopen is the only path back. It is what a Dock click
            // sends, so an app with a window already up simply shows it again.
            guard !bundleID.isEmpty else { return }
            DispatchQueue.main.async { open(bundleID) }
        }
    }

    /// Lifts every miniaturized window of `pid` out of the Dock, and answers
    /// whether the app had a window to lift at all.
    ///
    /// The answer is what separates the two broken cases: a window sitting in
    /// the Dock only needs deminiaturizing, while an app whose window was
    /// closed has none to raise and needs the reopen instead. Without
    /// Accessibility trust no window is visible from here, so the answer is
    /// `false` — which is the safe direction, because the reopen also works
    /// for a window that was merely minimized.
    private static func raiseWindows(of pid: pid_t) -> Bool {
        guard AXIsProcessTrusted() else { return false }

        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            app, kAXWindowsAttribute as CFString, &value
        ) == .success,
            let windows = value as? [AXUIElement],
            !windows.isEmpty
        else { return false }

        for window in windows {
            var minimized: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                window, kAXMinimizedAttribute as CFString, &minimized
            ) == .success, isTrue(minimized) else { continue }
            AXUIElementSetAttributeValue(
                window, kAXMinimizedAttribute as CFString, kCFBooleanFalse
            )
        }
        return true
    }

    /// `kAXMinimizedAttribute` answers with a `CFBoolean`, which arrives as an
    /// `NSNumber` through Swift — reading it as `Bool` directly is not reliable.
    private static func isTrue(_ value: CFTypeRef?) -> Bool {
        (value as? NSNumber)?.boolValue ?? false
    }

    /// Launches the app, or — for one that is already running — sends the
    /// reopen event a Dock click sends. Both end with its main window up.
    private static func open(_ bundleID: String) {
        guard let url = NSWorkspace.shared
            .urlForApplication(withBundleIdentifier: bundleID) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }
}
