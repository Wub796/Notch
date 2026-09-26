import CoreGraphics
import Foundation

/// Thresholds for the planar-vs-3D cue. Every one of them is a gate on the same
/// question: is there enough geometry in this window for the measurement to mean
/// anything?
struct GeometryTuning {
    /// Excess (`probeResidual / fitResidual`) at which the planar signal starts
    /// ramping off zero; about 1.0 means "a plane fits exactly".
    var excessFloor: CGFloat = 1.15
    /// Excess at which the planar signal saturates at 1.
    var excessCeiling: CGFloat = 2.0
    /// `|mean residual| / mean(|residual|)` below this reads as landmark noise
    /// rather than as coherent 3D parallax.
    var coherenceFloor: CGFloat = 0.35
    /// Minimum mean displacement of the fit set, in interocular-distance units,
    /// before the geometry votes at all.
    var motionGate: CGFloat = 0.008
    /// Minimum yaw range in degrees before the geometry votes — this is what
    /// closes the "smooth phone wobble" case, where pure translation clears
    /// `motionGate` with zero real parallax.
    var minYawRangeDegrees: CGFloat = 12

    static let `default` = GeometryTuning()
}

/// The cue's full state, including the numbers behind its level — kept whole
/// because the diagnostics readout shows them, and a cue that can't explain
/// itself is one nobody can tune.
struct GeometryLivenessResult: Equatable {
    let planarResidualScore: Float
    let planarConfidence: Float

    let validLandmarkCount: Int
    let pairsAnalyzed: Int
    let rejectedPairCount: Int
    let medianFitResidual: CGFloat?
    let medianProbeResidual: CGFloat?
    let excessRatio: CGFloat?
    let coherence: CGFloat?
    let motionMagnitude: CGFloat?
    /// Normalized distance ratios, for the diagnostics readout. Display only —
    /// these do not vote.
    let diagnosticRatios: [String: CGFloat]

    static let empty = GeometryLivenessResult(
        planarResidualScore: 0, planarConfidence: 0,
        validLandmarkCount: 0, pairsAnalyzed: 0, rejectedPairCount: 0,
        medianFitResidual: nil, medianProbeResidual: nil,
        excessRatio: nil, coherence: nil, motionMagnitude: nil,
        diagnosticRatios: [:]
    )

    /// Adapter into the shared cue vocabulary — see `LivenessCues.readings`.
    var planarReading: CueReading {
        CueReading(level: planarResidualScore, confidence: planarConfidence)
    }
}

/// Regions that sit on roughly one shallow surface and are spread widely enough
/// to constrain an 8-DOF homography. The nose is deliberately held out.
private let geometryFitRegions: Set<LandmarkRegion> = [
    .leftEye, .rightEye, .leftEyebrow, .rightEyebrow, .outerLips,
]

/// Protruding landmarks that sit geometrically *inside* the fit hull, so any
/// leftover error is depth rather than extrapolation. `faceContour` is excluded
/// on purpose: it is the silhouette, and its points slide with pose.
private let geometryProbeRegions: Set<LandmarkRegion> = [
    .nose, .noseCrest, .medianLine,
]

