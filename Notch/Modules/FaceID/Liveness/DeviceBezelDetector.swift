import CoreGraphics
import Vision

struct DeviceBezelObservation {
    /// Largest device-plausible rectangle found this frame, in the same pixel
    /// space as `DetectedFace.boundingBox`.
    let rectangle: CGRect?
    /// Fraction of the face's bounding box area that falls inside `rectangle`.
    let faceOverlapFraction: CGFloat?

    static let none = DeviceBezelObservation(rectangle: nil, faceOverlapFraction: nil)
}

/// Looks for a device bezel — a phone or tablet — around the face.
///
/// Ported from Glance (`Liveness/DeviceBezelDetector.swift`, MIT © Jonathan
/// Zhou). It can only ever produce positive evidence of spoofing, never positive
/// evidence of liveness: a frame with no rectangle found is `nil`, which the cue
/// treats as an abstention rather than as proof of a real face.
enum DeviceBezelDetector {
    /// First-pass estimates rather than values validated against real footage —
    /// tune here if false positives or negatives show up in use.
    private static func makeRequest() -> VNDetectRectanglesRequest {
        let request = VNDetectRectanglesRequest()
        request.minimumConfidence = 0.6
        // A fraction of image area, not of width or height.
        request.minimumSize = 0.15
        request.maximumObservations = 3
        // Covers phone-in-portrait (0.35) through a near-square tablet crop (1.0).
        request.minimumAspectRatio = 0.35
        request.maximumAspectRatio = 1.0
        // Generous, so a phone held at a slight angle still registers.
        request.quadratureTolerance = 30
        return request
    }

    /// Synchronous and CPU-bound — call from a background task, same as
    /// `FaceDetector.detectFaces`.
    static func detect(in image: CGImage, faceBoundingBox: CGRect) -> DeviceBezelObservation {
        let request = makeRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil,
              let results = request.results, !results.isEmpty
        else { return .none }

        let imageSize = CGSize(width: image.width, height: image.height)
        let candidates = results.map { FaceDetector.convertToImageSpace($0.boundingBox, imageSize: imageSize) }
        // The largest candidate is assumed to be the device itself rather than a
        // smaller qualifying detail inside it.
        guard let largest = candidates.max(by: { $0.width * $0.height < $1.width * $1.height }) else {
            return .none
        }

        let faceArea = faceBoundingBox.width * faceBoundingBox.height
        guard faceArea > 0 else {
            return DeviceBezelObservation(rectangle: largest, faceOverlapFraction: nil)
        }
        let intersection = largest.intersection(faceBoundingBox)
        let overlap = (intersection.width * intersection.height) / faceArea
        return DeviceBezelObservation(rectangle: largest, faceOverlapFraction: overlap)
    }
}
