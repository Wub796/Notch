import SwiftUI

/// Step one: what the notch is, and the one thing worth doing before anything
/// else — touching it.
///
/// The demo is a miniature of the top of the screen drawn inside the window
/// rather than a pointer to the real thing: the real notch is a few centimetres
/// above this window and a first-run screen that says "look up there" loses
/// every visitor who does not.
///
/// It is not a drawing of the notch, it is a *picture* of it: every size in it —
/// the open panel, the closed pill, both corner radii, the artwork, the icon
/// strip, the menu bar's type — is the app's own, drawn at full size and scaled
/// once. The panel is therefore as wide, as shallow and as round as the real one
/// on this Mac, and it follows the size preferences rather than disagreeing with
/// them.
struct OnboardingWelcomeView: View {
    /// Only for its geometry: the demo asks the app how big its notch and panel
    /// actually are instead of carrying its own idea of them.
    let state: NotchState

    @State private var isOpen: Bool
    @State private var isPinned = false
    @State private var hasTried: Bool
    @State private var isPlaying = true
    @State private var elapsed: Double = 84
    /// The pending close, so a pointer crossing the notch cannot flicker it.
    @State private var closeTask: Task<Void, Never>?
    @State private var arrivalTask: Task<Void, Never>?
    /// The panel's contents have arrived — see `startPanelArrival()`.
    @State private var panelArrived = false
    /// The opening sweep has been armed.
    @State private var sheenArmed = false
    /// Flips once, on entry: the screen arrives in the order it is read, the
    /// same way every other screen in the flow does.
    @State private var appeared = false

