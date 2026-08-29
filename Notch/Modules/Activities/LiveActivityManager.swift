import Foundation
import Observation

/// A live activity shown in the collapsed notch wings, iOS Dynamic
/// Island-style. Ordered by priority: a volume change outranks a battery
/// event, which outranks an imminent meeting, which outranks now-playing.
enum LiveActivity: Equatable {
    case music
    case lyrics(line: String)
    case timer(remaining: TimeInterval, progress: Double)
    case trackChange(title: String, artist: String)
    case meetingSoon(title: String, start: Date)
    case battery(percent: Int, charging: Bool, low: Bool)
    case screenLock(locked: Bool)
    case focusMode(name: String, symbol: String)
    case eyeBreak(active: Bool)
    case desktopChange
    case accessoryBattery(name: String, symbol: String, percent: Int)
    case volume(level: Float, muted: Bool)
    case brightness(level: Float)
}

/// Owns the transient activity sources (volume HUD, battery events). Both are
/// push-based system notifications, so the collapsed notch still does zero
/// periodic work. Calendar and music activities are derived in NotchState
/// from their own controllers.
@Observable
final class LiveActivityManager {
    /// The transient activity currently on screen, if any.
    private(set) var transient: LiveActivity?

    private let volumeMonitor = VolumeMonitor()
    private let powerMonitor = PowerMonitor()
    private var dismissWork: DispatchWorkItem?
    private var lastPowerSnapshot: PowerMonitor.Snapshot?
    private var wasLowBattery = false

    private static let volumeHUDDuration: TimeInterval = 1.6
    private static let batteryEventDuration: TimeInterval = 4.0
    private static let sneakPeekDuration: TimeInterval = 4.0
    private static let lockEventDuration: TimeInterval = 2.5
    private static let lowBatteryThreshold = 10

    func start() {
        if NotchSettings.shared.volumeHUDEnabled {
            volumeMonitor.onChange = { [weak self] level, muted in
                guard NotchSettings.shared.volumeHUDEnabled else { return }
                self?.show(.volume(level: level, muted: muted), for: Self.volumeHUDDuration)
            }
            volumeMonitor.start()
        }

        if NotchSettings.shared.liveActivitiesEnabled {
            lastPowerSnapshot = PowerMonitor.snapshot()
            wasLowBattery = (lastPowerSnapshot?.percent ?? 100) <= Self.lowBatteryThreshold
            powerMonitor.onChange = { [weak self] snapshot in
                self?.handlePowerChange(snapshot)
            }
            powerMonitor.start()

            // Session lock/unlock, announced by the system over the
            // distributed notification center (DynamicNotch's approach).
            let center = DistributedNotificationCenter.default()
            center.addObserver(
                forName: Notification.Name("com.apple.screenIsLocked"),
                object: nil, queue: .main
            ) { [weak self] _ in
                guard NotchSettings.shared.liveActivitiesEnabled else { return }
                self?.show(.screenLock(locked: true), for: Self.lockEventDuration)
            }
            center.addObserver(
                forName: Notification.Name("com.apple.screenIsUnlocked"),
                object: nil, queue: .main
            ) { [weak self] _ in
                guard NotchSettings.shared.liveActivitiesEnabled else { return }
                self?.show(.screenLock(locked: false), for: Self.lockEventDuration)
            }
        }
    }

    /// Sneak peek (boring.notch-style): a new track briefly announces itself
    /// in the collapsed notch.
    func showTrackChange(title: String, artist: String) {
        guard NotchSettings.shared.sneakPeekEnabled, !title.isEmpty else { return }
        show(.trackChange(title: title, artist: artist), for: Self.sneakPeekDuration)
    }

    /// Focus mode changed (Do Not Disturb, Work, Sleep…).
    func showFocusChange(name: String, symbol: String) {
        guard NotchSettings.shared.liveActivitiesEnabled else { return }
        show(.focusMode(name: name, symbol: symbol), for: Self.batteryEventDuration)
    }

    /// A Space switch.
    func showDesktopChange() {
        guard NotchSettings.shared.desktopChangeEnabled else { return }
        show(.desktopChange, for: 1.1)
    }

    /// Eye break started or ended.
    func showEyeBreak(active: Bool) {
        show(.eyeBreak(active: active), for: active ? EyeBreakManager.breakDuration : 2.0)
    }

    /// A newly connected accessory reporting its battery.
    func showAccessoryBattery(name: String, symbol: String, percent: Int) {
        guard NotchSettings.shared.liveActivitiesEnabled else { return }
        show(
            .accessoryBattery(name: name, symbol: symbol, percent: percent),
            for: Self.batteryEventDuration
        )
    }

    /// Volume HUD, raised when the media-key tap changes the level itself.
    ///
    /// The CoreAudio listener in `VolumeMonitor` also reports that change, so
    /// this is belt-and-braces — but the tap is the earlier signal, and it is
    /// the only one that fires when the tap has swallowed the key before
    /// anything else saw it.
    func showVolume(level: Float, muted: Bool) {
        guard NotchSettings.shared.volumeHUDEnabled else { return }
        show(.volume(level: level, muted: muted), for: Self.volumeHUDDuration)
    }

    /// Brightness HUD, raised when a brightness key changes the level.
    func showBrightness(level: Float) {
        guard NotchSettings.shared.brightnessHUDEnabled else { return }
        show(.brightness(level: level), for: Self.volumeHUDDuration)
    }

    /// Clears any transient activity immediately (used when a timer that owns
    /// the notch is cancelled).
    func clearTransient() {
        dismissWork?.cancel()
        transient = nil
    }

    private func handlePowerChange(_ snapshot: PowerMonitor.Snapshot) {
        guard NotchSettings.shared.liveActivitiesEnabled else { return }
        defer { lastPowerSnapshot = snapshot }

        let isLow = snapshot.percent <= Self.lowBatteryThreshold && !snapshot.onACPower
        let plugStateChanged = snapshot.onACPower != lastPowerSnapshot?.onACPower
        let becameLow = isLow && !wasLowBattery
        wasLowBattery = isLow

        // Announce plugging in/out and the low-battery crossing — not every
        // percent tick.
        guard plugStateChanged || becameLow else { return }
        show(
            .battery(percent: snapshot.percent, charging: snapshot.onACPower, low: isLow),
            for: Self.batteryEventDuration
        )
    }

    private func show(_ activity: LiveActivity, for duration: TimeInterval) {
        dismissWork?.cancel()
        transient = activity

        let work = DispatchWorkItem { [weak self] in
            self?.transient = nil
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }
}
