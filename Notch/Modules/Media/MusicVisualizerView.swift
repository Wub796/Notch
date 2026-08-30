import SwiftUI

/// Three bars beside the notch that follow the audio.
///
/// Two sources, in order of honesty:
///
/// 1. **The output mix.** With "Real-time audio meter" on, `bands` carries
///    the low/mid/high energy of what is actually playing, measured from the
///    system's own output through `SystemAudioMeter`. The bars are then the
///    music — they punch on a kick, thin out in a quiet passage, and stop
///    dead in a gap, because that is what the samples say.
/// 2. **The output level.** Without that permission the loudest real signal
///    available is the volume itself, which is genuine but static, so the
///    motion is a shaped oscillation scaled by it. The bars still shrink when
///    the volume drops and flatten on mute; they just cannot know the track.
struct MusicVisualizerView: View {
    let accent: Color
    let isPlaying: Bool

    /// System output level, 0...1. Zero when muted.
    let level: Float

    /// Measured band energies, 0...1, when the real meter is running.
    var bands: [Float]?

    /// Each bar keeps its own period and reach, so they never march in step.
    private static let periods: [Double] = [0.62, 0.44, 0.53]
    private static let reach: [Double] = [0.78, 1.0, 0.86]
    private static let barWidth: CGFloat = 4
    private static let maxHeight: CGFloat = 15

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
        .accessibilityLabel("Output level")
        .accessibilityValue("\(Int((level * 100).rounded())) percent")
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

    /// Measured: the band's own real audio energy, scaled by the actual output level.
    private func meteredHeight(_ index: Int) -> CGFloat {
        guard let bands, bands.indices.contains(index) else { return Self.barWidth }
        let volume = CGFloat(min(max(level, 0), 1))
        let energy = CGFloat(min(max(bands[index], 0), 1))
        let effectiveEnergy = min(energy * 1.35, 1.0)
        let effectiveVolume = volume > 0.01 ? max(volume, 0.35) : 0
        let range = Self.maxHeight - Self.barWidth
        let dynamicHeight = Self.barWidth + range * effectiveEnergy * effectiveVolume
        return min(max(dynamicHeight, Self.barWidth), Self.maxHeight)
    }

    /// Output-driven fallback: directly follows the actual system volume level of the Mac.
    private func height(at elapsed: TimeInterval, index: Int) -> CGFloat {
        let clamped = CGFloat(min(max(level, 0), 1))
        guard isPlaying, clamped > 0.001 else { return Self.barWidth }

        let weights: [CGFloat] = [0.75, 1.0, 0.85]
        let weight = weights[min(index, weights.count - 1)]
        let phase = (elapsed * 2.8 + Double(index) * 0.5)
        let pulse = CGFloat(sin(phase) * 0.16 + 0.84)

        let range = Self.maxHeight - Self.barWidth
        let target = Self.barWidth + range * clamped * weight * pulse
        return min(max(target, Self.barWidth), Self.maxHeight)
    }
}
