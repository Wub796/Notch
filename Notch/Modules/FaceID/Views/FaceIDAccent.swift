import SwiftUI

/// Face ID's accent palette, matching Glance's visual identity.
enum FaceIDAccent {
    private static let base = (r: 0x34 / 255.0, g: 0x99 / 255.0, b: 0xFF / 255.0)

    static let accent = Color(red: base.r, green: base.g, blue: base.b)
    static let pale = Color(red: 0xCF / 255, green: 0xE7 / 255, blue: 0xFF / 255)
    static let bright = Color(red: 0x7F / 255, green: 0xC2 / 255, blue: 0xFF / 255)
    static let deep = Color(red: 0x1F / 255, green: 0x6B / 255, blue: 0xD1 / 255)

    /// White at 0, `accent` at 1.
    static func whiteToAccent(_ t: Double) -> Color {
        let t = min(max(t, 0), 1)
        return Color(
            red: 1 + (base.r - 1) * t,
            green: 1 + (base.g - 1) * t,
            blue: 1 + (base.b - 1) * t
        )
    }
}

/// Geometry and animation constants for Face ID setup, ported from Glance.
enum FaceIDMetrics {
    static let cameraCircleDiameter: CGFloat = 185
    static let tickRingOuterDiameter: CGFloat = 200

    /// 10 ticks per 45deg sector x 8 sectors = 80 ticks tiling the ring.
    static let tickCount = 80
    static let ticksPerSector = 10
    /// Width of the live turn indicator, in ticks.
    static let turnIndicatorTickSpan = 6
    /// Indicator stretch at full intensity.
    static let turnIndicatorLengthBoost: CGFloat = 5
    static let tickLengthUnlit: CGFloat = 12
    static let tickLengthLit: CGFloat = 20
    static let tickWidth: CGFloat = 2.4
    /// Stroke width of the solid ring the ticks merge into on completion.
    static let completionRingWidth: CGFloat = 14
    /// Inset from outer tips so the completion ring reads slightly inside the ticks.
    static let completionRingRadiusInset: CGFloat = 8
    /// Width ticks expand to when merging into the completion ring.
    static var tickWidthComplete: CGFloat {
        2 * .pi * (tickRingOuterDiameter / 2) / CGFloat(tickCount) * 1.2
    }
    /// Per-tick stagger for the sector-fill animation.
    static let tickStagger: Double = 0.008

    /// Reserved diameter for camera preview + outward-growing tick ring.
    static var enrollCameraClusterDiameter: CGFloat {
        tickRingOuterDiameter + tickLengthLit * 2
    }

    // Camera-complete sequence timings (seconds)
    static let guideOverlayFadeOut: Double = 0.35
    static let previewFadeOut: Double = 0.4
    static let checkmarkDelay: Double = 0.2
    static let checkmarkDrawDuration: Double = 0.28

    // Direction sweep
    static let sweepMasterOpacity: Double = 0.6
    static let sweepFadeIn: Double = 0.5
    static let sweepFadeOut: Double = 0.35
    static let sweepDirectionCrossfade: Double = 0.25
    static let sweepPoseDelay: Double = 0.36
    static let enrollTooFarChevronSize: CGFloat = 32
}
