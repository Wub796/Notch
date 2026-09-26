import CoreGraphics
import Foundation
import Observation

/// One pose in the guided capture: center plus the eight compass directions, in
/// the exact order they are presented to the user.
///
/// The gate is Vision's own yaw and pitch rather than a measurement of this
/// module's own making, because that is what the capture Glance validated is
/// built on and its bands are tuned against exactly those numbers. Yaw is
/// positive for a turn to the user's left — matching the mirrored preview — and
/// pitch is negative for a face tilted up; both signs were confirmed against
/// real frames upstream rather than assumed, and a sign taken backwards here
/// would leave the user turning the wrong way with no way to tell why. That is
/// why the pose order, the bands, and the per-pose leniencies are carried over
/// rather than re-derived.
enum FaceIDPose: String, CaseIterable, Identifiable {
    case center
    case left
    case topLeft = "top_left"
    case top
    case topRight = "top_right"
    case right
    case bottomRight = "bottom_right"
    case bottom
    case bottomLeft = "bottom_left"

    var id: String { rawValue }

    enum YawBand { case left, none, right }
    enum PitchBand { case up, none, down }

    var yawBand: YawBand {
        switch self {
        case .left, .topLeft, .bottomLeft: .left
        case .right, .topRight, .bottomRight: .right
        case .center, .top, .bottom: .none
        }
    }

    var pitchBand: PitchBand {
        switch self {
        case .top, .topLeft, .topRight: .up
        case .bottom, .bottomLeft, .bottomRight: .down
        case .center, .left, .right: .none
        }
    }

    /// What the screen tells the user to do. Written as an instruction rather
    /// than a label, because this is the only guidance they get.
    var instruction: String {
        switch self {
        case .center: "Look straight at the camera"
        case .left: "Turn your head slightly left"
        case .topLeft: "Turn your head to the top left"
        case .top: "Turn your head slightly up"
        case .topRight: "Turn your head to the top right"
        case .right: "Turn your head slightly right"
        case .bottomRight: "Turn your head to the bottom right"
        case .bottom: "Turn your head slightly down"
        case .bottomLeft: "Turn your head to the bottom left"
        }
    }

    /// Relaxes this pose's yaw and pitch bands — the same knob as
    /// `stallWidenFactor`, so above 1 is easier. Turning to either bottom corner
    /// is the hardest thing asked for here, between the jaw and the camera's own
    /// angle, and it is the pose that would otherwise strand the whole capture.
    var matchLeniency: Float {
        switch self {
        case .bottomLeft, .bottomRight: 1.5
        case .bottom: 1.2
        default: 1
        }
    }
}

/// The guided capture: prompts a pose, waits for the face to be held in it, takes
/// that pose's samples, and moves on.
///
/// Adapted from Glance's onboarding capture (`Onboarding/OnboardingController`
/// and `EnrollmentDirectionSweep`, MIT © Jonathan Zhou). The capture rules are
/// its own, carried over number for number — two samples per pose, half a second
/// held inside the pose's bands before anything counts, three matching frames in
/// a row, a permissive quality floor, and a camera allowed to settle before the
/// first sample — because those are what make a capture feel like it is
/// following the user rather than arguing with them. The framing is this app's:
/// Notch's panel is already the surface the user is looking at, so a second
/// full-screen onboarding window would be a second place to get the geometry
/// wrong.
@Observable
final class FaceIDEnrollmentSession {
    enum Phase: Equatable {
        case idle
        /// Warming the camera and the model up.
        case starting
        /// Capturing the current pose.
        case capturing
        /// All poses captured, waiting for the user to name and save.
        case ready
        case failed(String)
    }

    // MARK: - Capture rules

    /// Nine poses, two samples each: enough for a stable averaged template
    /// without holding the user in any one direction for long. Two per pose
    /// rather than one because a single embedding per direction is a single
    /// chance to catch a blink.
    static let samplesPerPose = 2

