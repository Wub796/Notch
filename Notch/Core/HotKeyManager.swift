import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A single system-wide hotkey for toggling the notch.
///
/// Carbon's `RegisterEventHotKey` is used deliberately: unlike an
/// `NSEvent` global key monitor it needs no Accessibility permission, and it
/// keeps working while other apps are focused.
final class HotKeyManager {
    static let shared = HotKeyManager()

    /// The shortcuts offered in Settings. Keeping this a fixed list avoids
    /// shipping a full shortcut recorder while still letting people avoid a
    /// clash with something they already use.
    enum Shortcut: String, CaseIterable, Identifiable {
        case disabled
        case optionCommandN
        case controlOptionN
        case commandShiftBackslash
        case f13

        var id: String { rawValue }

        var title: String {
            switch self {
            case .disabled: "Off"
            case .optionCommandN: "⌥⌘N"
            case .controlOptionN: "⌃⌥N"
            case .commandShiftBackslash: "⇧⌘\\"
            case .f13: "F13"
            }
        }

        var keyCode: UInt32? {
            switch self {
            case .disabled: nil
            case .optionCommandN, .controlOptionN: UInt32(kVK_ANSI_N)
            case .commandShiftBackslash: UInt32(kVK_ANSI_Backslash)
            case .f13: UInt32(kVK_F13)
            }
        }

        var modifiers: UInt32 {
            switch self {
            case .disabled: 0
            case .optionCommandN: UInt32(optionKey | cmdKey)
            case .controlOptionN: UInt32(controlKey | optionKey)
            case .commandShiftBackslash: UInt32(shiftKey | cmdKey)
            case .f13: 0
            }
        }

        /// The same shortcut expressed for SwiftUI, so the menu bar item can
        /// advertise whatever the user actually chose. The menu used to
        /// hardcode ⌥⌘N and went on claiming it after the shortcut changed.
        /// nil where the shortcut cannot be expressed as a menu equivalent:
        /// Off, and F13, which `KeyEquivalent` has no case for. The menu item
        /// then carries no keys, which is honest — better than advertising a
        /// shortcut the menu cannot actually invoke.
        var menuKey: KeyEquivalent? {
            switch self {
            case .disabled, .f13: nil
            case .optionCommandN, .controlOptionN: "n"
            case .commandShiftBackslash: "\\"
            }
        }

        // Fully qualified: Carbon declares an `EventModifiers` of its own, and
        // this file imports both.
        var menuModifiers: SwiftUI.EventModifiers {
            switch self {
            case .disabled, .f13: []
            case .optionCommandN: [.command, .option]
            case .controlOptionN: [.control, .option]
            case .commandShiftBackslash: [.command, .shift]
            }
        }
    }

    /// Invoked on the main queue when the shortcut fires.
    var onTrigger: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private static let signature = OSType(0x4E4F5443) // 'NOTC'

    private init() {}

    func apply(_ shortcut: Shortcut) {
        unregister()
        guard let keyCode = shortcut.keyCode else { return }
        installHandlerIfNeeded()

        var reference: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(
            keyCode,
            shortcut.modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        // A clash with an existing system shortcut just leaves it unbound;
        // the app carries on without one.
        guard status == noErr else { return }
        hotKeyRef = reference
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let context = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context in
                guard let context, let event else { return OSStatus(eventNotHandledErr) }

                var identifier = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &identifier
                )
                guard status == noErr, identifier.signature == HotKeyManager.signature else {
                    return OSStatus(eventNotHandledErr)
                }

                let manager = Unmanaged<HotKeyManager>.fromOpaque(context)
                    .takeUnretainedValue()
                DispatchQueue.main.async {
                    manager.onTrigger?()
                }
                return noErr
            },
            1,
            &spec,
            context,
            &eventHandler
        )
    }

    private func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
    }
}
