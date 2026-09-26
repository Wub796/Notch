import CoreGraphics
import Vision

/// Turns an aligned or cropped face into a vector that can be compared against
/// other faces.
///
/// Two implementations, deliberately: `ArcFaceEmbedder` is the real
/// face-discriminative model, and `VisionFeaturePrintEmbedder` is Apple's
/// built-in, which is only about 5-7% similarity apart between different
/// people — far too thin to gate an unlock on, but better than refusing to work
/// at all if the bundled model is missing.
///
/// Ported from Glance (`FaceEmbedder.swift`, MIT © Jonathan Zhou).
protocol FaceEmbedder: Sendable {
    /// Shown in the UI so it is obvious which embedder produced a saved sample.
    var name: String { get }
    /// Persisted alongside every sample. `FaceIDSecureFaceStore` and
    /// `FaceIdentity.isStale(comparedTo:)` use it to refuse comparing across
    /// different embedders, which would otherwise not error — it would just
    /// produce confident nonsense.
    var modelIdentifier: String { get }
    /// Declared output length, for cross-model mismatch detection without
    /// running an embedding first.
    var embeddingDimension: Int { get }
    /// Whether this embedder needs a canonically-aligned 112x112 input
    /// (ArcFace) as opposed to tolerating a loose crop (Vision feature print).
    var requiresAlignment: Bool { get }
    func embedding(for face: CGImage) throws -> [Float]
}

enum FaceEmbedderError: LocalizedError {
    case noObservation
    case unsupportedElementType

    var errorDescription: String? {
        switch self {
        case .noObservation:
            "Vision didn't produce a feature print for this image."
        case .unsupportedElementType:
            "The feature print used an unexpected element type."
        }
    }
}

struct VisionFeaturePrintEmbedder: FaceEmbedder {
    let name = "Vision Feature Print"
    let modelIdentifier = "vision-feature-print-v1"
    /// A nominal hint only. `modelIdentifier` is the real discriminator the
    /// store relies on.
    let embeddingDimension = 2048
    let requiresAlignment = false

    func embedding(for face: CGImage) throws -> [Float] {
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: face, options: [:])
        try handler.perform([request])

        guard let observation = request.results?.first as? VNFeaturePrintObservation else {
            throw FaceEmbedderError.noObservation
        }
        return try Self.floatVector(from: observation)
    }

    /// Decodes Vision's raw bytes and element type into `[Float]` so it can
    /// persist as plain JSON and be averaged with the other samples.
    private static func floatVector(from observation: VNFeaturePrintObservation) throws -> [Float] {
        let count = observation.elementCount
        switch observation.elementType {
        case .float:
            var result = [Float](repeating: 0, count: count)
            observation.data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                let buffer = raw.bindMemory(to: Float.self)
                for index in 0..<count { result[index] = buffer[index] }
            }
            return result
        case .double:
            var result = [Float](repeating: 0, count: count)
            observation.data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                let buffer = raw.bindMemory(to: Double.self)
                for index in 0..<count { result[index] = Float(buffer[index]) }
            }
            return result
        default:
            throw FaceEmbedderError.unsupportedElementType
        }
    }
}

/// The comparisons the whole feature is built out of.
enum FaceEmbedding {
    /// Scales `vector` to unit length. Matters as soon as vectors are combined
    /// — see `average`.
    static func l2Normalized(_ vector: [Float]) -> [Float] {
        let norm = sqrt(vector.reduce(Float(0)) { $0 + $1 * $1 })
        guard norm > 0 else { return vector }
        return vector.map { $0 / norm }
    }

    /// Cosine similarity, range -1...1. The raw value ArcFace thresholds are
    /// quoted in, and what `matchThreshold` is expressed as.
    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        for index in 0..<a.count {
            dot += a[index] * b[index]
            normA += a[index] * a[index]
            normB += b[index] * b[index]
        }
        guard normA > 0, normB > 0 else { return 0 }
        return dot / (normA.squareRoot() * normB.squareRoot())
    }

    /// A 0-100 readout of the same number, for the UI. Deliberately not the
    /// value anything compares against: percentages read as "87% sure" when
    /// they are a cosine distance, so the threshold is always applied to the
    /// raw similarity.
    static func similarityPercent(_ a: [Float], _ b: [Float]) -> Double {
        let similarity = cosineSimilarity(a, b)
        return Double((similarity + 1) / 2) * 100
    }

    /// Normalize each sample, average, then renormalize — a plain element-wise
    /// mean would let one sample with a larger magnitude silently dominate the
    /// template it contributes to.
    static func average(_ vectors: [[Float]]) -> [Float]? {
        guard let first = vectors.first, !first.isEmpty else { return nil }
        let count = Float(vectors.count)
        var sum = [Float](repeating: 0, count: first.count)
        for vector in vectors where vector.count == first.count {
            let normalized = l2Normalized(vector)
            for index in 0..<normalized.count { sum[index] += normalized[index] }
        }
        let mean = sum.map { $0 / count }
        return l2Normalized(mean)
    }
}
