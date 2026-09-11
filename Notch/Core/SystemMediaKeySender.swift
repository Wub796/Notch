import AppKit
import ApplicationServices

/// Sends system-wide hardware media key events (Play/Pause, Next, Previous) to macOS.
/// This allows direct pause/play control for any video or audio playing on the Mac,
/// including YouTube, Netflix, Chrome, Safari, Arc, Firefox, Spotify, Apple Music, VLC, IINA, etc.
enum SystemMediaKeySender {
    static let NX_KEYTYPE_PLAY: Int32 = 16
    static let NX_KEYTYPE_NEXT: Int32 = 17
    static let NX_KEYTYPE_PREVIOUS: Int32 = 18
    static let NX_KEYTYPE_FAST: Int32 = 19
    static let NX_KEYTYPE_REWIND: Int32 = 20

    static func togglePlayPause() {
        sendMediaKey(NX_KEYTYPE_PLAY)
    }

    static func nextTrack() {
        sendMediaKey(NX_KEYTYPE_NEXT)
    }

    static func previousTrack() {
        sendMediaKey(NX_KEYTYPE_PREVIOUS)
    }

    /// `NX_KEYDOWN` / `NX_KEYUP` from IOKit's `ev_keymap.h`. A system-defined
    /// media-key event carries one of these in the modifier-flags field *and*
    /// in the low word of `data1` — naming them beats the bare hex pair that
    /// these snippets usually ship with.
    private static let keyDownFlag: Int32 = 0xa00
    private static let keyUpFlag: Int32 = 0xb00

    private static func sendMediaKey(_ key: Int32) {
        func postKey(down: Bool) {
            let flag = down ? keyDownFlag : keyUpFlag
            let flags = NSEvent.ModifierFlags(rawValue: UInt(flag))
            let data1 = Int((key << 16) | flag)
            let ev = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: flags,
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: -1
            )
            // Posted once, at the HID level, from which it flows up through
            // the session taps on its own. Posting to all three delivered the
            // same key three times: play/pause toggled back and Next skipped
            // two or three tracks.
            ev?.cgEvent?.post(tap: .cghidEventTap)
        }

        postKey(down: true)
        postKey(down: false)
    }
}
