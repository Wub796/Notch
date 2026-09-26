import CoreGraphics

/// One cue's latest reading.
///
/// `confidence` 0 is always an abstention, never a reading of zero: a cue that
/// can't see anything must not be able to convict *or* acquit.
struct CueReading: Equatable {
    /// 0...1 strength of this cue's own evidence, in the direction that cue
    /// argues for — spoof-ness for deny cues, liveness for confirm cues.
    let level: Float
    let confidence: Float

    static let none = CueReading(level: 0, confidence: 0)
}

enum LivenessCueRole: Equatable {
    /// Evidence of a spoof. Firing fails the scan outright and overrides any
    /// confirmation that already happened.
    case deny
    /// Evidence of a real face. Firing passes the liveness half of the scan.
    case confirm
}

/// The five independent cues. There is deliberately no combined score: deny
/// cues override confirm cues unconditionally, and a confirm cue's absence is
/// never a failure — a live person can sit perfectly still and not blink.
enum LivenessCue: String, CaseIterable, Hashable, Identifiable {
    case glossGlare
    case deviceDetected
    case flatVs3D
    case depthPose
    case blink

    var id: String { rawValue }

    var title: String {
        switch self {
        case .glossGlare: "Gloss/glare"
        case .deviceDetected: "Device detected"
        case .flatVs3D: "Flat vs 3D"
        case .depthPose: "Depth/pose"
        case .blink: "Blink"
        }
    }

    var role: LivenessCueRole {
        switch self {
        case .glossGlare, .deviceDetected: .deny
        case .flatVs3D, .depthPose, .blink: .confirm
        }
    }

    /// What firing actually means, in one line, for the diagnostics readout.
    var explanation: String {
        switch self {
        case .glossGlare:
            "A large flat specular highlight — glass or screen glare rather than skin's small scattered shine."
        case .deviceDetected:
            "A device-shaped rectangle overlaps the face, like a phone or tablet held up."
        case .flatVs3D:
            "Held-out nose points miss the fitted plane — the face has real depth."
        case .depthPose:
            "The nose offset tracks head yaw, so the nose sits off the eye plane and this isn't flat."
        case .blink:
            "Eye aspect ratio dipped and recovered — a photo cannot blink."
        }
    }
}

/// How much liveness checking runs. Both modes always run the deny cues; the
/// difference is only whether a positive proof of life is also required before
/// unlocking.
enum LivenessMode: String, CaseIterable, Identifiable, Sendable {
    /// Deny-only: "confirmed unless proven wrong". Never blocks a user who holds
    /// still — the default.
    case light
    /// Deny cues plus at least one confirm cue. Can block a user who sits
    /// perfectly still and never blinks for the whole scan.
    case heavy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: "Light"
        case .heavy: "Heavy"
        }
    }

    var summary: String {
        switch self {
        case .light: "Rejects obvious spoofs."
        case .heavy: "Also requires proof of a real face."
        }
    }
}

/// Fire thresholds per cue: a cue counts a frame when its reading is confident
/// and at or above `level`, and fires once it has counted `frames` of them
/// within the scan.
///
/// Seeded from real-device observation in Glance, and the two comments worth
/// keeping are the ones that aren't obvious: `flatVs3DLevel` is not 0.5 because
/// Vision's own jitter measures 0.21-0.46 on a still face, and `depthPoseLevel`
/// is high because that reading is a remapped correlation where 0.5 means zero
/// correlation.
struct LivenessTuning: Equatable {
    var glossLevel: Float = 0.04
    var glossFrames: Int = 3

    /// Deliberately lower than `glossLevel` — the device rectangle detector was
    /// the one signal proven reliable on real hardware.
    var deviceLevel: Float = 0.15
    var deviceFrames: Int = 3

    var flatVs3DLevel: Float = 0.25
    var flatVs3DFrames: Int = 2

