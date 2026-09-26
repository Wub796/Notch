import CoreGraphics

/// Turns a native-resolution face crop into a `GlareSample`.
///
/// Ported from Glance (`Liveness/GlareCueExtractor.swift`, MIT © Jonathan Zhou).
/// One decode-and-scan pass with no frequency-domain work, which is what makes
/// it cheap enough to run on every liveness frame rather than every fifth.
enum GlareCueExtractor {
    /// Near-white and near-gray: the signature of a direct specular highlight,
    /// as opposed to a bright colored surface.
    private static let specularLumaFloor: Float = 235
    private static let specularChromaTolerance: Float = 10

    /// Coarse on purpose — the grid only has to distinguish "one blob" from
    /// "many scattered points".
    private static let clusterGridSize = 8

    /// Returns `nil` only if the crop couldn't be rasterized. A too-small crop
    /// still yields a sample; the discounting happens in the cue, through
    /// `cropPixelWidth`.
    static func extract(faceCrop: CGImage) -> GlareSample? {
        let width = faceCrop.width
        let height = faceCrop.height
        guard width > 0, height > 0 else { return nil }

        var data = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = data.withUnsafeMutableBytes({ buffer -> CGContext? in
            CGContext(
                data: buffer.baseAddress,
                width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        }) else { return nil }
        context.draw(faceCrop, in: CGRect(x: 0, y: 0, width: width, height: height))

        var gridCounts = [Int](repeating: 0, count: clusterGridSize * clusterGridSize)
        var specularTotal = 0

        data.withUnsafeBufferPointer { bytes in
            for y in 0..<height {
                let rowBase = y * width * 4
                let gridY = min(clusterGridSize - 1, y * clusterGridSize / height)
                for x in 0..<width {
                    let offset = rowBase + x * 4
                    let red = Float(bytes[offset])
                    let green = Float(bytes[offset + 1])
                    let blue = Float(bytes[offset + 2])

                    let luma = 0.299 * red + 0.587 * green + 0.114 * blue
                    guard luma >= specularLumaFloor else { continue }
                    // Rec. 601 chroma, offset to be centered on 128 — which is
                    // what makes "near-gray" a cheap absolute test.
                    let cb = -0.168736 * red - 0.331264 * green + 0.5 * blue + 128
                    let cr = 0.5 * red - 0.418688 * green - 0.081312 * blue + 128
                    guard abs(cb - 128) <= specularChromaTolerance,
                          abs(cr - 128) <= specularChromaTolerance
                    else { continue }

                    specularTotal += 1
                    let gridX = min(clusterGridSize - 1, x * clusterGridSize / width)
                    gridCounts[gridY * clusterGridSize + gridX] += 1
                }
            }
        }

        let pixelCount = width * height
        let specularFraction = Float(specularTotal) / Float(pixelCount)
        let largestCluster = gridCounts.max() ?? 0
        let clusterRatio = specularTotal > 0 ? Float(largestCluster) / Float(specularTotal) : 0

        return GlareSample(
            cropPixelWidth: CGFloat(width),
            specularFraction: specularFraction,
            specularClusterRatio: clusterRatio
        )
    }
}
