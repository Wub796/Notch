import CoreGraphics
import Vision

/// Every landmark region this app reads from `VNFaceLandmarks2D`. Includes
/// regions `FaceAligner` never needs — the liveness check samples more of them
/// for its residual-coherence measurements.
enum LandmarkRegion: String, CaseIterable, Hashable {
    case leftEye, rightEye
    case leftEyebrow, rightEyebrow
    case nose, noseCrest
    case outerLips, innerLips
    case faceContour, medianLine
}

/// One landmark point, tagged with where it came from. `indexInRegion` is what
/// lets two frames' points be paired up for a cross-frame comparison.
struct LandmarkPoint {
    let point: CGPoint
    let region: LandmarkRegion
    let indexInRegion: Int
}

/// The landmark math shared by `FaceAligner` and the liveness analyzer —
/// deliberately one copy, because the two disagreeing about what a point means
/// is a bug that shows up as a mysterious similarity shift rather than as a
/// compile error.
///
/// Ported from Glance (`Liveness/LandmarkGeometry.swift`, MIT © Jonathan Zhou).
enum LandmarkGeometry {
    /// Vision returns points in bottom-left-origin, y-up space; this flips them
    /// to top-left/y-down to match `DetectedFace.boundingBox`.
    static func imagePoints(of region: VNFaceLandmarkRegion2D, imageSize: CGSize) -> [CGPoint] {
        region.pointsInImage(imageSize: imageSize).map { CGPoint(x: $0.x, y: imageSize.height - $0.y) }
    }

    static func centroid(of region: VNFaceLandmarkRegion2D, imageSize: CGSize) -> CGPoint? {
        let points = imagePoints(of: region, imageSize: imageSize)
        guard !points.isEmpty else { return nil }
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }

    /// Prefers the pupil landmark (a precise detected point) over the eye
    /// outline's centroid, which is only an approximation derived from eyelid
    /// boundary points.
    static func eyeCenter(
        pupil: VNFaceLandmarkRegion2D?,
        eye: VNFaceLandmarkRegion2D?,
        imageSize: CGSize
    ) -> CGPoint? {
        if let pupil, let center = centroid(of: pupil, imageSize: imageSize) { return center }
        if let eye { return centroid(of: eye, imageSize: imageSize) }
        return nil
    }

    /// Distance between the two eye centers — the normalization scale used
    /// throughout liveness scoring, so every measurement stays comparable
    /// regardless of how far the face is from the camera.
    static func interocularDistance(from landmarks: VNFaceLandmarks2D, imageSize: CGSize) -> CGFloat? {
        guard let left = eyeCenter(
                  pupil: landmarks.leftPupil, eye: landmarks.leftEye, imageSize: imageSize
              ),
              let right = eyeCenter(
                  pupil: landmarks.rightPupil, eye: landmarks.rightEye, imageSize: imageSize
              )
        else { return nil }
        return hypot(left.x - right.x, left.y - right.y)
    }

    /// Height over width of a landmark region's bounding box — a stand-in for
    /// the classic 6-point eye aspect ratio, since Vision's point count is not
    /// the fixed six that formula assumes.
    private static func boundingBoxAspectRatio(
        of region: VNFaceLandmarkRegion2D,
        imageSize: CGSize
    ) -> CGFloat? {
        let points = imagePoints(of: region, imageSize: imageSize)
        guard points.count >= 3,
              let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max()
        else { return nil }
        let width = maxX - minX
        guard width > 0 else { return nil }
        return (maxY - minY) / width
    }

    static func eyeAspectRatio(of eyeRegion: VNFaceLandmarkRegion2D, imageSize: CGSize) -> CGFloat? {
        boundingBoxAspectRatio(of: eyeRegion, imageSize: imageSize)
    }

    static func region(_ region: LandmarkRegion, of landmarks: VNFaceLandmarks2D) -> VNFaceLandmarkRegion2D? {
        switch region {
        case .leftEye: landmarks.leftEye
        case .rightEye: landmarks.rightEye
        case .leftEyebrow: landmarks.leftEyebrow
        case .rightEyebrow: landmarks.rightEyebrow
        case .nose: landmarks.nose
        case .noseCrest: landmarks.noseCrest
        case .outerLips: landmarks.outerLips
        case .innerLips: landmarks.innerLips
        case .faceContour: landmarks.faceContour
        case .medianLine: landmarks.medianLine
        }
    }

