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
    private(set) var remaining: TimeInterval = 0

    /// Fired when timer state or countdown changes for notch live activity updates.
    var onStateChange: (() -> Void)?

    /// Fired when a timer completes, for the live activity + notification.
    var onFinished: (() -> Void)?

    private var tickTimer: Timer?

    var isRunning: Bool {
        deadline != nil || isPaused
    }

    var progress: Double {
        guard totalDuration > 0 else { return 0 }
        return max(0, min(1, 1 - (remaining / totalDuration)))
    }

    func start(minutes: Int) {
        start(duration: TimeInterval(minutes) * 60)
    }

    func start(duration: TimeInterval) {
        guard duration > 0 else { return }
        totalDuration = duration
        remaining = duration
        deadline = Date().addingTimeInterval(duration)
        isPaused = false
        scheduleTick()
        onStateChange?()
    }

    func addMinutes(_ minutes: Int) {
        let delta = TimeInterval(minutes) * 60
        if isPaused {
            pausedRemaining += delta
            remaining = pausedRemaining
        } else if let deadline {
            self.deadline = deadline.addingTimeInterval(delta)
            remaining = max(self.deadline!.timeIntervalSinceNow, 0)
        } else {
            start(duration: delta)
            return
        }
        totalDuration += delta
        onStateChange?()
    }

    func togglePause() {
        if isPaused {
            deadline = Date().addingTimeInterval(pausedRemaining)
            isPaused = false
            remaining = pausedRemaining
            scheduleTick()
        } else {
            pausedRemaining = remaining
            isPaused = true
            tickTimer?.invalidate()
            tickTimer = nil
        }
        onStateChange?()
    }

    func cancel() {
        tickTimer?.invalidate()
        tickTimer = nil
        deadline = nil
        isPaused = false
        pausedRemaining = 0
        totalDuration = 0
        remaining = 0
        onStateChange?()
    }

    private func scheduleTick() {
        tickTimer?.invalidate()
        updateRemaining()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.updateRemaining()
            if self.remaining <= 0 {
                self.finish()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.tickTimer = timer
    }

    private func updateRemaining() {
        if isPaused {
            remaining = pausedRemaining
        } else if let deadline {
            remaining = max(deadline.timeIntervalSinceNow, 0)
        } else {
            remaining = 0
        }
    }

    private func finish() {
        tickTimer?.invalidate()
        tickTimer = nil
        deadline = nil
        totalDuration = 0
        remaining = 0
        onFinished?()
        onStateChange?()
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
