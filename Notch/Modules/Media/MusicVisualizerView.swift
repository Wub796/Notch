import SwiftUI

/// Three bars beside the notch that follow the audio.
///
/// Each bar is one range of frequencies — low, mid, high — and the three are
/// meant to be read as a meter rather than as a shape: a kick fills the first
/// and leaves the third alone, cymbals do the opposite, and a track that is
/// all vocal puts everything in the middle. Two sources, in order of honesty:
///
/// 1. **The output mix.** With "Real-time audio meter" on, `bands` carries the
///    measured magnitude of each of those three ranges, split out of the
///    output mix by a CoreAudio tap through `SystemAudioMeter`. The bars are
///    then the music — they punch on a kick, thin out in a quiet passage, and
///    stop dead in a gap, because that is what the samples say. Needs macOS
///    14.2 and audio access; without either, this is nil and case 2 runs.
/// 2. **The output level.** The loudest real signal left is the volume
///    itself, which is genuine but static and has no frequencies in it, so the
///    motion is a shaped oscillation scaled by it. The bars still shrink when
///    the volume drops and flatten on mute; they just cannot know the track,
///    and they cannot differ from each other by anything but their own phase.
struct MusicVisualizerView: View {
    let accent: Color
    let isPlaying: Bool

    /// System output level, 0...1. Zero when muted.
    let level: Float

    /// Measured band energies, 0...1, in low/mid/high order, when the real
    /// meter is running.
    var bands: [Float]?

    /// Each bar keeps its own period, so the fallback's oscillation never
    /// marches in step.
    private static let periods: [Double] = [0.62, 0.44, 0.53]
    private static let barWidth: CGFloat = 4
    private static let maxHeight: CGFloat = 15

    /// A per-band lift, applied only on the measured path. A mix's energy
    /// falls off with frequency almost by definition — a kick carries tens of
    /// dB more than the air on a vocal — so an untrimmed meter reads as a
    /// permanent staircase: a lively first bar and a nearly dead third. This
    /// lifts the top two so the third has travel to show, without touching
    /// what each bar is measuring.
    private static let bandTrim: [CGFloat] = [1.0, 1.12, 1.32]

    private var isMetered: Bool {
        (bands?.count ?? 0) >= 3
    }

    var body: some View {
        Group {
            if isMetered {
                // The meter publishes at 30Hz; animating between its values is
                // all the motion needed, so no timeline is driven here.
                bars { index in meteredHeight(index) }
                    .animation(.easeOut(duration: 0.07), value: bands ?? [])
            } else {
                TimelineView(.animation(minimumInterval: 1 / 24, paused: !isPlaying)) { context in
                    let elapsed = context.date.timeIntervalSinceReferenceDate
                    bars { index in height(at: elapsed, index: index) }
                        // The level itself changes in steps, so ease between
                        // them rather than jumping on a volume key press.
                        .animation(.easeOut(duration: 0.18), value: level)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isMetered ? "Output bands" : "Output level")
        .accessibilityValue(accessibilityValue)
    }

    /// The measured path speaks in three numbers, because that is what it is
    /// drawing; the fallback has one.
    private var accessibilityValue: String {
        guard isMetered, let bands else {
            return "\(Int((level * 100).rounded())) percent"
        }
        let names = ["low", "mid", "high"]
        return zip(names, bands)
            .map { "\($0) \(Int(($1 * 100).rounded())) percent" }
            .joined(separator: ", ")
    }

    private func bars(_ height: @escaping (Int) -> CGFloat) -> some View {
        HStack(alignment: .center, spacing: 3.5) {
            ForEach(Array(Self.periods.indices), id: \.self) { index in
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [accent, accent.opacity(0.55)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: Self.barWidth, height: height(index))
            }
        }
        .frame(height: Self.maxHeight)
    }

    /// Measured: this bar's own band, and nothing else.
    ///
    /// The magnitude arrives already normalized against fixed dBFS limits and
    /// already enveloped (`AudioBandAnalyzer`), so all that is left here is the
    /// trim and the bar's travel. In particular it is *not* scaled by the
    /// output volume a second time: the tap is upstream of the volume, so the
    /// mix these numbers came from is what is playing, and multiplying it by
    /// the slider would leave the third bar pinned to the floor on quiet
    /// listening — which is the shape this change exists to remove.
    private func meteredHeight(_ index: Int) -> CGFloat {
        guard isPlaying, let bands, bands.indices.contains(index) else { return Self.barWidth }
        // Mute is the one thing the samples cannot show, because the tap sits
        // ahead of the mute. The bars go flat with the speakers.
        guard level > 0.001 else { return Self.barWidth }

        let magnitude = CGFloat(min(max(bands[index], 0), 1)) * Self.bandTrim[index]
        guard magnitude > 0.01 else { return Self.barWidth }
        let range = Self.maxHeight - Self.barWidth
        let height = Self.barWidth + range * min(magnitude, 1)
        return min(max(height, Self.barWidth), Self.maxHeight)
    }

    /// Output-driven fallback: directly follows the actual system volume level of the Mac with dynamic wave motion when playing.
    private func height(at elapsed: TimeInterval, index: Int) -> CGFloat {
        guard isPlaying else { return Self.barWidth }
        let clamped = CGFloat(min(max(level, 0), 1))
        guard clamped > 0.001 else { return Self.barWidth }

        let weights: [CGFloat] = [0.8, 1.0, 0.85]
        let weight = weights[min(index, weights.count - 1)]
        let phase = (elapsed * 3.5 + Double(index) * 0.7)
        let oscillation = (sin(phase) + 1.0) / 2.0 // 0.0 ... 1.0

        let range = Self.maxHeight - Self.barWidth
        let target = Self.barWidth + range * clamped * weight * CGFloat(0.2 + 0.8 * oscillation)
        return min(max(target, Self.barWidth), Self.maxHeight)
    }
}
