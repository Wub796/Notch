import Sparkle

/// Owns Sparkle's updater for the agent application.
///
/// Keeping the controller alive for the lifetime of the process is required by
/// Sparkle; the standard controller also handles automatic checks and the
/// update UI. The feed URL and update policy live in Info.plist so release
/// tooling can change them without changing Swift code.
final class UpdateController {
    static let shared = UpdateController()

    private let updaterController: SPUStandardUpdaterController

    /// Held strongly because Sparkle references the user driver's delegate
    /// weakly, and a freshly built one would be released before the first
    /// scheduled check ever consulted it. See `UpdateReminderDelegate`.
    private let reminderDelegate = UpdateReminderDelegate()

    private init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: reminderDelegate
        )
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}

/// The standard user driver's gentle-reminder support.
///
/// Sparkle logs a warning at launch for a background app that schedules its own
/// update checks without declaring this: the alert a scheduled check raises then
/// arrives behind everything else, where the user of a menu-bar app never meets
/// it. The declaration is the whole fix — Sparkle's condition is exactly this
/// one property — and leaving the presenting to the standard driver is right for
/// an app with no dock badge to carry a quieter reminder.
final class UpdateReminderDelegate: NSObject, SPUStandardUserDriverDelegate {
    /// True: the app has considered reminders and supports them. Without it,
    /// Sparkle warns once per launch, as it did here.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Says out loud what the property above implies — the standard driver shows
    /// the update. Returning false would move that responsibility onto this
    /// class, which has no UI of its own to show anything with.
    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        true
    }
}
