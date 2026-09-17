import SwiftUI

/// The seekable playback bar shared by every surface that shows a player.
///
/// Extracted from the standalone `MediaPlayerView`, which the Devices screen's
/// "Now" section replaced — the view went, this did not, because the Now
/// section scrubs with it.
struct ScrubberBar: View {
    let duration: TimeInterval
    let elapsed: TimeInterval
    let accent: Color
    let onSeek: (TimeInterval) -> Void

    /// Called continuously while the thumb moves, with the position under it.
    /// Lets the lyric highlight follow the drag in real time instead of only
    /// after release; does not move playback.
    var onScrubPreview: ((TimeInterval) -> Void)? = nil
    /// Called once when the drag ends (after `onSeek`), so the consumer can
    /// stop previewing and hand the highlight back to the playhead.
    var onScrubEnd: (() -> Void)? = nil

    @State private var dragFraction: Double?
    @State private var hovering = false
    @State private var showRemaining = true

    private var playbackFraction: Double {
        guard duration > 0 else { return 0 }
        return min(max(elapsed / duration, 0), 1)
    }

    private var displayedFraction: Double {
        dragFraction ?? playbackFraction
    }

    private var isInteracting: Bool {
        hovering || dragFraction != nil
    }

    /// While dragging, the readout follows the drag rather than playback, so
    /// the number under the thumb is the position you are about to seek to.
    private var remaining: TimeInterval {
        guard duration > 0 else { return 0 }
        let position = dragFraction.map { $0 * duration } ?? elapsed
        return max(duration - min(position, duration), 0)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(Self.timeString(dragFraction.map { $0 * duration } ?? elapsed))
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(NotchTheme.inkPrimary)
                // Sized by its content: a fixed 34 clipped anything past
                // "9:59", so long tracks and podcasts lost digits.
                .fixedSize()
                .contentTransition(.numericText())
                .animation(dragFraction == nil ? NotchAnimations.content : nil, value: elapsed)

            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.16))
                    Capsule()
                        .fill(accent)
                        .frame(width: max(width * displayedFraction, 0))

                    if isInteracting {
                        Circle()
                            .fill(.white)
                            .frame(width: 11, height: 11)
                            .shadow(color: .black.opacity(0.4), radius: 3)
                            .offset(x: max(width * displayedFraction - 5.5, 0))
                            .transition(.opacity)
                    }
                }
                .frame(height: isInteracting ? 7 : 4)
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard duration > 0, width > 0 else { return }
                            let fraction = min(max(value.location.x / width, 0), 1)
                            dragFraction = fraction
                            onScrubPreview?(fraction * duration)
                        }
                        .onEnded { _ in
                            if let fraction = dragFraction {
                                onSeek(fraction * duration)
                            }
                            dragFraction = nil
                            onScrubEnd?()
                        }
                )
            }
            .frame(height: 14)
            // The thickness/grow settle keeps the house spring; the elapsed
            // label fades between values instead of hard-cutting each tick.
            .animation(.notchSpring, value: isInteracting)
            .onHover { hovering = $0 }

            Text(showRemaining
                ? "−" + Self.timeString(remaining)
                : Self.timeString(duration))
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(NotchTheme.inkPrimary)
                .fixedSize()
                .contentShape(Rectangle())
                .onTapGesture { showRemaining.toggle() }
                .accessibilityLabel(showRemaining ? "Time remaining" : "Track duration")
                .accessibilityHint("Click to toggle between remaining and total time")
        }
        .opacity(duration > 0 ? 1 : 0.4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Playback position")
        .accessibilityValue(
            "\(Self.timeString(elapsed)) of \(Self.timeString(duration))"
        )
    }
}

extension ScrubberBar {
    /// "3:07", or "1:02:33" once a track runs past an hour — podcasts and DJ
    /// sets did the latter and came out as "83:20".
    static func timeString(_ interval: TimeInterval) -> String {
        guard interval.isFinite, interval >= 0 else { return "0:00" }
        let total = Int(interval)
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}
