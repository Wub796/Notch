import AppKit
import CoreGraphics
import Foundation
import Observation

/// Connects face recognition to the actual unlock path.
///
/// Ported from Glance (`FaceUnlockCoordinator.swift`, MIT © Jonathan Zhou). The
/// structure is deliberately kept: one long-lived object owns the camera, the
/// pipeline, the liveness analyzer, and the credential controller, and it is the
/// only place that decides whether a scan should happen and what happens when one
/// succeeds. Everything else — the panel screen, the settings pane, the overlay —
/// observes it or calls into it.
///
/// Two things are worth stating plainly, because they are the trade this feature
/// makes and neither is visible from the code:
///
/// - **This is not Face ID.** A MacBook webcam sees a flat 2D image, with none of
///   the depth sensing that makes Face ID on an iPhone trustworthy. With liveness
///   checking on, a printed photo and a photo on a phone screen are defeated with
///   reasonable confidence; a video replay is not reliably defeated. Anyone who
///   has the unlocked Mac, the enrolled face, and a recording of it can get in.
/// - **The password is typed for you.** macOS exposes no API that lets a
///   third-party app authorize a login, so an unlock here means synthesizing the
///   stored password into the lock screen's own field. That is why the password
///   sits behind Touch ID, why the session re-locks on an idle timer, and why a
///   scan requires CGSession to confirm the screen really is locked before
///   anything is typed.
@MainActor
@Observable
final class FaceIDController {
    enum ScanMode {
        /// Triggered by a lock or wake. May type the stored password.
        case unlock
        /// Started by hand from the panel. Measures and reports, but never types
        /// anything — the password belongs to the lock screen, and running a test
        /// scan while the user is in the middle of other work must not type it.
        case measure
    }

    /// How many consecutive frames must fail to match before the scan is called a
    /// mismatch. One bad-angle frame is noise, not a verdict.
    private let wrongFaceStreakThreshold = 6

    /// How long a scan's frames are barred from *ending* it as a mismatch.
    ///
    /// The opening moments of a scan are evidence about the camera and about the
    /// person still moving into place, not about who they are: a device that has
    /// just switched on delivers dark, soft frames while it settles, and six of
    /// those in a row — a fifth of a second once frames are flowing — is exactly
    /// the run that closes a scan as "face not recognized". Nothing else is
    /// held back for this long: a match still latches and unlocks the instant it
    /// is found, liveness still denies the moment a cue fires, and the window
    /// itself is unchanged. Same reasoning as the enrollment's settle delay.
    private static let mismatchSettleDuration: TimeInterval = 1.5

    private(set) var statusMessage = "Idle"
    private(set) var lastOutcome: String?
    private(set) var isScanning = false

    /// Live diagnostics for the panel's readout: what the last frames actually
    /// measured. Kept here rather than in the view so the numbers shown are the
    /// numbers the gate used.
    private(set) var lastScored: [ScoredIdentity] = []
    private(set) var lastLiveness = LivenessSnapshot.empty
    private(set) var lastGeometry = GeometryLivenessResult.empty
    private(set) var lastAlignmentTier: AlignmentTier?
    private(set) var lastQuality: Float?
    private(set) var lastFaceBoundingBox: CGRect?

    let lockMonitor = LockMonitor()
    let camera = FaceIDCamera()
    let pipeline: FaceRecognitionPipeline
    let credentials: FaceIDCredentialController

    private var scanTask: Task<Void, Never>?
    /// Bumped by every `startScanCycle()`; a superseded cycle bails as soon as it
    /// notices. `Task.cancel()` is cooperative, so without this a cancelled cycle
    /// could still reach its own `camera.stop()` and switch the camera off under
    /// the cycle that replaced it.
    private var scanGeneration = 0
    private var hasArmedForCurrentLock = false
    /// One shot per lock session: an auto-retry that could itself auto-retry would
    /// keep the camera on for the whole lock session.
    private var hasAutoRetriedForCurrentLock = false
    private var autoRetryTask: Task<Void, Never>?
    /// When the last cycle was armed — collapses a single lid-open, which fires
    /// several wake signals within a few hundred milliseconds, into one arm.
    private var lastArmedAt: ContinuousClock.Instant?
    private let rearmDebounce: Duration = .seconds(2)
    /// Gap between headless auto-retries, just to keep the camera from restarting
    /// in a tight loop.
    private let headlessRetryDelay: Duration = .seconds(1)

