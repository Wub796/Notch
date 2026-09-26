import CoreGraphics
import Foundation

struct FaceRecognitionResult {
    let embedding: [Float]
    /// What was actually fed to the embedder, for the debug readout to inspect.
    let alignedImage: CGImage
    let alignmentTier: AlignmentTier
    let quality: Float?
    let face: DetectedFace
}

enum FaceRecognitionPipelineError: LocalizedError {
    case noFaceDetected
    case alignmentFailed

    var errorDescription: String? {
        switch self {
        case .noFaceDetected: "No face detected in the frame."
        case .alignmentFailed: "Couldn't align the detected face."
        }
    }
}

/// An identity and how well the scanned face matched it.
struct ScoredIdentity {
    let identity: FaceIdentity
    /// Similarity against the identity's averaged template — the number the
    /// unlock threshold is applied to.
    let centroidSimilarity: Float
    /// Similarity against the single closest sample. Catches the case where
    /// averaging blurred together poses that should never have been blended.
    let maxSampleSimilarity: Float
}

/// Detect, align, embed, score.
///
/// Ported from Glance (`FaceRecognitionPipeline.swift`, MIT © Jonathan Zhou).
/// The only place that constructs a `FaceEmbedder`, so every consumer is
/// looking at the same model and a fallback is a single decision rather than
/// several.
final class FaceRecognitionPipeline {
    /// One per app. Partly so every consumer scores against the same model, and
    /// partly because loading ArcFace is the expensive part of starting a scan —
    /// a second instance would hold a second copy of a 7MB network to say the
    /// same thing.
    static let shared = FaceRecognitionPipeline()

    let embedder: FaceEmbedder

    /// Set when ArcFace failed to load and the weaker Vision feature print is
    /// in use instead. Surfaced in the UI, because a face enrolled under one
    /// embedder can never match under the other.
    let usingFallbackEmbedder: Bool
    let fallbackReason: String?

    init() {
        do {
            embedder = try ArcFaceEmbedder()
            usingFallbackEmbedder = false
            fallbackReason = nil
        } catch {
            embedder = VisionFeaturePrintEmbedder()
            usingFallbackEmbedder = true
            fallbackReason = error.localizedDescription
        }
    }

    // MARK: - Warm-up

    private let warmUpLock = NSLock()
    private var warmUpTask: Task<Void, Never>?
    private var isWarm = false

    /// Pays the one-time costs that a cold process would otherwise charge to the
    /// first scan's window.
    ///
    /// Both halves are lazy inside their frameworks: Core ML compiles the model's
    /// graph for its compute units on the first `prediction`, and Vision loads
    /// its detectors on the first `perform`. Either can take longer than a whole
    /// frame — longer than a scan can spare — so a scan that starts cold spends
    /// its window waiting for a compiler and reports "no face detected", then
    /// works perfectly on the very next attempt. That is exactly the shape of a
    /// first-scan-always-fails bug, and it is not a recognition problem at all.
    ///
    /// Idempotent and safe to call from anywhere: the work happens once, and
    /// every later call returns as soon as that first one is done.
    func warmUp() async {
        let pending: Task<Void, Never>? = warmUpLock.withLock {
            guard !isWarm else { return nil }
            if let warmUpTask { return warmUpTask }
            let embedder = self.embedder
            let task = Task.detached(priority: .utility) {
                Self.runWarmUp(embedder: embedder)
            }
            warmUpTask = task
            return task
        }
        guard let pending else { return }
        await pending.value
        warmUpLock.withLock {
            isWarm = true
            warmUpTask = nil
        }
    }

    /// One throwaway pass on a blank frame. What is being paid for is loading and
    /// compilation, so it deliberately does not matter what is in the image —
    /// and nothing here is kept.
    private static func runWarmUp(embedder: FaceEmbedder) {
        #if DEBUG
        let started = ContinuousClock.now
        #endif

        if let frame = blankImage(width: 640, height: 480) {
            _ = try? FaceDetector.detectFaces(in: frame)
        }
        if let aligned = blankImage(width: FaceAligner.outputSize, height: FaceAligner.outputSize) {
            _ = try? embedder.embedding(for: aligned)
        }

        #if DEBUG
        print("[FaceID] pipeline: warmed in \(ContinuousClock.now - started)")
        #endif
    }

    private static func blankImage(width: Int, height: Int) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else { return nil }
        // Mid-grey rather than black: a brighter frame is closer to what a lit
        // face looks like, so nothing in the load path can take a shortcut it
        // would not take on real frames.
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// Runs the whole chain on one frame. Synchronous and CPU-bound: callers
    /// run this from a background task.
    ///
    /// - Parameter previousBoundingBox: last frame's selected box, so a
    ///   continuous scan keeps its selection stuck to the same person instead
    ///   of re-picking between two similar faces every frame.
    func recognize(in frame: CGImage, preferNear previousBoundingBox: CGRect? = nil) throws -> FaceRecognitionResult {
        let faces = try FaceDetector.detectFaces(in: frame)
        guard let face = Self.selectDominantFace(in: faces, preferNear: previousBoundingBox) else {
            throw FaceRecognitionPipelineError.noFaceDetected
        }
        return try recognize(face, in: frame)
    }

