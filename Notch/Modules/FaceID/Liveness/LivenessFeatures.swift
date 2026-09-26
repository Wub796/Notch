import CoreGraphics
import Foundation
import Vision

/// The Vision-facing half of liveness: turns a recognition result into a
/// plain, Vision-free `LivenessFrame`, which is what keeps the decision logic
/// testable without a camera.
///
/// Ported from Glance (`Liveness/LivenessFeatures.swift`, MIT © Jonathan Zhou).
enum LivenessFeatureExtractor {
    /// Never fails — a face with no landmarks still yields a frame, and the cues
    /// that need landmarks abstain from it.
    ///
    /// - Parameter frame: the full camera frame, *not* `result.alignedImage`. A
    ///   112x112 warp has no room around the face for `DeviceBezelDetector` to
    ///   see a device edge, and no native pixels for the glare measurement.
    static func extract(
        from result: FaceRecognitionResult,
        frame: CGImage,
        faceCrop: CGImage? = nil,
        timestamp: Date = Date()
    ) -> LivenessFrame {
        let face = result.face
        let deviceOverlap = DeviceBezelDetector.detect(in: frame, faceBoundingBox: face.boundingBox)
            .faceOverlapFraction
        let glare = faceCrop.flatMap { GlareCueExtractor.extract(faceCrop: $0) }

        guard let landmarks = face.landmarks else {
            return LivenessFrame(
                timestamp: timestamp,
                landmarks: [],
                interocularDistance: nil,
                yaw: face.yaw,
                leftEyeAspectRatio: nil,
                rightEyeAspectRatio: nil,
                noseOffsetRatio: nil,
                hasReliableLandmarks: false,
                deviceOverlapFraction: deviceOverlap,
                glare: glare
            )
        }

        let imageSize = face.imageSize
        let points = LandmarkGeometry.allPoints(from: landmarks, imageSize: imageSize)
        let interocular = LandmarkGeometry.interocularDistance(from: landmarks, imageSize: imageSize)
        let leftEyeAspectRatio = landmarks.leftEye.flatMap {
            LandmarkGeometry.eyeAspectRatio(of: $0, imageSize: imageSize)
        }
        let rightEyeAspectRatio = landmarks.rightEye.flatMap {
            LandmarkGeometry.eyeAspectRatio(of: $0, imageSize: imageSize)
        }

        let eyeLeft = LandmarkGeometry.eyeCenter(
            pupil: landmarks.leftPupil, eye: landmarks.leftEye, imageSize: imageSize
        )
        let eyeRight = LandmarkGeometry.eyeCenter(
            pupil: landmarks.rightPupil, eye: landmarks.rightEye, imageSize: imageSize
        )

        var noseOffsetRatio: CGFloat?
        if let interocular, interocular > 0,
           let eyeLeft, let eyeRight,
           let nose = landmarks.nose,
           let noseCenter = LandmarkGeometry.centroid(of: nose, imageSize: imageSize) {
            let eyeMidlineX = (eyeLeft.x + eyeRight.x) / 2
            noseOffsetRatio = (noseCenter.x - eyeMidlineX) / interocular
        }

        return LivenessFrame(
            timestamp: timestamp,
            landmarks: points,
            interocularDistance: interocular,
            yaw: face.yaw,
            leftEyeAspectRatio: leftEyeAspectRatio,
            rightEyeAspectRatio: rightEyeAspectRatio,
            noseOffsetRatio: noseOffsetRatio,
            hasReliableLandmarks: result.alignmentTier == .fivePoint,
            deviceOverlapFraction: deviceOverlap,
            glare: glare
        )
    }
}