    /// Every point Vision detected, tagged by region and position so a later
    /// frame's points can be matched back up. A region missing in this frame
    /// simply contributes nothing.
    static func allPoints(from landmarks: VNFaceLandmarks2D, imageSize: CGSize) -> [LandmarkPoint] {
        var result: [LandmarkPoint] = []
        for regionCase in LandmarkRegion.allCases {
            guard let vnRegion = region(regionCase, of: landmarks) else { continue }
            let points = imagePoints(of: vnRegion, imageSize: imageSize)
            for (index, point) in points.enumerated() {
                result.append(LandmarkPoint(point: point, region: regionCase, indexInRegion: index))
            }
        }
        return result
    }

    // MARK: - Homography (projective transform)
    //
    // Used by the liveness geometry cue. A flat presentation — a photo, or a
    // phone screen held up — can only ever produce motion a homography explains
    // exactly; a real face's protruding features leave residual error that a
    // homography fitted to the flat regions cannot absorb.

    struct Homography {
        let h11, h12, h13, h21, h22, h23, h31, h32, h33: CGFloat

        func apply(_ point: CGPoint) -> CGPoint {
            let w = h31 * point.x + h32 * point.y + h33
            guard abs(w) > 1e-12 else { return point }
            return CGPoint(
                x: (h11 * point.x + h12 * point.y + h13) / w,
                y: (h21 * point.x + h22 * point.y + h23) / w
            )
        }
    }

    /// Hartley-normalized DLT homography with `h33 = 1`, solved as an 8x8
    /// normal-equation system. Needs at least four correspondences; six or more
    /// is the practical floor callers use, so the fit is overdetermined.
    static func solveHomography(
        from sourcePoints: [CGPoint],
        to destinationPoints: [CGPoint],
        weights: [CGFloat]? = nil
    ) -> Homography? {
        guard sourcePoints.count == destinationPoints.count, sourcePoints.count >= 4 else { return nil }
        if let weights {
            guard weights.count == sourcePoints.count else { return nil }
        }

        guard let sourceTransform = normalizingTransform(sourcePoints),
              let destinationTransform = normalizingTransform(destinationPoints)
        else { return nil }

        let count = sourcePoints.count
        var ata = Array(repeating: Array(repeating: CGFloat(0), count: 8), count: 8)
        var atb = Array(repeating: CGFloat(0), count: 8)

        for index in 0..<count {
            let source = applyNormalization(sourcePoints[index], sourceTransform)
            let destination = applyNormalization(destinationPoints[index], destinationTransform)
            let weight = (weights?[index] ?? 1).squareRoot()
            guard weight > 0 else { continue }
            let x = source.x, y = source.y, u = destination.x, v = destination.y
            // Two DLT rows, with h33 fixed at 1:
            // [x y 1 0 0 0 -u x -u y] · h = u
            // [0 0 0 x y 1 -v x -v y] · h = v
            let row0: [CGFloat] = [x * weight, y * weight, weight, 0, 0, 0, -u * x * weight, -u * y * weight]
            let row1: [CGFloat] = [0, 0, 0, x * weight, y * weight, weight, -v * x * weight, -v * y * weight]
            accumulateNormalEquations(row0, u * weight, into: &ata, atb: &atb)
            accumulateNormalEquations(row1, v * weight, into: &ata, atb: &atb)
        }

        guard let solution = solveLinearSystem(ata, atb) else { return nil }
        let normalized = Homography(
            h11: solution[0], h12: solution[1], h13: solution[2],
            h21: solution[3], h22: solution[4], h23: solution[5],
            h31: solution[6], h32: solution[7], h33: 1
        )
        return denormalizeHomography(normalized, source: sourceTransform, destination: destinationTransform)
    }

