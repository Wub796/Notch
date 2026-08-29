import AppKit
import ApplicationServices
import Foundation

/// Intercepts the volume and brightness keys so the notch can show its own HUD
/// instead of the system's.
///
/// Ported from boring.notch's `MediaKeyInterceptor`. macOS delivers these as
/// `systemDefined` events (CGEventType 14, NSEvent subtype 8) carrying the key
/// in the high half of `data1`; a tap at `.cghidEventTap` sees them before
/// WindowServer raises its own overlay. Swallowing the event (returning nil)
/// and applying the change ourselves is what replaces the system HUD rather
/// than drawing a second one beside it.
///
/// This needs Accessibility access — an event tap always does — so it is
/// opt-in, and everything degrades to the system HUD when it is off or the
/// permission is missing.
@MainActor
final class MediaKeyInterceptor {
    static let shared = MediaKeyInterceptor()

    /// The `NX_KEYTYPE_*` constants the tap acts on.
    private enum KeyType: Int {
        case soundUp = 0
        case soundDown = 1
        case brightnessUp = 2
        case brightnessDown = 3
        case mute = 7
    }

    /// macOS's own increment: sixteen steps across the range. Option-Shift
    /// quarters it, as in the reference and in macOS itself.
    private static let step: Float = 1.0 / 16.0

    private static let systemDefinedEventType = CGEventType(rawValue: 14)!

    /// Called with the new value so the notch can raise its HUD.
    var onVolume: ((Float, Bool) -> Void)?
    var onBrightness: ((Float) -> Void)?

    /// Reads and writes the actual system values.
    var volumeSource: (() -> Float)?
    var setVolume: ((Float) -> Void)?
    var isMuted: (() -> Bool)?
    var toggleMute: (() -> Void)?
    var brightnessSource: (() -> Float)?
    var setBrightness: ((Float) -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private init() {}

    var isRunning: Bool { eventTap != nil }

    /// Whether macOS has granted this app Accessibility access.
    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Opens the Accessibility prompt. macOS only shows it once per app
    /// binary, so a denied user has to be sent to System Settings instead.
    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }
        guard NotchSettings.shared.hudReplacement, Self.isAccessibilityTrusted else {
            return false
        }

        let mask = CGEventMask(1 << Self.systemDefinedEventType.rawValue)
        let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, _, event, context in
                guard let context else { return Unmanaged.passRetained(event) }
                let interceptor = Unmanaged<MediaKeyInterceptor>
                    .fromOpaque(context)
                    .takeUnretainedValue()
                return interceptor.handle(event)
            },
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )

        guard let tap else { return false }
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        eventTap = nil
    }

    // MARK: - Event handling

    /// Runs on the event-tap thread, so every action is hopped to the main
    /// actor. Returns nil to swallow a key we handled, or the event untouched
    /// for anything else.
    private nonisolated func handle(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        // A disabled tap (timeout, or user input while it was blocked) has to
        // be re-armed or the keys stop working entirely.
        if event.type == .tapDisabledByTimeout || event.type == .tapDisabledByUserInput {
            Task { @MainActor in MediaKeyInterceptor.shared.reenable() }
            return Unmanaged.passRetained(event)
        }

        guard event.type != .null,
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.type == .systemDefined,
              nsEvent.subtype.rawValue == 8
        else { return Unmanaged.passRetained(event) }

        let data1 = nsEvent.data1
        let keyCode = (data1 & 0xFFFF_0000) >> 16
        // 0xA is key-down, 0xB key-up; only the press acts.
        let state = (data1 & 0xFF00) >> 8

        guard state == 0xA, let key = KeyType(rawValue: keyCode) else {
            return Unmanaged.passRetained(event)
        }

        let flags = nsEvent.modifierFlags
        // Option alone opens the relevant System Settings pane, as macOS does;
        // leave that to the system rather than swallowing it.
        guard !(flags.contains(.option) && !flags.contains(.shift)) else {
            return Unmanaged.passRetained(event)
        }
        let fineStep = flags.contains(.option) && flags.contains(.shift)

        Task { @MainActor in
            MediaKeyInterceptor.shared.apply(key: key, fineStep: fineStep)
        }
        return nil
    }

    private func reenable() {
        guard let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private func apply(key: KeyType, fineStep: Bool) {
        let delta = Self.step / (fineStep ? 4 : 1)

        switch key {
        case .soundUp, .soundDown:
            let current = volumeSource?() ?? 0
            let target = min(max(current + (key == .soundUp ? delta : -delta), 0), 1)
            setVolume?(target)
            onVolume?(target, isMuted?() ?? false)

        case .mute:
            toggleMute?()
            let muted = isMuted?() ?? false
            onVolume?(muted ? 0 : (volumeSource?() ?? 0), muted)

        case .brightnessUp, .brightnessDown:
            let current = brightnessSource?() ?? 0
            let target = min(max(current + (key == .brightnessUp ? delta : -delta), 0), 1)
            setBrightness?(target)
            onBrightness?(target)
        }
    }
}
