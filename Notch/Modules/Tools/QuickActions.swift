import AppKit
import Foundation
import Observation

/// Small system actions worth having one click away. Everything here uses
/// public API or a scripted System Events call — nothing needs a helper
/// daemon.
@Observable
final class QuickActions {
    private(set) var isDarkMode = true
    /// How many items are in the Trash, or nil when that cannot be read.
    private(set) var trashItemCount: Int?

    /// Why the last action didn't work, if it didn't. These all go through
    /// AppleScript, which fails silently when the one-time Automation consent
    /// was declined — a button that does nothing and says nothing is worse
    /// than one that explains itself.
    private(set) var lastError: String?

    @ObservationIgnored private var themeObserver: NSObjectProtocol?

    init() {
        refresh()
        // Keeps the appearance button honest when the theme changes anywhere
        // else — Control Center, System Settings, an automatic schedule. It
        // used to notice only the next time the Tools screen appeared.
        themeObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit {
        if let themeObserver {
            DistributedNotificationCenter.default().removeObserver(themeObserver)
        }
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
        run(script, describing: "change the appearance", completion: { [weak self] in
            self?.refresh()
        })
    }

    // MARK: - Session

    /// Sleeps the display immediately — the usual way people "lock" a Mac.
    func sleepDisplay() {
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
        let script = """
        tell application "System Events" to keystroke "q" \
        using {control down, command down}
        """
        run(script, describing: "lock the screen", failure: { [weak self] in
            self?.sleepDisplay()
            self?.lastError = "Locking needs Accessibility access — slept the display instead."
        })
    }

    // MARK: - Trash

    func emptyTrash() {
        run(
            "tell application \"Finder\" to empty trash",
            describing: "empty the Trash",
            completion: { [weak self] in self?.refresh() }
        )
    }

    /// How many items are in the Trash, or nil when it cannot be read.
    ///
    /// `url(for: .trashDirectory,)` throws with `appropriateFor: nil` on some
    /// systems, so the home directory path is the fallback, and
    /// `.skipsHiddenFiles` keeps the Finder's .DS_Store from counting as an
    /// item. Unreadable is not empty: without Full Disk Access both paths
    /// throw, and reporting that as zero disabled the button as "Trash Empty"
    /// however full the Trash was. Emptying goes through the Finder, which
    /// needs no such access, so an unknown count keeps the button live.
    private static func countTrashItems() -> Int? {
        let manager = FileManager.default
        let candidates = [
            try? manager.url(
                for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false
            ),
            manager.homeDirectoryForCurrentUser.appendingPathComponent(".Trash"),
        ].compactMap { $0 }

        for trash in candidates {
            guard let contents = try? manager.contentsOfDirectory(
                at: trash,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }
            return contents.count
        }
        return nil
    }

    // MARK: - Helpers

    private func run(
        _ source: String,
        describing action: String,
        failure: (() -> Void)? = nil,
        completion: (() -> Void)? = nil
    ) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            let failed = error != nil
            DispatchQueue.main.async { [weak self] in
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
