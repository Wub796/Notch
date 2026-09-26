import AppKit
import CoreGraphics
import Foundation
import Observation

/// Which signal most recently fired.
///
/// `withObservationTracking`'s `onChange` does not say which property changed,
/// so observers read this alongside the monotonic `eventCount` to tell one
/// event from the next.
enum LockEventKind {
    case screenLocked
    case screenUnlocked
    case willSleep
    /// Display turned back on, from system sleep, display sleep, or the
    /// screensaver stopping.
    case wake
}

/// Lock/unlock and sleep/wake state, for the Face ID triggers.
///
/// Ported from Glance (`LockMonitor.swift`, MIT © Jonathan Zhou). The single
/// most important line in it is the comment on `isScreenLocked`: none of these
/// notifications are trustworthy as a security gate, which is why every
/// decision that matters re-derives the truth from CGSession instead.
@Observable
final class LockMonitor {
    /// NOT trustworthy on its own: any same-user process can post these
    /// distributed notifications, and this process can be suspended before one
    /// is delivered (a lid-close sleep racing a lock, for instance). A UI and
    /// trigger signal only, never a gate.
    private(set) var isScreenLocked: Bool = false

    /// Catches the case above: the lock may have happened while suspended, so
    /// wake is the first chance to notice. Callers should re-derive lock state
    /// with `isScreenActuallyLocked()` rather than trust `isScreenLocked`.
    private(set) var wakeEventCount: Int = 0

    /// True from `willSleepNotification` until the next wake.
    /// `screenIsLocked` fires about 150ms before the system actually finishes
    /// suspending, so callers skip acting on a lock while this is true and wait
    /// for the wake trigger instead.
    private(set) var isSleeping: Bool = false

    /// Observers track `eventCount` — which changes on every event, even a
    /// repeat of the same kind — then read `lastEvent`.
    private(set) var lastEvent: LockEventKind?
    private(set) var eventCount: Int = 0

    private var distributedObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []

    init() {
        startMonitoring()
    }

    deinit {
        let distributed = DistributedNotificationCenter.default()
        for observer in distributedObservers {
            distributed.removeObserver(observer)
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers {
            workspace.removeObserver(observer)
        }
    }

    private func startMonitoring() {
        let distributed = DistributedNotificationCenter.default()
        distributedObservers.append(distributed.addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isScreenLocked = true
            self?.record(.screenLocked)
        })
        distributedObservers.append(distributed.addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isScreenLocked = false
            self?.record(.screenUnlocked)
        })
        // Observing the key press that dismisses the screensaver is not
        // possible — Secure Event Input suppresses keyboard taps on the lock
        // screen regardless of Accessibility — so this notification stands in
        // for it.
        distributedObservers.append(distributed.addObserver(
            forName: Notification.Name("com.apple.screensaver.didstop"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.record(.wake)
        })

        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(workspace.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isSleeping = true
            self?.record(.willSleep)
        })
        // Display-level and system-level wake are treated as equivalent
        // triggers: they land within ~100ms of each other, in either order.
        workspaceObservers.append(workspace.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.recordWake()
        })
        workspaceObservers.append(workspace.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.recordWake()
        })
    }

    private func recordWake() {
        isSleeping = false
        wakeEventCount += 1
        record(.wake)
    }

    private func record(_ kind: LockEventKind) {
        lastEvent = kind
        eventCount += 1
    }

    /// Authoritative lock state from the CoreGraphics session server rather
    /// than a spoofable notification. Fails closed: if the session dictionary
    /// can't be read, the answer is "not locked", so nothing types a password
    /// on the strength of a missing answer.
    static func isScreenActuallyLocked() -> Bool {
        guard let dictionary = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            return false
        }
        return (dictionary["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }
}
