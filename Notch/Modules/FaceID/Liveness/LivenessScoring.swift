import CoreGraphics
import Foundation

/// One frame's worth of liveness-relevant measurements, already normalized and
/// free of any Vision types.
///
/// Ported from Glance (`Liveness/LivenessScoring.swift`, MIT © Jonathan Zhou),
/// where the split exists so the decision logic can be exercised on synthetic
/// frames with no camera and no Vision at all.
struct LivenessFrame {
    let timestamp: Date
    /// Every landmark point Vision found this frame, tagged by region.
    let landmarks: [LandmarkPoint]
    /// Distance between the two eye centers — the normalization scale for every
    /// ratio below, so a measurement means the same thing up close and far away.
    let interocularDistance: CGFloat?
    let yaw: Float?
    let leftEyeAspectRatio: CGFloat?
    let rightEyeAspectRatio: CGFloat?
    /// `(noseCentroid.x − eyeMidpoint.x) / interocularDistance`. Tracks
    /// `tan(yaw)` on a real face and stays constant on any flat presentation —
    /// see `poseDepthConsistency` below.
    let noseOffsetRatio: CGFloat?
    /// Whether landmarks came from full 5-point detection rather than a degraded
    /// fallback. Cues that need precision skip frames where this is false.
    let hasReliableLandmarks: Bool
    /// Fraction of the face's bounding box covered by a detected device-shaped
    /// rectangle; `nil` when detection didn't run or found nothing. Read by the
    /// `deviceDetected` deny cue.
    let deviceOverlapFraction: CGFloat?
    /// Specular-highlight measurements from a native-resolution face crop; `nil`
    /// when no crop was available, in which case the `glossGlare` deny cue
    /// abstains.
    let glare: GlareSample?

    /// An explicit init so `glare` can default to `nil` — a defaulted `let`
    /// property is otherwise excluded from the synthesized memberwise init
    /// rather than becoming optional.
    init(
        timestamp: Date,
        landmarks: [LandmarkPoint],
        interocularDistance: CGFloat?,
        yaw: Float?,
        leftEyeAspectRatio: CGFloat?,
        rightEyeAspectRatio: CGFloat?,
        noseOffsetRatio: CGFloat?,
        hasReliableLandmarks: Bool,
        deviceOverlapFraction: CGFloat?,
        glare: GlareSample? = nil
    ) {
        self.timestamp = timestamp
        self.landmarks = landmarks
        self.interocularDistance = interocularDistance
        self.yaw = yaw
        self.leftEyeAspectRatio = leftEyeAspectRatio
        self.rightEyeAspectRatio = rightEyeAspectRatio
        self.noseOffsetRatio = noseOffsetRatio
        self.hasReliableLandmarks = hasReliableLandmarks
        self.deviceOverlapFraction = deviceOverlapFraction
        self.glare = glare
    }
}

/// The two confirm cues that need more than one frame: depth/pose consistency
/// and blink dynamics.
enum LivenessScoring {
    // MARK: - Depth/pose consistency (confirm cue)

    /// Correlates the nose's offset from the eye midline against `tan(yaw)`.
    ///
    /// On a real face the nose sits off the eye plane, so turning the head moves
    /// it across the image and the two track each other. On a flat
    /// presentation — a photo, or a screen — the whole thing rotates rigidly and
    /// the offset stays put. Abstains at small yaw ranges, where the predicted
    /// displacement is below Vision's landmark noise floor and the correlation
    /// would be measuring jitter rather than geometry.
    static func poseDepthConsistency(_ window: [LivenessFrame]) -> CueReading {
        let pairs = window.compactMap { frame -> (CGFloat, CGFloat)? in
            guard let offset = frame.noseOffsetRatio, let yaw = frame.yaw, frame.hasReliableLandmarks else {
                return nil
            }
            return (offset, CGFloat(tan(yaw)))
        }
        guard pairs.count >= 4 else { return .none }

        let yaws = pairs.map(\.1)
        guard let minimumYaw = yaws.min(), let maximumYaw = yaws.max() else { return .none }
        let yawRange = abs(atan(maximumYaw) - atan(minimumYaw))
        // Below about 12 degrees the predicted displacement is sub-pixel —
        // the same underlying limit `GeometryTuning.minYawRangeDegrees` gates on.
        let minimumMeasurableRange: CGFloat = 12 * .pi / 180
        guard yawRange > minimumMeasurableRange else { return .none }

        guard let correlation = pearsonCorrelation(pairs.map(\.0), pairs.map(\.1)) else { return .none }
        let level = Float(clamp((correlation + 1) / 2, 0, 1))
        // Confidence ramps in over the next ~15 degrees past the minimum: the
        // more rotation was observed, the more the correlation is worth.
        let confidence = Float(clamp((yawRange - minimumMeasurableRange) / (15 * .pi / 180), 0, 1))
        return CueReading(level: level, confidence: confidence)
    }

    private static func pearsonCorrelation(_ xs: [CGFloat], _ ys: [CGFloat]) -> CGFloat? {
        guard xs.count == ys.count, xs.count >= 2 else { return nil }
        let count = CGFloat(xs.count)
        let meanX = xs.reduce(0, +) / count
        let meanY = ys.reduce(0, +) / count
        var covariance: CGFloat = 0
        var varianceX: CGFloat = 0
        var varianceY: CGFloat = 0
        for index in 0..<xs.count {
            let dx = xs[index] - meanX
            let dy = ys[index] - meanY
            covariance += dx * dy
            varianceX += dx * dx
            varianceY += dy * dy
        }
        guard varianceX > 0, varianceY > 0 else { return nil }
        return covariance / (varianceX.squareRoot() * varianceY.squareRoot())
    }

    // MARK: - Blink dynamics (confirm cue)

    /// Looks for a dip and a recovery in eye aspect ratio.
    ///
    /// Never mandatory: a short scan window often contains no blink at all, and
    /// that abstains rather than failing. The thresholds are loose because
    /// Vision's landmark model doesn't fully collapse the eyelid contour during
    /// a real blink, and recovery is checked within a radius of frames because a
    /// blink spans several at ~20fps.
    static func blinkDynamics(_ window: [LivenessFrame]) -> CueReading {
        let aspectRatios = window.compactMap { frame -> CGFloat? in
            guard let left = frame.leftEyeAspectRatio, let right = frame.rightEyeAspectRatio else { return nil }
            return (left + right) / 2
        }
        guard aspectRatios.count >= 4 else { return .none }

        let baseline = aspectRatios.max() ?? 0
        guard baseline > 0 else { return .none }
        guard let minimum = aspectRatios.min(), let minimumIndex = aspectRatios.firstIndex(of: minimum) else {
            return .none
        }

        let dipRatio = minimum / baseline
        let recoveryRadius = 3
        let openBefore = aspectRatios[..<minimumIndex].suffix(recoveryRadius).contains { $0 / baseline > 0.7 }
        let openAfter = aspectRatios[(minimumIndex + 1)...].prefix(recoveryRadius).contains { $0 / baseline > 0.7 }
        let hasNeighborRecovery = minimumIndex > 0
            && minimumIndex < aspectRatios.count - 1
            && openBefore && openAfter

        guard dipRatio < 0.65, hasNeighborRecovery else { return .none }
        return CueReading(level: 1, confidence: 1)
    }

    private static func clamp<T: Comparable>(_ value: T, _ lower: T, _ upper: T) -> T {
        min(max(value, lower), upper)
    }
}
