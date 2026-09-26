import Foundation

/// One band of an EQ curve: a centre frequency, how much to lift or cut it, and
/// how wide the effect is.
///
/// `q` is meaningful for the parametric presets and for AutoEQ profiles, which
/// each name their own widths. The graphic EQ this app's UI shows uses the fixed
/// width in `EqualizerPreset.graphicQ`, where every band is the same shape and
/// only the gains move — which is what makes a ten-slider EQ behave the way a
/// hardware one does.
struct EQBand: Codable, Equatable, Identifiable, Hashable {
    var frequency: Double
    /// Decibels, not a linear factor: a curve reads in the units it is judged in.
    var gain: Float
    var q: Double

    var id: String { String(format: "%.1f", frequency) }
}

/// A named curve, and the fixed sliders the custom curve is edited on.
struct EqualizerPreset: Equatable, Identifiable {
    /// The id stored for a curve the user has moved by hand.
    static let customID = "custom"

    /// The width every graphic band uses. About one octave, which is what makes
    /// neighbouring sliders overlap a little rather than leaving gaps between
    /// them.
    static let graphicQ: Double = 1.1

    /// Ten centres, an octave apart, low to high — the band layout of a graphic
    /// equalizer, and the one the panel draws.
    static let graphicFrequencies: [Double] = [31, 62, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000]

    /// A curve at unity: the state that means "this app is untouched", which is
    /// why it is the default rather than merely the first preset.
    static let flat = EqualizerPreset(
        id: "flat",
        title: "Flat",
        bands: graphicFrequencies.map { EQBand(frequency: $0, gain: 0, q: graphicQ) }
    )

    let id: String
    let title: String
    let bands: [EQBand]

    /// Short description shown under a preset's name in the picker.
    var summary: String {
        switch id {
        case "flat": "No change"
        case "vocal": "Pushes voices forward"
        case "bass": "Lifts the low end"
        case "treble": "Opens up the top"
        case "podcast": "Trims rumble, sharpens speech"
        case "night": "Keeps detail at low volume"
        default: "Custom curve"
        }
    }

    /// The built-in curves, written as offsets from unity rather than as
    /// absolute gains so the shape of each is legible at a glance.
    ///
    /// These are this app's own: chosen from what the bands do (a presence lift
    /// around 2–4 kHz for voices, a rumble cut under 125 Hz for speech, a broad
    /// low lift for weight) rather than copied from any other equalizer's list.
    static let builtIns: [EqualizerPreset] = [
        flat,
        EqualizerPreset(
            id: "vocal",
            title: "Vocal clarity",
            bands: graphicGains([-2, -2, -1, 1, 2, 3, 3, 2, 0, -1])
        ),
        EqualizerPreset(
            id: "bass",
            title: "Bass lift",
            bands: graphicGains([5, 4, 3, 2, 1, 0, 0, 0, 0, 0])
        ),
        EqualizerPreset(
            id: "treble",
            title: "Treble lift",
            bands: graphicGains([0, 0, 0, 0, 0, 1, 2, 3, 3, 2])
        ),
        EqualizerPreset(
            id: "podcast",
            title: "Podcast",
            bands: graphicGains([-6, -5, -3, -1, 1, 3, 4, 3, 1, 0])
        ),
        EqualizerPreset(
            id: "night",
            title: "Late night",
            bands: graphicGains([3, 3, 2, 0, -1, 0, 1, 2, 2, 1])
        ),
    ]

    static func preset(for id: String) -> EqualizerPreset? {
        builtIns.first { $0.id == id }
    }

    /// Turns ten slider positions into a curve on the standard centres.
    static func graphicGains(_ gains: [Float]) -> [EQBand] {
        zip(graphicFrequencies, gains).map { frequency, gain in
            EQBand(frequency: frequency, gain: gain, q: graphicQ)
        }
    }

    /// Pads or trims a curve to exactly one gain per graphic band, so a
    /// parametric preset (or an imported profile) can be shown on the same ten
    /// sliders the custom curve is edited on.
    static func graphicGains(from bands: [EQBand]) -> [Float] {
        graphicFrequencies.map { centre in
            // The band whose own centre is nearest takes the value; a curve with
            // two filters near one slider (a shelf pair, say) contributes the
            // sum, which is what that slider would have to do to match it.
            let near = bands.filter { abs(log2($0.frequency / centre)) < 0.5 }
            if near.isEmpty { return 0 }
            if near.count == 1 { return near[0].gain }
            return near.map(\.gain).reduce(0, +)
        }
    }
}
