import AppKit
import Observation
import SwiftUI

/// The panel's Liquid Glass surface.
///
/// Let the system render the material instead of painting our own tints,
/// highlights, and borders on top of it — that is exactly the custom-background
/// layering Apple asks us to remove. Liquid Glass "reflects color and light of
/// surrounding content", so a restrained artwork tint is enough to make the
/// pane feel owned by the track.
///
/// The panel takes the `.clear` variant, not `.regular`. The brief is a pane
/// that reads as *glass* — you should see the lock-screen photograph bending
/// through it — and `.regular` is the variant that most wants to be read as a
/// solid surface: it lays down enough of its own body to blur the backdrop into
/// opacity. `.clear` transmits far more of what sits behind the pane, which is
/// the whole effect here. Apple's one caution for it is legibility: clear glass
/// gives away almost nothing of its own, so a dimming layer *behind* the glass
/// keeps the white track ink legible over a bright desktop photo. The scrim is
/// deliberately shallow (a fifth of black) — deep enough to anchor white text,
/// shallow enough that the photograph still reads through the pane.
///
/// The artwork tint only nudges the hue; it is kept faint (see the call site)
/// so it cannot haze over the backdrop the way a `.regular` tint would.
///
/// The deployment target is still macOS 14, so the frosted-material fallback
/// remains for older systems. Its fill drops to half opacity to match the
/// clearer read of the glass path rather than the old near-opaque frost.
private struct FaceIDNowPlayingGlassBackground: View {
    let tint: Color

    /// Depth of the legibility scrim behind the clear glass. Shallow by
    /// design: Apple's `.clear` guidance is only that content "remains
    /// legible", not that the pane should stop being see-through.
    private let scrimOpacity: Double = 0.2

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: FaceIDGeometry.nowPlayingPanelCornerRadius, style: .continuous)
    }

    @ViewBuilder
    var body: some View {
        if #available(macOS 26.0, *) {
            shape
                .fill(.clear)
                .glassEffect(.clear.tint(tint), in: shape)
                // Behind the glass, per Apple's `.clear` example, so the
                // material keeps refracting the backdrop while the scrim holds
                // the ink legible over a bright desktop.
                .background(shape.fill(.black.opacity(scrimOpacity)))
        } else {
            shape
                .fill(.ultraThinMaterial.opacity(0.5))
                .overlay {
                    shape.fill(
                        LinearGradient(
                            colors: [.white.opacity(0.1), .white.opacity(0.02), tint.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(.screen)
                }
                .overlay { shape.strokeBorder(.white.opacity(0.16), lineWidth: 0.7) }
        }
    }
}

/// Rounds an individual control with the Liquid Glass material — Apple's
/// guidance is to reach for `glassEffect(_:in:)` on custom interactive
/// controls rather than hand-rolled fills. On macOS 26 the system renders the
/// glass; older systems fall back to a subtle frosted disc so the affordance
/// survives everywhere. The effect is applied *after* the label's own frame so
/// it flows through the transport row and merges in the effect container.
private struct NowPlayingGlassControl: ViewModifier {
    let shape: AnyShape

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: shape)
        } else {
            content.background(shape.fill(.ultraThinMaterial.opacity(0.4)))
        }
    }
}

extension NowPlayingGlassControl {
    static var circle: NowPlayingGlassControl { NowPlayingGlassControl(shape: AnyShape(Circle())) }

    static func roundedRect(cornerRadius: CGFloat) -> NowPlayingGlassControl {
        NowPlayingGlassControl(shape: AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)))
    }
}

/// Groups sibling Liquid Glass controls in a `GlassEffectContainer`. Apple
/// recommends a container both for rendering performance and so the controls'
/// glass can blend/merge instead of stacking as separate layers. A no-op on
/// pre-26 systems, which use a flat material fallback.
private struct NowPlayingGlassRow<Content: View>: View {
    let spacing: CGFloat
    let content: Content