    /// Aligns and embeds an already-chosen face. Enrollment uses this to bypass
    /// the prominence filter, so a face that is simply too far away reads as
    /// "move closer" rather than as "nobody there".
    func recognize(_ face: DetectedFace, in frame: CGImage) throws -> FaceRecognitionResult {
        let inputImage: CGImage
        let tier: AlignmentTier
        if embedder.requiresAlignment {
            guard let aligned = FaceAligner.align(face, from: frame) else {
                throw FaceRecognitionPipelineError.alignmentFailed
            }
            inputImage = aligned.image
            tier = aligned.tier
        } else {
            guard let cropped = FaceDetector.crop(face, from: frame) else {
                throw FaceRecognitionPipelineError.alignmentFailed
            }
            inputImage = cropped
            tier = .paddedCrop
        }

        let embedding = try embedder.embedding(for: inputImage)
        return FaceRecognitionResult(
            embedding: embedding,
            alignedImage: inputImage,
            alignmentTier: tier,
            quality: face.quality,
            face: face
        )
    }

    /// Largest face by area, with no prominence cutoff — unlike
    /// `selectDominantFace`, so enrollment can tell "too far" apart from
    /// "nobody there" and prompt accordingly.
    static func largestFace(in faces: [DetectedFace]) -> DetectedFace? {
        faces.max { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }
    }

    /// Below this fraction of the frame's width, a face is a bystander rather
    /// than a candidate — shared with the enrollment screen's "move closer"
    /// prompt. `nonisolated(unsafe)` because it is read from background work
    /// that can't touch `FaceIDSettings`.
    nonisolated(unsafe) static var minimumProminentFaceWidth: Float = 0.21

    /// Max normalized-coordinate drift between frames still counted as the same
    /// person.
    private static let continuityDistanceTolerance: CGFloat = 0.3

    /// Picks the person actually at the camera rather than a bystander behind
    /// them: filters out faces below `minimumProminentFaceWidth`, then prefers
    /// continuity with `previousBoundingBox` over raw largest-by-area, so two
    /// similarly sized faces can't flip-flop the selection frame to frame and
    /// starve the wrong-face streak of agreement.
    static func selectDominantFace(
        in faces: [DetectedFace],
        preferNear previousBoundingBox: CGRect? = nil
    ) -> DetectedFace? {
        let candidates = faces.filter {
            $0.normalizedBoundingBox.width >= CGFloat(minimumProminentFaceWidth)
        }
        guard !candidates.isEmpty else { return nil }

        if let previous = previousBoundingBox {
            let previousCenter = CGPoint(x: previous.midX, y: previous.midY)
            if let nearest = candidates.min(by: {
                distance(from: $0, to: previousCenter) < distance(from: $1, to: previousCenter)
            }),
               distance(from: nearest, to: previousCenter) < continuityDistanceTolerance {
                return nearest
            }
        }

        return candidates.max {
            $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height
        }
    }

    private static func distance(from face: DetectedFace, to point: CGPoint) -> CGFloat {
        let center = CGPoint(
            x: face.normalizedBoundingBox.midX,
            y: face.normalizedBoundingBox.midY
        )
        return hypot(center.x - point.x, center.y - point.y)
    }
}

extension FaceRecognitionPipeline {
    /// Sorted by centroid similarity, descending. Includes stale identities —
    /// ones enrolled under a different embedder — because `bestMatch` is what
    /// excludes them from actually matching, and the UI still wants to show
    /// them as stale rather than as absent.
    func score(_ embedding: [Float], against identities: [FaceIdentity]) -> [ScoredIdentity] {
        identities.compactMap { identity in
            guard let template = identity.template, !identity.samples.isEmpty else { return nil }
            let centroidSimilarity = FaceEmbedding.cosineSimilarity(embedding, template)
            let maxSampleSimilarity = identity.samples
                .map { FaceEmbedding.cosineSimilarity(embedding, $0.embedding) }
                .max() ?? centroidSimilarity
            return ScoredIdentity(
                identity: identity,
                centroidSimilarity: centroidSimilarity,
                maxSampleSimilarity: maxSampleSimilarity
            )
        }.sorted { $0.centroidSimilarity > $1.centroidSimilarity }
    }

    /// Shared by the test readout and the unlock path, so tuning never diverges
    /// between what the user sees and what the gate decides.
    ///
    /// Both the averaged template and the best single sample must clear the
    /// threshold, and there is deliberately no runner-up margin check: the same
    /// person can be enrolled twice under different appearances, so two of
    /// their own profiles legitimately score close together, and a margin check
    /// cannot tell that apart from two different people colliding.
    func bestMatch(in scored: [ScoredIdentity], threshold: Float) -> ScoredIdentity? {
        guard let first = scored.first, !first.identity.isStale(comparedTo: embedder) else { return nil }
        guard first.centroidSimilarity >= threshold, first.maxSampleSimilarity >= threshold else { return nil }
        return first
    }
}
