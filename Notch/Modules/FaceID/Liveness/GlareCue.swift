import CoreGraphics

/// The pixel-domain half of the gloss/glare cue — what
/// `GlareCueExtractor.extract(faceCrop:)` produces and `LivenessCues.glossGlare`
/// reads. Deliberately free of Vision and CoreImage so the cue stays measurable
/// without either.
///
/// Ported from Glance (`Liveness/GlareCue.swift`, MIT © Jonathan Zhou).
struct GlareSample: Equatable {
    /// Native pixel width of the measured crop. The crop renderer only ever
    /// downsamples, so this is an honest detail measure — and the cue's
    /// confidence weights down as it shrinks.
    let cropPixelWidth: CGFloat

    /// Fraction of crop pixels that are near-saturated and low-chroma, which is
    /// what a direct specular reflection looks like.
    let specularFraction: Float

    /// How concentrated the specular pixels are into one region — the densest
    /// 8x8 grid cell's share of them. This is the measurement that separates
    /// glass glare from a shiny forehead, which is scattered rather than
    /// clustered.
    let specularClusterRatio: Float
}
