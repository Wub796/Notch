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
        run(script) { [weak self] in
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

    /// Locks the screen via the Keychain menu's lock command.
    func lockScreen() {
        NotchTheme.Haptics.generic()
        let script = """
        tell application "System Events" to keystroke "q" \
        using {control down, command down}
        """
        run(script, completion: nil)
    }

    // MARK: - Trash

    func emptyTrash() {
        NotchTheme.Haptics.generic()
        run("tell application \"Finder\" to empty trash") { [weak self] in
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

    private func run(_ source: String, completion: (() -> Void)?) {
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            if let completion {
                DispatchQueue.main.async(execute: completion)
            }
        }
    }
}