/// Planar vs 3D liveness: the one cue that asks whether the thing in front of
/// the camera has depth.
///
/// Ported from Glance (`Liveness/GeometryLiveness.swift`, MIT © Jonathan Zhou).
/// The method: fit a homography to the flat regions between two frames, then
/// measure how badly the protruding landmarks miss it. A photo or a screen can
/// only ever move rigidly, so the fit absorbs everything and the residual stays
/// near the noise floor. A real face rotates in three dimensions, and the nose
/// has nowhere to hide.
///
/// A higher `planarResidualScore` means more like a live face — the cue is a
/// confirm cue, so "flat" is the suspicious reading and it reports the evidence
/// that the face *isn't* flat.
enum GeometryLiveness {
    static func evaluate(_ window: [LivenessFrame], tuning: GeometryTuning = .default) -> GeometryLivenessResult {
        let lastLandmarkCount = window.last?.landmarks.count ?? 0
        var diagnostics = diagnosticRatios(from: window.last)

        guard window.count >= 3 else {
            return GeometryLivenessResult(
                planarResidualScore: 0, planarConfidence: 0,
                validLandmarkCount: lastLandmarkCount, pairsAnalyzed: 0, rejectedPairCount: 0,
                medianFitResidual: nil, medianProbeResidual: nil,
                excessRatio: nil, coherence: nil, motionMagnitude: nil,
                diagnosticRatios: diagnostics
            )
        }

        let yawRange = yawRangeDegrees(window)
        let yawGateOK = (yawRange ?? 0) >= tuning.minYawRangeDegrees
        if let yawRange { diagnostics["yaw range (deg)"] = yawRange }

        var excesses: [CGFloat] = []
        var coherences: [CGFloat] = []
        var motions: [CGFloat] = []
        var fitResiduals: [CGFloat] = []
        var probeResiduals: [CGFloat] = []
        var weights: [CGFloat] = []
        var rejected = 0
        var skippedForMotion = 0

        for (first, second, weight) in pairIndices(count: window.count) {
            guard let sample = pairGeometry(from: window[first], to: window[second]) else {
                rejected += 1
                continue
            }
            if sample.motion < tuning.motionGate {
                skippedForMotion += 1
                continue
            }
            excesses.append(sample.excess)
            coherences.append(sample.coherence)
            motions.append(sample.motion)
            fitResiduals.append(sample.fitResidual)
            probeResiduals.append(sample.probeResidual)
            weights.append(weight)
        }

        let pairsAnalyzed = excesses.count
        let medianFit = fitResiduals.isEmpty ? nil : LandmarkGeometry.medianValue(fitResiduals)
        let medianProbe = probeResiduals.isEmpty ? nil : LandmarkGeometry.medianValue(probeResiduals)
        let excess = weightedMedian(excesses, weights: weights)
        let coherence = weightedMedian(coherences, weights: weights)
        let motion = motions.isEmpty ? nil : (motions.reduce(0, +) / CGFloat(motions.count))

        // Abstention is (level 0, confidence 0). The level is never read when
        // the confidence is zero, which is what lets "no idea" be distinct from
        // "definitely flat".
        var planarScore: Float = 0
        var planarConfidence: Float = 0
        if yawGateOK, let excess, let coherence, pairsAnalyzed >= 2 {
            // Unstructured leftover is landmark jitter, not 3D evidence.
            let coherenceFactor = Float(clamp(
                (coherence - tuning.coherenceFloor) / max(1 - tuning.coherenceFloor, 0.01), 0, 1
            ))
            let excessScore = Float(clamp(
                (excess - tuning.excessFloor) / max(tuning.excessCeiling - tuning.excessFloor, 0.01), 0, 1
            ))
            planarScore = excessScore * (0.35 + 0.65 * coherenceFactor)
            planarConfidence = Float(clamp(Double(pairsAnalyzed) / 6.0, 0, 1)) * (0.5 + 0.5 * coherenceFactor)
        } else if !yawGateOK {
            // Not enough head rotation to tell flat from 3D — see
            // `minYawRangeDegrees`.
            planarScore = 0
            planarConfidence = 0
        } else if skippedForMotion > 0, pairsAnalyzed == 0 {
            // Motion never cleared the gate, so abstain rather than call it a photo.
            planarScore = 0
            planarConfidence = 0
        }

        return GeometryLivenessResult(
            planarResidualScore: planarScore,
            planarConfidence: planarConfidence,
            validLandmarkCount: lastLandmarkCount,
            pairsAnalyzed: pairsAnalyzed,
            rejectedPairCount: rejected,
            medianFitResidual: medianFit,
            medianProbeResidual: medianProbe,
            excessRatio: excess,
            coherence: coherence,
            motionMagnitude: motion,
            diagnosticRatios: diagnostics
        )
    }

    /// Yaw range across frames that report one; `nil` if too few do.
    private static func yawRangeDegrees(_ window: [LivenessFrame]) -> CGFloat? {
        let yawsInDegrees = window.compactMap { $0.yaw }.map { CGFloat($0) * 180 / .pi }
        guard yawsInDegrees.count >= 3,
              let low = yawsInDegrees.min(),
              let high = yawsInDegrees.max()
        else { return nil }
        return high - low
    }

    // MARK: - Pair geometry

    private struct PairSample {
        let fitResidual: CGFloat
        let probeResidual: CGFloat
        let excess: CGFloat
        let coherence: CGFloat
        let motion: CGFloat
    }

