import AppKit
import SwiftUI

/// Collapsed and peek states: pure black, hugging the hardware notch, with
/// live-activity wings — now playing, a volume HUD, battery events, or an
/// imminent meeting — appearing around the camera housing.
struct CollapsedNotchView: View {
    let state: NotchState
    let namespace: Namespace.ID

    var body: some View {
        ZStack {
            switch state.collapsedActivity {
            case .music:
                musicWings
            case let .lyrics(line):
                LyricActivityView(
                    notchWidth: state.notchSize.width,
                    notchHeight: state.notchSize.height,
                    line: line,
                    artwork: state.media.artwork,
                    accent: state.media.accent
                )
            case let .trackChange(title, artist):
                TrackChangeActivityView(
                    notchWidth: state.notchSize.width,
                    title: title,
                    artist: artist,
                    artwork: state.media.artwork,
                    accent: state.media.accent
                )
            case let .volume(level, muted):
                VolumeActivityView(
                    notchWidth: state.notchSize.width,
                    level: level,
                    muted: muted
                )
            case let .battery(percent, charging, low):
                BatteryActivityView(
                    notchWidth: state.notchSize.width,
                    percent: percent,
                    charging: charging,
                    low: low
                )
            case let .screenLock(locked):
                ScreenLockActivityView(
                    notchWidth: state.notchSize.width,
                    locked: locked
                )
            case let .meetingSoon(title, start):
                TimelineView(.everyMinute) { context in
                    MeetingActivityView(
                        notchWidth: state.notchSize.width,
                        title: title,
                        start: start,
                        now: context.date
                    )
                }
            case nil:
                if state.settings.showIdleFace {
                    idleFaceWing
                } else {
                    Color.clear
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var idleFaceWing: some View {
        ActivityWingLayout(
            notchWidth: state.notchSize.width,
            leading: Color.clear.frame(width: 1),
            trailing: IdleFaceView()
        )
    }

    private var musicWings: some View {
        ActivityWingLayout(
            notchWidth: state.notchSize.width,
            leading: miniArtwork,
            trailing: AudioBarsView(isAnimating: state.media.isPlaying, tint: state.media.accent)
        )
    }

    private var miniArtwork: some View {
        Group {
            if let artwork = state.media.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(NotchTheme.surfaceHover)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 10))
                            .foregroundStyle(NotchTheme.inkSecondary)
                    }
            }
        }
        .frame(width: 20, height: 20)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .matchedGeometryEffect(id: "albumArt", in: namespace)
        .accessibilityHidden(true)
    }
}

/// Minimal four-bar equalizer shown in the right wing, tinted with the
/// artwork accent; freezes at rest heights while paused. Purely decorative:
/// hidden from accessibility, and held static under Reduce Motion.
struct AudioBarsView: View {
    let isAnimating: Bool
    let tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animate = false

    private let barHeights: [CGFloat] = [10, 16, 7, 13]

    private var shouldAnimate: Bool {
        isAnimating && !reduceMotion
    }

    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(barHeights.indices, id: \.self) { index in
                Capsule()
                    .fill(tint)
                    .frame(width: 2.5, height: barHeight(index))
                    .animation(
                        shouldAnimate
                            ? .easeInOut(duration: 0.45)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.12)
                            : .default,
                        value: animate
                    )
            }
        }
        .frame(height: 16)
        .accessibilityHidden(true)
        .onAppear { animate = shouldAnimate }
        .onChange(of: shouldAnimate) { _, animating in
            animate = animating
        }
    }

    private func barHeight(_ index: Int) -> CGFloat {
        if animate { return barHeights[index] }
        // Reduce Motion while playing: hold mid heights instead of pulsing.
        return isAnimating ? barHeights[index] * 0.6 : 4
    }
}
