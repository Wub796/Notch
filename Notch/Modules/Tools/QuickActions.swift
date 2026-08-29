import AppKit
import Foundation
import Observation

/// Small system actions worth having one click away. Everything here uses
/// public API or a scripted System Events call — nothing needs a helper
/// daemon.
@Observable
final class QuickActions {
    private(set) var isDarkMode = true
    private(set) var trashItemCount = 0

    /// Why the last action didn't work, if it didn't. These all go through
    /// AppleScript, which fails silently when the one-time Automation consent
    /// was declined — a button that does nothing and says nothing is worse
    /// than one that explains itself.
    private(set) var lastError: String?

    init() {
        refresh()
    }

    func refresh() {
        isDarkMode = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        trashItemCount = Self.countTrashItems()
    }

    // MARK: - Appearance

    /// Flips the system light/dark appearance. Requires the one-time
    /// Automation consent for System Events.
    func toggleAppearance() {
        let script = """
        tell application "System Events"
            tell appearance preferences
                set dark mode to not dark mode
            end tell
        end tell
        """
        run(script, describing: "change the appearance") { [weak self] in
            self?.refresh()
        }
        NotchTheme.Haptics.generic()
    }

    // MARK: - Session

    /// Sleeps the display immediately — the usual way people "lock" a Mac.
    func sleepDisplay() {
        NotchTheme.Haptics.generic()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["displaysleepnow"]
        try? process.run()
    }

    /// Locks the screen with the system's Control-Command-Q shortcut. That
    /// needs Accessibility consent to post a synthetic keystroke, so when it
    /// fails this falls back to sleeping the display, which locks the Mac
    /// wherever "require password after sleep" is set.
    func lockScreen() {
        NotchTheme.Haptics.generic()
        let script = """
        tell application "System Events" to keystroke "q" \
        using {control down, command down}
        """
        run(script, describing: "lock the screen", failure: { [weak self] in
            self?.sleepDisplay()
            self?.lastError = "Locking needs Accessibility access — slept the display instead."
        }, completion: nil)
    }

    // MARK: - Trash

    func emptyTrash() {
        NotchTheme.Haptics.generic()
        run("tell application \"Finder\" to empty trash", describing: "empty the Trash") { [weak self] in
            self?.refresh()
        }
    }

    private static func countTrashItems() -> Int {
        guard let trash = try? FileManager.default.url(
            for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        ) else { return 0 }
        let contents = try? FileManager.default.contentsOfDirectory(
            at: trash, includingPropertiesForKeys: nil
        )
        return contents?.count ?? 0
    }

    // MARK: - Helpers

    private func run(
        _ source: String,
        describing action: String,
        failure: (() -> Void)? = nil,
        completion: (() -> Void)?
    ) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            let failed = error != nil
            DispatchQueue.main.async {
                if failed {
                    if let failure {
                        failure()
                    } else {
                        self?.lastError = "Couldn't \(action). Allow Notch under "
                            + "Privacy & Security → Automation."
                    }
                } else {
                    self?.lastError = nil
                    completion?()
                }
            }
        }
    }
}
