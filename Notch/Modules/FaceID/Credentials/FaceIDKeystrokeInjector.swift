import ApplicationServices
import CoreGraphics
import Foundation

/// Types a password into whatever holds keyboard focus, through synthesized
/// keystrokes posted at the HID tap so they reach the lock screen's secure
/// text field.
///
/// Ported from Glance (`KeystrokeInjector.swift`, MIT © Jonathan Zhou). Every
/// ordering detail in here is a fix for something observed on a real lock
/// screen, which is why it looks fussier than "post the characters":
///
/// - The focused field is cleared first, so a stray keypress on the lock screen
///   isn't prepended to the password.
/// - Clearing uses positional keys (⌘→, ⌘⌫) rather than ⌘A, whose "A" moves
///   with the keyboard layout.
/// - Every character goes through `keyboardSetUnicodeString`, so the password
///   types correctly on layouts that have no key for it.
enum FaceIDKeystrokeInjector {
    enum KeystrokeError: LocalizedError {
        case accessibilityNotGranted
        case eventCreationFailed

        var errorDescription: String? {
            switch self {
            case .accessibilityNotGranted:
                "Accessibility permission is required to type the password. Open System Settings → "
                    + "Privacy & Security → Accessibility and enable Notch."
            case .eventCreationFailed:
                "Couldn't create the keyboard event for that keystroke."
            }
        }
    }

    /// Every synthesized event is a real key press, so the pauses between them
    /// are not politeness: the login window drops events that arrive in the
    /// same runloop turn, and a dropped character in a password is a failed
    /// unlock with no visible cause.
    private static let interKeyDelay: TimeInterval = 0.012

    /// True if the app has Accessibility permission. Never prompts.
    static func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Asks the system to show its Accessibility prompt, deep-linking to the
    /// right pane of System Settings.
    @discardableResult
    static func promptForAccessibility() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        let options = [promptKey: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Types the UTF-8 bytes into the focused field, then presses Return.
    ///
    /// Takes `Data` rather than `String` so the caller can hold the plaintext
    /// as a zero-able buffer; the decoded `String` lives only inside this call.
    /// Blocking.
    static func typeAndReturn(_ passwordBytes: Data) throws {
        guard isAccessibilityTrusted() else {
            throw KeystrokeError.accessibilityNotGranted
        }
        guard let text = String(data: passwordBytes, encoding: .utf8) else {
            throw KeystrokeError.eventCreationFailed
        }
        let source = CGEventSource(stateID: .hidSystemState)
        try clearFocusedField(source: source)
        for character in text {
            try postUnicode(String(character), source: source)
        }
        try postReturn(source: source)
    }

    /// ⌘→ to the end of whatever is already typed, then ⌘⌫ to delete back to
    /// the start.
    private static func clearFocusedField(source: CGEventSource?) throws {
        let rightArrow: CGKeyCode = 0x7C
        let delete: CGKeyCode = 0x33
        try postKey(rightArrow, flags: .maskCommand, source: source)
        try postKey(delete, flags: .maskCommand, source: source)
    }

    /// Posts a virtual key down and up, wrapped in a real ⌘ down and up when
    /// `flags` includes `.maskCommand` — some text fields ignore the bare flag
    /// without the accompanying key.
    private static func postKey(
        _ keyCode: CGKeyCode,
        flags: CGEventFlags = [],
        source: CGEventSource?
    ) throws {
        let command: CGKeyCode = 0x37
        let usesCommand = flags.contains(.maskCommand)
        if usesCommand {
            guard let commandDown = CGEvent(keyboardEventSource: source, virtualKey: command, keyDown: true) else {
                throw KeystrokeError.eventCreationFailed
            }
            commandDown.flags = .maskCommand
            commandDown.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: interKeyDelay)
        }
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else {
            throw KeystrokeError.eventCreationFailed
        }
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: interKeyDelay)
        keyUp.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: interKeyDelay)
        if usesCommand {
            guard let commandUp = CGEvent(keyboardEventSource: source, virtualKey: command, keyDown: false) else {
                throw KeystrokeError.eventCreationFailed
            }
            commandUp.flags = []
            commandUp.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: interKeyDelay)
        }
    }

    /// Per-character Unicode injection, which sidesteps the keyboard layout.
    private static func postUnicode(_ unicode: String, source: CGEventSource?) throws {
        let utf16 = Array(unicode.utf16)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        else {
            throw KeystrokeError.eventCreationFailed
        }
        utf16.withUnsafeBufferPointer { buffer in
            if let base = buffer.baseAddress {
                keyDown.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: base)
                keyUp.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: base)
            }
        }
        keyDown.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: interKeyDelay)
        keyUp.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: interKeyDelay)
    }

    /// The physical Return key (virtual key 0x24).
    private static func postReturn(source: CGEventSource?) throws {
        let returnKey: CGKeyCode = 0x24
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: returnKey, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: returnKey, keyDown: false)
        else {
            throw KeystrokeError.eventCreationFailed
        }
        keyDown.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: interKeyDelay)
        keyUp.post(tap: .cghidEventTap)
    }
}
