import AppKit
import SwiftUI

/// Collapsed state: pure black, exactly the hardware notch — plus small
/// "wings" with mini artwork and an accent-tinted audio visualizer while a
/// track is loaded.
struct CollapsedNotchView: View {
    let state: NotchState
    let namespace: Namespace.ID

    var body: some View {
        HStack(spacing: 0) {
            if state.showsMediaWings {
                miniArtwork
                    .padding(.leading, 12)
            }

            // The dead zone occupied by the physical notch hardware.
            Spacer(minLength: 0)

            if state.showsMediaWings {
                AudioBarsView(isAnimating: state.media.isPlaying, tint: state.media.accent)
                    .padding(.trailing, 14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var miniArtwork: some View {
        Group {
            if let artwork = state.media.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(NotchTheme.surfaceHover)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 10))
                            .foregroundStyle(NotchTheme.inkSecondary)
                    }
            }
        }
        .frame(width: 20, height: 20)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .matchedGeometryEffect(id: "albumArt", in: namespace)
    }
}

/// Minimal four-bar equalizer shown in the right wing, tinted with the
/// artwork accent; freezes at rest heights while paused.
struct AudioBarsView: View {
    let isAnimating: Bool
    let tint: Color

    @State private var animate = false

    private let barHeights: [CGFloat] = [10, 16, 7, 13]

    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(barHeights.indices, id: \.self) { index in
                Capsule()
                    .fill(tint)
                    .frame(width: 2.5, height: animate ? barHeights[index] : 4)
                    .animation(
                        isAnimating
                            ? .easeInOut(duration: 0.45)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.12)
                            : .default,
                        value: animate
                    )
            }
        }
        .frame(height: 16)
        .onAppear { animate = isAnimating }
        .onChange(of: isAnimating) { _, playing in
            animate = playing
        }
    }
}
