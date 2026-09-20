import AppKit
import SwiftUI

/// Collapsed and peek states: glass, hugging the hardware notch, with
/// live-activity wings — the weather glyph on the left and its bold
/// temperature on the right, now playing, a volume HUD, battery events,
/// or an imminent meeting.
struct CollapsedNotchView: View {
    let state: NotchState

    var body: some View {
        // Top-anchored, deliberately. The strip fills a frame exactly as tall as
        // `collapsedSize`, and centring it meant any mismatch — a drop height a
        // few points short of what is actually drawn — was split between the top
        // and bottom edges, pushing the wings up off the hardware notch. Anchored
        // to the top, the notch's own row can only ever stay welded where it
        // belongs and a shortfall spills harmlessly downward into the window.
        ZStack(alignment: .top) {
            activityStrip
                // One transition for every activity, keyed on the kind rather
                // than the value: the wings, the lyric line, the dropped rows
                // and the HUDs all used to cut hard between one another
                // because only two of the thirteen cases carried a transition.
                .id(state.collapsedActivity?.kind ?? "idle")
                .transition(NotchAnimations.activitySwap)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var activityStrip: some View {
        ZStack {
            switch state.collapsedActivity {
            // One branch, because they are one thing: the wings, plus a lyric
            // row when there is a lyric. Split across two cases, every arriving
            // and expiring line rebuilt the wings underneath it.
            case .music, .lyrics:
                VStack(spacing: 0) {
                    musicWings
                        .frame(height: state.adjustedNotchSize.height)

                    if case let .lyrics(line, duration) = state.collapsedActivity {
                        ZStack {
                            // Keyed on the line, so each one gets a fresh
                            // ticker that scrolls from its own start, and one
                            // line crossfades into the next in place.
                            LyricTickerText(
                                text: line,
                                duration: duration,
                                font: .notchBody.weight(.bold),
                                width: max(
                                    state.collapsedSize.width - NotchSizing.closedWingInset * 2,
                                    0
                                )
                            )
                            .id(line)
                            .transition(.opacity.animation(NotchAnimations.activity))
                        }
                        .foregroundStyle(state.media.accent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 26)
                        // The row arriving or leaving slides out of the notch.
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Lyric")
                        .accessibilityValue(line)
                    }
                }
                .animation(NotchAnimations.activity, value: state.collapsedActivity)
            case let .trackChange(title, artist):
                dropped {
                    droppedRow(
                        symbol: "music.note",
                        tint: state.media.accent,
                        label: artist.isEmpty ? title : "\(title) - \(artist)",
                        value: nil
                    )
                }
            case let .volume(level, muted):
                droppedHUD(
                    kind: .volume(muted: muted),
                    value: Binding(
                        get: { CGFloat(muted ? 0 : level) },
                        set: { newValue in
                            let level = Float(newValue)
                            state.audio.setVolume(level)
                            // Re-raise the activity so the bar shows where the
                            // drag put it, and so the dismiss timer restarts —
                            // otherwise the HUD reads the value from before the
                            // drag and snaps back under the finger.
                            state.activities.showVolume(level: level, muted: level == 0)
                        }
                    )
                )
            case let .brightness(level):
                droppedHUD(
                    kind: .brightness,
                    value: Binding(
                        get: { CGFloat(level) },
                        set: { newValue in
                            let level = Float(newValue)
                            state.brightness.setBrightness(level)
                            state.activities.showBrightness(level: level)
                        }
                    )
                )
            case let .battery(percent, charging, low):
                // When charging, the dedicated popup takes over: the notch's
                // own row keeps whatever it was wearing (music wings or
                // weather), and the popup pops in on a band beneath the
                // notch — iOS-style — then eases away on dismiss.
                if charging {
                    VStack(spacing: 0) {
                        notchRowFlank
                            .frame(height: state.adjustedNotchSize.height)

                        ChargingPopupView(level: CGFloat(percent) / 100)
                            .padding(.horizontal, NotchSizing.closedDropInset)
                            // Clearance under the hardware cutout. The popup used
                            // to start flush with the notch's bottom edge, and at
                            // its natural height (45.6pt) inside a 46pt band the
                            // centring pushed its top 3.4pt *above* that edge — so
                            // its rounded top corners were painted over by the
                            // notch and the pill read as hinged to it rather than
                            // floating below it, iOS-style.
                            .padding(.top, NotchSizing.chargingPopupTopGap)
                            .padding(.bottom, 6)
                            .frame(maxWidth: .infinity)
                            // Top-aligned, not centred: the gap above the pill is
                            // then exactly the constant, whatever the pill's own
                            // height does with the text, and any slack falls
                            // below it where nothing is drawn.
                            .frame(height: NotchSizing.chargingPopupBandHeight, alignment: .top)
                            .transition(NotchAnimations.chargePop)
                    }
                } else {
                    // Dropped like every other reading. In the wings, "Low
                    // Battery" alone was wider than a wing, so the label ran
                    // under the camera housing.
                    dropped {
                        droppedRow(
                            symbol: low ? "battery.25percent" : "battery.75percent",
                            tint: low ? .red : NotchTheme.battery,
                            label: low ? "Low Battery" : "On Battery",
                            value: "\(percent)%"
                        )
                    }
                }
            case let .screenLock(locked):
                dropped {
                    droppedRow(
                        symbol: locked ? "lock.fill" : "lock.open.fill",
                        label: locked ? "Locked" : "Unlocked",
                        value: nil
                    )
                }
            case let .timer(remaining, progress):
                dropped(height: 42) {
                    VStack(spacing: 4) {
                        droppedRow(
                            symbol: "timer",
                            tint: .orange,
                            label: "Timer",
                            value: TimerManager.timeString(remaining)
                        )
                        DraggableProgressBar(
                            value: .constant(CGFloat(progress)),
                            tint: .orange,
                            inline: true
                        )
                        .frame(height: 4)
                    }
                }
            case let .focusMode(name, symbol):
                dropped {
                    droppedRow(symbol: symbol, tint: .purple, label: name, value: nil)
                }
            case let .eyeBreak(active):
                dropped {
                    droppedRow(
                        symbol: active ? "eye.fill" : "eye",
                        tint: .green,
                        label: active ? "Look 20 feet away" : "Eye break over",
                        value: nil
                    )
                }
            case let .fileCaught(name, source):
                dropped(height: 54) {
                    CaughtFileRow(
                        caught: state.fileCatcher.latest,
                        name: name,
                        source: source,
                        onReveal: {
                            if let url = state.fileCatcher.latest?.url {
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            }
                            state.fileCatcher.dismiss()
                        },
                        onDismiss: { state.fileCatcher.dismiss() }
                    )
                }
            case let .desktopChange(index):
                DesktopChangeActivityView(index: index, notchWidth: state.safeNotchSize.width)
            case let .accessoryBattery(name, symbol, percent):
                dropped {
                    droppedRow(
                        symbol: symbol,
                        tint: percent <= 20 ? .red : NotchTheme.battery,
                        label: name,
                        value: "\(percent)%"
                    )
                }
            case let .meetingSoon(title, start):
                TimelineView(.everyMinute) { context in
                    dropped {
                        droppedRow(
                            symbol: "calendar",
                            tint: .blue,
                            label: title,
                            value: Self.countdown(to: start, from: context.date)
                        )
                    }
                }
            case nil:
                if state.settings.showCompactWeather {
                    weatherFlank
                } else {
                    Color.clear
                }
            }
        }
    }

    /// "in 12m" / "in 40s" / "now", for the meeting activity's trailing
    /// reading. Seconds matter because the shortest reminder lead is a minute:
    /// rounding that to whole minutes would have the row announce a meeting
    /// that is still 59 seconds away as "now".
    private static func countdown(to start: Date, from now: Date) -> String {
        let seconds = start.timeIntervalSince(now)
        if seconds <= 0 { return "now" }
        if seconds < 60 { return "in \(max(1, Int(seconds)))s" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "in \(minutes)m" }
        return "in \(minutes / 60)h \(minutes % 60)m"
    }

    /// Wraps any activity content in the dropped form: the notch's own row
    /// keeps its weather wings, and the activity gets the full width beneath.
    private func dropped<Content: View>(
        height: CGFloat = 36,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            notchRowFlank
                .frame(height: state.adjustedNotchSize.height)

            // The band gets a surface rather than sitting on bare black. On a
            // shape that is already black against a black notch, content with
            // no pane under it reads as text floating in a void — the tile is
            // what makes the drop look like part of the hardware.
            content()
                .frame(maxWidth: .infinity)
                .frame(height: height - 8)
                .padding(.horizontal, NotchTheme.Space.m)
                .notchTile(radius: NotchTheme.Radius.tile)
                .padding(.horizontal, NotchSizing.closedDropInset)
                .padding(.bottom, 7)
        }
    }

    /// The shape every dropped activity uses: glyph, label, trailing reading.
    private func droppedRow(
        symbol: String,
        tint: Color = NotchTheme.inkPrimary,
        label: String,
        value: String?
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 18)

            Text(label)
                .font(.notchBody.weight(.bold))
                .foregroundStyle(NotchTheme.inkPrimary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            if let value {
                Text(value)
                    .font(.notchBody.weight(.bold).monospacedDigit())
                    .foregroundStyle(tint)
                    .contentTransition(.numericText())
                    .fixedSize()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value ?? "")
    }

    /// Volume and brightness drop a full-width bar beneath the hardware notch
    /// instead of splitting themselves across the wings. A level bar cut in
    /// half by the camera housing cannot be read at a glance; giving it the
    /// whole width, with the glyph and percentage flanking it, can.
    private func droppedHUD(
        kind: InlineHUD.Kind,
        value: Binding<CGFloat>
    ) -> some View {
        VStack(spacing: 0) {
            // The notch's own row keeps whatever it was already wearing, so
            // the pill does not appear to lose it for the second the HUD is up.
            notchRowFlank
                .frame(height: state.adjustedNotchSize.height)

            DroppedHUDBar(
                kind: kind,
                value: value,
                showsPercentage: state.settings.showHUDPercentage,
                horizontalInset: NotchSizing.closedDropInset
            )
            .frame(height: 34)
        }
    }

    /// What flanks the hardware notch on its own row while an activity is
    /// dropped beneath it. Media owns the wings whenever something is
    /// playing — cover on the left, visualiser on the right, and the weather
    /// stays out of the way until playback stops.
    @ViewBuilder
    private var notchRowFlank: some View {
        if state.isAudioActive {
            musicWings
        } else if state.settings.showCompactWeather {
            weatherFlank
        } else {
            ActivityWingLayout(
                notchWidth: state.safeNotchSize.width,
                leading: Color.clear.frame(width: 1, height: 1),
                trailing: Color.clear.frame(width: 1, height: 1)
            )
        }
    }

    /// The weather glyph and temperature either side of the notch — what the
    /// idle pill wears, and what stays on the notch's own row while some other
    /// activity is dropped beneath it.
    private var weatherFlank: some View {
        ActivityWingLayout(
            notchWidth: state.safeNotchSize.width,
            leading: weatherIcon,
            trailing: weatherTemperature
        )
    }

    /// The condition glyph, on the left of the hardware notch.
    private var weatherIcon: some View {
        Group {
            if let weather = state.weather.snapshot {
                Image(systemName: WeatherService.symbol(
                    for: weather.weatherCode,
                    isDay: weather.isDay
                ))
                .font(.system(size: 15, weight: .semibold))
                .symbolRenderingMode(.multicolor)
            } else {
                Image(systemName: "cloud.sun.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(NotchTheme.inkMuted)
            }
        }
        .accessibilityHidden(true)
    }

    /// The bold temperature readout, on the right of the hardware notch.
    private var weatherTemperature: some View {
        Group {
            if let weather = state.weather.snapshot {
                Text(WeatherService.temperatureString(celsius: weather.temperatureCelsius))
                    .font(.notchHeadline.monospacedDigit())
                    .foregroundStyle(NotchTheme.inkPrimary)
                    .contentTransition(.numericText())
            } else {
                Text("--°")
                    .font(.notchHeadline)
                    .foregroundStyle(NotchTheme.inkMuted)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Current weather")
        .accessibilityValue(
            state.weather.snapshot.map {
                WeatherService.temperatureString(celsius: $0.temperatureCelsius)
                + ", " + WeatherService.condition(for: $0.weatherCode)
            } ?? "Unavailable"
        )
    }

    /// While music is playing the wings belong to the music: the cover on the
    /// left, a visualiser tinted from it on the right. The weather takes them
    /// back the moment playback stops.
    @ViewBuilder
    private var musicWings: some View {
        // The waveform is the permanent trailing wing while anything is
        // playing — the charging state lives in the top-bar battery, never
        // on the closed notch's sides.
        ActivityWingLayout(
            notchWidth: state.safeNotchSize.width,
            leading: miniArtwork,
            leadingInset: NotchSizing.closedArtworkInset,
            trailing: MusicVisualizerView(
                accent: state.media.accent,
                // When the notch is following a tracked source (a real player
                // or a probed browser video), the visualiser must freeze the
                // moment that source is paused — the player keeps its audio
                // object alive while paused, so the CoreAudio any-app signal
                // alone would keep the bars dancing. Only with no media at
                // all does the visualiser fall back to "is anything at all
                // making sound" to decide whether to move.
                isPlaying: state.media.hasTrack || state.media.isBrowserVideo
                    ? state.media.isPlaying
                    : state.audioApps.isAnyAudioPlaying,
                level: state.audio.isMuted ? 0 : state.audio.volume,
                bands: state.visualizerBands
            )
        )
    }

    /// The cover, or — when the sound is not coming from a player with a
    /// now-playing session — the icon of whatever app CoreAudio says is
    /// making it.
    private var miniArtwork: some View {
        Group {
            // A 22pt wing tile: a full crossfade would strobe at this size,
            // so the swap is a short opacity blend keyed on `artworkVersion`.
            miniArtworkContent
                .id(state.media.artworkVersion)
                .transition(.opacity)
        }
        .frame(width: Self.artworkSide, height: Self.artworkSide)
        .clipShape(RoundedRectangle(cornerRadius: artworkCornerRadius, style: .continuous))
        .animation(NotchAnimations.activity, value: state.media.artworkVersion)
        .accessibilityHidden(true)
    }

    /// The closed cover tile, square.
    private static let artworkSide: CGFloat = 22

    /// The cover's corner, nested in the notch's own.
    ///
    /// Nested corners only read as one shape when they follow one rule: an
    /// inner corner's radius is the outer one's minus the black between them.
    /// The cover sits `closedArtworkInset` from the frame edge, so on a closed
    /// notch that is 8pt of black, and the radius is 16 - 8 = 8.
    ///
    /// 11 is the same rule against the 5pt the tile has above and below it,
    /// and it was what this drew for a while. It cannot work here: 11 is half
    /// the tile's 22pt side, so the tile has no straight edge left and reads as
    /// a circle dropped in the pill rather than a corner of the same family.
    ///
    /// The notch's own radius is clamped by half the pill's height before it is
    /// drawn: a 32pt pill asking for an 18pt bottom corner gets 16. That
    /// clamped value is the closed pair's top radius, so 16 is what this
    /// subtracts from rather than the nominal 18.
    ///
    /// Both are drawn with `ContinuousCorner`'s geometry, so the two curves are
    /// the same curve at different sizes, which is what makes the numbers add
    /// up: fitting the two corner arcs back out of the drawn shape puts their
    /// centres 3.3pt apart (0.3pt of that horizontally), leaves at least 4.9pt
    /// of black around the whole tile — the same 5pt it has above and below it
    /// — and 5.1pt between the two arcs themselves.
    private var artworkCornerRadius: CGFloat {
        let gap = NotchSizing.closedArtworkInset - NotchSizing.closedFlareInset
        return max(NotchSizing.cornerRadiusInsets.closed.top - gap, 0)
    }

    @ViewBuilder
    private var miniArtworkContent: some View {
        if let artwork = state.media.artwork {
            Image(nsImage: artwork)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else if let icon = state.audioApps.apps.first(where: \.isPlaying)?.icon {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            // Same corner as the tile it is standing in for: any rounder and
            // its curve would be clipped away by the tile's own.
            RoundedRectangle(cornerRadius: artworkCornerRadius, style: .continuous)
                .fill(NotchTheme.surfaceHover)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 10))
                        .foregroundStyle(NotchTheme.inkSecondary)
                }
        }
    }
}

/// A file that just landed, shown under the closed notch.
///
/// The thumbnail is the drag source: the entire point is that a finished
/// download or a fresh screenshot can go straight where it belongs without a
/// trip through Finder. Clicking reveals it instead, and the row eases away on
/// its own after a few seconds whether or not it was touched.
private struct CaughtFileRow: View {
    let caught: FileCatcher.Catch?
    let name: String
    let source: FileCatcher.Source
    let onReveal: () -> Void
    let onDismiss: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: NotchTheme.Space.s) {
            thumbnail

            VStack(alignment: .leading, spacing: 1) {
                Text(source.label)
                    .font(.notchEyebrow)
                    .tracking(0.7)
                    .foregroundStyle(NotchTheme.inkMuted)

                Text(name)
                    .font(.notchBody)
                    .foregroundStyle(NotchTheme.inkPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: NotchTheme.Space.xs)

            // Only on hover: at rest the row should read as the file, not as a
            // pair of buttons.
            if isHovering {
                Button(action: onReveal) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(NotchTheme.inkSecondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
                .help("Reveal in Finder")

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(NotchTheme.inkSecondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
                .help("Dismiss")
            }
        }
        .animation(NotchAnimations.content, value: isHovering)
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(source.label): \(name)")
        .accessibilityHint("Drag to move the file, or click to reveal it in Finder")
    }

    @ViewBuilder
    private var thumbnail: some View {
        let tile = Group {
            if let icon = caught?.icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(3)
            } else {
                Image(systemName: source.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(NotchTheme.inkSecondary)
            }
        }
        .frame(width: 34, height: 34)
        .background {
            RoundedRectangle(cornerRadius: NotchTheme.Radius.thumb, style: .continuous)
                .fill(.white.opacity(0.07))
        }
        .clipShape(RoundedRectangle(cornerRadius: NotchTheme.Radius.thumb, style: .continuous))

        if let url = caught?.url {
            tile
                .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
                .help("Drag to move this file")
        } else {
            tile
        }
    }
}
