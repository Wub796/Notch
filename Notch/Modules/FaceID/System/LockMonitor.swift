import AppKit
import CoreGraphics
import Foundation
import Observation

/// Which signal most recently fired.
///
/// `withObservationTracking`'s `onChange` does not say which property changed,
/// so observers read this alongside the monotonic `eventCount` to tell one
/// event from the next.
enum LockEventKind: Equatable {
    case screenLocked
    case screenUnlocked
    case willSleep
    /// Display turned back on, from system sleep, display sleep, or the
    /// screensaver stopping.
    case wake

    var debugName: String {
        switch self {
        case .screenLocked: "screenLocked"
        case .screenUnlocked: "screenUnlocked"
        case .willSleep: "willSleep"
        case .wake: "wake"
        }
    }
}

/// Lock/unlock and sleep/wake state, for the Face ID triggers.
///
/// Ported from Glance (`LockMonitor.swift`, MIT © Jonathan Zhou). The single
/// most important line in it is the comment on `isScreenLocked`: none of these
/// notifications are trustworthy as a security gate, which is why every
/// decision that matters re-derives the truth from CGSession instead.
@Observable
final class LockMonitor: NSObject {
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
    /// Latest lock or wake signal; `willSleep` must not overwrite a lock that
    /// arrived moments earlier, and unlock clears the pending trigger.
    private(set) var latestTriggerEvent: LockEventKind?
    private(set) var eventCount: Int = 0

    private var workspaceObservers: [NSObjectProtocol] = []
    private var lastUnlockSignalAt: Date?

    override init() {
        super.init()
        startMonitoring()
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
        let workspace = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers {
            workspace.removeObserver(observer)
        }
    }

    private func startMonitoring() {
        let distributed = DistributedNotificationCenter.default()
        // This accessory app can be suspended while it has no active windows.
        // The closure-based observer uses the default suspension policy, which
        // can defer a lock notification until the user has already typed their
        // password. Selector observers let the system deliver these security
        // lifecycle signals immediately, even when the app is suspended.
        distributed.addObserver(
            self,
            selector: #selector(screenDidLock(_:)),
            name: Notification.Name("com.apple.screenIsLocked"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        distributed.addObserver(
            self,
            selector: #selector(screenDidUnlock(_:)),
            name: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        // Observing the key press that dismisses the screensaver is not
        // possible — Secure Event Input suppresses keyboard taps on the lock
        // screen regardless of Accessibility — so this notification stands in
        // for it.
        distributed.addObserver(
            self,
            selector: #selector(screensaverDidStop(_:)),
            name: Notification.Name("com.apple.screensaver.didstop"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

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

    @objc private func screenDidLock(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isScreenLocked = true
            self.record(.screenLocked)
        }
    }

    @objc private func screenDidUnlock(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isScreenLocked = false
            self.record(.screenUnlocked)
        }
    }

    @objc private func screensaverDidStop(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.record(.wake)
        }
    }

    private func recordWake() {
        isSleeping = false
        wakeEventCount += 1
        record(.wake)
    }

    private func record(_ kind: LockEventKind) {
        lastEvent = kind
        switch kind {
        case .screenLocked, .wake:
            latestTriggerEvent = kind
        case .screenUnlocked:
            latestTriggerEvent = nil
            lastUnlockSignalAt = Date()
        case .willSleep:
            break
        }
        eventCount += 1
        #if DEBUG
        print("[FaceID] lock monitor: received \(kind.debugName) (#\(eventCount))")
        #endif
    }

    /// Reconciles the distributed notifications with the authoritative session
    /// state. This catches a lock notification missed while the app was
    /// suspended, and also provides a startup check if Notch launches at the
    /// login window. Returns nil only when CGSession could not be read.
    @discardableResult
    func refreshFromSystem(reconcileUnlocked: Bool = false) -> Bool? {
        guard let actuallyLocked = Self.screenLockState() else { return nil }

        if actuallyLocked {
            // `screenIsUnlocked` can arrive slightly before CGSession flips its
            // value. Avoid interpreting that short transition as a fresh lock;
            // an actual new lock notification still records immediately above.
            if let lastUnlockSignalAt,
               Date().timeIntervalSince(lastUnlockSignalAt) < 1.5,
               latestTriggerEvent == nil {
                return true
            }
            isScreenLocked = true
            // Recover a lock that happened before our observer was installed.
            // If a lock notification already arrived, retain its original signal.
            if latestTriggerEvent == nil {
                record(.screenLocked)
            }
            return true
        }

        // The distributed lock notification arrives before the system finishes
        // transitioning. Keep that pending signal intact while the caller polls;
        // only clear it after an explicit unlock or an exhausted reconciliation.
        if reconcileUnlocked, isScreenLocked || latestTriggerEvent != nil {
            isScreenLocked = false
            record(.screenUnlocked)
        }
        return false
    }

    /// Authoritative lock state from the CoreGraphics session server rather
    /// than a spoofable notification. Fails closed: if the session dictionary
    /// can't be read, the answer is "not locked", so nothing types a password
    /// on the strength of a missing answer.
    static func screenLockState() -> Bool? {
        guard let dictionary = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            return nil
        }
        return dictionary["CGSSessionScreenIsLocked"] as? Bool
    }

    static func isScreenActuallyLocked() -> Bool {
        screenLockState() == true
    }
}