    private let spaceKeyMonitor = SpaceKeyMonitor()
    private var hasObservedLockEvents = false
    /// Re-locks the Touch ID session after the idle interval the user chose.
    private var autoLocker: FaceIDSessionAutoLocker?

    /// True while this app is showing the panel as a manual test scan, which is
    /// what routes the resolve path to the overlay's one-shot presentation rather
    /// than the armed one.
    private var isManualScan = false

    private var settings: FaceIDSettings { .shared }

    /// When off there is no panel at all — every overlay call below is conditioned
    /// on this rather than each one remembering to skip the video.
    private var showsUI: Bool { settings.showUnlockAnimation }

    init() {
        credentials = .shared
        pipeline = .shared
        spaceKeyMonitor.onSpaceKeyDown = { [weak self] in
            self?.handleSpaceKeyPress()
        }
    }

    // MARK: - Lifecycle

    /// Begins watching lock and wake events. Called once at launch; does nothing
    /// while the feature is switched off, so nothing is listening that shouldn't be.
    ///
    /// Also the point where the session's idle timer is armed: it only has anything
    /// to enforce once the feature is on.
    func start() {
        guard !hasObservedLockEvents else { return }
        hasObservedLockEvents = true
        autoLocker = FaceIDSessionAutoLocker(credentials: credentials)
        observeLockAndWakeEvents()
        // Paid here, at launch, so that it can never be paid by a scan instead —
        // see `FaceRecognitionPipeline.warmUp()`. Backgrounded, because nothing
        // is waiting for it and the app has a menu bar to draw.
        if settings.isEnabled {
            Task { [pipeline] in await pipeline.warmUp() }
        }
    }

    /// Tears everything down: no triggers, no camera, no panel.
    func stop() {
        hasObservedLockEvents = false
        disarmOverlay()
        spaceKeyMonitor.stop()
        credentials.lockSession()
    }