    init(spacing: CGFloat, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}
/// A lock-screen now-playing surface driven by the app's shared media, audio,
/// and brightness controllers. Its glass follows the Liquid Glass reference.
struct FaceIDNowPlayingPlayer: View {
    let media: MediaController
    let audioController: AudioOutputManager
    let brightnessController: BrightnessController

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
                    .frame(width: 112, height: 112)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8)
                    }
                    .shadow(color: media.accent.opacity(0.18), radius: 12, y: 5)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text(media.sourceAppName?.uppercased() ?? "NOW PLAYING")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.25)
                        .foregroundStyle(media.accent.opacity(0.95))
                        .lineLimit(1)

                    Text(title)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(NotchTheme.inkPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // The pane stays up across tracks, and the artwork
                        // beside this text already crossfades; the title and
                        // artist fading through each other keeps the two in
                        // step instead of one swapping while the other eases.
                        .contentTransition(.opacity)
                        .animation(NotchAnimations.content, value: title)

                    Text(subtitle)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(NotchTheme.inkSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentTransition(.opacity)
                        .animation(NotchAnimations.content, value: subtitle)

                    NowPlayingGlassRow(spacing: 21) {
                        HStack(spacing: 21) {
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
                                    .contentShape(Circle())
                                    .modifier(NowPlayingGlassControl.circle)
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
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            TimelineView(.animation(minimumInterval: 0.1, paused: !media.isPlaying)) { _ in
                ScrubberBar(
                    duration: media.track?.duration ?? 0,
                    elapsed: media.currentElapsed,
                    // Matches the timeline above: the fill glides between two
                    // of its ticks instead of stepping at each one.
                    sampleInterval: 0.1,
                    accent: media.accent,
                    onSeek: { media.seek(to: $0) },
                    onScrubPreview: { media.previewScrub(to: $0) },
                    onScrubEnd: { media.endScrubPreview() }
                )
            }
            .frame(height: 18)
            .padding(.horizontal, 2)

            NowPlayingGlassRow(spacing: 12) {
                HStack(spacing: 12) {
                    levelControl(
                        title: "Volume",
                        symbol: audioController.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                        value: audioController.volume,
                        tint: .white,
                        isAvailable: audioController.currentDeviceID != 0,
                        onChange: { audioController.setVolume($0) }
                    )

                    levelControl(
                        title: "Brightness",
                        symbol: "sun.max.fill",
                        value: brightnessController.brightness,
                        tint: Color(red: 1, green: 0.8, blue: 0.2),
                        isAvailable: brightnessController.isAvailable,
                        onChange: { _ = brightnessController.setBrightness($0) }
                    )
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            FaceIDNowPlayingGlassBackground(tint: media.accent.opacity(0.14))
        }
        .overlay {
            // A whisper of a rim so the pane reads as an edge against the
            // desktop photo. The material, not this stroke, does the work, so
            // the stroke is kept barely-there — a heavier highlight would
            // re-solidify the pane we just made see-through.
            RoundedRectangle(cornerRadius: FaceIDGeometry.nowPlayingPanelCornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.22), media.accent.opacity(0.14), .white.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.6
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: FaceIDGeometry.nowPlayingPanelCornerRadius, style: .continuous))
        // A softer, tighter shadow. The old drop was heavy enough to lift the
        // pane off the photo as a slab; glass sits *in* the scene.
        .shadow(color: .black.opacity(0.22), radius: 24, y: 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Now playing: \(title) by \(subtitle)")
    }

    private func levelControl(
        title: String,
        symbol: String,
        value: Float,
        tint: Color,
        isAvailable: Bool,
        onChange: @escaping (Float) -> Void
    ) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 13)
                Text(title)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(NotchTheme.inkSecondary)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text("\(Int(min(max(value, 0), 1) * 100))%")
                    .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(NotchTheme.inkPrimary)
                    .contentTransition(.numericText())
            }

            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { onChange(Float($0)) }
                ),
                in: 0...1
            )
            .controlSize(.small)
            .tint(tint)
            .disabled(!isAvailable)
            .accessibilityLabel(title)
            .accessibilityValue("\(Int(min(max(value, 0), 1) * 100)) percent")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 52)
        .modifier(NowPlayingGlassControl.roundedRect(cornerRadius: 16))
        .opacity(isAvailable ? 1 : 0.55)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title) control")
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
                .frame(width: 36, height: 36)
                .contentShape(Circle())
                .modifier(NowPlayingGlassControl.circle)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(label)
    }
}

