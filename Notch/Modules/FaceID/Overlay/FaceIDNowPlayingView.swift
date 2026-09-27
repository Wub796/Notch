import AppKit
import Observation
import SwiftUI

/// macOS 26 introduced SwiftUI's native Liquid Glass API. Keep the project buildable
/// for its macOS 14 deployment target and use a frosted, highlighted fallback there.
private struct FaceIDNowPlayingGlassBackground: View {
    let tint: Color

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: FaceIDGeometry.nowPlayingPanelCornerRadius, style: .continuous)
    }

    @ViewBuilder
    var body: some View {
        if #available(macOS 26.0, *) {
            shape
                .fill(Color.white.opacity(0.035))
                .glassEffect(.regular.tint(tint), in: shape)
        } else {
            shape
                .fill(.ultraThinMaterial)
                .overlay { shape.fill(Color.white.opacity(0.055)) }
        }
    }
}

private struct InteractiveGlassControl: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Circle())
        } else {
            content
        }
    }
}

/// A larger lock-screen now-playing surface driven by the app's existing shared
/// media controller. Its visual treatment follows lucasromerodb's Liquid Glass
/// reference while using Apple's native SwiftUI effect rather than its CSS/SVG demo.
struct FaceIDNowPlayingPlayer: View {
    let media: MediaController

    private var title: String {
        if let title = media.track?.title, !title.isEmpty { return title }
        return media.sourceAppName ?? "Now Playing"
    }

    private var subtitle: String {
        if let artist = media.track?.artist, !artist.isEmpty { return artist }
        return media.isPlaying ? "Playing" : "Paused"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                artwork
                    .frame(width: 88, height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.7)
                    }
                    .shadow(color: media.accent.opacity(0.28), radius: 12, y: 5)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text(media.sourceAppName?.uppercased() ?? "NOW PLAYING")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.25)
                        .foregroundStyle(media.accent.opacity(0.95))
                        .lineLimit(1)

                    Text(title)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(NotchTheme.inkPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(NotchTheme.inkSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 17) {
                        transportButton("backward.fill", label: "Previous track", size: 15) {
                            media.previousTrack()
                        }

                        Button {
                            media.togglePlayPause()
                        } label: {
                            Image(systemName: media.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(NotchTheme.inkPrimary)
                                .frame(width: 40, height: 36)
                                .background(Circle().fill(Color.white.opacity(0.14)))
                                .contentShape(Circle())
                                .modifier(InteractiveGlassControl())
                        }
                        .buttonStyle(PressableButtonStyle())
                        .contentTransition(.symbolEffect(.replace))
                        .accessibilityLabel(media.isPlaying ? "Pause" : "Play")

                        transportButton("forward.fill", label: "Next track", size: 15) {
                            media.nextTrack()
                        }
                    }
                    .padding(.top, 1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            TimelineView(.animation(minimumInterval: 0.1, paused: !media.isPlaying)) { _ in
                ScrubberBar(
                    duration: media.track?.duration ?? 0,
                    elapsed: media.currentElapsed,
                    accent: media.accent,
                    onSeek: { media.seek(to: $0) },
                    onScrubPreview: { media.previewScrub(to: $0) },
                    onScrubEnd: { media.endScrubPreview() }
                )
            }
            .frame(height: 18)
            .padding(.horizontal, 2)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            FaceIDNowPlayingGlassBackground(tint: media.accent.opacity(0.2))
        }
        .overlay {
            RoundedRectangle(cornerRadius: FaceIDGeometry.nowPlayingPanelCornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.5), media.accent.opacity(0.38), .white.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: FaceIDGeometry.nowPlayingPanelCornerRadius, style: .continuous))
        .shadow(color: media.accent.opacity(0.16), radius: 30, y: 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Now playing: \(title) by \(subtitle)")
    }

    @ViewBuilder
    private var artwork: some View {
        if let artwork = media.artwork {
            Image(nsImage: artwork)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .id(media.artworkVersion)
                .transition(.opacity)
                .animation(NotchAnimations.activity, value: media.artworkVersion)
        } else if let icon = media.sourceAppIcon {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(15)
                .background(Color.white.opacity(0.08))
        } else {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(NotchTheme.inkMuted)
                }
        }
    }

    private func transportButton(
        _ symbol: String,
        label: String,
        size: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(NotchTheme.inkPrimary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.white.opacity(0.1)))
                .contentShape(Circle())
                .modifier(InteractiveGlassControl())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(label)
    }
}