    private static func pairGeometry(from first: LivenessFrame, to second: LivenessFrame) -> PairSample? {
        guard second.hasReliableLandmarks, first.hasReliableLandmarks else { return nil }
        guard let iod = second.interocularDistance, iod > 0 else { return nil }
        let matched = correspondingPoints(first.landmarks, second.landmarks)
        let (fitSource, fitDestination) = flatten(matched, in: geometryFitRegions)
        let (probeSource, probeDestination) = flatten(matched, in: geometryProbeRegions)
        let (eyeSource, eyeDestination) = flatten(matched, in: [.leftEye, .rightEye])
        guard fitSource.count >= 6, probeSource.count >= 2 else { return nil }
        guard let homography = LandmarkGeometry.solveRobustHomography(
            from: fitSource, to: fitDestination
        ) else { return nil }

        let eyeMagnitudes = zip(eyeSource, eyeDestination).map {
            hypot($1.x - homography.apply($0).x, $1.y - homography.apply($0).y) / iod
        }
        let probeVectors: [(CGFloat, CGFloat)] = zip(probeSource, probeDestination).map { source, destination in
            let predicted = homography.apply(source)
            return (
                (destination.x - predicted.x) / iod,
                (destination.y - predicted.y) / iod
            )
        }
        let probeMagnitudes = probeVectors.map { hypot($0.0, $0.1) }
        // The eyes are the rigid anchors: expression in the fit set must not be
        // allowed to set the noise scale, or a smile reads as depth.
        let noiseMagnitudes: [CGFloat]
        if eyeMagnitudes.count >= 2 {
            noiseMagnitudes = eyeMagnitudes
        } else {
            noiseMagnitudes = zip(fitSource, fitDestination).map {
                hypot($1.x - homography.apply($0).x, $1.y - homography.apply($0).y) / iod
            }
        }
        let fitResidual = LandmarkGeometry.medianValue(noiseMagnitudes)
        let probeResidual = LandmarkGeometry.medianValue(probeMagnitudes)
        let noiseFloor: CGFloat = 0.002
        let excess = probeResidual / max(fitResidual, noiseFloor)

        let meanX = probeVectors.reduce(CGFloat(0)) { $0 + $1.0 } / CGFloat(probeVectors.count)
        let meanY = probeVectors.reduce(CGFloat(0)) { $0 + $1.1 } / CGFloat(probeVectors.count)
        let meanMagnitude = probeMagnitudes.reduce(0, +) / CGFloat(probeMagnitudes.count)
        let coherence = meanMagnitude > 1e-8 ? hypot(meanX, meanY) / meanMagnitude : 0

        let motion = zip(fitSource, fitDestination)
            .map { hypot($1.x - $0.x, $1.y - $0.y) }
            .reduce(0, +) / (CGFloat(fitSource.count) * iod)

        return PairSample(
            fitResidual: fitResidual,
            probeResidual: probeResidual,
            excess: excess,
            coherence: coherence,
            motion: motion
        )
    }

    /// Points present, with matching per-region counts, in both frames — which
    /// is what avoids silently pairing unrelated points from a region Vision
    /// tracked differently in the two frames.
    private static func correspondingPoints(
        _ first: [LandmarkPoint],
        _ second: [LandmarkPoint]
    ) -> [LandmarkRegion: (source: [CGPoint], destination: [CGPoint])] {
        let firstByRegion = Dictionary(grouping: first, by: \.region)
        let secondByRegion = Dictionary(grouping: second, by: \.region)
        var result: [LandmarkRegion: (source: [CGPoint], destination: [CGPoint])] = [:]
        for region in LandmarkRegion.allCases {
            guard let firstPoints = firstByRegion[region],
                  let secondPoints = secondByRegion[region],
                  firstPoints.count == secondPoints.count,
                  !firstPoints.isEmpty
            else { continue }
            let sortedFirst = firstPoints.sorted { $0.indexInRegion < $1.indexInRegion }
            let sortedSecond = secondPoints.sorted { $0.indexInRegion < $1.indexInRegion }
            result[region] = (sortedFirst.map(\.point), sortedSecond.map(\.point))
        }
        return result
    }

