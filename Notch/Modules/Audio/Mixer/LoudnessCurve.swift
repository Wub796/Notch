import Foundation

/// Volume-dependent tone correction: at low output levels the ear loses far
/// more bass than treble, so a mix played quietly sounds thinner than the same
/// mix played loudly. This adds a low lift back as the volume drops, plus a
/// much smaller high lift.
///
/// Deliberately a two-shelf approximation of that effect rather than the
/// tabulated ISO 226 contours. The standard is defined by a table of
/// thresholds measured per third-octave band and by a specific reference
/// level; a table retyped here would be a claim about measurement this app
/// cannot make and cannot test, while the *shape* — bass rising most, treble a
/// little, mids almost not at all — is what a listener actually hears. The
/// constants below are chosen to sit inside the range the contours describe:
/// at the quietest end the low shelf is under 8 dB, where the standard's own
/// 40–60 phon difference at 50 Hz is in the same region, and the mids are left
/// alone entirely.
enum LoudnessCurve {
    /// The level at which nothing is added — full output. Below it the
    /// compensation scales in linearly, reaching its maximum at `quietest`.
    static let referenceVolume: Float = 1
    /// The level the curve is scaled against: at or below this, the lift is at
    /// its maximum. Not zero, because a mix at 10% is already as quiet as this
    /// is meant to help.
    static let quietestVolume: Float = 0.15

    /// Largest low-shelf lift, in dB.
    static let maximumLowGain: Double = 8
    /// Largest high-shelf lift, in dB — the ear's treble loss is a fraction of
    /// its bass loss, so this is a fraction of the other figure.
    static let maximumHighGain: Double = 3

    /// The shelves for a given output volume. Empty at full volume, so a strip
    /// with only loudness switched on and the Mac at 100% stays transparent —
    /// no filters, no tap, nothing running.
    static func shelves(for volume: Float, sampleRate: Double) -> [Biquad] {
        let amount = strength(for: volume)
        guard amount > 0.001 else { return [] }

        return [
            Biquad.lowShelf(
                frequency: 120,
                gainDB: maximumLowGain * amount,
                slope: 0.8,
                sampleRate: sampleRate
            ),
            Biquad.highShelf(
                frequency: 6_000,
                gainDB: maximumHighGain * amount,
                slope: 0.7,
                sampleRate: sampleRate
            ),
        ]
    }

    /// How much of the compensation to apply, 0…1 — the only thing that varies
    /// with volume, so both shelves stay in proportion to each other.
    static func strength(for volume: Float) -> Double {
        let span = max(referenceVolume - quietestVolume, 0.0001)
        let position = (referenceVolume - min(max(volume, 0), referenceVolume)) / span
        return Double(min(max(position, 0), 1))
    }
}