/// Shows the detached player only for an armed lock-screen session. The view uses
/// click-through hit testing so a click on the native password field still passes on.
@MainActor
@Observable
final class FaceIDNowPlayingWindowController {
    private let window = NowPlayingPanelWindow()
    private var media: MediaController?
    private var isSkyLightDelegated = false
    private var isArmed = false
    private var cursorPollTimer: Timer?

    init() {
        window.contentView = NSHostingView(rootView: EmptyView())
    }

    func configure(mediaController: MediaController) {
        media = mediaController
        window.contentView = NSHostingView(rootView: FaceIDNowPlayingPlayer(media: mediaController))
        observeMediaVisibility()
        reconcileVisibility()
    }

    /// Track changes arrive through the shared observable media model; observe
    /// them here so the separate panel follows playback without a duplicate poller.
    private func observeMediaVisibility() {
        guard let media else { return }
        withObservationTracking {
            _ = media.hasTrack
            _ = media.isPlaying
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.observeMediaVisibility()
                self.reconcileVisibility()
            }
        }
    }

    func setArmed(_ armed: Bool) {
        isArmed = armed
        reconcileVisibility()
    }

    func repositionIfVisible() {
        guard window.isVisible else { return }
        reconcileVisibility()
    }

    func refresh() {
        reconcileVisibility()
    }

    func hide() {
        guard window.isVisible else { return }
        if isSkyLightDelegated, let skyLight = FaceIDSkyLight.shared {
            skyLight.undelegate(window)
            isSkyLightDelegated = false
        }
        window.ignoresMouseEvents = true
        cursorPollTimer?.invalidate()
        cursorPollTimer = nil
        window.orderOut(nil)
    }

    private var hasTrackToShow: Bool {
        guard let media else { return false }
        return media.hasTrack || media.isPlaying
    }

    private func reconcileVisibility() {
        guard hasTrackToShow, isArmed,
              let screen = FaceIDGeometry.preferredScreen()
        else {
            hide()
            return
        }

        let size = CGSize(
            width: FaceIDGeometry.nowPlayingPlayerWidth,
            height: FaceIDGeometry.nowPlayingPlayerHeight
        )
        window.setFrameOrigin(FaceIDGeometry.nowPlayingOrigin(for: screen, size: size))
        window.orderFrontRegardless()
        if LockMonitor.isScreenActuallyLocked(), let skyLight = FaceIDSkyLight.shared {
            if !isSkyLightDelegated {
                skyLight.delegate(window)
                isSkyLightDelegated = true
            }
        } else if isSkyLightDelegated, let skyLight = FaceIDSkyLight.shared {
            skyLight.undelegate(window)
            isSkyLightDelegated = false
        }
        updateMousePassthrough()
        if cursorPollTimer == nil {
            let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateMousePassthrough() }
            }
            RunLoop.main.add(timer, forMode: .common)
            cursorPollTimer = timer
        }
    }

    private func updateMousePassthrough() {
        // Compute hit testing even when the panel currently ignores mouse events;
        // otherwise the initial click-through state could never be turned off.
        guard window.isVisible else {
            window.ignoresMouseEvents = true
            return
        }
        guard let hostView = window.contentView else { return }
        let windowPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let local = hostView.convert(windowPoint, from: nil)
        let topDown = CGPoint(
            x: local.x,
            y: hostView.isFlipped ? local.y : hostView.bounds.height - local.y
        )
        window.ignoresMouseEvents = !hostView.bounds.contains(topDown)
    }
}

private final class NowPlayingPanelWindow: NSPanel {
    init() {
        let size = CGSize(
            width: FaceIDGeometry.nowPlayingPlayerWidth,
            height: FaceIDGeometry.nowPlayingPlayerHeight
        )
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        level = .mainMenu + 3
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        ignoresMouseEvents = true
        becomesKeyOnlyIfNeeded = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