    /// Re-subscribes on every change — `withObservationTracking` only fires once
    /// per registration.
    private func observeLockAndWakeEvents() {
        withObservationTracking {
            _ = lockMonitor.isScreenLocked
            _ = lockMonitor.wakeEventCount
            _ = lockMonitor.isSleeping
            // Also tracked so a stopped screensaver and a display-only wake still
            // wake this up.
            _ = lockMonitor.eventCount
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.observeLockAndWakeEvents()
                guard let self, self.hasObservedLockEvents else { return }
                // A brief settle delay: CGSession's reported state can lag the
                // true state right after a wake.
                try? await Task.sleep(nanoseconds: 300_000_000)
                self.evaluateTrigger()
            }
        }
    }

    // MARK: - Triggers

    private func evaluateTrigger() {
        guard LockMonitor.isScreenActuallyLocked() else {
            hasArmedForCurrentLock = false
            hasAutoRetriedForCurrentLock = false
            disarmOverlay()
            return
        }
        guard !lockMonitor.isSleeping else { return }

        // `.wake` — from sleep, display sleep, or the screensaver stopping — is an
        // explicit "let me back in", so it clears the one-shot guard. The debounce
        // keeps the several wake signals from one lid-open from each re-arming and
        // fighting over the camera.
        if lockMonitor.lastEvent == .wake, !isWithinRecentArmBurst {
            hasArmedForCurrentLock = false
        }

        // Runs before the armed guard: the space monitor's lifetime is tied to
        // "locked and opted in", not to whether a scan has already run.
        updateSpaceMonitor()

        guard settings.isEnabled, !hasArmedForCurrentLock else { return }
        guard let signal = requiredTrigger(for: lockMonitor.lastEvent) else { return }
        // A pinned display that isn't connected bails entirely rather than showing
        // up somewhere else — but it says so rather than failing silently, because
        // from the outside an unlit lock screen is indistinguishable from a broken
        // camera or a forgotten password.
        guard FaceIDGeometry.preferredScreen() != nil else {
            statusMessage = FaceIDGeometry.pinnedDisplayMissingMessage
            return
        }

        guard FaceIDCredentials.isSessionUnlocked else {
            statusMessage = "Face ID is on, but the session is locked — authenticate once from the Face ID screen."
            return
        }
        guard FaceIDCredentials.hasStoredPassword() else {
            statusMessage = "Face ID is on, but no password is stored yet."
            return
        }

        // A deselected trigger means "don't scan for this signal automatically",
        // not "do nothing": the user can still hover the notch to start one.
        let shouldAutoScan = settings.unlockTriggers.contains(signal)

        hasArmedForCurrentLock = true
        lastArmedAt = .now
        Task { [weak self] in
            // `arm()` only shows a small closed silhouette, so this is just a brief
            // buffer past the login window's own entrance.
            try? await Task.sleep(nanoseconds: 250_000_000)
            await self?.arm(autoScan: shouldAutoScan)
        }
    }

    /// Whether the last arm was recent enough to belong to the same wake burst
    /// rather than to be a new one.
    private var isWithinRecentArmBurst: Bool {
        guard let lastArmedAt else { return false }
        return ContinuousClock.now - lastArmedAt < rearmDebounce
    }

    /// `nil` for signals that should arm nothing, including a nil `lastEvent` —
    /// otherwise the first observation after launch would fire regardless of what
    /// the user selected.
    private func requiredTrigger(for event: LockEventKind?) -> UnlockTrigger? {
        switch event {
        case .wake: .onWake
        case .screenLocked: .onLock
        case .screenUnlocked, .willSleep, nil: nil
        }
    }

    private func disarmOverlay() {
        guard !isManualScan else { return }
        scanTask?.cancel()
        scanTask = nil
        // Bumping the generation makes any cycle still suspended at
        // `await camera.start()` inert, rather than resuming and re-showing the
        // panel.
        scanGeneration &+= 1
        autoRetryTask?.cancel()
        autoRetryTask = nil
        camera.stop()
        isScanning = false
        FaceIDOverlayController.shared.disarm()
        // Covers the feature being switched off directly, keeping "disarmed" and
        // "not listening for space" in lockstep.
        spaceKeyMonitor.stop()
    }

    /// Idempotent, and safe to call on every lock and wake event. Deliberately does
    /// not prompt for Input Monitoring: a missing grant simply means "don't listen".
    private func updateSpaceMonitor() {
        let shouldListen = settings.isEnabled
            && settings.unlockTriggers.contains(.onSpace)
            && LockMonitor.isScreenActuallyLocked()
            && SpaceKeyMonitor.hasInputMonitoringAccess()
        if shouldListen {
            spaceKeyMonitor.start()
        } else {
            spaceKeyMonitor.stop()
        }
    }

    /// Runs the same gate chain as `evaluateTrigger`, then starts a scan.
    /// Independent of `LockMonitor` events, so it doesn't touch
    /// `hasArmedForCurrentLock`.
    private func handleSpaceKeyPress() {
        guard settings.isEnabled,
              settings.unlockTriggers.contains(.onSpace),
              LockMonitor.isScreenActuallyLocked(),
              FaceIDGeometry.preferredScreen() != nil,
              FaceIDCredentials.isSessionUnlocked,
              FaceIDCredentials.hasStoredPassword()
        else { return }

        // Already looking: swallows auto-repeat and double presses, and lets
        // "on wake"/"on lock" take precedence over "on space" with no special case.
        guard FaceIDOverlayController.shared.phase != .scanning else { return }

        guard showsUI else {
            // Headless: no panel, just scan.
            startScanCycle(mode: .unlock)
            return
        }
        if FaceIDOverlayController.shared.isArmed {
            // The closed silhouette is already up, so expand and scan — the same
            // path a hover retry takes.
            startScanCycle(mode: .unlock)
        } else {
            Task { [weak self] in await self?.arm(autoScan: true) }
        }
    }

    /// Either way the panel still arms: a deselected trigger only skips the
    /// automatic scan, leaving hover-to-start available.
    private func arm(autoScan: Bool) async {
        guard LockMonitor.isScreenActuallyLocked() else { return }
        guard showsUI else {
            // Headless: `evaluateTrigger()` already established that autoScan is
            // true here, so this is simply "start scanning".
            guard autoScan else { return }
            startScanCycle(mode: .unlock)
            return
        }
        FaceIDOverlayController.shared.arm { [weak self] in
            self?.startScanCycle(mode: .unlock)
        }
        if autoScan {
            startScanCycle(mode: .unlock)
        }
    }

    // MARK: - Manual (test) scan

    /// Runs a scan the user asked for from the panel, with the same detection,
    /// alignment, liveness, and scoring as the real thing — and deliberately
    /// without typing anything afterwards.
    func startManualScan() {
        guard !isScanning else { return }
        isManualScan = true
        autoRetryTask?.cancel()
        autoRetryTask = nil
        FaceIDOverlayController.shared.present { [weak self] in
            self?.startScanCycle(mode: .measure)
        }
        startScanCycle(mode: .measure)
    }

    /// Ends a manual scan and puts the overlay away.
    func endManualScan() {
        isManualScan = false
        scanTask?.cancel()
        scanTask = nil
        scanGeneration &+= 1
        camera.stop()
        isScanning = false
        FaceIDOverlayController.shared.dismissImmediately()
    }

    // MARK: - Scan cycle

    /// Called on arm, and again whenever the panel's hover activation fires.
    private func startScanCycle(mode: ScanMode) {
        scanTask?.cancel()
        scanGeneration &+= 1
        let generation = scanGeneration
        scanTask = Task { [weak self] in
            await self?.runScanCycle(generation: generation, mode: mode)
        }
    }

    private func runScanCycle(generation: Int, mode: ScanMode) async {
        if mode == .unlock {
            guard LockMonitor.isScreenActuallyLocked() else { return }
        }

        // Before the window opens rather than inside it: see
        // `FaceRecognitionPipeline.warmUp()`. `start()` has normally paid this at
        // launch, which is what makes the first scan of a session behave like
        // every scan after it.
        await pipeline.warmUp()
        guard generation == scanGeneration else { return }

        await camera.start()
        guard generation == scanGeneration else { return }

        if let error = camera.errorMessage {
            statusMessage = error
            camera.stop()
            isScanning = false
            return
        }

        // The window is meant to be spent looking at the user, and
        // `startRunning()` returns long before the first frame arrives — so
        // without this, a cold camera spends the front of the scan producing no
        // frames at all, and a scan with no frames finds no face.
        await waitForFirstFrame()
        guard generation == scanGeneration else { return }

        let showsUI = self.showsUI
        if showsUI {
            FaceIDOverlayController.shared.beginScanning()
        }
        isScanning = true
        statusMessage = "Looking for your face…"
        #if DEBUG
        print("[FaceID] scan: begin (\(mode == .unlock ? "unlock" : "measure"), "
            + "window=\(settings.faceDetectionSeconds)s)")
        #endif

        let outcome = await observeScanWindow(
            deadline: Date().addingTimeInterval(TimeInterval(settings.faceDetectionSeconds)),
            requireOverlayScanning: showsUI,
            mode: mode
        )

        // A newer cycle owns the camera and the panel now: leave both alone, and
        // leave the auto-retry one-shot unspent.
        guard generation == scanGeneration else { return }

        #if DEBUG
        print("[FaceID] scan: outcome \(Self.describe(outcome)) — "
            + "best=\(lastScored.first.map { String(format: "%.3f", $0.centroidSimilarity) } ?? "—") "
            + "tier=\(lastAlignmentTier?.rawValue ?? "—") quality=\(lastQuality.map { String(format: "%.2f", $0) } ?? "—")")
        #endif

        camera.stop()
        isScanning = false

        if mode == .measure {
            switch outcome {
            case .matched(let scored):
                statusMessage = "Recognized \(scored.identity.name) — this scan would have unlocked."
                FaceIDOverlayController.shared.finish(success: true)
            case .consistentlyWrongFace:
                statusMessage = "Face not recognized."
                FaceIDOverlayController.shared.finish(success: false)
            case .spoofSuspected:
                statusMessage = "Couldn't confirm a live face — this looks like a photo or a screen."
                FaceIDOverlayController.shared.finish(success: false)
            case .noResolution:
                statusMessage = "No face detected."
                FaceIDOverlayController.shared.finish(success: false)
            }
            isManualScan = false
            return
        }

        switch outcome {
        case .matched:
            // The unlock already happened inside `observeScanWindow`; this only
            // decides whether anything is shown about it.
            if showsUI {
                FaceIDOverlayController.shared.finish(success: true)
            }
        case .consistentlyWrongFace:
            statusMessage = "Face not recognized."
            if showsUI {
                FaceIDOverlayController.shared.finish(success: false)
                statusMessage = "Face not recognized — hover the notch to try again."
                scheduleAutoRetryIfEnabled(after: FaceIDOverlayController.shared.failureHoldDuration)
            } else {
                scheduleAutoRetryIfEnabled(after: headlessRetryDelay)
            }
        case .spoofSuspected:
            statusMessage = "Couldn't confirm a live face."
            if showsUI {
                FaceIDOverlayController.shared.finish(success: false)
                statusMessage = "Couldn't confirm a live face — hover the notch to try again."
                scheduleAutoRetryIfEnabled(after: FaceIDOverlayController.shared.failureHoldDuration)
            } else {
                scheduleAutoRetryIfEnabled(after: headlessRetryDelay)
            }
        case .noResolution:
            statusMessage = "No face detected."
            if showsUI {
                // No explicit collapse: the overlay's own scan timeout fires on the
                // same mark and collapses itself.
                statusMessage = "No face detected — hover the notch to try again."
                scheduleAutoRetryIfEnabled(after: FaceIDOverlayController.shared.collapseAnimationDuration)
            } else {
                scheduleAutoRetryIfEnabled(after: headlessRetryDelay)
            }
        }
    }

    /// Waits for the camera to deliver a frame before the scan clock starts.
    /// Bounded, because a camera that never delivers one must not hang the cycle.
    private func waitForFirstFrame(timeout: Duration = .seconds(2)) async {
        let deadline = ContinuousClock.now + timeout
        while camera.currentFrame == nil, ContinuousClock.now < deadline, !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    /// `delay` waits out whatever the panel is still showing, so a retry never
    /// starts underneath the previous outcome.
    private func scheduleAutoRetryIfEnabled(after delay: Duration) {
        guard settings.autoRetryOnce, !hasAutoRetriedForCurrentLock else { return }
        hasAutoRetriedForCurrentLock = true
        autoRetryTask?.cancel()
        autoRetryTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            // Re-checked rather than trusted across the delay: the user may have
            // unlocked by password or retried by hand while this waited.
            guard LockMonitor.isScreenActuallyLocked(), self.settings.isEnabled else { return }
            if self.showsUI {
                guard FaceIDOverlayController.shared.phase == .closed else { return }
            }
            self.startScanCycle(mode: .unlock)
        }
    }

    private enum ScanOutcome {
        case matched(ScoredIdentity)
        case consistentlyWrongFace
        /// A deny cue fired — glare or a device rectangle — so the face is
        /// rejected as a spoof regardless of whether it matched. Same failure path
        /// as `.consistentlyWrongFace`, and a different message.
        case spoofSuspected
        case noResolution
    }

    private static func describe(_ outcome: ScanOutcome) -> String {
        switch outcome {
        case .matched(let scored): "matched \(scored.identity.name)"
        case .consistentlyWrongFace: "wrong face"
        case .spoofSuspected: "spoof suspected"
        case .noResolution: "no resolution"
        }
    }

    /// Recognition and liveness run concurrently and each latches when it
    /// succeeds, so the unlock fires the moment the second one lands. Liveness
    /// never fails a scan by staying undecided; it simply keeps scanning until the
    /// deadline.
    ///
    /// `requireOverlayScanning` bails early once the panel's own timeout has
    /// collapsed the UI — which is only meaningful when there is a panel, since
    /// headlessly the phase never becomes `.scanning` at all.
    private func observeScanWindow(
        deadline: Date,
        requireOverlayScanning: Bool,
        mode: ScanMode
    ) async -> ScanOutcome {
        let livenessEnabled = settings.livenessChecksEnabled
        let liveness = LivenessAnalyzer()
        liveness.modeProvider = { [weak self] in self?.settings.livenessMode ?? .light }
        var consecutiveWrongFaceFrames = 0

        /// Cleared the moment a detected face fails to match, so a latched match
        /// can't be handed to whoever steps in front of the camera next.
        var readyMatch: ScoredIdentity?
        /// Turning liveness off makes this half permanently ready.
        var livenessConfirmed = !livenessEnabled
        /// Last frame's selected face, passed back so `selectDominantFace` stays on
        /// the same person instead of flip-flopping between two faces.
        var previousBoundingBox: CGRect?
        /// A cheap way to tell "no new camera frame yet" from "a fresh frame" —
        /// without it, a repeat frame would corrupt the motion cues by pretending
        /// time had passed when nothing moved.
        var lastProcessedFrameID: UInt64?
        /// When a failed frame may start counting toward a mismatch verdict.
        let verdictStart = Date().addingTimeInterval(Self.mismatchSettleDuration)
        /// The two numbers that tell "the camera delivered nothing" apart from
        /// "the camera delivered frames nobody was recognized in" — the whole
        /// diagnosis of a scan that finds no face, and neither is visible from
        /// outside the loop.
        #if DEBUG
        var framesSeen = 0
        var facesSeen = 0
        #endif

        while Date() < deadline, !Task.isCancelled,
              !requireOverlayScanning || FaceIDOverlayController.shared.phase == .scanning {
            if mode == .unlock, !LockMonitor.isScreenActuallyLocked() {
                return .noResolution
            }

            guard let frame = camera.currentFrame, frame.id != lastProcessedFrameID else {
                // 20ms keeps the liveness window's sample count high while staying
                // near the camera's own ~33ms cadence.
                try? await Task.sleep(nanoseconds: 20_000_000)
                continue
            }
            lastProcessedFrameID = frame.id
            #if DEBUG
            framesSeen += 1
            #endif

            let pipeline = self.pipeline
            let carriedBoundingBox = previousBoundingBox
            let outcome = await Task.detached(priority: .userInitiated) {
                () -> (FaceRecognitionResult, LivenessFrame)?
            in
                guard let result = try? pipeline.recognize(
                    in: frame.image,
                    preferNear: carriedBoundingBox
                ) else { return nil }
                let faceCrop = FaceIDCamera.renderCrop(from: frame, imageRect: result.face.boundingBox)
                return (result, LivenessFeatureExtractor.extract(
                    from: result,
                    frame: frame.image,
                    faceCrop: faceCrop
                ))
            }.value

            guard let (result, livenessFrame) = outcome else {
                consecutiveWrongFaceFrames = 0
                previousBoundingBox = nil
                lastScored = []
                try? await Task.sleep(nanoseconds: 20_000_000)
                continue
            }
            #if DEBUG
            facesSeen += 1
            #endif
            previousBoundingBox = result.face.normalizedBoundingBox
            lastFaceBoundingBox = result.face.normalizedBoundingBox
            lastAlignmentTier = result.alignmentTier
            lastQuality = result.quality

            // Fed regardless of match, so liveness stays a genuinely independent
            // gate rather than one starved by recognition confidence.
            var confirmingCue: LivenessCue?
            if livenessEnabled {
                let snapshot = liveness.observe(livenessFrame)
                lastLiveness = snapshot
                lastGeometry = liveness.lastGeometry
                switch snapshot.decision {
                case .denied:
                    lastOutcome = snapshot.decision.denialReason
                    return .spoofSuspected
                case .confirmed(let cue):
                    livenessConfirmed = true
                    confirmingCue = cue
                case .pending:
                    break
                }
            }

            // `activeIdentities`, not `identities`: an identity the user switched
            // off stays enrolled but must not unlock anything.
            let scored = pipeline.score(result.embedding, against: FaceEnrollmentStore.shared.activeIdentities)
            lastScored = scored
            let matched = pipeline.bestMatch(in: scored, threshold: settings.matchThreshold)

            if let matched {
                consecutiveWrongFaceFrames = 0
                readyMatch = matched
            } else {
                readyMatch = nil
                // Not counted at all while the camera is still settling, rather
                // than counted but ignored — a streak that has already filled up
                // would trip the verdict on the first frame past the deadline.
                if Date() >= verdictStart {
                    consecutiveWrongFaceFrames += 1
                    if consecutiveWrongFaceFrames >= wrongFaceStreakThreshold {
                        return .consistentlyWrongFace
                    }
                }
            }

            if let readyMatch, livenessConfirmed {
                let livenessNote = livenessEnabled
                    ? (confirmingCue.map { "live via \($0.title)" } ?? "liveness clear")
                    : "liveness off"
                lastOutcome = "Matched \(readyMatch.identity.name) at "
                    + "\(String(format: "%.3f", readyMatch.centroidSimilarity)), \(livenessNote)."

                guard mode == .unlock else {
                    return .matched(readyMatch)
                }

                statusMessage = "Recognized — unlocking…"
                await credentials.injectStoredPassword(requireAuthoritativeLock: true)
                return .matched(readyMatch)
            }

            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        #if DEBUG
        print("[FaceID] scan: window closed with no resolution — "
            + "frames=\(framesSeen) withFace=\(facesSeen) "
            + "livenessConfirmed=\(livenessConfirmed) latchedMatch=\(readyMatch != nil)")
        #endif
        return .noResolution
    }
}
