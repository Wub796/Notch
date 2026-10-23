import AppKit
import Observation
import SwiftUI

/// The panel's Liquid Glass surface.
///
/// Let the system render the material instead of painting our own tints,
/// highlights, and borders on top of it — that is exactly the custom-background
/// layering Apple asks us to remove. Liquid Glass "reflects color and light of
/// surrounding content" on its own, and what surrounds this pane is the user's
/// lock-screen photograph.
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
/// The pane is deliberately colourless. It used to carry a tint taken from the
/// artwork, which made the glass read as a wash of the album cover rather than
/// as glass — and this pane sits on the user's own lock-screen photograph, whose
/// colour is the only one that belongs there.
///
/// The deployment target is still macOS 14, so the frosted-material fallback
/// remains for older systems. Its fill drops to half opacity to match the
/// clearer read of the glass path rather than the old near-opaque frost.
private struct FaceIDNowPlayingGlassBackground: View {
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
                .glassEffect(.clear, in: shape)
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
                            colors: [.white.opacity(0.1), .white.opacity(0.02), .white.opacity(0.05)],
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
/// A lock-screen now-playing surface driven by the app's shared media model.
///
/// The composition is the one macOS and iOS put on a lock screen: the artwork
/// on the leading side with the title and artist beside it, a seek bar reading
/// elapsed on the left and remaining on the right, and one row of evenly spaced
/// transport glyphs beneath it. The glass behind all of it takes no colour from
/// the track, so the pane stays glass over the user's own photograph.
///
/// It is only ever the player: volume and brightness belong to the notch's own
/// HUD, which is where the rest of the app shows them, and repeating that pair
/// here put two of the same control on one lock screen.
struct FaceIDNowPlayingPlayer: View {
    let media: MediaController
    let audioController: AudioOutputManager

    private var title: String {
        if let title = media.track?.title, !title.isEmpty { return title }
        return media.sourceAppName ?? "Now Playing"
    }

    private var subtitle: String {
        if let artist = media.track?.artist, !artist.isEmpty { return artist }
        return media.isPlaying ? "Playing" : "Paused"
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                artwork
                    .frame(width: 92, height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
                    }
                    .shadow(color: .black.opacity(0.28), radius: 10, y: 4)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 19, weight: .semibold))
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
                        .font(.system(size: 15))
                        .foregroundStyle(NotchTheme.inkSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentTransition(.opacity)
                        .animation(NotchAnimations.content, value: subtitle)
                }
            }

            TimelineView(.animation(minimumInterval: 0.1, paused: !media.isPlaying)) { _ in
                ScrubberBar(
                    duration: media.track?.duration ?? 0,
                    elapsed: media.currentElapsed,
                    // Matches the timeline above: the fill glides between two
                    // of its ticks instead of stepping at each one.
                    sampleInterval: 0.1,
                    // White, not the artwork's accent: on this pane the
                    // reference keeps every control monochrome and lets the
                    // photograph around the glass carry the colour.
                    accent: .white,
                    onSeek: { media.seek(to: $0) },
                    onScrubPreview: { media.previewScrub(to: $0) },
                    onScrubEnd: { media.endScrubPreview() }
                )
            }
            .frame(height: 18)

            HStack(spacing: 0) {
                favoriteButton
                transportButton("backward.fill", label: "Previous track") {
                    media.previousTrack()
                }
                playPauseButton
                transportButton("forward.fill", label: "Next track") {
                    media.nextTrack()
                }
                outputMenu
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            FaceIDNowPlayingGlassBackground()
        }
        .overlay {
            // A whisper of a rim so the pane reads as an edge against the
            // desktop photo. The material, not this stroke, does the work, so
            // the stroke is kept barely-there — a heavier highlight would
            // re-solidify the pane we just made see-through.
            RoundedRectangle(cornerRadius: FaceIDGeometry.nowPlayingPanelCornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.22), .white.opacity(0.10), .white.opacity(0.06)],
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

    @ViewBuilder
    private var artwork: some View {
        if let artwork = media.cover.image {
            Image(nsImage: artwork)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .id(media.cover.version)
                .transition(.opacity)
                .animation(NotchAnimations.activity, value: media.cover.version)
        } else if let icon = media.sourceAppIcon {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(12)
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

    /// Every control in the row takes an equal share of the width, which is what
    /// spaces the five glyphs evenly from edge to edge.
    private func transportButton(
        _ symbol: String,
        label: String,
        size: CGFloat = 20,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(NotchTheme.inkPrimary)
                .frame(maxWidth: .infinity, minHeight: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(label)
    }

    private var playPauseButton: some View {
        Button {
            media.togglePlayPause()
        } label: {
            Image(systemName: media.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(NotchTheme.inkPrimary)
                .frame(maxWidth: .infinity, minHeight: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .contentTransition(.symbolEffect(.replace))
        .accessibilityLabel(media.isPlaying ? "Pause" : "Play")
    }

    /// Only one player can take a favourite from here — see `MediaController`'s
    /// `canFavorite` — so the glyph dims rather than pretending when the track
    /// belongs to an app that has no such switch.
    private var favoriteButton: some View {
        Button {
            media.toggleFavorite()
        } label: {
            Image(systemName: media.isFavorite ? "heart.fill" : "heart")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(NotchTheme.inkPrimary)
                .frame(maxWidth: .infinity, minHeight: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!media.canFavorite)
        .opacity(media.canFavorite ? 1 : 0.35)
        .accessibilityLabel(media.isFavorite ? "Remove from favourites" : "Add to favourites")
    }

    /// Where the sound is going, and where else it could go — the same system
    /// default output the notch's own audio screens read and set.
    private var outputMenu: some View {
        Menu {
            ForEach(audioController.devices) { device in
                Button {
                    audioController.select(device)
                } label: {
                    Label(device.name, systemImage: device.symbolName)
                }
            }
        } label: {
            Image(systemName: audioController.currentSymbol)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(NotchTheme.inkPrimary)
                .frame(maxWidth: .infinity, minHeight: 36)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Output: \(audioController.currentDeviceName)")
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
        audioController: AudioOutputManager
    ) {
        media = mediaController
        self.lockMonitor = lockMonitor
        window.contentView = NSHostingView(
            rootView: FaceIDNowPlayingPlayer(
                media: mediaController,
                audioController: audioController
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
