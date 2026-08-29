import SwiftUI

/// Three bars beside the notch whose height follows the live output level.
///
/// What this is and is not. The bars' amplitude is the real system output
/// volume, read from CoreAudio and updated by its property listeners — turn
/// the volume down and they shrink, mute and they flatten, immediately. What
/// they are *not* is a spectrum analyser: their motion is a shaped oscillation,
/// not the waveform of the track.
///
/// That distinction is forced. Reading another app's audio samples on macOS
/// needs either a Core Audio process tap, which is macOS 14.4 SDK only, or
/// ScreenCaptureKit audio capture, which costs a Screen Recording permission
/// for a decoration. Neither is available here, so the honest thing is to
/// drive the one real signal that is — the level — and shape the rest.
struct MusicVisualizerView: View {
    let accent: Color
    let isPlaying: Bool

    /// System output level, 0...1. Zero when muted.
    let level: Float

    /// Each bar keeps its own period and reach, so they never march in step.
    private static let periods: [Double] = [0.62, 0.44, 0.53]
    private static let reach: [Double] = [0.78, 1.0, 0.86]
    private static let barWidth: CGFloat = 4
    private static let maxHeight: CGFloat = 15

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: !isPlaying)) { context in
            let elapsed = context.date.timeIntervalSinceReferenceDate

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
                        .frame(width: Self.barWidth, height: height(at: elapsed, index: index))
                }
            }
            .frame(height: Self.maxHeight)
            // The level itself changes in steps, so ease between them rather
            // than letting the bars jump when a volume key is pressed.
            .animation(.easeOut(duration: 0.18), value: level)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Output level")
        .accessibilityValue("\(Int((level * 100).rounded())) percent")
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
