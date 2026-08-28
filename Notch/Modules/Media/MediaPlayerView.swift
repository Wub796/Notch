import AppKit
import SwiftUI

/// Expanded media module: large artwork (matched-geometry from the collapsed
/// wing), track info, transport controls, progress, and live lyrics.
struct MediaPlayerView: View {
    let media: MediaController
    let namespace: Namespace.ID

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    artwork
                    trackInfo
                }
                progressBar
                transportControls
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            LyricsView(lyrics: media.lyrics)
                .frame(width: 250)
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
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(0.1))
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 26))
                            .foregroundStyle(.white.opacity(0.45))
                    }
            }
        }
        .frame(width: 76, height: 76)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .matchedGeometryEffect(id: "albumArt", in: namespace)
        .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
    }

    private var trackInfo: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(media.track?.title ?? "Nothing Playing")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(media.track?.artist ?? "Play something to see it here")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
            if let album = media.track?.album, !album.isEmpty {
                Text(album)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var progressBar: some View {
        VStack(spacing: 3) {
            GeometryReader { proxy in
                let duration = media.track?.duration ?? 0
                let fraction = duration > 0
                    ? min(max(media.displayedElapsed / duration, 0), 1)
                    : 0
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.15))
                    Capsule()
                        .fill(.white.opacity(0.85))
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 4)

            HStack {
                Text(Self.timeString(media.displayedElapsed))
                Spacer()
                Text(Self.timeString(media.track?.duration ?? 0))
            }
            .font(.system(size: 9, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.45))
        }
    }

    private var transportControls: some View {
        HStack(spacing: 26) {
            Spacer()
            transportButton("backward.fill", size: 15) {
                media.previousTrack()
            }
            transportButton(media.isPlaying ? "pause.fill" : "play.fill", size: 21) {
                media.togglePlayPause()
            }
            transportButton("forward.fill", size: 15) {
                media.nextTrack()
            }
            Spacer()
        }
    }

    private func transportButton(
        _ systemImage: String,
        size: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    static func timeString(_ interval: TimeInterval) -> String {
        guard interval.isFinite, interval >= 0 else { return "0:00" }
        let total = Int(interval)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
