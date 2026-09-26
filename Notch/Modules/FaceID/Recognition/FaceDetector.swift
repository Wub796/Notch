import CoreGraphics
import Vision

/// A face Vision found in one frame, in the two coordinate spaces the rest of
/// the module needs.
struct DetectedFace {
    /// Pixel-space bounding box, top-left origin — ready to crop with.
    let boundingBox: CGRect
    /// Vision's original normalized box, kept as-is because it is the exact
    /// format `layerRectConverted(fromMetadataOutputRect:)` expects.
    let normalizedBoundingBox: CGRect
    /// 0...1 confidence from Vision that this is a face, which tracks image
    /// quality and pose suitability for recognition. `nil` if the quality
    /// request produced nothing for this face.
    let quality: Float?
    /// Head rotation in radians, when Vision could estimate it. Yaw drives the
    /// guided enrollment capture; roll and pitch are read by the liveness
    /// diagnostics.
    let yaw: Float?
    let roll: Float?
    let pitch: Float?
    /// Facial landmarks, when available. Feeds `FaceAligner` for the canonical
    /// 112x112 alignment ArcFace requires, and the liveness cues.
    let landmarks: VNFaceLandmarks2D?
    /// Needed by `landmarks.pointsInImage(_:)` to convert normalized landmark
    /// points into `boundingBox`'s pixel space.
    let imageSize: CGSize
}

/// Pure, synchronous, CPU-bound detection — deliberately a plain enum of static
/// functions so callers can run it on a background task.
///
/// Ported from Glance (`FaceDetector.swift`, MIT © Jonathan Zhou).
enum FaceDetector {
    /// Runs face rectangles, capture quality, and landmarks on one frame.
    ///
    /// Quality and landmarks are chained to the rectangle results via
    /// `inputFaceObservations` rather than run independently, so the three
    /// results correspond one to one in order — matching them back up by
    /// bounding-box float equality is fragile in exactly the case that matters,
    /// a face at the edge of the crop.
    static func detectFaces(in image: CGImage) throws -> [DetectedFace] {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        let rectanglesRequest = VNDetectFaceRectanglesRequest()
        try handler.perform([rectanglesRequest])
        let faceObservations = rectanglesRequest.results ?? []
        guard !faceObservations.isEmpty else { return [] }

        let qualityRequest = VNDetectFaceCaptureQualityRequest()
        let landmarksRequest = VNDetectFaceLandmarksRequest()
        qualityRequest.inputFaceObservations = faceObservations
        landmarksRequest.inputFaceObservations = faceObservations
        try handler.perform([qualityRequest, landmarksRequest])

        let qualityResults = qualityRequest.results ?? []
        let landmarkResults = landmarksRequest.results ?? []
        let imageSize = CGSize(width: image.width, height: image.height)

        return faceObservations.enumerated().map { index, observation in
            let pixelRect = convertToImageSpace(observation.boundingBox, imageSize: imageSize)
            return DetectedFace(
                boundingBox: pixelRect,
                normalizedBoundingBox: observation.boundingBox,
                quality: qualityResults.indices.contains(index) ? qualityResults[index].faceCaptureQuality : nil,
                yaw: observation.yaw?.floatValue,
                roll: observation.roll?.floatValue,
                pitch: observation.pitch?.floatValue,
                landmarks: landmarkResults.indices.contains(index) ? landmarkResults[index].landmarks : nil,
                imageSize: imageSize
            )
        }
    }

    /// Vision's normalized rect has its origin at the bottom left; `CGImage`
    /// cropping expects pixel coordinates with the origin at the top left. This
    /// flips the Y axis, and nothing else in the module should.
    static func convertToImageSpace(_ normalizedRect: CGRect, imageSize: CGSize) -> CGRect {
        let x = normalizedRect.origin.x * imageSize.width
        let width = normalizedRect.width * imageSize.width
        let height = normalizedRect.height * imageSize.height
        let y = (1 - normalizedRect.origin.y) * imageSize.height - height
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Crops `face` out of `image`, padded slightly around the detected box so
    /// the embedder sees a little context beyond eyes, nose, and mouth.
    static func crop(_ face: DetectedFace, from image: CGImage, paddingFraction: CGFloat = 0.2) -> CGImage? {
        let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let padX = face.boundingBox.width * paddingFraction
        let padY = face.boundingBox.height * paddingFraction
        let padded = face.boundingBox.insetBy(dx: -padX, dy: -padY).intersection(imageBounds)
        guard !padded.isEmpty else { return nil }
        return image.cropping(to: padded)
    }
}
