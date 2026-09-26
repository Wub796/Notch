import CoreGraphics
import CoreML
import CoreVideo

/// The real recognition model: ArcFace (w600k_mbf), bundled as
/// `ArcFace.mlpackage` and compiled by Xcode into a `.mlmodelc` inside the app.
///
/// Requires a canonically-aligned 112x112 input — see `FaceAligner`. Unlike the
/// Vision feature print, accuracy depends entirely on that alignment.
///
/// Ported from Glance (`ArcFaceEmbedder.swift`, MIT © Jonathan Zhou). The model
/// weights originate from InsightFace's w600k_mbf ArcFace checkpoint; see
/// `THIRD-PARTY-NOTICES.md` at the repository root for the terms that apply to
/// them, which are separate from the MIT licence on the surrounding code.
final class ArcFaceEmbedder: FaceEmbedder, @unchecked Sendable {
    let name = "ArcFace (w600k_mbf)"
    let modelIdentifier = "arcface-w600k_mbf-v1"
    let embeddingDimension = 512
    let requiresAlignment = true

    enum ArcFaceEmbedderError: LocalizedError {
        case modelNotFound
        case modelLoadFailed(String)
        case pixelBufferCreationFailed
        case unexpectedInputSize(got: (Int, Int), expected: Int)
        case unexpectedOutput(String)

        var errorDescription: String? {
            switch self {
            case .modelNotFound:
                "ArcFace.mlpackage isn't in the app bundle. It should be picked up automatically from "
                    + "Notch/Modules/FaceID/Resources — check that folder is still in the target."
            case .modelLoadFailed(let detail):
                "Failed to load the ArcFace Core ML model: \(detail)"
            case .pixelBufferCreationFailed:
                "Couldn't prepare the aligned face image for Core ML."
            case .unexpectedInputSize(let got, let expected):
                "ArcFace expects a \(expected)x\(expected) aligned image, got \(got.0)x\(got.1). "
                    + "Run the face through FaceAligner first."
            case .unexpectedOutput(let detail):
                "The ArcFace model produced an unexpected output: \(detail)"
            }
        }
    }

    private static let inputSize = FaceAligner.outputSize
    private static let inputName = "input_image"
    private static let outputName = "embedding"

    // Loaded once and reused: model load dominates a single inference.
    private let model: MLModel
    private let pixelBufferPool: CVPixelBufferPool

    /// Throws immediately if the model isn't bundled, so callers can fall back
    /// to `VisionFeaturePrintEmbedder` instead of failing every scan.
    init() throws {
        guard let modelURL = Self.locateModel() else {
            throw ArcFaceEmbedderError.modelNotFound
        }
        let loadable = try Self.loadableURL(for: modelURL)

        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all

        do {
            model = try MLModel(contentsOf: loadable, configuration: configuration)
        } catch {
            throw ArcFaceEmbedderError.modelLoadFailed(error.localizedDescription)
        }

        guard let pool = Self.makePixelBufferPool(size: Self.inputSize) else {
            throw ArcFaceEmbedderError.pixelBufferCreationFailed
        }
        pixelBufferPool = pool
    }

    /// Both names are checked in case the model was added under a different
    /// filename at some point — and both containers, because which one is in the
    /// bundle is Xcode's decision rather than the source tree's.
    ///
    /// The compiled form is the one Xcode's Core ML build phase produces. The
    /// package is the fallback for the other possible outcome of a folder-based
    /// project — the package copied in as a resource, uncompiled — which is worth
    /// covering because the alternative is not an error the user can see: the
    /// pipeline quietly drops to the Vision feature print, and every scan then
    /// compares apples to oranges against faces enrolled under ArcFace.
    private static func locateModel() -> URL? {
        let names = ["ArcFace", "w600k_mbf"]
        for name in names {
            if let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc") {
                return url
            }
        }
        for name in names {
            if let url = Bundle.main.url(forResource: name, withExtension: "mlpackage") {
                return url
            }
        }
        // Last resort: walk the bundle, because a synchronized folder can copy
        // the package into a subdirectory of the resource root rather than into
        // it. Nested frameworks are skipped — they cannot contain our model, and
        // walking one on first scan would cost more than the search is worth.
        guard let root = Bundle.main.resourceURL,
              let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        else { return nil }
        for case let url as URL in walk {
            let ext = url.pathExtension
            if ext == "framework" || ext == "app" || ext == "bundle" {
                walk.skipDescendants()
                continue
            }
            guard ext == "mlmodelc" || ext == "mlpackage" else { continue }
            if names.contains(url.deletingPathExtension().lastPathComponent) {
                return url
            }
        }
        return nil
    }

    /// `MLModel(contentsOf:)` loads a *compiled* model. A package that reached
    /// the bundle without being compiled is compiled here — once, on first load,
    /// into Core ML's own cache directory — rather than throwing and losing
    /// recognition to the fallback embedder over a packaging detail.
    private static func loadableURL(for url: URL) throws -> URL {
        let ext = url.pathExtension
        guard ext == "mlpackage" || ext == "mlmodel" else { return url }
        do {
            return try MLModel.compileModel(at: url)
        } catch {
            throw ArcFaceEmbedderError.modelLoadFailed(error.localizedDescription)
        }
    }

    private static func makePixelBufferPool(size: Int) -> CVPixelBufferPool? {
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: size,
            kCVPixelBufferHeightKey as String: size,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
        ]
        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &pool)
        return pool
    }

    /// `MLModel.prediction(from:)` is synchronous and blocking — callers run
    /// this off the main thread.
    func embedding(for face: CGImage) throws -> [Float] {
        guard face.width == Self.inputSize, face.height == Self.inputSize else {
            throw ArcFaceEmbedderError.unexpectedInputSize(
                got: (face.width, face.height),
                expected: Self.inputSize
            )
        }

        var pixelBufferOut: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferPool, &pixelBufferOut)
        guard status == kCVReturnSuccess, let pixelBuffer = pixelBufferOut else {
            throw ArcFaceEmbedderError.pixelBufferCreationFailed
        }
        try Self.render(face, into: pixelBuffer)

        let input = try MLDictionaryFeatureProvider(
            dictionary: [Self.inputName: MLFeatureValue(pixelBuffer: pixelBuffer)]
        )
        let output = try model.prediction(from: input)

        guard let multiArray = output.featureValue(for: Self.outputName)?.multiArrayValue else {
            throw ArcFaceEmbedderError.unexpectedOutput("no '\(Self.outputName)' output found")
        }
        guard multiArray.count == embeddingDimension else {
            throw ArcFaceEmbedderError.unexpectedOutput(
                "expected \(embeddingDimension) floats, got \(multiArray.count)"
            )
        }

        let raw = Self.floatVector(from: multiArray)
        return FaceEmbedding.l2Normalized(raw)
    }

    private static func render(_ image: CGImage, into pixelBuffer: CVPixelBuffer) throws {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            throw ArcFaceEmbedderError.pixelBufferCreationFailed
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }

    /// `MLMultiArray` storage is not guaranteed to be a flat, stride-1 buffer,
    /// so this indexes through the array's own subscript rather than a raw
    /// pointer over its bytes.
    private static func floatVector(from array: MLMultiArray) -> [Float] {
        var result = [Float](repeating: 0, count: array.count)
        for index in 0..<array.count {
            result[index] = array[index].floatValue
        }
        return result
    }
}
