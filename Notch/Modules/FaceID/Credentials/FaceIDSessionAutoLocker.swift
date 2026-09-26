import AppKit
import Foundation

/// Enforces `FaceIDSettings.autoLockInterval`: re-locks the Touch ID session
/// once it has been idle past the user's chosen limit.
///
/// Ported from Glance (`SessionAutoLocker.swift`, MIT © Jonathan Zhou). This is
/// the counterweight to gating the session rather than each unlock: without it,
/// one Touch ID prompt at setup would authorize typing the password into the
/// lock screen for as long as the app stayed running.
final class FaceIDSessionAutoLocker {
    private let credentials: FaceIDCredentialController
    private var timer: Timer?

    /// Coarse on purpose — the shortest selectable limit is a whole day, and
    /// the decision compares timestamps rather than counting ticks, so a
    /// five-minute check costs nothing and can't drift out of range.
    private let checkInterval: TimeInterval = 5 * 60

    private var wakeObserver: NSObjectProtocol?

    init(credentials: FaceIDCredentialController) {
        self.credentials = credentials
        // `.common` so the countdown keeps being checked during tracking
        // runloop modes — an open menu, a drag, a live resize.
        let timer = Timer(timeInterval: checkInterval, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.evaluate() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        // Also evaluate on wake: no timer fires during sleep, but the elapsed
        // time still counts as idle once the two timestamps are compared.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.evaluate()
        }

        evaluate()
    }

    deinit {
        timer?.invalidate()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    /// Routed through the credential controller rather than through
    /// `FaceIDCredentials` directly, so the UI's `isSessionUnlocked` flag can't
    /// go stale while the session silently locks underneath it.
    func evaluate() {
        guard FaceIDCredentials.isSessionUnlocked,
              let lastActivityAt = FaceIDCredentials.lastActivityAt
        else { return }

        let idleLimit = FaceIDSettings.shared.autoLockInterval.duration
        guard Date().timeIntervalSince(lastActivityAt) >= idleLimit else { return }

        credentials.lockSession()
    }
}
