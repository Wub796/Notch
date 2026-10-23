import AppKit

/// Keeps the app's own windows out of screen recordings and screen shares.
///
/// `sharingType = .none` is the one public switch for this: the window server
/// stops offering the window's contents to capture clients that ask per
/// window — QuickTime, the screenshot service, most call recorders. A capture
/// that asks for the whole display instead is a different path and is not
/// covered, which is the half of this feature worth stating plainly rather
/// than promising.
///
/// Applied by whoever owns the window, not by an observer in the settings
/// model: the notch panel is rebuilt when a display changes, and a new window
/// has to be told too. Every entry point calls this again.
enum ScreenCapturePrivacy {
    static func apply() {
        let wanted: NSWindow.SharingType =
            NotchSettings.shared.hideFromScreenCapture ? .none : .readOnly

        for window in NSApp.windows where window.sharingType != wanted {
            window.sharingType = wanted
        }
    }
}
