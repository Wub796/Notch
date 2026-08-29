import SwiftUI

/// Three thick vertical bars that rise and fall while music plays, tinted from
/// the current cover.
///
/// Not a real spectrum: macOS gives no public access to another app's audio
/// samples, so nothing here claims to be measuring the track. It is an
/// indicator that something is playing, which is what the bars in the notch
/// are for — and it stops dead when playback pauses rather than miming.
struct MusicVisualizerView: View {
    let accent: Color
    let isPlaying: Bool

    /// Each bar keeps its own period, so they never march in step.
    private static let periods: [Double] = [0.62, 0.44, 0.53]
    private static let barWidth: CGFloat = 4
    private static let height: CGFloat = 15

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !isPlaying)) { context in
            let elapsed = context.date.timeIntervalSinceReferenceDate

            HStack(alignment: .center, spacing: 3.5) {
                ForEach(Array(Self.periods.enumerated()), id: \.offset) { index, period in
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [accent, accent.opacity(0.55)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(
                            width: Self.barWidth,
                            height: barHeight(at: elapsed, period: period, index: index)
                        )
                }
            }
            .frame(height: Self.height)
        }
        .accessibilityHidden(true)
    }

    /// A sine per bar, offset so the three are out of phase, resting at a
    /// short stub when paused so the indicator does not vanish.
    private func barHeight(at elapsed: TimeInterval, period: Double, index: Int) -> CGFloat {
        guard isPlaying else { return Self.barWidth }
        let phase = (elapsed / period + Double(index) * 0.37) * 2 * .pi
        let unit = (sin(phase) + 1) / 2
        return Self.barWidth + (Self.height - Self.barWidth) * CGFloat(unit)
    }
}
