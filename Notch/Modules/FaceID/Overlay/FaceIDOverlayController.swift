import AppKit
import Observation
import SwiftUI

/// The only object other Face ID code should touch to show, resolve, or hide the
/// notch panel.
///
/// Ported from Glance (`NotchOverlay/NotchOverlayController.swift`, MIT ©
/// Jonathan Zhou). Interaction is hover-driven rather than click-driven: a
/// non-activating panel otherwise needs a first click just to gain focus before a
/// second click registers, and "click it twice" is a bug report, not a design.
@MainActor
@Observable
final class FaceIDOverlayController {
    /// One overlay for the whole feature, so the lock and wake triggers can never
    /// run two of them at once rather than leaving that to luck.
    static let shared = FaceIDOverlayController()

    enum Phase: Equatable {
        /// Armed: the window stays on screen here and answers hover; otherwise it
        /// is ordered out entirely.
        case closed
        /// Expanded, showing the idle still image and actively looking for a face.
        case scanning
        /// The success animation is playing, then it auto-collapses.
        case success
        /// The failure animation is playing or held; it collapses after a hold
        /// unless the user hovers first to retry.
        case failure
        case collapsing
    }

    private(set) var phase: Phase = .closed
    private(set) var media: FaceIDScanMedia = .idle
    private(set) var geometry: FaceIDGeometry = .forMainScreen()
    /// Read by the view for the hover-driven size and shadow bump. Irrelevant to
    /// the phase machine itself.
    private(set) var isArmed = false

    /// Pill style only: whether the pill is parked on screen at rest rather than
    /// off-screen. Deliberately separate from `isArmed`, which it lags on the way
    /// in — that lag is the slide into place — and leads on the way out.
    private(set) var isPillDocked = false

    /// Snapshotted from settings when a cycle begins rather than read live, so a
    /// preferences change mid-attempt can't change how the attempt resolves or how
    /// big the panel is while it does.
    private(set) var activeUnlockStyle: UnlockAnimationStyle = .original

    /// What a hover-driven activation should do, set by `arm()` (and kept across
    /// scan cycles, so a hover after a failure retries) or by the one-shot
    /// `present()` used by the panel's own test scan.
    private var onActivate: (() -> Void)?

    private let windowController = FaceIDOverlayWindowController()
    private var resolveTask: Task<Void, Never>?
    private var scanTimeoutTask: Task<Void, Never>?

    /// Guards the priming render pass, which only has to happen once.
    private var hasPrimedWindow = false

    /// Matches the success asset's duration — about 1.22s — plus a beat to read
    /// its final frame.
    private let successHoldDuration: Duration = .milliseconds(1_700)
    /// Not private: the coordinator's auto-retry waits this out too, so a retry
    /// can't start underneath the failure the user is still looking at.
    let failureHoldDuration: Duration = .seconds(5)
    /// Reads the same setting the coordinator's scan window does, so the two
    /// independent timers expire together.
    private var scanTimeoutDuration: Duration {
        .seconds(FaceIDSettings.shared.faceDetectionSeconds)
    }
    /// Long enough for the closing spring to settle before the window is hidden —
    /// collapsing state too early made the window visibly pop away mid-animation.
    let collapseAnimationDuration: Duration = .milliseconds(700)

    private init() {
        windowController.contentView = NSHostingView(rootView: FaceIDOverlayView(controller: self))
        // A display connecting or disconnecting mid-flow can flip notch style to
        // pill style.
        windowController.onScreenParametersChanged = { [weak self] in
            guard let self else { return }
            self.geometry = self.windowController.currentGeometry
        }
    }

    // MARK: - Armed mode (the lock and wake triggers)