    static var totalSampleCount: Int { FaceIDPose.allCases.count * samplesPerPose }

    /// Consecutive matching frames required before a capture fires — this is what
    /// debounces a lucky frame caught on the way *through* a pose boundary.
    private static let requiredMatchStreak = 3

    /// How long the pose has to be held, continuously, before frames start
    /// counting at all: the user should be settled into the turn, not captured
    /// mid-motion.
    private static let poseHoldDuration: Duration = .milliseconds(500)

    /// A deliberately permissive floor for Vision's capture-quality score. There
    /// is no universal cutoff for it, and a mediocre sample costs the template
    /// far less than a capture that stalls does.
    private static let qualityFloor: Float = 0.2

    /// No captures are accepted for this long once the camera comes up, so the
    /// first samples aren't taken while the image is still settling.
    /// Detection and the pose guidance run throughout — only capture waits.
    private static let initialCaptureDelay: Duration = .seconds(1.5)

    /// Enrollment wants a closer face than a scan's bystander cutoff: sitting
    /// back in a chair is still near enough to unlock, but too far for a
    /// template worth averaging.
    private static var minimumFaceWidth: Float {
        max(FaceRecognitionPipeline.minimumProminentFaceWidth, 0.2)
    }

    // Pose-matching bands, in radians — Glance's numbers, in Glance's frame.
    private static let yawInnerThreshold: Float = 0.25
    private static let yawCenterTolerance: Float = 0.18
    private static let yawOuterCap: Float = 1.2
    private static let pitchInnerThreshold: Float = 0.20
    private static let pitchCenterTolerance: Float = 0.15
    private static let pitchOuterCap: Float = 0.9

    /// Past this, the bands widen so an unusual camera angle or a stiff neck
    /// can't strand the user on one pose forever.
    private static let stallTimeout: Duration = .seconds(12)
    private static let stallWidenFactor: Float = 1.25

    private static let frameInterval: UInt64 = 20_000_000 // 20ms, near the camera's own ~33ms cadence

    // MARK: - State

    private(set) var phase: Phase = .idle
    private(set) var poseIndex = 0
    private(set) var samples: [FaceSample] = []
    private(set) var previewFaces: [DetectedFace] = []
    /// Set while a face is detected but too small to enroll — the "move closer"
    /// prompt, which is distinct from "no face at all".
    private(set) var isTooFar = false
    /// Live distance from the current pose's bands, 0...1, for a progress ring.
    private(set) var poseProgress: Double = 0
    /// Plain-language state under the instruction, so a capture that is waiting
    /// says what it is waiting for.
    private(set) var hint: String = "Hold still"

    /// The camera is shared with the scan path rather than a second session:
    /// only one of the two is ever running, and a second `AVCaptureSession` on
    /// the same device would hold the light on twice.
    let camera: FaceIDCamera
    let pipeline: FaceRecognitionPipeline

    private var captureTask: Task<Void, Never>?
    private var lastProcessedFrameID: UInt64?
    /// Consecutive frames that have satisfied the current pose's bands and the
    /// capture's own gates.
    private var matchingStreak = 0
    /// Samples already taken for the pose in progress.
    private var capturedForCurrentPose = 0
    private var poseStartedAt: ContinuousClock.Instant = .now
    /// Set once when the capture begins, not per pose, so it only holds back the
    /// first sample rather than pausing again after every pose change.
    private var captureReadyAt: ContinuousClock.Instant = .now
    /// When the current pose first started matching continuously; `nil` while
    /// out of band. Capture waits `poseHoldDuration` past this instant.
    private var poseHoldStartedAt: ContinuousClock.Instant?

    init(camera: FaceIDCamera, pipeline: FaceRecognitionPipeline) {
        self.camera = camera
        self.pipeline = pipeline
    }

    var currentPose: FaceIDPose {
        FaceIDPose.allCases[min(poseIndex, FaceIDPose.allCases.count - 1)]
    }

