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
///
/// Three things are deliberately not in this file. The tap runs on its own
/// thread (see `EventTapHost`), because a callback served from the main run
/// loop is disabled by the system whenever this app is busy — which is the
/// normal state of the app this lives in — and a disabled tap hands the keys
/// back to the system HUD. The decision about a tap in each state is
/// `MediaKeyTapPolicy`, a pure function, because a real tap cannot be disabled
/// on demand and that decision is the whole of the recovery logic. What is left
/// here is the gate, the health check that acts on the decision, and the keys
/// themselves.
///
/// Not actor-isolated, matching `HotKeyManager`: both are singletons whose
/// public surface is driven from the main thread and whose C callback arrives
/// on a tap thread and hops to main explicitly. Marking it `@MainActor` makes
/// every call from `NotchState` — which is a plain observable class — an
/// isolation error.
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

    /// How often the tap's health is checked while HUD replacement is on. One
    /// local `tapIsEnabled` call — no polling of anything outside this process
    /// — and the only thing that notices a tap the system switched off without
    /// telling us.
    ///
    /// Five seconds rather than fifteen: while the tap is off, macOS draws its
    /// own volume and brightness overlay, so the gap is exactly as long as the
    /// notch is liable to draw a second one beside it. The check is a single
    /// boolean read of a local port, so the cost of asking more often is nil.
    private static let healthInterval: TimeInterval = 5

    /// Called with the new value so the notch can raise its HUD.
    var onVolume: ((Float, Bool) -> Void)?
    var onBrightness: ((Float) -> Void)?

    /// True while a volume or brightness key press is ours: HUD replacement is
    /// wanted, Accessibility is granted, and the system still has the tap
    /// enabled.
    ///
    /// The honest answer to "who is drawing the level overlay right now". When
    /// it is false the key press reached macOS, which raised its own HUD — and
    /// the notch must not raise a second one from the CoreAudio listener that
    /// sees the same change.
    var isIntercepting: Bool {
        NotchSettings.shared.hudReplacement && Self.isAccessibilityTrusted && host.isEnabled
    }

    /// Reads and writes the actual system values.
    var volumeSource: (() -> Float)?
    var setVolume: ((Float) -> Void)?
    var isMuted: (() -> Bool)?
    var toggleMute: (() -> Void)?
    var brightnessSource: (() -> Float)?
    /// Writes brightness and returns the level actually stored (the clamped
    /// value the reader should display), so a key press can show where the
    /// bar is without re-reading the panel — which used to surface a stale
    /// brighter display value as a "bounce back" to ~43%.
    var setBrightness: ((Float) -> Float)?

    private let host: EventTapHost

    /// The health check. Main thread only — a `Timer` scheduled there — and
    /// alive for exactly as long as HUD replacement is wanted.
    private var watchdog: Timer?
    /// Whether a re-arm has already been tried for the tap in hand. Main thread
    /// only, like the watchdog: the tap thread never takes this decision.
    private var rearmAttempted = false

    private init() {
        // The handler reaches `shared` rather than capturing `self`: this runs
        // while that very static is being initialized, and the reference is
        // only read when an event arrives, long after it is done.
        host = EventTapHost { event in
            MediaKeyInterceptor.shared.handle(event)
        }
    }

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

    /// Brings the tap up, or back up, when it should be running.
    ///
    /// The single entry point for every recovery path — wake, the display
    /// waking, the app coming forward, the health check — so there is one place
    /// that decides whether the tap is healthy, worth re-arming, or dead enough
    /// to rebuild. The decision itself is `MediaKeyTapPolicy`, which is a pure
    /// function and is checked without a live tap.
    func ensureRunning() {
        guard NotchSettings.shared.hudReplacement else {
            stop()
            return
        }
        // Armed before the trust test on purpose: Accessibility can be granted
        // while the app is running, and this keeps checking so the grant is
        // picked up without a relaunch.
        armWatchdog()

        switch MediaKeyTapPolicy.action(
            wanted: true,
            trusted: Self.isAccessibilityTrusted,
            hasTap: host.hasTap,
            enabled: host.isEnabled,
            ageSinceArmed: host.ageSinceArmed,
            settleTime: MediaKeyTapPolicy.defaultSettleTime,
            rearmAttempted: rearmAttempted
        ) {
        case .healthy:
            // Anything a re-arm may have been waiting for has happened.
            rearmAttempted = false
        case .none:
            break
        case .install:
            startTap()
        case .rearm:
            // `EventTapHost` re-arms from the disable event itself; this is the
            // path for a disable event that never arrived.
            rearmAttempted = true
            host.rearm()
        case .rebuild:
            // A port that will not come back: `tapEnable` on an invalidated one
            // reports success and changes nothing, so it has to be replaced.
            stopTap()
            startTap()
        case .teardown:
            // Wanted, but not permitted: hand the keys back to the system and
            // keep watching for the permission to return.
            stopTap()
        }
    }

    /// Takes the tap down and stops checking on it — for HUD replacement being
    /// switched off, and for app termination.
    func stop() {
        watchdog?.invalidate()
        watchdog = nil
        stopTap()
    }

    @discardableResult
    private func startTap() -> Bool {
        guard NotchSettings.shared.hudReplacement, Self.isAccessibilityTrusted else {
            return false
        }
        let mask = CGEventMask(1 << Self.systemDefinedEventType.rawValue)
        guard host.start(eventsOfInterest: mask) else { return false }
        // A fresh tap has a fresh lifetime in front of it.
        rearmAttempted = false
        armWatchdog()
        return true
    }

    /// Drops the tap without touching the watchdog, so the trust-lost path can
    /// hand the keys back while still watching for the permission to return.
    private func stopTap() {
        host.stop()
        rearmAttempted = false
    }

    private func armWatchdog() {
        guard watchdog == nil else { return }
        watchdog = Timer.scheduledRepeating(every: Self.healthInterval) { [weak self] in
            self?.ensureRunning()
        }
    }

    // MARK: - Event handling

    /// Runs on the event-tap thread, so every action is hopped to the main
    /// queue. Returns nil to swallow a key we handled, or the event untouched
    /// for anything else.
    ///
    /// Only the *action* needs the main thread. Reading the key out of an event
    /// is a plain `NSEvent(cgEvent:)` plus its `data1` and nothing else, which
    /// is thread-agnostic — it is the class-level `NSEvent` queries, not the
    /// instance ones, that belong to the main thread.
    private func handle(_ event: CGEvent) -> Unmanaged<CGEvent>? {
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

        DispatchQueue.main.async { [weak self] in
            self?.apply(key: key, fineStep: fineStep)
        }
        return nil
    }

    private func apply(key: KeyType, fineStep: Bool) {
        let delta = Self.step / (fineStep ? 4 : 1)

        switch key {
        case .soundUp, .soundDown:
            let current = volumeSource?() ?? 0
            let target = min(max(current + (key == .soundUp ? delta : -delta), 0), 1)
            setVolume?(target)
            // Show the value we just set. Reading back used to mean a second
            // blocking round trip to the device on the main thread — at key
            // auto-repeat rate — and the device's property listener corrects
            // the published value a moment later anyway if it disagreed.
            onVolume?(target, target == 0)

        case .mute:
            toggleMute?()
            let muted = isMuted?() ?? false
            onVolume?(muted ? 0 : (volumeSource?() ?? 0), muted)

        case .brightnessUp, .brightnessDown:
            // Zero is a real level, not a broken reader: a display stepped
            // down to true black reads back 0, and the old "0 means unreadable,
            // assume half" fallback made the very next key press jump to ~45% —
            // the bounce-back. Only guess when there is no reader at all.
            let current: Float
            if let source = brightnessSource {
                current = source()
            } else {
                current = 0.5
            }
            let target = min(max(current + (key == .brightnessUp ? delta : -delta), 0), 1)
            // `setBrightness` returns the clamped level it stored, so we can
            // show the position we actually set without re-reading the panel.
            // Re-reading right after a write was what surfaced a stale brighter
            // display value as a "bounce back" (e.g. it snapped to ~43% the
            // moment a key hit 0).
            let shown = setBrightness?(target) ?? target
            onBrightness?(shown)
        }
    }
}