    private static func flatten(
        _ byRegion: [LandmarkRegion: (source: [CGPoint], destination: [CGPoint])],
        in regions: Set<LandmarkRegion>
    ) -> (source: [CGPoint], destination: [CGPoint]) {
        var source: [CGPoint] = []
        var destination: [CGPoint] = []
        for region in LandmarkRegion.allCases where regions.contains(region) {
            guard let points = byRegion[region] else { continue }
            source += points.source
            destination += points.destination
        }
        return (source, destination)
    }

    /// Which frame pairs to compare, and how much each is worth.
    ///
    /// Adjacent pairs dominate because they have the most overlap; the
    /// half-window pair adds range, and the first-to-last pair is the longest
    /// baseline in the window and so gets the highest weight.
    private static func pairIndices(count: Int) -> [(Int, Int, CGFloat)] {
        guard count >= 2 else { return [] }
        var pairs: [(Int, Int, CGFloat)] = []
        for index in 0..<(count - 1) {
            pairs.append((index, index + 1, 1))
        }
        let half = max(count / 2, 2)
        if count > 4 {
            for index in 0..<(count - half) {
                pairs.append((index, index + half, 2))
            }
        }
        if count > 2 {
            pairs.append((0, count - 1, 3))
        }
        return pairs
    }

    // MARK: - Diagnostic ratios (display only)

    private static func centroid(_ points: [LandmarkPoint]?) -> CGPoint? {
        guard let points, !points.isEmpty else { return nil }
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.point.x, y: $0.y + $1.point.y) }
        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }

    private static func diagnosticRatios(from frame: LivenessFrame?) -> [String: CGFloat] {
        guard let frame else { return [:] }
        let grouped = Dictionary(grouping: frame.landmarks, by: \.region)
        var ratios: [String: CGFloat] = [:]
        if let iod = frame.interocularDistance, iod > 0 { ratios["interocular"] = iod }
        let xs = frame.landmarks.map(\.point.x)
        let ys = frame.landmarks.map(\.point.y)
        let faceWidth = (xs.max() ?? 0) - (xs.min() ?? 0)
        let faceHeight = (ys.max() ?? 0) - (ys.min() ?? 0)
        if faceWidth > 0, let iod = frame.interocularDistance, iod > 0 {
            ratios["eye / faceW"] = iod / faceWidth
        }
        if let left = centroid(grouped[.leftEye]), let right = centroid(grouped[.rightEye]),
           let nose = centroid(grouped[.nose]), faceHeight > 0 {
            let eyeMiddle = CGPoint(x: (left.x + right.x) / 2, y: (left.y + right.y) / 2)
            ratios["nose-eye / faceH"] = hypot(nose.x - eyeMiddle.x, nose.y - eyeMiddle.y) / faceHeight
            if let lips = grouped[.outerLips], !lips.isEmpty {
                let mouth = CGPoint(
                    x: lips.reduce(CGFloat(0)) { $0 + $1.point.x } / CGFloat(lips.count),
                    y: lips.reduce(CGFloat(0)) { $0 + $1.point.y } / CGFloat(lips.count)
                )
                ratios["nose-mouth / faceH"] = hypot(mouth.x - nose.x, mouth.y - nose.y) / faceHeight
                if faceWidth > 0 {
                    let mouthWidth = (lips.map(\.point.x).max() ?? 0) - (lips.map(\.point.x).min() ?? 0)
                    ratios["mouthW / faceW"] = mouthWidth / faceWidth
                }
                let noseToMouth = hypot(mouth.x - nose.x, mouth.y - nose.y)
                if noseToMouth > 0, let iod = frame.interocularDistance {
                    ratios["eye / nose-mouth"] = iod / noseToMouth
                }
            }
        }
        return ratios
    }

    // MARK: - Stats

    private static func weightedMedian(_ values: [CGFloat], weights: [CGFloat]) -> CGFloat? {
        guard !values.isEmpty, values.count == weights.count else { return nil }
        let sorted = zip(values, weights).sorted { $0.0 < $1.0 }
        let total = sorted.reduce(CGFloat(0)) { $0 + $1.1 }
        guard total > 0 else { return LandmarkGeometry.medianValue(values) }
        var accumulated: CGFloat = 0
        for (value, weight) in sorted {
            accumulated += weight
            if accumulated >= total / 2 { return value }
        }
        return sorted.last?.0
    }

    private static func clamp<T: Comparable>(_ value: T, _ lower: T, _ upper: T) -> T {
        min(max(value, lower), upper)
    }
}