/// Shows the detached player whenever playback is available on the
/// CGSession-confirmed lock screen, independently of Face ID activation or
/// scan triggers. Its window remains click-through outside the panel so the
/// native password field still works.
@MainActor
@Observable
final class FaceIDNowPlayingWindowController {
    private let window = NowPlayingPanelWindow()
    private var media: MediaController?
    private var lockMonitor: LockMonitor?
    private var isSkyLightDelegated = false
    private var cursorPollTimer: Timer?
    private var visibilityRetryTimer: Timer?

    /// Development lever: `--debug-now-playing` parks the pane on screen while
    /// the session is unlocked, so the player's layout can be looked at (and
    /// this class's lock-state plumbing exercised) without locking the Mac. It
    /// deliberately never joins the elevated lock-screen space.
    private static var debugAlwaysVisible: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--debug-now-playing")
        #else
        false
        #endif
    }

    init() {
        window.contentView = NSHostingView(rootView: EmptyView())
    }

    func configure(
        mediaController: MediaController,
        lockMonitor: LockMonitor,
        audioController: AudioOutputManager,
        brightnessController: BrightnessController
    ) {
        media = mediaController
        self.lockMonitor = lockMonitor
        window.contentView = NSHostingView(
            rootView: FaceIDNowPlayingPlayer(
                media: mediaController,
                audioController: audioController,
                brightnessController: brightnessController
            )
        )
        observeMediaVisibility()
        observeScreenLockState()
        startVisibilityRetry()
        reconcileVisibility()
    }

    /// Track changes arrive through the shared observable media model; observe
    /// them here so the separate panel follows playback without a duplicate poller.
    private func observeMediaVisibility() {
        guard let media else { return }
        withObservationTracking {
            _ = media.hasTrack
            _ = media.isPlaying
            // Also tracked: whether this session is music at all is decided by
            // which app owns it, and a source can change under a track that
            // stays put (the adapter naming its client a moment after launch).
            _ = media.sourceAppBundleID
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.observeMediaVisibility()
                self.reconcileVisibility()
            }
        }
    }

    /// Re-checks both media and lock state, including after display changes.
    func refresh() {
        reconcileVisibility()
    }

    private func observeScreenLockState() {
        guard let lockMonitor else { return }
        withObservationTracking {
            // Observe only macOS's authoritative lock bit. Face ID's pending
            // lock/wake trigger is a scan policy, not a prerequisite for media UI.
            _ = lockMonitor.confirmedScreenLockState
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.observeScreenLockState()
                self.reconcileVisibility()
            }
        }
    }

    func hide() {
        if isSkyLightDelegated, let skyLight = FaceIDSkyLight.shared {
            skyLight.undelegate(window)
            isSkyLightDelegated = false
        }
        if !window.ignoresMouseEvents {
            window.ignoresMouseEvents = true
        }
        cursorPollTimer?.invalidate()
        cursorPollTimer = nil
        guard window.isVisible else { return }
        // Ordered out directly and left fully opaque for the next arrival.
        window.orderOut(nil)
        window.alphaValue = 1
        #if DEBUG
        print("[FaceID] player: hidden")
        #endif
    }

    private func startVisibilityRetry() {
        guard visibilityRetryTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let lockMonitor = self.lockMonitor else { return }
                _ = lockMonitor.refreshFromSystem()
                self.refresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        visibilityRetryTimer = timer
    }

    /// Music only. MediaRemote carries a session for anything the system is
    /// playing — a browser video, a video file, the TV app, a podcast — and a
    /// transport pane over any of those is not what this surface is for. The
    /// test is `musicPlayerOwnsSource`, the same one the transport uses: the
    /// session belongs to one of the two music players the notch can drive.
    /// An unrecognized client is not music, so nothing is shown for it.
    private var hasTrackToShow: Bool {
        guard let media else { return false }
        guard media.hasTrack || media.isPlaying else { return false }
        return media.musicPlayerOwnsSource
    }

    private func reconcileVisibility() {
        // The authoritative session bit is re-read here rather than mirrored
        // from the lock monitor: this runs both from the retry timer and from
        // every observation change, and a mirror that is one refresh behind is
        // exactly how the pane ends up ordered out with the lock screen up.
        let isLocked = LockMonitor.isScreenActuallyLocked()
        guard hasTrackToShow, Self.debugAlwaysVisible || isLocked,
              let screen = FaceIDGeometry.preferredScreen()
        else {
            hide()
            return
        }

        let size = CGSize(
            width: FaceIDGeometry.nowPlayingPlayerWidth,
            height: FaceIDGeometry.nowPlayingPlayerHeight
        )
        // Both of these are idempotent, but only the transitions are applied.
        // This runs again from the 1 Hz visibility retry, and re-ordering a
        // window that is already front forces the hosted Liquid Glass through
        // another render pass on top of the frame it is already drawing —
        // SwiftUI reports that as "glassEffect() tried to update multiple
        // times per frame".
        let origin = FaceIDGeometry.nowPlayingOrigin(for: screen, size: size)
        if window.frame.origin != origin {
            window.setFrameOrigin(origin)
        }
        // Into the elevated space before it is ordered in, so the pane arrives
        // already above the login window instead of being composited once in
        // the ordinary space. Never while the debug lever is on: a delegated
        // window floats over everything, which is not what a desktop preview
        // of the player is for.
        if isLocked, !Self.debugAlwaysVisible, let skyLight = FaceIDSkyLight.shared {
            if !isSkyLightDelegated {
                skyLight.delegate(window)
                isSkyLightDelegated = true
            }
        } else if isSkyLightDelegated, let skyLight = FaceIDSkyLight.shared {
            skyLight.undelegate(window)
            isSkyLightDelegated = false
        }
        if !window.isVisible {
            // Fully opaque before it is ordered in, never faded up from zero.
            // AppKit's `NSAnimationContext` window-alpha animation does not
            // commit for this background accessory app (reproduced on macOS
            // 27: the animator leaves `alphaValue` at 0 while a direct write
            // sticks), so a pane whose arrival hangs on that fade is simply
            // never seen. That is the bug this replaced: the arrival was an
            // `alphaValue = 0` write followed by a fade that never landed, so
            // the window was on screen and invisible the entire time.
            window.alphaValue = 1
            window.orderFrontRegardless()
            #if DEBUG
            print("[FaceID] player: shown locked=\(isLocked) preview=\(Self.debugAlwaysVisible) "
                + "track=\(media?.hasTrack ?? false) playing=\(media?.isPlaying ?? false) "
                + "screen=\(screen.localizedName)")
            #endif
        } else if window.alphaValue < 1 {
            window.alphaValue = 1
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
        let shouldIgnore: Bool
        if window.isVisible, let hostView = window.contentView {
            let windowPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
            let local = hostView.convert(windowPoint, from: nil)
            let topDown = CGPoint(
                x: local.x,
                y: hostView.isFlipped ? local.y : hostView.bounds.height - local.y
            )
            shouldIgnore = !hostView.bounds.contains(topDown)
        } else {
            shouldIgnore = true
        }
        // Only write on a change. This runs from a 30 Hz cursor poll, and
        // re-assigning the value it already has still makes AppKit redo the
        // window's mouse tracking, which fires enter/exit at the cursor and
        // rebuilds the interactive glass controls' hover state every tick —
        // the other half of the "glassEffect() tried to update multiple times
        // per frame" report. Same guard as the notch panel's own pointer-driven
        // click-through.
        if window.ignoresMouseEvents != shouldIgnore {
            window.ignoresMouseEvents = shouldIgnore
        }
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
