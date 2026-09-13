import Foundation
import Observation

/// 20-20-20 eye-break reminders (Sapphire's eye break module): every 20
/// minutes, look 20 feet away for 20 seconds. Announced in the notch.
@Observable
final class EyeBreakManager {
    private(set) var isEnabled = false
    private(set) var nextBreakAt: Date?
    private(set) var isOnBreak = false
    private(set) var breakEndsAt: Date?

    /// Fired when a break starts or ends, for the live activity.
    var onBreakChange: ((Bool) -> Void)?

    private var timer: Timer?

    static let workInterval: TimeInterval = 20 * 60
    static let breakDuration: TimeInterval = 20

    var timeUntilBreak: TimeInterval {
        guard let nextBreakAt else { return 0 }
        return max(nextBreakAt.timeIntervalSinceNow, 0)
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        enabled ? scheduleNextBreak() : stop()
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        nextBreakAt = nil
        breakEndsAt = nil
        if isOnBreak {
            isOnBreak = false
            onBreakChange?(false)
        }
    }

    private func scheduleNextBreak() {
        timer?.invalidate()
        isOnBreak = false
        breakEndsAt = nil
        nextBreakAt = Date().addingTimeInterval(Self.workInterval)
        // `.common`, like every other timer here: `Timer.scheduledTimer`
        // registers in `.default` only, so a break falling due while a menu
        // was open or a scroll was in flight fired late.
        timer = Timer.scheduledOneShot(after: Self.workInterval) { [weak self] in
            self?.beginBreak()
        }
    }

    private func beginBreak() {
        guard isEnabled else { return }
        timer?.invalidate()
        isOnBreak = true
        nextBreakAt = nil
        breakEndsAt = Date().addingTimeInterval(Self.breakDuration)
        onBreakChange?(true)
        TimerManager.postNotification(
            title: "Eye break",
            body: "Look about 20 feet away for 20 seconds."
        )

        timer = Timer.scheduledOneShot(after: Self.breakDuration) { [weak self] in
            self?.endBreak()
        }
    }

    private func endBreak() {
        guard isOnBreak else { return }
        isOnBreak = false
        breakEndsAt = nil
        onBreakChange?(false)
        TimerManager.postNotification(
            title: "Eye break over",
            body: "Back to it."
        )
        if isEnabled {
            scheduleNextBreak()
        }
    }
}
