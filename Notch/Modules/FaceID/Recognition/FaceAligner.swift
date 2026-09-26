import CoreGraphics
import Vision

struct AlignedFace {
    /// 112x112, canonically aligned.
    let image: CGImage
    let tier: AlignmentTier
}

/// How a face was prepared for the embedder, best to worst. Recorded because
/// the liveness cues need to know whether the landmarks were trustworthy: a
/// frame that fell back to a padded crop has no landmarks to measure, and a
/// cue that can't see must abstain rather than vote.
enum AlignmentTier: String {
    case fivePoint = "5-point"
    case twoPoint = "2-point (eyes only)"
    case paddedCrop = "padded crop (no alignment)"
}

/// Warps a detected face into the canonical pose ArcFace expects.
///
/// Ported from Glance (`FaceAligner.swift`, MIT © Jonathan Zhou). The whole
/// reason this exists: ArcFace was trained on faces aligned to a fixed
/// template, so feeding it a loose crop doesn't degrade gracefully — it
/// produces an embedding that is confidently wrong, which is worse than no
/// match at all.
enum FaceAligner {
    static let outputSize = 112

    /// The standard ArcFace 112x112 template: left eye, right eye, nose, left
    /// mouth corner, right mouth corner. "Left" and "right" here are on-screen,
    /// not anatomical — see the ordering fix in `fivePoints(from:imageSize:)`.
    private static let referencePoints: [CGPoint] = [
        CGPoint(x: 38.2946, y: 51.6963),
        CGPoint(x: 73.5318, y: 51.5014),
        CGPoint(x: 56.0252, y: 71.7366),
        CGPoint(x: 41.5493, y: 92.3655),
        CGPoint(x: 70.7299, y: 92.2041),
    ]
    private static let eyeReferencePoints = Array(referencePoints[0...1])

    /// Best effort, in descending order: 5-point landmarks, then 2-point (eyes
    /// only), then a padded crop with no alignment at all. `nil` only if even
    /// the crop fails.
    static func align(_ face: DetectedFace, from image: CGImage) -> AlignedFace? {
        let imageSize = CGSize(width: image.width, height: image.height)

        if let landmarks = face.landmarks,
           let points = fivePoints(from: landmarks, imageSize: imageSize),
           let warped = warp(image, sourcePoints: points, destinationPoints: referencePoints) {
            return AlignedFace(image: warped, tier: .fivePoint)
        }

        if let landmarks = face.landmarks,
           let eyes = twoPoints(from: landmarks, imageSize: imageSize),
           let warped = warp(image, sourcePoints: eyes, destinationPoints: eyeReferencePoints) {
            return AlignedFace(image: warped, tier: .twoPoint)
        }

        guard let cropped = FaceDetector.crop(face, from: image),
              let resized = resize(cropped, to: outputSize)
        else { return nil }
        return AlignedFace(image: resized, tier: .paddedCrop)
    }

    // MARK: - Landmark extraction
    //
    // Point, centroid, eye-center, and transform math all lives in
    // `LandmarkGeometry`, shared with the liveness analyzer so the two can't
    // drift apart on what "the eye center" means.

    private static func fivePoints(from landmarks: VNFaceLandmarks2D, imageSize: CGSize) -> [CGPoint]? {
        guard let eyeA = LandmarkGeometry.eyeCenter(
                  pupil: landmarks.leftPupil, eye: landmarks.leftEye, imageSize: imageSize
              ),
              let eyeB = LandmarkGeometry.eyeCenter(
                  pupil: landmarks.rightPupil, eye: landmarks.rightEye, imageSize: imageSize
              ),
              let nose = landmarks.nose,
              let noseCenter = LandmarkGeometry.centroid(of: nose, imageSize: imageSize),
              let outerLips = landmarks.outerLips
        else { return nil }

        // Vision's leftEye/rightEye are anatomical, not on-screen, so the
        // points are sorted by x rather than trusted by label.
        let imageLeftEye = eyeA.x <= eyeB.x ? eyeA : eyeB
        let imageRightEye = eyeA.x <= eyeB.x ? eyeB : eyeA

        let lipPoints = LandmarkGeometry.imagePoints(of: outerLips, imageSize: imageSize)
        guard let imageLeftMouth = lipPoints.min(by: { $0.x < $1.x }),
              let imageRightMouth = lipPoints.max(by: { $0.x < $1.x })
        else { return nil }

        return [imageLeftEye, imageRightEye, noseCenter, imageLeftMouth, imageRightMouth]
    }

    private static func twoPoints(from landmarks: VNFaceLandmarks2D, imageSize: CGSize) -> [CGPoint]? {
        guard let eyeA = LandmarkGeometry.eyeCenter(
                  pupil: landmarks.leftPupil, eye: landmarks.leftEye, imageSize: imageSize
              ),
              let eyeB = LandmarkGeometry.eyeCenter(
                  pupil: landmarks.rightPupil, eye: landmarks.rightEye, imageSize: imageSize
              )
        else { return nil }
        return eyeA.x <= eyeB.x ? [eyeA, eyeB] : [eyeB, eyeA]
    }

    // MARK: - Warp

    /// Landmark points arrive in top-left/y-down space but are flipped before
    /// solving, because `CGContext` is bottom-left/y-up. The image itself needs
    /// no flip: `CGContext.draw(_:in:)` already handles a `CGImage`'s row order.
    private static func warp(
        _ image: CGImage,
        sourcePoints: [CGPoint],
        destinationPoints: [CGPoint]
    ) -> CGImage? {
        let imageHeight = CGFloat(image.height)
        let sourceFlipped = sourcePoints.map { CGPoint(x: $0.x, y: imageHeight - $0.y) }
        let destinationFlipped = destinationPoints.map { CGPoint(x: $0.x, y: CGFloat(outputSize) - $0.y) }

        guard let transform = LandmarkGeometry.solveSimilarityTransform(
            from: sourceFlipped, to: destinationFlipped
        ) else { return nil }

        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: outputSize, height: outputSize,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        context.concatenate(transform)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

        return context.makeImage()
    }

    private static func resize(_ image: CGImage, to size: Int) -> CGImage? {
        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        return context.makeImage()
    }
}