    /// Two-pass IRLS around `solveHomography` with a Tukey biweight, so one
    /// wildly jittered landmark can't drag the fitted plane around. The cutoff
    /// comes from the full set's median, which keeps a smiling mouth in the fit
    /// rather than letting an underconstrained homography absorb real parallax
    /// as if it were noise.
    static func solveRobustHomography(
        from sourcePoints: [CGPoint],
        to destinationPoints: [CGPoint]
    ) -> Homography? {
        guard var current = solveHomography(from: sourcePoints, to: destinationPoints) else { return nil }
        for _ in 0..<2 {
            let residuals = zip(sourcePoints, destinationPoints).map {
                hypot($1.x - current.apply($0).x, $1.y - current.apply($0).y)
            }
            let scale = max(medianValue(residuals), 1e-4)
            let cutoff = 4.685 * 1.4826 * scale
            var weights: [CGFloat] = residuals.map { residual in
                let u = residual / cutoff
                if u >= 1 { return 0 }
                let t = 1 - u * u
                return t * t
            }
            let inliers = weights.filter { $0 > 0 }.count
            if inliers < 6 {
                weights = Array(repeating: 1, count: sourcePoints.count)
            }
            if let refined = solveHomography(from: sourcePoints, to: destinationPoints, weights: weights) {
                current = refined
            }
        }
        return current
    }

    private struct SimilarityNorm {
        let scale: CGFloat
        let centerX: CGFloat
        let centerY: CGFloat
    }

    /// Translate to the centroid, then scale so the mean distance from the
    /// origin is sqrt(2) — Hartley normalization, which is what keeps the
    /// 8x8 system well conditioned for points measured in pixels.
    private static func normalizingTransform(_ points: [CGPoint]) -> SimilarityNorm? {
        let count = CGFloat(points.count)
        guard count > 0 else { return nil }
        let centerX = points.reduce(CGFloat(0)) { $0 + $1.x } / count
        let centerY = points.reduce(CGFloat(0)) { $0 + $1.y } / count
        let meanDistance = points.reduce(CGFloat(0)) {
            $0 + hypot($1.x - centerX, $1.y - centerY)
        } / count
        guard meanDistance > 1e-8 else { return nil }
        return SimilarityNorm(
            scale: CGFloat(2).squareRoot() / meanDistance,
            centerX: centerX,
            centerY: centerY
        )
    }

    private static func applyNormalization(_ point: CGPoint, _ transform: SimilarityNorm) -> CGPoint {
        CGPoint(
            x: transform.scale * (point.x - transform.centerX),
            y: transform.scale * (point.y - transform.centerY)
        )
    }

    /// `H = Tdst⁻¹ · Hn · Tsrc` — undoes the normalization on the solved matrix.
    private static func denormalizeHomography(
        _ homography: Homography,
        source: SimilarityNorm,
        destination: SimilarityNorm
    ) -> Homography {
        let s1 = source.scale, cx1 = source.centerX, cy1 = source.centerY
        let s2 = destination.scale, cx2 = destination.centerX, cy2 = destination.centerY
        let sourceTransform = (s1, CGFloat(0), -s1 * cx1, CGFloat(0), s1, -s1 * cy1, CGFloat(0), CGFloat(0), CGFloat(1))
        let normalized = (
            homography.h11, homography.h12, homography.h13,
            homography.h21, homography.h22, homography.h23,
            homography.h31, homography.h32, homography.h33
        )
        let combined = multiply3x3(normalized, sourceTransform)
        let destinationInverse = (1 / s2, CGFloat(0), cx2, CGFloat(0), 1 / s2, cy2, CGFloat(0), CGFloat(0), CGFloat(1))
        let result = multiply3x3(destinationInverse, combined)
        return Homography(
            h11: result.0, h12: result.1, h13: result.2,
            h21: result.3, h22: result.4, h23: result.5,
            h31: result.6, h32: result.7, h33: result.8
        )
    }

    private static func multiply3x3(
        _ a: (CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat),
        _ b: (CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)
    ) -> (CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat) {
        (
            a.0 * b.0 + a.1 * b.3 + a.2 * b.6,
            a.0 * b.1 + a.1 * b.4 + a.2 * b.7,
            a.0 * b.2 + a.1 * b.5 + a.2 * b.8,
            a.3 * b.0 + a.4 * b.3 + a.5 * b.6,
            a.3 * b.1 + a.4 * b.4 + a.5 * b.7,
            a.3 * b.2 + a.4 * b.5 + a.5 * b.8,
            a.6 * b.0 + a.7 * b.3 + a.8 * b.6,
            a.6 * b.1 + a.7 * b.4 + a.8 * b.7,
            a.6 * b.2 + a.7 * b.5 + a.8 * b.8
        )
    }