    /// Read as `(r + 1) / 2`, so 0.5 is zero correlation and 0.8 requires r ≥ 0.6.
    var depthPoseLevel: Float = 0.8
    var depthPoseFrames: Int = 2

    /// A blink is already a discrete dip-and-recover event rather than a ramping
    /// level, so one firing frame is the event itself.
    var blinkFrames: Int = 1

    /// Frames Light mode waits before auto-confirming, so the deny cues get a
    /// fair chance to fire first — otherwise a first-frame match could unlock
    /// before glare or device detection ever ran.
    var lightModeMinimumFrames: Int = 3

    static let `default` = LivenessTuning()

    func level(for cue: LivenessCue) -> Float {
        switch cue {
        case .glossGlare: glossLevel
        case .deviceDetected: deviceLevel
        case .flatVs3D: flatVs3DLevel
        case .depthPose: depthPoseLevel
        // Any confident blink reading is the event — see `blinkFrames`.
        case .blink: 0.5
        }
    }

    func frames(for cue: LivenessCue) -> Int {
        switch cue {
        case .glossGlare: glossFrames
        case .deviceDetected: deviceFrames
        case .flatVs3D: flatVs3DFrames
        case .depthPose: depthPoseFrames
        case .blink: blinkFrames
        }
    }
}

enum LivenessDecision: Equatable {
    /// Nothing decided yet. Not a failure — the scan keeps going.
    case pending
    /// The cue is `nil` when Light mode auto-confirmed rather than a cue firing.
    case confirmed(by: LivenessCue?)
    case denied(by: LivenessCue)

    var isConfirmed: Bool { if case .confirmed = self { return true }; return false }
    var isDenied: Bool { if case .denied = self { return true }; return false }

    /// The user-facing explanation for a denial, matching the tone of the scan's
    /// other outcome strings — it is shown at the lock screen, so it has to
    /// explain itself without a console.
    var denialReason: String? {
        guard case .denied(let cue) = self else { return nil }
        switch cue {
        case .glossGlare:
            return "Screen glare detected — this looks like a photo on a display."
        case .deviceDetected:
            return "A device-shaped rectangle was detected around the face — this looks like a photo or a screen."
        default:
            return "The liveness check failed."
        }
    }
}

/// Running state for one cue across a scan.
struct LivenessCueState: Equatable {
    var reading: CueReading = .none
    /// Cumulative rather than consecutive, which is what makes the counting
    /// forgiving of the one-frame dropouts Vision produces mid-scan.
    var framesCounted: Int = 0
    var hasFired: Bool = false

    /// 0...1 progress toward firing, for the diagnostics readout.
    func progress(threshold: Int) -> Float {
        guard threshold > 0 else { return hasFired ? 1 : 0 }
        return min(1, Float(framesCounted) / Float(threshold))
    }
}

struct LivenessSnapshot: Equatable {
    let decision: LivenessDecision
    let mode: LivenessMode
    let cueStates: [LivenessCue: LivenessCueState]
    let frameCount: Int

    static let empty = LivenessSnapshot(decision: .pending, mode: .light, cueStates: [:], frameCount: 0)

    func state(for cue: LivenessCue) -> LivenessCueState {
        cueStates[cue] ?? LivenessCueState()
    }
}

/// The stateful decision core, kept as a plain struct rather than folded into
/// `LivenessAnalyzer` so it can be driven frame by frame with no camera, no
/// Vision, and no actor in the way.
struct LivenessEvaluator {
    var mode: LivenessMode
    var tuning: LivenessTuning
    /// The diagnostics readout can switch individual cues off to isolate one;
    /// the unlock path leaves this at "all enabled".
    var enabledCues: Set<LivenessCue>

    private(set) var states: [LivenessCue: LivenessCueState] = [:]
    private(set) var framesObserved: Int = 0