    /// - Parameter startsOpen: renders the demo with its panel already open.
    ///   Only ever set by `--debug-render-onboarding`, which draws the picture
    ///   offscreen to be measured — a hovered, open panel is the state worth
    ///   measuring, and no headless run can produce a hover.
    init(state: NotchState, startsOpen: Bool = false) {
        self.state = state
        _isOpen = State(initialValue: startsOpen)
        _hasTried = State(initialValue: startsOpen)
        // The panel's contents are staged in by `startPanelArrival()`, which
        // needs a live frame or two to run — an offscreen render is over before
        // it could, so the measured picture would be a panel with nothing in
        // it. Started open, the contents begin arrived: the render exists to
        // measure the panel, and an empty one cannot be measured.
        _panelArrived = State(initialValue: startsOpen)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            hero
                .onboardingReveal(0, appeared: appeared)
            menuBarDemo
                .padding(.top, 18)
                .onboardingReveal(1, appeared: appeared)
            tryCard
                .padding(.top, 14)
                .onboardingReveal(2, appeared: appeared)
            rows
                .padding(.top, 14)
                .onboardingReveal(3, appeared: appeared)
            Spacer(minLength: 8)
            Text("Notch lives in your menu bar — no Dock icon, no window to manage.")
                .font(.system(size: 10.5))
                .foregroundStyle(NotchTheme.inkMuted)
                .padding(.bottom, 2)
                .onboardingReveal(4, appeared: appeared)
        }
        .onAppear { appeared = true }
        .padding(.horizontal, 26)
        .padding(.top, 28)
        // The demo's own clock: only the demo reads it, and pausing the
        // transport pauses it, which is the whole reason the play button is
        // there. A task rather than a timer publisher so it dies with the view.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, isPlaying else { continue }
                elapsed = (elapsed + 1).truncatingRemainder(dividingBy: Self.duration)
            }
        }
        .onDisappear {
            closeTask?.cancel()
            arrivalTask?.cancel()
        }
        .onChange(of: isOpen) { _, open in
            if !open { resetPanelArrival() }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Meet your notch.")
                .font(.system(size: 26, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(NotchTheme.inkPrimary)
            Text("The black strip at the top of your Mac. Hover it to peek, click it to open the panel, and drop things on it to shelve them.")
                .font(.system(size: 13))
                .lineSpacing(2)
                .foregroundStyle(NotchTheme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - The demo

    // MARK: Geometry, from the app itself

    /// The picture's geometry, derived from the app's own — see
    /// `OnboardingDemoGeometry`. Nothing about the demo's size is decided here.
    private var geometry: OnboardingDemoGeometry { .current(state: state) }

    private var menuBarDemo: some View {
        // The height is the crop's own aspect ratio applied to the width the
        // window gives it — not a number picked for it, which is what keeps the
        // miniature honest when the panel's size preference changes.
        Color.clear
            .aspectRatio(geometry.crop.width / geometry.crop.height, contentMode: .fit)
            .overlay {
                GeometryReader { proxy in
                    picture(scale: geometry.scale(fitting: proxy.size.width))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
            )
            .accessibilityElement()
            .accessibilityLabel("A miniature of the top of your screen with the notch in it")
    }

    /// Everything is drawn at the size the app draws it — the picture is `crop`
    /// points wide, in real 13pt menu bar type and a real 18pt title — and the
    /// finished picture is then scaled in one move.
    ///
    /// This is the whole reason the miniature can be trusted: the panel, the
    /// pill, the artwork, the icon strip and the type all carry the app's own
    /// sizes, and a single `scaleEffect` shrinks them together. A part with a
    /// number of its own could be wrong; a part with the app's number cannot.
    private func picture(scale k: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [Color(white: 0.145), Color(white: 0.065)],
                startPoint: .top,
                endPoint: .bottom
            )
            menuBarStrip
            notchPicture
        }
        .frame(width: geometry.crop.width, height: geometry.crop.height, alignment: .topLeading)
        .scaleEffect(k, anchor: .topLeading)
        .frame(
            width: geometry.crop.width * k,
            height: geometry.crop.height * k,
            alignment: .topLeading
        )
    }

    /// The menu bar the notch is welded to, at its real height and type size.
    /// Drawn rather than described: the point of the screen is that the notch is
    /// *part of* the bar, and the clock and status glyphs are what make it read
    /// as one.
    private var menuBarStrip: some View {
        HStack(spacing: 22) {
            Text("Notch").fontWeight(.semibold)
            Text("Settings")
            Text("Help")
            Spacer(minLength: 0)
            Image(systemName: "wifi")
            Image(systemName: "battery.100")
            Text("Tue 9:41 AM")
        }
        .font(.system(size: 13))
        .foregroundStyle(NotchTheme.inkMuted)
        .padding(.horizontal, 12)
        .frame(width: geometry.crop.width, height: geometry.notch.height, alignment: .leading)
        // The bar steps back when the panel opens, the way a real menu bar
        // recedes behind the notch rather than competing with it.
        .opacity(isOpen ? 0.7 : 1)
        .animation(OnboardingMotion.notchSpring, value: isOpen)
    }

    /// The pill, and the panel it becomes — both at the app's own size for that
    /// state, the panel hanging from the top of the crop the way the real one
    /// hangs from the top of the screen.
    private var notchPicture: some View {
        // Closed, this is the *drawn* pill rather than the cutout: the wings the
        // demo shows are part of the shape the app paints, so the picture's
        // closed shape and its containing frame are `closedPill`. The cutout
        // inside it (`geometry.notch`) is still where the wing layout reserves
        // its dead zone and where the open panel's hardware cutout is drawn.
        let size = isOpen ? geometry.slab : geometry.closedPill
        let radii = isOpen ? geometry.openRadii : geometry.closedRadii

        return ZStack(alignment: .top) {
            // Behind the pill, outward: the invitation to touch it, gone for
            // good once it has been. Around the whole pill rather than the
            // cutout — a ring drawn at the cutout's width would sit entirely
            // behind the pill's own wings — see `closedPill` in
            // `OnboardingDemoGeometry`.
            OnboardingInviteHalo(
                width: geometry.closedPill.width,
                height: geometry.closedPill.height,
                topRadius: geometry.closedRadii.top,
                bottomRadius: geometry.closedRadii.bottom,
                isActive: !hasTried
            )

            NotchShape(
                topCornerRadius: radii.top,
                bottomCornerRadius: radii.bottom
            )
            .fill(Color(white: 0.02))
            .overlay {
                NotchShape(
                    topCornerRadius: radii.top,
                    bottomCornerRadius: radii.bottom
                )
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
            }

            // The pill's contents leave *into* the pill and come back only after
            // the panel has cleared, which is the handoff the real closed strip
            // makes (`NotchAnimations.closedStrip`): the two never cross-fade
            // over each other.
            closedContent
                .scaleEffect(isOpen && !reduced ? 0.9 : 1, anchor: .center)
                .blur(radius: isOpen && !reduced ? 1.5 : 0)
                .opacity(isOpen ? 0 : 1)
                .animation(
                    isOpen ? .easeOut(duration: 0.10) : .easeOut(duration: 0.20).delay(0.12),
                    value: isOpen
                )

            // The panel's contents exist only while the panel does.
            //
            // Laid out inside the closed pill instead — which is how this
            // started — the module's own minimum size is larger than the pill
            // in both directions: the cover, the title and the Now/Audio switch
            // cannot compress past a certain width, and the two cards cannot
            // compress past their heights. A ZStack is as big as its largest
            // child, so the pill's own black shape grew to hold a panel that
            // was not on screen, and the closed notch was drawn as a slab. The
            // real thing has no module until it opens, and neither does this.
            if isOpen {
                panelContent
                    .frame(
                        width: geometry.slab.width,
                        height: geometry.slab.height,
                        alignment: .top
                    )
                    .clipShape(
                        NotchShape(topCornerRadius: radii.top, bottomCornerRadius: radii.bottom)
                    )
                    .overlay {
                        // The unfolded glass catching the light, once, as it
                        // opens.
                        OnboardingSheen(isActive: sheenArmed, cornerRadius: radii.bottom)
                            .clipShape(
                                NotchShape(
                                    topCornerRadius: radii.top,
                                    bottomCornerRadius: radii.bottom
                                )
                            )
                    }
                    .transition(.opacity.animation(
                        isOpen ? .easeOut(duration: 0.24) : .easeOut(duration: 0.09)
                    ))
                    .onAppear { startPanelArrival() }
                    .onDisappear { resetPanelArrival() }
            }

            if isOpen {
                // The hardware notch itself, drawn over the panel's header the
                // way the real dead zone is: a cutout the header's own controls
                // flank, not something they move aside for. Its band is the
                // header's, so the silhouette's lower corners round into the
                // panel where the app's own dead zone does.
                NotchShape(
                    topCornerRadius: geometry.closedRadii.top,
                    bottomCornerRadius: geometry.closedRadii.bottom
                )
                .fill(Color(white: 0.02))
                .frame(width: geometry.notch.width, height: geometry.topBar)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)
            }
        }
        .frame(width: size.width, height: size.height)
        // Centered in the crop, hanging from its top: the panel is as wide as
        // the app makes it, not as wide as the window happens to be.
        .frame(width: geometry.crop.width, alignment: .top)
        .animation(OnboardingMotion.notchSpring, value: isOpen)
        .contentShape(Rectangle())
        .onHover(perform: hoverChanged)
        .onTapGesture {
            isPinned.toggle()
            setOpen(isPinned)
        }
        .accessibilityElement()
        .accessibilityLabel("The notch — hover to peek, click to open")
        .accessibilityAddTraits(.isButton)
    }

    /// The closed pill's own contents, in the app's own wings: the cover tile in
    /// the leading one and the visualiser in the trailing one, at the insets
    /// `CollapsedNotchView` places them at. `ActivityWingLayout` is the app's own
    /// wing layout, so the two sides and the dead zone between them are arranged
    /// exactly as they are on the real pill.
    private var closedContent: some View {
        ActivityWingLayout(
            notchWidth: geometry.notch.width,
            leading: RoundedRectangle(
                cornerRadius: OnboardingDemoGeometry.closedArtworkCorner,
                style: .continuous
            )
            .fill(artwork)
            .frame(
                width: OnboardingDemoGeometry.closedArtworkSide,
                height: OnboardingDemoGeometry.closedArtworkSide
            ),
            leadingInset: NotchSizing.closedArtworkInset,
            trailing: OnboardingMeter(
                bars: 3,
                width: 4,
                range: 4 ... 15,
                tint: demoAccent,
                isActive: isPlaying
            ),
            trailingInset: NotchSizing.closedWingInset
        )
    }

    /// The open panel, arriving in the order it is read: the hero card first,
    /// then the playback card under it. Each waits a beat longer than the one
    /// before it and neither scales up from nothing — the panel has already
    /// unfolded around them, so they only have to settle into place.
    private var panelContent: some View {
        VStack(spacing: OnboardingDemoGeometry.headerGap) {
            header

            VStack(spacing: geometry.sectionGap) {
                heroTile
                    .modifier(DemoPartEffect(isOpen: panelArrived, reduced: reduced))
                    .animation(demoArrival(0, open: panelArrived), value: panelArrived)

                playbackTile
                    .modifier(DemoPartEffect(isOpen: panelArrived, reduced: reduced))
                    .animation(demoArrival(1, open: panelArrived), value: panelArrived)
            }
            .padding(.bottom, geometry.bottomSafe)
            .frame(height: geometry.module)
        }
        .padding(.horizontal, geometry.sideInset)
        .padding(.bottom, geometry.bottomInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// The strip the real panel keeps at its top: the back button that leaves
    /// the audio page, at the page's own size and corner. The app's trailing
    /// flank is empty on this page, and the notch's own dead zone is drawn over
    /// the strip afterwards — the header flanks the notch, it does not move out
    /// of its way.
    private var header: some View {
        // `NotchBackButton`, drawn rather than used: the demo's panel is one tap
        // target that pins it open, and a live button inside it would eat the
        // clicks that landed on it.
        Image(systemName: "chevron.left")
            .font(.system(size: 13, weight: .heavy))
            .foregroundStyle(NotchTheme.inkPrimary)
            .frame(width: 28, height: 28)
            .background(Circle().fill(.white.opacity(0.12)))
            .padding(.top, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: geometry.topBar)
            .allowsHitTesting(false)
    }

    /// The card the Now page leads with: the cover and what is playing on the
    /// left, the Now/Audio switch on the right, on the page's own tile at its
    /// own radius. The cover is the 76pt one the page actually draws.
    private var heroTile: some View {
        HStack(alignment: .top, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                RoundedRectangle(
                    cornerRadius: OnboardingDemoGeometry.heroArtworkCorner,
                    style: .continuous
                )
                .fill(artwork)
                .frame(
                    width: OnboardingDemoGeometry.heroArtwork.width,
                    height: OnboardingDemoGeometry.heroArtwork.height
                )
                .shadow(color: demoAccent.opacity(0.38), radius: 14, y: 5)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Sunset Drive")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(NotchTheme.inkPrimary)
                        .lineLimit(1)
                    artistRow
                    Text("Afterglow")
                        .font(.notchCaption)
                        .foregroundStyle(NotchTheme.inkSecondary)
                        .lineLimit(1)
                }
            }
            .padding(.top, 6)

            Spacer(minLength: 8)

            sectionSwitch
        }
        .padding(.horizontal, NotchTheme.Space.m)
        .padding(.vertical, NotchTheme.Space.s)
        .frame(height: geometry.heroTile)
        .notchTile(radius: NotchTheme.Radius.card)
    }

    /// The artist as the page draws them: an initialled disc, then the name.
    private var artistRow: some View {
        HStack(spacing: 8) {
            Text("A")
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundStyle(NotchTheme.inkPrimary)
                .frame(width: 18, height: 18)
                .background(Circle().fill(NotchTheme.surfaceHover))

            Text("Aurora Lane")
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundStyle(NotchTheme.inkPrimary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
    }

    /// The page's section switch: one capsule holding its two pills, the live
    /// one filled with the system accent.
    private var sectionSwitch: some View {
        HStack(spacing: 4) {
            sectionPill("Now", "music.note.list", isActive: true)
            sectionPill("Audio", "hifispeaker.fill", isActive: false)
        }
        .padding(3)
        .background(Capsule().fill(Color.white.opacity(0.06)))
    }

    private func sectionPill(_ title: String, _ symbol: String, isActive: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
        }
        .foregroundStyle(isActive ? Color.white : NotchTheme.inkSecondary)
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background {
            if isActive {
                Capsule().fill(Color.accentColor)
            }
        }
    }

    /// The card under the hero: the playhead, the transport, and the
    /// shuffle/heart row, at the page's own sizes — a 38pt circle for the one
    /// control that actually does something here, 28pt between them.
    private var playbackTile: some View {
        VStack(alignment: .leading, spacing: NotchTheme.Space.s) {
            scrubberRow
            transportRow
            bottomActions
        }
        .padding(.horizontal, NotchTheme.Space.m)
        .padding(.vertical, NotchTheme.Space.s)
        .frame(height: geometry.playbackTile)
        .notchTile(radius: NotchTheme.Radius.card)
    }

    /// The seek bar, as `ScrubberBar` draws it: the elapsed time, the track with
    /// the cover's own accent through it, and what is left of the track.
    private var scrubberRow: some View {
        HStack(spacing: 8) {
            Text(timeLabel)
                .contentTransition(.numericText())

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.16))
                    Capsule()
                        .fill(demoAccent)
                        .frame(width: proxy.size.width * elapsed / Self.duration)
                }
                .frame(height: 4)
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 14)

            Text(remainingLabel)
                .contentTransition(.numericText())
        }
        .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
        .foregroundStyle(NotchTheme.inkPrimary)
    }

    private var transportRow: some View {
        HStack(spacing: 28) {
            transportGlyph("backward.fill")

            Button {
                isPlaying.toggle()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(NotchTheme.inkPrimary)
                    // The glyph swaps rather than cutting to the other one.
                    .contentTransition(reduced ? .opacity : .symbolEffect(.replace))
                    .symbolEffect(.bounce, value: isPlaying)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.white.opacity(0.12)))
                    .contentShape(Circle())
            }
            .buttonStyle(PressableButtonStyle())
            .help(isPlaying ? "Pause the demo" : "Play the demo")

            transportGlyph("forward.fill")
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    /// The row under the transport: shuffle, favourite, lyrics.
    private var bottomActions: some View {
        HStack(spacing: 28) {
            transportGlyph("shuffle", size: 15)
            transportGlyph("heart", size: 15)
            transportGlyph("list.bullet.rectangle", size: 15)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func transportGlyph(_ symbol: String, size: CGFloat = 16) -> some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(NotchTheme.inkPrimary)
            .frame(width: 30, height: 30)
    }

    /// The colour the cover hands the player: the app tints the playhead and the
    /// pill's meter with the artwork's own average, so the demo uses the middle
    /// of its cover's gradient.
    private var demoAccent: Color {
        Color(red: 185 / 255, green: 94 / 255, blue: 144 / 255)
    }

    /// One part of the panel, arriving after the pill has begun to grow, and
    /// leaving in the reverse of the order it arrived in.
    ///
    /// The departure is quick and slightly staggered — the transport goes, then
    /// what is playing, then the artwork — because the pill is already
    /// contracting around it: contents that linger on a shape that is closing
    /// read as a rendering fault rather than as a transition.
    private func demoArrival(_ index: Int, open: Bool) -> Animation {
        guard !OnboardingMotion.prefersReducedMotion else { return NotchAnimations.reduced }
        guard open else { return .easeOut(duration: 0.09).delay(Double(2 - index) * 0.02) }
        return .timingCurve(0.23, 1, 0.32, 1, duration: 0.30).delay(0.06 + Double(index) * 0.05)
    }

    private var reduced: Bool { OnboardingMotion.prefersReducedMotion }

    private var artwork: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 244 / 255, green: 114 / 255, blue: 88 / 255),
                Color(red: 126 / 255, green: 74 / 255, blue: 200 / 255),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// The demo's own elapsed time, so the playhead and the two times agree
    /// with each other.
    private var timeLabel: String { Self.label(elapsed) }

    /// What is left of the track, as `ScrubberBar` shows it by default: a
    /// countdown, with the minus sign it prefixes one with.
    private var remainingLabel: String { "−" + Self.label(Self.duration - elapsed) }

    private static func label(_ interval: Double) -> String {
        let seconds = Int(interval)
        return "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }

    /// The track the demo is playing: 3:47, the length the picture's right-hand
    /// time has always shown.
    private static let duration: Double = 227

    // MARK: - Copy

    private var tryCard: some View {
        HStack(spacing: 12) {
            Image(systemName: hasTried ? "checkmark" : "arrow.up")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(hasTried ? OnboardingVerdict.grantedInk : NotchTheme.inkSecondary)
                .contentTransition(reduced ? .opacity : .symbolEffect(.replace))
                // Deliberately not pulsing. The invitation is the ring around
                // the notch — the thing to actually touch — and two things
                // competing for attention is worse than one, besides being a
                // redraw per frame for as long as the screen is open.
                .frame(width: 30, height: 30)
                .background {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(hasTried ? Color.green.opacity(0.18) : Color.white.opacity(0.075))
                }
                .scaleEffect(hasTried && !reduced ? 1.06 : 1)
                .animation(OnboardingMotion.confirmation, value: hasTried)

            VStack(alignment: .leading, spacing: 3) {
                Text(hasTried ? "That's it." : "Try it right now")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(NotchTheme.inkPrimary)
                Text(hasTried
                     ? "Hover peeks, click pins it open, click again lets it close."
                     : "Point at the notch above — it opens on hover.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(NotchTheme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(hasTried ? Color.green.opacity(0.12) : Color.white.opacity(0.05))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            hasTried ? Color.green.opacity(0.28) : Color.white.opacity(0.075),
                            lineWidth: 1
                        )
                }
        }
        .animation(NotchAnimations.content, value: hasTried)
    }

    private var rows: some View {
        VStack(spacing: 0) {
            row("cursorarrow.motionlines", "Hover", "Peek at what's playing.")
            divider
            row("cursorarrow.click", "Click", "Open the full panel, and keep it open.")
            divider
            row("arrow.down.doc", "Drop", "Shelve a file or a snippet, drag it back out later.")
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(height: 1)
    }

    private func row(_ icon: String, _ name: String, _ description: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(NotchTheme.inkMuted)
                .frame(width: 20)
            Text(name)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(NotchTheme.inkPrimary)
                .frame(width: 62, alignment: .leading)
            Text(description)
                .font(.system(size: 11.5))
                .foregroundStyle(NotchTheme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }

    // MARK: - State

    private func setOpen(_ open: Bool) {
        isOpen = open
        if open, !hasTried { hasTried = true }
    }

    /// The panel's own arrival: the two cards and the opening sweep are staged
    /// a beat after the panel's shape appears, because a view that has just
    /// been inserted has no state change yet for an animation to hang on. Set
    /// from the panel content's `onAppear`, which only exists while it does.
    private func startPanelArrival() {
        arrivalTask?.cancel()
        arrivalTask = Task { @MainActor in
            // A beat, so the inserted content is on screen first: set in the
            // same transaction that inserted it, the state change has nothing
            // to animate from and the arrival is skipped.
            try? await Task.sleep(for: .seconds(0.05))
            guard !Task.isCancelled, isOpen else { return }
            sheenArmed = true
            panelArrived = true
        }
    }

    private func resetPanelArrival() {
        arrivalTask?.cancel()
        panelArrived = false
        sheenArmed = false
    }

    /// A pointer crossing the notch should not flicker it shut, so the close
    /// waits a beat. Opening is immediate, because that is the answer to what
    /// the pointer just asked.
    private func hoverChanged(_ hovering: Bool) {
        closeTask?.cancel()
        guard !hovering else { return setOpen(true) }
        guard !isPinned else { return }

        closeTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(OnboardingMotion.demoCloseGrace))
            guard !Task.isCancelled else { return }
            setOpen(false)
        }
    }

}

/// A part of the demo panel arriving.
///
/// Out of a slight blur and a scale anchored to the top, which is what the real
/// panel's content does (`NotchAnimations.panelContent`): the demo's job is to
/// show the app's motion rather than a hand-drawn approximation of it, and the
/// blur is most of why the real thing reads as glass resolving rather than as
/// items appearing. Under Reduce Motion it is a plain fade.
private struct DemoPartEffect: ViewModifier {
    let isOpen: Bool
    let reduced: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(isOpen || reduced ? 1 : 0.97, anchor: .top)
            .blur(radius: isOpen || reduced ? 0 : 2.5)
            .opacity(isOpen ? 1 : 0)
    }
}
