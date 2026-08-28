import AppKit
import SwiftUI

/// Expanded media module: large artwork (matched-geometry from the collapsed
/// wing), track info, a seekable scrubber, transport controls, and live
/// lyrics — all tinted by the artwork-derived accent.
struct MediaPlayerView: View {
    let media: MediaController
    let namespace: Namespace.ID

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    artwork
                    trackInfo
                }
                ScrubberBar(
                    duration: media.track?.duration ?? 0,
                    elapsed: media.displayedElapsed,
                    accent: media.accent
                ) { target in
                    media.seek(to: target)
                }
                transportControls
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .fill(NotchTheme.hairline)
                .frame(width: 1)
                .padding(.vertical, 6)

            LyricsView(lyrics: media.lyrics, accent: media.accent) { time in
                media.seek(to: time + 0.05)
            }
            .frame(width: 235)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var artwork: some View {
        Group {
            if let image = media.artwork {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                // Vinyl-style placeholder disc.
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(NotchTheme.surface)
                    .overlay {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [.white.opacity(0.16), .white.opacity(0.03)],
                                    center: .center,
                                    startRadius: 4,
                                    endRadius: 34
                                )
                            )
                            .padding(8)
                    }
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 22))
                            .foregroundStyle(NotchTheme.inkMuted)
                    }
            }
        }
        .frame(width: 82, height: 82)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .matchedGeometryEffect(id: "albumArt", in: namespace)
        .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
    }

    private var trackInfo: some View {
        VStack(alignment: .leading, spacing: 3) {
            MarqueeText(
                text: media.track?.title ?? "Nothing Playing",
                font: .system(size: 14.5, weight: .semibold),
                width: 222
            )
            .foregroundStyle(NotchTheme.inkPrimary)
            Text(media.track?.artist ?? "Play something to see it here")
                .font(.system(size: 12))
                .foregroundStyle(NotchTheme.inkSecondary)
                .lineLimit(1)
            if let album = media.track?.album, !album.isEmpty {
                Text(album)
                    .font(.system(size: 11))
                    .foregroundStyle(NotchTheme.inkMuted)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var transportControls: some View {
        HStack(spacing: 24) {
            Spacer()

            TransportIconButton(
                systemImage: "backward.fill",
                accessibilityLabel: "Previous track",
                isEnabled: media.hasTrack
            ) {
                media.previousTrack()
            }

            Button {
                media.togglePlayPause()
            } label: {
                Image(systemName: media.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 40, height: 40)
                    .background {
                        Circle().fill(media.accent)
                    }
                    .contentShape(Circle())
            }
            .buttonStyle(PressableButtonStyle())
            .hoverLift(1.05)
            .shadow(color: media.accent.opacity(0.35), radius: 10, y: 2)
            .disabled(!media.hasTrack)
            .opacity(media.hasTrack ? 1 : 0.35)
            .accessibilityLabel(media.isPlaying ? "Pause" : "Play")

            TransportIconButton(
                systemImage: "forward.fill",
                accessibilityLabel: "Next track",
                isEnabled: media.hasTrack
            ) {
                media.nextTrack()
            }

            Spacer()
        }
    }

    static func timeString(_ interval: TimeInterval) -> String {
        guard interval.isFinite, interval >= 0 else { return "0:00" }
        let total = Int(interval)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Secondary transport control: faint circular hover background, press
/// compression, dimmed when disabled.
private struct TransportIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let isEnabled: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(NotchTheme.inkPrimary)
                .frame(width: 32, height: 32)
                .background {
                    Circle().fill(.white.opacity(hovering ? 0.1 : 0))
                }
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { isHovering in
            withAnimation(.notchSpring) {
                hovering = isHovering
            }
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Seekable progress bar: grows on hover, shows a knob while interacting, and
/// commits the seek on release.
struct ScrubberBar: View {
    let duration: TimeInterval
    let elapsed: TimeInterval
    let accent: Color
    let onSeek: (TimeInterval) -> Void

    @State private var dragFraction: Double?
    @State private var hovering = false
    @State private var showRemaining = false

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

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.14))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [accent.opacity(0.75), accent],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
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
                            dragFraction = min(max(value.location.x / width, 0), 1)
                        }
                        .onEnded { _ in
                            if let fraction = dragFraction {
                                onSeek(fraction * duration)
                            }
                            dragFraction = nil
                        }
                )
            }
            .frame(height: 14)
            .animation(.notchSpring, value: isInteracting)
            .onHover { hovering = $0 }

            HStack {
                Text(MediaPlayerView.timeString(dragFraction.map { $0 * duration } ?? elapsed))
                Spacer()
                // Click to flip between total and remaining time.
                Text(showRemaining
                    ? "−" + MediaPlayerView.timeString(max(duration - elapsed, 0))
                    : MediaPlayerView.timeString(duration))
                    .contentShape(Rectangle())
                    .onTapGesture { showRemaining.toggle() }
                    .accessibilityLabel(showRemaining ? "Time remaining" : "Track duration")
                    .accessibilityHint("Click to toggle between total and remaining time")
            }
            .font(.system(size: 9.5, weight: .medium).monospacedDigit())
            .foregroundStyle(NotchTheme.inkMuted)
        }
        .opacity(duration > 0 ? 1 : 0.4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Playback position")
        .accessibilityValue(
            "\(MediaPlayerView.timeString(elapsed)) of \(MediaPlayerView.timeString(duration))"
        )
    }
}