    /// Samples taken so far, against the 18 the capture asks for.
    var captureCount: Int { samples.count }

    var progress: Double {
        Double(samples.count) / Double(Self.totalSampleCount)
    }

    var hasEnoughSamples: Bool { samples.count >= 3 }

    var isRunning: Bool {
        switch phase {
        case .starting, .capturing: true
        case .idle, .ready, .failed: false
        }
    }

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        samples = []
        poseIndex = 0
        matchingStreak = 0
        capturedForCurrentPose = 0
        lastProcessedFrameID = nil
        poseHoldStartedAt = nil
        phase = .starting

        captureTask?.cancel()
        captureTask = Task { [weak self] in
            await self?.run()
        }
    }

    func cancel() {
        captureTask?.cancel()
        captureTask = nil
        camera.stop()
        phase = .idle
        poseProgress = 0
        previewFaces = []
        isTooFar = false
        hint = "Hold still"
    }

    /// Commits the captured samples as a named identity. Throws on an encrypted
    /// write failure rather than reporting success the store didn't take.
    @discardableResult
    func commit(name: String, replacing existingID: UUID?) throws -> FaceIdentity? {
        let committed = try FaceEnrollmentStore.shared.commitEnrollment(
            replacing: existingID,
            name: name,
            samples: samples,
            embedder: pipeline.embedder
        )
        phase = .idle
        poseIndex = 0
        capturedForCurrentPose = 0
        samples = []
        return committed
    }

    // MARK: - Capture loop

    private func run() async {
        // The model's first inference costs more than a whole pose is worth
        // waiting for, and it would otherwise be spent inside the first pose —
        // see `FaceRecognitionPipeline.warmUp()`.
        await pipeline.warmUp()
        guard !Task.isCancelled else { return }

        await camera.start()
        guard !Task.isCancelled else { return }

        if let error = camera.errorMessage {
            phase = .failed(error)
            camera.stop()
            return
        }
        phase = .capturing
        poseStartedAt = .now
        captureReadyAt = .now + Self.initialCaptureDelay
        poseHoldStartedAt = nil

        while !Task.isCancelled, poseIndex < FaceIDPose.allCases.count {
            guard let frame = camera.currentFrame, frame.id != lastProcessedFrameID else {
                try? await Task.sleep(nanoseconds: Self.frameInterval)
                continue
            }
            lastProcessedFrameID = frame.id

            // Detection, alignment, embedding and the pose read all run off the
            // main thread: this loop is thousands of inferences and it drives a
            // live UI.
            let pipeline = self.pipeline
            let outcome = await Task.detached(priority: .userInitiated) {
                () -> EnrollFrameOutcome in
                do {
                    let faces = try FaceDetector.detectFaces(in: frame.image)
                    // The largest face with no prominence cutoff, so a face that
                    // is merely too far away reads as "move closer" rather than
                    // as nobody there.
                    guard let face = FaceRecognitionPipeline.largestFace(in: faces) else {
                        return .noFace
                    }
                    if Float(face.normalizedBoundingBox.width) < Self.minimumFaceWidth {
                        return .tooFar(face)
                    }
                    return .ready(try pipeline.recognize(face, in: frame.image))
                } catch {
                    return .noFace
                }
            }.value

            guard !Task.isCancelled else { return }

            switch outcome {
            case .noFace:
                previewFaces = []
                isTooFar = false
                matchingStreak = 0
                poseHoldStartedAt = nil
                poseProgress = 0
                hint = "Looking for a face…"
            case .tooFar(let face):
                // The box is kept: "come closer" is only convincing if the
                // screen shows that the face *was* seen.
                previewFaces = [face]
                isTooFar = true
                matchingStreak = 0
                poseHoldStartedAt = nil
                poseProgress = 0
                hint = "Move closer to the camera"
            case .ready(let result):
                previewFaces = [result.face]
                isTooFar = false
                process(result, pose: currentPose)
            }

            try? await Task.sleep(nanoseconds: Self.frameInterval)
        }

        guard !Task.isCancelled else { return }
        camera.stop()
        previewFaces = []
        #if DEBUG
        print("[FaceID] enroll: finished with \(samples.count)/\(Self.totalSampleCount) samples")
        #endif
        phase = hasEnoughSamples ? .ready : .failed("Not enough poses were captured. Try again in better light.")
    }

    private enum EnrollFrameOutcome {
        case noFace
        case tooFar(DetectedFace)
        case ready(FaceRecognitionResult)
    }

    /// Applies the capture's gates to one already-recognized frame and, when they
    /// all hold for long enough, takes the sample.
    private func process(_ result: FaceRecognitionResult, pose: FaceIDPose) {
        // Detection ran regardless; only capture waits for the camera to settle.
        guard ContinuousClock.now >= captureReadyAt else {
            resetPoseHold()
            hint = "Hold still"
            return
        }

        guard let yaw = result.face.yaw, let pitch = result.face.pitch else {
            resetPoseHold()
            poseProgress = 0
            hint = "Keep your whole face in view"
            return
        }

        let widened = ContinuousClock.now - poseStartedAt > Self.stallTimeout
        poseProgress = Self.poseProgress(yaw: yaw, pitch: pitch, pose: pose, widened: widened)

        // A quality score below the floor is a blurred or badly lit frame, and
        // an embedding taken from one would drag the averaged template toward
        // noise for every scan that follows. Tolerated deliberately: the frame is
        // skipped, not the pose.
        let qualityOK = result.quality.map { $0 >= Self.qualityFloor } ?? true
        // Only a five-point fit is reliably canonical; ArcFace on a looser
        // alignment produces an embedding that is confidently wrong.
        let alignmentOK = result.alignmentTier == .fivePoint
        guard qualityOK, alignmentOK else {
            resetPoseHold()
            hint = alignmentOK ? "That frame was too soft — hold still" : "Keep your whole face in view"
            return
        }

        guard Self.poseMatches(yaw: yaw, pitch: pitch, pose: pose, widened: widened) else {
            resetPoseHold()
            hint = Self.turnHint(yaw: yaw, pitch: pitch, pose: pose)
            return
        }

        // Matched — but only a *held* match counts, so the sample is taken once
        // the user has settled into the turn rather than passing through it.
        if poseHoldStartedAt == nil {
            poseHoldStartedAt = .now
        }
        hint = "Hold still"
        guard let holdStarted = poseHoldStartedAt, ContinuousClock.now - holdStarted >= Self.poseHoldDuration else {
            return
        }

        matchingStreak += 1
        guard matchingStreak >= Self.requiredMatchStreak else { return }
        capture(result, pose: pose)
    }

    private func capture(_ result: FaceRecognitionResult, pose: FaceIDPose) {
        // Only the streak is cleared: the hold that has already been earned stays
        // earned, so a pose's second sample follows its first a few frames later
        // rather than making the user hold the turn twice. It is cleared when the
        // pose advances.
        matchingStreak = 0

        samples.append(FaceSample(
            embedding: result.embedding,
            pose: pose.rawValue,
            capturedAt: Date(),
            quality: result.quality
        ))
        capturedForCurrentPose += 1
        #if DEBUG
        print("[FaceID] enroll: captured \(pose.rawValue) (\(samples.count)/\(Self.totalSampleCount)) "
            + "quality=\(result.quality.map { String(format: "%.2f", $0) } ?? "—")")
        #endif

        guard capturedForCurrentPose >= Self.samplesPerPose else { return }
        capturedForCurrentPose = 0
        poseIndex += 1
        poseStartedAt = .now
        poseHoldStartedAt = nil
        poseProgress = 0
    }

    private func resetPoseHold() {
        matchingStreak = 0
        poseHoldStartedAt = nil
    }

    // MARK: - Pose matching

    private static func poseMatches(yaw: Float, pitch: Float, pose: FaceIDPose, widened: Bool) -> Bool {
        let factor = (widened ? stallWidenFactor : 1) * pose.matchLeniency
        return yawMatches(yaw, band: pose.yawBand, factor: factor)
            && pitchMatches(pitch, band: pose.pitchBand, factor: factor)
    }

    private static func yawMatches(_ yaw: Float, band: FaceIDPose.YawBand, factor: Float) -> Bool {
        switch band {
        case .none: abs(yaw) < yawCenterTolerance * factor
        case .left: yaw > yawInnerThreshold / factor && yaw < yawOuterCap
        case .right: yaw < -yawInnerThreshold / factor && yaw > -yawOuterCap
        }
    }

    /// Negative pitch is a face tilted up. Confirmed upstream against real
    /// frames: Vision's pitch runs opposite to the obvious reading.
    private static func pitchMatches(_ pitch: Float, band: FaceIDPose.PitchBand, factor: Float) -> Bool {
        switch band {
        case .none: abs(pitch) < pitchCenterTolerance * factor
        case .up: pitch < -pitchInnerThreshold / factor && pitch > -pitchOuterCap
        case .down: pitch > pitchInnerThreshold / factor && pitch < pitchOuterCap
        }
    }

    /// How close the last frame was to the pose, 0...1, for the progress ring.
    /// Measured in the units the gate itself uses, so the ring reaches the top
    /// exactly as the pose starts matching.
    private static func poseProgress(yaw: Float, pitch: Float, pose: FaceIDPose, widened: Bool) -> Double {
        let factor = (widened ? stallWidenFactor : 1) * pose.matchLeniency
        let yawCloseness = closeness(
            of: yaw,
            tolerance: yawCenterTolerance,
            inner: yawInnerThreshold,
            factor: factor,
            isNeutral: pose.yawBand == .none
        )
        let pitchCloseness = closeness(
            of: pitch,
            tolerance: pitchCenterTolerance,
            inner: pitchInnerThreshold,
            factor: factor,
            isNeutral: pose.pitchBand == .none
        )
        return min(yawCloseness, pitchCloseness)
    }

    /// A neutral axis is *at* its target when it is small, so its progress falls
    /// away from center; a turned axis has to reach its threshold before it is
    /// there at all, so its progress rises toward it.
    private static func closeness(
        of value: Float,
        tolerance: Float,
        inner: Float,
        factor: Float,
        isNeutral: Bool
    ) -> Double {
        let magnitude = abs(value)
        if isNeutral {
            let limit = max(tolerance * factor, 0.001)
            return Double(max(0, min(1, 1 - magnitude / limit)))
        }
        let target = max(inner / factor, 0.001)
        return Double(max(0, min(1, magnitude / target)))
    }

    /// Which way to turn is the only actionable feedback when a pose isn't
    /// matching yet, and a progress ring alone cannot say it.
    private static func turnHint(yaw: Float, pitch: Float, pose: FaceIDPose) -> String {
        var parts: [String] = []
        switch pose.yawBand {
        case .none where abs(yaw) >= yawCenterTolerance: parts.append("face the camera straight on")
        case .left where yaw <= 0: parts.append("turn a little further left")
        case .left where yaw >= yawOuterCap: parts.append("turn back a little")
        case .right where yaw >= 0: parts.append("turn a little further right")
        case .right where yaw <= -yawOuterCap: parts.append("turn back a little")
        default: break
        }
        switch pose.pitchBand {
        case .none where abs(pitch) >= pitchCenterTolerance: parts.append("level your head")
        case .up where pitch >= 0: parts.append("tilt up")
        case .up where pitch <= -pitchOuterCap: parts.append("tilt back a little")
        case .down where pitch <= 0: parts.append("tilt down")
        case .down where pitch >= pitchOuterCap: parts.append("tilt back a little")
        default: break
        }
        guard !parts.isEmpty else { return "Hold still" }
        return "Now \(parts.joined(separator: ", "))"
    }
}
