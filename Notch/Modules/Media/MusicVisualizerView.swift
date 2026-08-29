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

    /// Measured: the band's own energy, still scaled by the output level so
    /// turning the volume down visibly quiets the bars.
    private func meteredHeight(_ index: Int) -> CGFloat {
        guard let bands, bands.indices.contains(index) else { return Self.barWidth }
        let volume = CGFloat(min(max(level, 0), 1))
        let energy = CGFloat(min(max(bands[index], 0), 1))
        return Self.barWidth + (Self.maxHeight - Self.barWidth) * energy * max(volume, 0.15)
    }

    private func height(at elapsed: TimeInterval, index: Int) -> CGFloat {
        let clamped = CGFloat(min(max(level, 0), 1))
        // Silent or paused: a row of stubs, so the indicator stays present
        // without pretending anything is happening.
        guard isPlaying, clamped > 0.001 else { return Self.barWidth }

        let phase = (elapsed / Self.periods[index] + Double(index) * 0.37) * 2 * .pi
        let unit = (sin(phase) + 1) / 2 * Self.reach[index]

        // The level sets the ceiling; the oscillation fills it. A quarter of
        // the range is held back as a floor so quiet playback still reads as
        // playing rather than as silence.
        let ceiling = (Self.maxHeight - Self.barWidth) * clamped
        return Self.barWidth + ceiling * CGFloat(0.25 + 0.75 * unit)
    }
}
