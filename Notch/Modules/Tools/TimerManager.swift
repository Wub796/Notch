import Foundation
import Observation
import UserNotifications

/// Countdown timer surfaced as a notch live activity — Sapphire's timer
/// module. One timer at a time, driven by a wall-clock deadline so it stays
/// accurate regardless of tick jitter.
@Observable
final class TimerManager {
    private(set) var deadline: Date?
    private(set) var isPaused = false
    private(set) var pausedRemaining: TimeInterval = 0
    private(set) var totalDuration: TimeInterval = 0

    /// Fired when a timer completes, for the live activity + notification.
    var onFinished: (() -> Void)?

    private var tickTimer: Timer?

    var isRunning: Bool {
        deadline != nil || isPaused
    }

    var remaining: TimeInterval {
        if isPaused { return pausedRemaining }
        guard let deadline else { return 0 }
        return max(deadline.timeIntervalSinceNow, 0)
    }

    var progress: Double {
        guard totalDuration > 0 else { return 0 }
        return 1 - (remaining / totalDuration)
    }

    func start(minutes: Int) {
        start(duration: TimeInterval(minutes) * 60)
    }

    func start(duration: TimeInterval) {
        guard duration > 0 else { return }
        totalDuration = duration
        deadline = Date().addingTimeInterval(duration)
        isPaused = false
        scheduleTick()
        NotchTheme.Haptics.generic()
    }

    func addMinutes(_ minutes: Int) {
        let delta = TimeInterval(minutes) * 60
        if isPaused {
            pausedRemaining += delta
        } else if let deadline {
            self.deadline = deadline.addingTimeInterval(delta)
        } else {
            start(duration: delta)
            return
        }
        totalDuration += delta
    }

    func togglePause() {
        if isPaused {
            deadline = Date().addingTimeInterval(pausedRemaining)
            isPaused = false
            scheduleTick()
        } else {
            pausedRemaining = remaining
            isPaused = true
            tickTimer?.invalidate()
            tickTimer = nil
        }
    }

    func cancel() {
        tickTimer?.invalidate()
        tickTimer = nil
        deadline = nil
        isPaused = false
        pausedRemaining = 0
        totalDuration = 0
    }

    private func scheduleTick() {
        tickTimer?.invalidate()
        // Half-second cadence keeps the countdown legible without burning CPU.
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.remaining <= 0 {
                self.finish()
            }
        }
    }

    private func finish() {
        tickTimer?.invalidate()
        tickTimer = nil
        deadline = nil
        totalDuration = 0
        NotchTheme.Haptics.generic()
        onFinished?()
        Self.postNotification(
            title: "Timer finished",
            body: "Your timer is up."
        )
    }

    /// Shared local-notification helper for the timer and eye-break modules.
    static func postNotification(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            center.add(UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            ))
        }
    }

    static func timeString(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded(.up))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