    init(
        mode: LivenessMode = .light,
        tuning: LivenessTuning = .default,
        enabledCues: Set<LivenessCue> = Set(LivenessCue.allCases)
    ) {
        self.mode = mode
        self.tuning = tuning
        self.enabledCues = enabledCues
    }

    mutating func reset() {
        states = [:]
        framesObserved = 0
    }

    /// Firing is latched: a cue that has fired stays fired for the rest of the
    /// scan, so a spoof can't wait out its own tell by behaving for a second.
    mutating func observe(_ readings: [LivenessCue: CueReading]) -> LivenessSnapshot {
        framesObserved += 1

        for cue in LivenessCue.allCases {
            var state = states[cue] ?? LivenessCueState()
            let reading = readings[cue] ?? .none
            state.reading = reading
            if reading.confidence > 0, reading.level >= tuning.level(for: cue) {
                state.framesCounted += 1
                if state.framesCounted >= tuning.frames(for: cue) {
                    state.hasFired = true
                }
            }
            states[cue] = state
        }

        return LivenessSnapshot(
            decision: currentDecision(),
            mode: mode,
            cueStates: states,
            frameCount: framesObserved
        )
    }

    /// Deny is evaluated first and unconditionally — it overrides any
    /// confirmation already reached, which is the whole point of the split.
    private func currentDecision() -> LivenessDecision {
        for cue in LivenessCue.allCases
        where cue.role == .deny && enabledCues.contains(cue) && (states[cue]?.hasFired ?? false) {
            return .denied(by: cue)
        }

        if mode == .light {
            return framesObserved >= tuning.lightModeMinimumFrames ? .confirmed(by: nil) : .pending
        }

        for cue in LivenessCue.allCases
        where cue.role == .confirm && enabledCues.contains(cue) && (states[cue]?.hasFired ?? false) {
            return .confirmed(by: cue)
        }

        return .pending
    }
}

/// Turns a rolling window into this frame's reading for every cue.
///
/// Deny cues read only the latest frame — they are about per-frame appearance.
/// Confirm cues read the whole window, because they are about motion.
enum LivenessCues {
    static func readings(window: [LivenessFrame], geometry: GeometryLivenessResult) -> [LivenessCue: CueReading] {
        [
            .glossGlare: glossGlare(window.last),
            .deviceDetected: deviceDetected(window.last),
            .flatVs3D: geometry.planarReading,
            .depthPose: LivenessScoring.poseDepthConsistency(window),
            .blink: LivenessScoring.blinkDynamics(window),
        ]
    }

    /// Skin gives many small scattered specular points; glass gives one large
    /// flat blob. `specularFraction` alone would fire on a bright forehead, so
    /// it is gated by how concentrated that glare is.
    static func glossGlare(_ frame: LivenessFrame?) -> CueReading {
        guard let glare = frame?.glare else { return .none }
        let fractionScore = ramp(glare.specularFraction, floor: 0.01, ceiling: 0.08)
        let clusterFactor = ramp(glare.specularClusterRatio, floor: 0.3, ceiling: 1.0)
        let level = fractionScore * (0.3 + 0.7 * clusterFactor)
        // Below about 50 native pixels of face there isn't enough detail to tell
        // a glare blob from a bright patch; ramps to full trust by ~130px.
        let confidence = ramp(Float(glare.cropPixelWidth), floor: 50, ceiling: 130)
        return CueReading(level: level, confidence: confidence)
    }

    /// The raw overlap fraction from `DeviceBezelDetector`, used directly rather
    /// than rescaled — it is already a 0...1 fraction of the face.
    static func deviceDetected(_ frame: LivenessFrame?) -> CueReading {
        guard let overlap = frame?.deviceOverlapFraction else { return .none }
        return CueReading(level: Float(min(max(overlap, 0), 1)), confidence: 1)
    }

    static func ramp(_ value: Float, floor: Float, ceiling: Float) -> Float {
        min(max((value - floor) / max(ceiling - floor, 0.0001), 0), 1)
    }
}
