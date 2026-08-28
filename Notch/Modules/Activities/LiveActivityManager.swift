import Foundation
import Observation

/// A live activity shown in the collapsed notch wings, iOS Dynamic
/// Island-style. Ordered by priority: a volume change outranks a battery
/// event, which outranks an imminent meeting, which outranks now-playing.
enum LiveActivity: Equatable {
    case music
    case lyrics(line: String)
    case trackChange(title: String, artist: String)
    case meetingSoon(title: String, start: Date)
    case battery(percent: Int, charging: Bool, low: Bool)
    case screenLock(locked: Bool)
    case volume(level: Float, muted: Bool)
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