    /// Arms the overlay for the lock-screen flow: shows the window and keeps it up
    /// until `disarm()`. `onActivate` restarts a scan when the user hovers.
    func arm(onActivate: @escaping () -> Void) {
        isArmed = true
        self.onActivate = onActivate
        geometry = windowController.currentGeometry
        phase = .closed
        media = .idle
        isPillDocked = false
        windowController.show()
        // Already shown and rendered while closed, which is the same thing priming
        // does.
        hasPrimedWindow = true
        updateInteractivity()

        guard geometry.style == .pill else {
            // The notch silhouette has nowhere to travel from: it is already on top
            // of hardware that is there.
            isPillDocked = true
            return
        }
        // Renders one real frame with the pill still off-screen, so flipping the
        // flag on the next runloop animates it down rather than appearing already
        // docked.
        windowController.displaySynchronously()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isArmed else { return }
            self.isPillDocked = true
        }
    }

    /// Hides the window for real. Only call once a lock-screen attempt is
    /// completely done: while armed, resolving an attempt returns to `.closed`,
    /// not here.
    ///
    /// If a success or collapse sequence is already resolving, this lets it finish
    /// naturally — clearing `isArmed` is enough, because the already-scheduled
    /// `collapse()` re-checks it once the hold expires and hides for real then.
    func disarm() {
        isArmed = false
        onActivate = nil
        // Undocked before the guard: if a success collapse is in flight, this turns
        // it into a full slide off-screen rather than a shrink to a resting pill.
        isPillDocked = false
        guard phase != .success, phase != .collapsing else { return }
        resolveTask?.cancel()
        resolveTask = nil
        scanTimeoutTask?.cancel()
        scanTimeoutTask = nil
        // Re-measured here rather than trusted from `arm()`: arming typically
        // happens right around a wake, when AppKit may not have finished laying out
        // the menu bar, so the auxiliary areas either side of the notch can read
        // back momentarily wrong. Refreshing before settling to `.closed` — the
        // shape most directly comparable with the real notch — self-corrects
        // instead of baking in a bad first reading.
        geometry = windowController.currentGeometry
        phase = .closed
        media = .idle
        windowController.setInteractive(false)

        guard geometry.style == .pill, windowController.isVisible else {
            windowController.hide()
            return
        }
        // The pill is visible at rest, so hiding right now would blink it away
        // instead of playing the slide up.
        Task { [weak self] in
            try? await Task.sleep(for: self?.collapseAnimationDuration ?? .milliseconds(700))
            guard let self, !self.isArmed, self.phase == .closed else { return }
            self.windowController.hide()
        }
    }

    /// Shows the idle still and auto-collapses silently — no failure animation —
    /// after `scanTimeoutDuration` if nothing resolves it first.
    func beginScanning() {
        resolveTask?.cancel()
        resolveTask = nil
        scanTimeoutTask?.cancel()
        geometry = windowController.currentGeometry
        activeUnlockStyle = FaceIDSettings.shared.effectiveUnlockAnimationStyle
        media = .idle
        phase = .scanning
        updateInteractivity()

        scanTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: self?.scanTimeoutDuration ?? .seconds(5))
            guard let self, !Task.isCancelled, self.phase == .scanning else { return }
            await self.collapse()
        }
    }

    // MARK: - Window priming

    /// On the very first show, presenting would otherwise render already-expanded
    /// with no prior closed frame for SwiftUI to animate away from. This runs one
    /// real closed-state show and render pass first.
    private func primeWindowIfNeeded(_ completion: @escaping () -> Void) {
        guard !hasPrimedWindow else {
            completion()
            return
        }
        hasPrimedWindow = true
        media = .idle
        phase = .closed
        windowController.show()
        windowController.displaySynchronously()
        // Queued as a closure literal rather than by handing `completion` to
        // `async(execute:)`: that parameter is `@Sendable`, and the retry
        // closures this takes are main-actor-bound values.
        DispatchQueue.main.async { completion() }
    }

    // MARK: - One-shot mode (the panel's own test scan)

    /// Shows the overlay in its scanning state without arming it, so the Face ID
    /// screen can run a real scan from inside the app. `onRetry` runs on hover
    /// after a failed attempt; pass nil to just collapse on hover.
    ///
    /// - Parameter styleOverride: forces a style regardless of the saved
    ///   preference, for the settings pane's live preview.
    func present(styleOverride: UnlockAnimationStyle? = nil, onRetry: (() -> Void)? = nil) {
        isArmed = false
        onActivate = onRetry
        resolveTask?.cancel()
        resolveTask = nil
        scanTimeoutTask?.cancel()
        scanTimeoutTask = nil
        geometry = windowController.currentGeometry
        activeUnlockStyle = styleOverride ?? FaceIDSettings.shared.effectiveUnlockAnimationStyle
        primeWindowIfNeeded { [weak self] in
            guard let self else { return }
            self.media = .idle
            self.phase = .scanning
            self.windowController.show()
            self.updateInteractivity()
        }
    }

    // MARK: - Resolving

    /// Resolves the current attempt. Success plays its animation and then collapses
    /// on its own; failure plays its animation and holds until either the hold
    /// expires or the user hovers to retry.
    func finish(success: Bool) {
        resolveTask?.cancel()
        scanTimeoutTask?.cancel()
        scanTimeoutTask = nil

        // `UnlockAnimationStyle.none` skips the success and failure video entirely;
        // the phase and retry behaviour are unaffected. Reads the cycle's captured
        // style, not live settings.
        let shouldAnimate = activeUnlockStyle != .none
        media = shouldAnimate ? (success ? .success : .failure) : .idle
        phase = success ? .success : .failure
        updateInteractivity()

        let hold = shouldAnimate
            ? (success ? successHoldDuration : failureHoldDuration)
            : .milliseconds(400)
        resolveTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: hold)
            guard !Task.isCancelled else { return }
            await self.collapse()
        }
    }

    /// Hover-driven activation: wakes from a closed or armed state, or retries from
    /// a held failure frame. A no-op while scanning, resolving, or collapsing.
    func activate() {
        // Gated here rather than in `updateInteractivity()`, so the cosmetic hover
        // bump stays unaffected and only the retry itself is removed.
        guard FaceIDSettings.shared.retryOnHover else { return }
        switch phase {
        case .closed, .failure:
            guard let onActivate else {
                if phase == .failure { Task { await collapse() } }
                return
            }
            resolveTask?.cancel()
            resolveTask = nil
            if !isArmed {
                // Captures its own style here: the armed path doesn't need to,
                // because `onActivate()` routes through `beginScanning()`, which
                // captures it.
                activeUnlockStyle = FaceIDSettings.shared.effectiveUnlockAnimationStyle
                media = .idle
                phase = .scanning
                updateInteractivity()
            }
            onActivate()
        case .scanning, .success, .collapsing:
            break
        }
    }

    /// Collapses gracefully: animates shut, then either leaves the window at rest —
    /// closed, still on screen, still answering hover, if armed — or orders it out.
    func collapse() async {
        guard phase != .closed, phase != .collapsing else { return }
        phase = .collapsing
        updateInteractivity()
        try? await Task.sleep(for: collapseAnimationDuration)
        guard phase == .collapsing else { return }

        // The same re-measure as `disarm()`: self-corrects a geometry captured
        // during a mid-wake reading, before the panel settles back to `.closed`.
        geometry = windowController.currentGeometry
        media = .idle
        if isArmed {
            phase = .closed
            updateInteractivity()
        } else {
            phase = .closed
            windowController.hide()
        }
    }

    /// Tears the overlay down without any resolve animation. Deliberately a no-op
    /// while a success or collapse is in flight: interrupting that made the window
    /// vanish abruptly at exactly the moment the user was looking at it.
    func dismissImmediately() {
        guard phase != .success, phase != .collapsing else { return }
        resolveTask?.cancel()
        resolveTask = nil
        scanTimeoutTask?.cancel()
        scanTimeoutTask = nil
        phase = .closed
        media = .idle
        isPillDocked = false
        windowController.setInteractive(false)
        windowController.hide()
    }

    private func updateInteractivity() {
        // Click-through otherwise, so the overlay never intercepts anything it
        // doesn't need to. A held failure needs the mouse so hover-to-retry works.
        windowController.setInteractive(isArmed || phase == .failure)
    }

    /// Called by `FaceIDOverlayView` whenever the visible panel's own frame changes
    /// — see `FaceIDOverlayWindowController.updateMousePassthrough()`.
    func updateInteractiveContentRect(_ rect: CGRect?) {
        windowController.setInteractiveContentRect(rect)
    }
}