    private static func accumulateNormalEquations(
        _ row: [CGFloat],
        _ b: CGFloat,
        into ata: inout [[CGFloat]],
        atb: inout [CGFloat]
    ) {
        for i in 0..<8 {
            atb[i] += row[i] * b
            for j in 0..<8 {
                ata[i][j] += row[i] * row[j]
            }
        }
    }

    /// Gaussian elimination with partial pivoting. `nil` if the system is singular.
    static func solveLinearSystem(_ matrix: [[CGFloat]], _ rhs: [CGFloat]) -> [CGFloat]? {
        let count = rhs.count
        guard matrix.count == count, matrix.allSatisfy({ $0.count == count }) else { return nil }
        var a = matrix
        var b = rhs
        for k in 0..<count {
            var pivot = k
            var largest = abs(a[k][k])
            if k + 1 < count {
                for i in (k + 1)..<count {
                    let value = abs(a[i][k])
                    if value > largest {
                        largest = value
                        pivot = i
                    }
                }
            }
            if largest < 1e-12 { return nil }
            if pivot != k {
                a.swapAt(k, pivot)
                b.swapAt(k, pivot)
            }
            let diagonal = a[k][k]
            if k + 1 < count {
                for i in (k + 1)..<count {
                    let factor = a[i][k] / diagonal
                    for j in k..<count {
                        a[i][j] -= factor * a[k][j]
                    }
                    b[i] -= factor * b[k]
                }
            }
        }
        var solution = [CGFloat](repeating: 0, count: count)
        for i in stride(from: count - 1, through: 0, by: -1) {
            var sum = b[i]
            if i + 1 < count {
                for j in (i + 1)..<count {
                    sum -= a[i][j] * solution[j]
                }
            }
            guard abs(a[i][i]) > 1e-12 else { return nil }
            solution[i] = sum / a[i][i]
        }
        return solution
    }

    static func medianValue(_ values: [CGFloat]) -> CGFloat {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    // MARK: - Similarity transform

    /// Closed-form least-squares similarity transform — rotation, uniform
    /// scale, translation — via 2D Procrustes in complex-number form, so no SVD
    /// is needed. This is exactly the model a flat presentation is limited to;
    /// motion it can't explain is the non-rigid residual the liveness geometry
    /// cue measures.
    static func solveSimilarityTransform(
        from sourcePoints: [CGPoint],
        to destinationPoints: [CGPoint]
    ) -> CGAffineTransform? {
        guard sourcePoints.count == destinationPoints.count, sourcePoints.count >= 2 else { return nil }

        let count = CGFloat(sourcePoints.count)
        let sourceSum = sourcePoints.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        let sourceMean = CGPoint(x: sourceSum.x / count, y: sourceSum.y / count)
        let destinationSum = destinationPoints.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        let destinationMean = CGPoint(x: destinationSum.x / count, y: destinationSum.y / count)

        var numeratorReal: CGFloat = 0
        var numeratorImaginary: CGFloat = 0
        var denominator: CGFloat = 0
        for index in 0..<sourcePoints.count {
            let p = CGPoint(x: sourcePoints[index].x - sourceMean.x, y: sourcePoints[index].y - sourceMean.y)
            let q = CGPoint(
                x: destinationPoints[index].x - destinationMean.x,
                y: destinationPoints[index].y - destinationMean.y
            )
            // q * conj(p) = (qx + i·qy)(px − i·py) = (qx·px + qy·py) + i(qy·px − qx·py)
            numeratorReal += q.x * p.x + q.y * p.y
            numeratorImaginary += q.y * p.x - q.x * p.y
            denominator += p.x * p.x + p.y * p.y
        }
        guard denominator > 0 else { return nil }

        // scale·cos(theta), scale·sin(theta)
        let sc = numeratorReal / denominator
        let ss = numeratorImaginary / denominator

        // dst = R · scale · (src − srcMean) + dstMean, expanded into
        // CGAffineTransform's convention:
        //   x' = a·x + c·y + tx
        //   y' = b·x + d·y + ty
        let a = sc, b = ss, c = -ss, d = sc
        let tx = destinationMean.x - (a * sourceMean.x + c * sourceMean.y)
        let ty = destinationMean.y - (b * sourceMean.x + d * sourceMean.y)
        return CGAffineTransform(a: a, b: b, c: c, d: d, tx: tx, ty: ty)
    }
}
