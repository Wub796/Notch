import AppKit
import SwiftUI

/// The home dashboard's fixed row height, shared with NotchState so the
/// slab can size itself to the content without waiting on a runtime
/// measurement (which never reliably landed, leaving a black band under the
/// dashboard). Keep these in step with the layout below.
enum HomeDashboardMetrics {
    /// The full music column: a single artwork/text row inside its surface.
    /// The artwork tile is the tallest element — the title/artist/transport
    /// block sits beside it, not beneath it — so the row is the tile's own
    /// side, plus the card's vertical padding above and below it.
    ///
    /// Counting a stacked transport row here made the slab ~42pt taller than
    /// its content, which is the black strip this measurement exists to avoid.
    static var musicColumnHeight: CGFloat {
        HomeDashboardSizing.coverArtSize + NotchTheme.Space.s * 2
    }
    /// A row of other-audio chips beneath the music row: the 4pt VStack gap
    /// plus the chip row itself (14pt glyph + 3pt padding above and below).
    static let otherAudioChipsHeight: CGFloat = 24

    /// The dashboard row's height. Every pane is given exactly this, so the
    /// row no longer depends on which widgets are showing — it used to fall out
    /// of the music column, which was fine only while music was always there.
    /// The chips row lives inside the music pane, so it counts only when the
    /// music pane is on the dashboard.
    static func naturalHeight(hasOtherAudioChips: Bool) -> CGFloat {
        hasOtherAudioChips
            ? musicColumnHeight + otherAudioChipsHeight
            : musicColumnHeight
    }
}

/// The home dashboard: a row of up to three widgets, chosen and ordered in
/// Settings. By default the player, weather and calendar, as in the Sapphire
/// reference.
///
/// Budget: `NotchState.moduleContentSize`. The row is three cards that hug
/// their own content, so that budget is spent rather than merely respected —
/// and the cards do not all react to it the same way. The player's card is
/// elastic: it gives width back when the row is tight, clipping its title, so
/// a long track name costs the card's own text and never the neighbours'
/// widths. The weather and calendar cards are rigid, because the readings and
/// cells are what makes them readable at a glance, and a squeezed one spills
/// rather than shrinks — the weather card keeps its metrics column, and the
/// player's card is the one that ends up narrow. What keeps them whole is the
/// arrangement: `HomeDashboardSizing`, picked from the width the module
/// actually got, sizes their caps and cells, and the two arrangements'
/// minimums are checked against that width before either is drawn.
struct HomeDashboardView: View {
    let state: NotchState
    let namespace: Namespace.ID

    /// The widgets the user chose, left to right.
    private var widgets: [DashboardWidget] {
        state.settings.dashboardWidgets
    }

    /// Which arrangement the cards are drawn in, from the width the module was
    /// actually given. See `HomeDashboardSizing`: the caps, glyph sizes and
    /// day cells below all come from here, so the dashboard cannot lay itself
    /// out at one size while the slab is sized for another.
    private var sizing: HomeDashboardSizing {
        HomeDashboardSizing.sizing(forContentWidth: state.moduleContentSize.width)
    }

    /// One height for every pane, whichever widgets are showing. NotchState
    /// sizes the slab from the same value, so the two cannot disagree.
    private var rowHeight: CGFloat {
        HomeDashboardMetrics.naturalHeight(
            hasOtherAudioChips: widgets.contains(.music) && !otherAudioApps.isEmpty
        )
    }

    var body: some View {
        // Panes of one height on a shared baseline, divided by a uniform gap.
        // The player card is raised above the other two so that it — the row's
        // elastic card, and the one that draws a long title window — is served
        // the spare width first. It is also the only pane that can shrink: its
        // title clips, where the weather and calendar cards hold readings at a
        // size somebody chose, so a tight row is paid for here and no card is
        // pushed past the slab.
        HStack(alignment: .center, spacing: sizing.paneGap) {
            ForEach(widgets) { widget in
                pane(for: widget)
                    .frame(height: rowHeight)
                    .layoutPriority(widget == .music ? 1 : 0)
                    .transition(.opacity)
            }
        }
        .animation(NotchAnimations.content, value: widgets)
        // No vertical filler. The module is height-fitted to its content, and
        // a flexible maxHeight frame here would let the fit measure the full
        // budget instead of the row's real height.
        .frame(maxWidth: .infinity)
        #if DEBUG
        // The arrangement questions this log answers, per open: which cards
        // were drawn, how wide the module handed them, and whether that width
        // even holds the smaller arrangement. The arithmetic itself has its
        // own tests; what cannot be checked offscreen is the width the panel
        // actually gives the module.
        .onAppear {
            let content = state.moduleContentSize.width
            print("[Notch] home cards: \(sizing.arrangement.rawValue) at \(Int(content))pt"
                  + " (needs \(Int(sizing.minimumContentWidth))pt), player card up to"
                  + " \(Int(sizing.musicMaximumWidth))pt, weather needs"
                  + " \(Int(sizing.weatherMinimumWidth))pt")
            if content < HomeDashboardSizing.compact.minimumContentWidth {
                print("[Notch] home cards: module narrower than the compact"
                      + " arrangement — the rigid cards will be squeezed")
            }
        }
        #endif
    }

    @ViewBuilder
    private func pane(for widget: DashboardWidget) -> some View {
        switch widget {
        case .music:
            musicPane
        case .weather:
            weatherSection
        case .calendar:
            calendarSection
        case .system:
            SystemWidget(state: state)
        case .battery:
            BatteryWidget(state: state)
        case .timer:
            TimerWidget(state: state)
        }
    }

    // MARK: - Music

    /// The player card: the row's elastic card, its block pinned to the left.
    ///
    /// It gives width back when the row is tight — clipping the title rather
    /// than pushing its neighbours past the slab — and it takes the width the
    /// two cards beside it leave when the row is roomy, up to
    /// `musicMaximumWidth`. It is the row's *smallest* card on the tuned slab
    /// for that reason: the weather card holds its metrics column and the
    /// calendar its day strip, and the player card is what is left (measured:
    /// 326pt of player card beside 304pt of weather and 294pt of calendar,
    /// with every card at its own size and no slack on any side).
    ///
    /// The block is pinned to the card's leading edge — cover first, then the
    /// text column — and never centred: the elements read from the left rim
    /// whatever the card's width, and the width a short title does not use sits
    /// at the card's far end rather than around it.
    ///
    /// The two candidates are the card at the block's own width — cover, title
    /// window, transport row, which a short title asks for — and the same card
    /// filled to whatever the row can afford, clipping the title inside it.
    /// `ViewThatFits` takes the first whenever it fits, which is what keeps the
    /// transport row under the text block: in the filled card the column runs
    /// the full title window, and a transport row centred in *that* drifts
    /// right of a short title. Either way the tile is `musicMaximumWidth`.
    private var musicPane: some View {
        ViewThatFits(in: .horizontal) {
            musicCard
                .fixedSize(horizontal: true, vertical: false)
            musicCard
        }
        .frame(
            maxWidth: sizing.musicMaximumWidth,
            maxHeight: .infinity,
            alignment: .leading
        )
        .notchTile(radius: NotchTheme.Radius.card)
    }

    /// The card's own body: the padding and the two rows, with no width of its
    /// own beyond what the content asks for — the pane above decides how much
    /// room it is given, and pins the block to the card's left rim.
    private var musicCard: some View {
        musicSection
            .padding(.horizontal, sizing.panePadding)
            .padding(.vertical, NotchTheme.Space.s)
    }

    private var activeAudioApp: AudioAppMonitor.App? {
        state.audioApps.apps.first(where: \.isPlaying)
    }

    private var displayTitle: String {
        if state.media.isBrowserVideo, let title = state.media.track?.title, !title.isEmpty {
            return title
        }
        if let title = state.media.track?.title, !title.isEmpty {
            return title
        }
        if let active = activeAudioApp {
            return active.name
        }
        return "Nothing Playing"
    }

    private var displayArtist: String {
        if state.media.isBrowserVideo, let artist = state.media.track?.artist, !artist.isEmpty {
            return artist
        }
        if let artist = state.media.track?.artist, !artist.isEmpty {
            return artist
        }
        if activeAudioApp != nil {
            return "Active Audio"
        }
        return "Nothing is playing"
    }

    /// Apps currently putting audio out besides the one the hero card is
    /// already showing — the music source when a track is loaded, otherwise
    /// the first playing app. These are the YouTube / Chrome / Safari-style
    /// sources that used to be invisible whenever music had the spotlight.
    /// Single source of truth lives on NotchState, which also sizes the slab
    /// to this row — keeping the two in step is what that property is for.
    private var otherAudioApps: [AudioAppMonitor.App] {
        state.otherAudioApps
    }

    /// Leading, like every other thing on the panel: the cover, the text column
    /// and the chips row all start from the card's left rim. Only the transport
    /// row inside the column is centred, and it is centred under its own text
    /// rather than under the card.
    private var musicSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: sizing.coverGap) {
                Button(action: openSource) {
                    artwork
                }
                // The cover opens the app the music is playing in; the full
                // player is the rail's media control, and the title beside it.
                .buttonStyle(PressableButtonStyle())
                .contentShape(Rectangle())
                .help(sourceHelp)

                VStack(alignment: .leading, spacing: 2) {
                    // Uppercase and letterspaced, as in the reference: the title is
                    // the loudest thing on the panel. Long titles marquee instead
                    // of truncating — same treatment the Now player's title gets.
                    MarqueeText(
                        text: displayTitle.uppercased(),
                        font: .system(size: 18, weight: .heavy, design: .rounded),
                        width: sizing.marqueeWidth,
                        tracking: 2.0
                    )
                    .foregroundStyle(NotchTheme.inkPrimary)
                    .contentShape(Rectangle())
                    .onTapGesture { state.select(.audio) }

                    HStack(spacing: 4) {
                        Text(displayArtist)
                            .font(.system(size: 13.5, weight: .medium, design: .rounded))
                            .foregroundStyle(NotchTheme.inkSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: sizing.artistWidth, alignment: .leading)

                    }

                    // Transport sits centred under the text block rather than
                    // flush left, which is what makes the column read as one unit.
                    HStack(spacing: 16) {
                        transportButton("backward.fill", size: 15, label: "Previous track") {
                            state.media.previousTrack()
                        }
                        transportButton(
                            state.media.isPlaying ? "pause.fill" : "play.fill",
                            size: 18,
                            label: state.media.isPlaying ? "Pause" : "Play"
                        ) {
                            // No spring wrapper: the icon crossfades via
                            // contentTransition, press feedback via
                            // PressableButtonStyle. Bounce on a frequent
                            // transport control reads as jitter.
                            state.media.togglePlayPause()
                        }
                        transportButton("forward.fill", size: 15, label: "Next track") {
                            state.media.nextTrack()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 2)
                }
                // This column is the dashboard's elastic width. It takes
                // whatever the weather and calendar cards leave and gives it
                // back — clipping the title, truncating the artist — when the
                // row is tight. It used to be `fixedSize`, which turned a long
                // track name into a demand on the whole row: the two cards
                // beside it were squeezed past their own content and painted
                // out past the slab's edge, which is the state
                // `HomeDashboardSizing` exists to keep the panel out of. The
                // cap is what keeps the transport row centred under the text
                // rather than drifting right when the card has width to spare,
                // because its `maxWidth: .infinity` frame would take all of it.
                // The card itself is capped to this same width plus the cover
                // and padding (`musicMaximumWidth`), so spare width is not
                // collected here as empty tile either.
                .frame(maxWidth: sizing.marqueeWidth, alignment: .leading)
                .help("Open the full player")
            }

            if !otherAudioApps.isEmpty {
                otherAudioAppsRow
            }
        }
    }

    /// Compact chips for every other app making sound right now. Each chip
    /// splits the row evenly and truncates its label, so any number of
    /// sources fit without ever overflowing the section; clicking one brings
    /// that app to the front.
    /// Brings the music's app forward and gets the notch out of its way. With
    /// no app to open — nothing playing at all — the cover opens the player.
    private func openSource() {
        if state.media.openableSourceName != nil {
            state.media.openSourceApp()
        } else if let app = activeAudioApp {
            app.activate()
        } else {
            state.select(.audio)
            return
        }
        state.collapse()
    }

    private var sourceHelp: String {
        guard let name = state.media.openableSourceName ?? activeAudioApp?.name else {
            return "Open the full player"
        }
        return "Open \(name)"
    }

    private var otherAudioAppsRow: some View {
        HStack(spacing: 8) {
            ForEach(otherAudioApps) { app in
                Button {
                    app.activate()
                } label: {
                    HStack(spacing: 4) {
                        Group {
                            if let icon = app.icon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 14, height: 14)
                            } else {
                                Image(systemName: "waveform")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(NotchTheme.inkMuted)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))

                        Text(app.name)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(NotchTheme.inkPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(.white.opacity(0.08)))
                    .contentShape(Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .frame(maxWidth: .infinity)
                .help("Bring \(app.name) to front")
            }
        }
        .frame(maxWidth: 320, alignment: .leading)
    }

    private var artwork: some View {
        let side = HomeDashboardSizing.coverArtSize
        return ZStack {
            // Keyed on `artworkVersion` so the cover crossfades on track
            // change; the stable container below keeps the open/close morph
            // and the source-app badge fixed while the image swaps.
            artworkContent
                .id(state.media.artworkVersion)
                .transition(.opacity)
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .matchedGeometryEffect(id: "albumArt", in: namespace)
        .shadow(color: state.media.accent.opacity(0.38), radius: 12, y: 4)
        .animation(NotchAnimations.content, value: state.media.artworkVersion)
        .overlay(alignment: .bottomTrailing) {
            if let icon = state.media.sourceAppIcon ?? (state.media.artwork != nil ? activeAudioApp?.icon : nil) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 20, height: 20)
                    .clipShape(Circle())

                    .overlay { Circle().stroke(.black, lineWidth: 1.5) }
                    .offset(x: 4, y: 4)
                    .help(state.media.sourceAppName ?? "")
                    .accessibilityLabel("Playing in \(state.media.sourceAppName ?? "another app")")
            }
        }
    }

    @ViewBuilder
    private var artworkContent: some View {
        if state.media.isBrowserVideo, let image = state.media.artwork {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else if let image = state.media.artwork {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else if let icon = state.media.sourceAppIcon ?? activeAudioApp?.icon {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(14)
                .background(Color.white.opacity(0.08))
        } else {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(NotchTheme.inkMuted)
                }
        }
    }

    private func transportButton(
        _ systemImage: String,
        size: CGFloat,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(NotchTheme.inkPrimary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.white.opacity(0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .modifier(HoverIconModifier())
        .contentTransition(.symbolEffect(.replace))
        .accessibilityLabel(label)
    }

    // MARK: - Weather

    @ViewBuilder
    private var weatherSection: some View {
        if let weather = state.weather.snapshot {
            HStack(alignment: .center, spacing: sizing.readoutGap) {
                Image(systemName: WeatherService.symbol(
                    for: weather.weatherCode,
                    isDay: weather.isDay
                ))
                .font(.system(size: sizing.weatherGlyphSize))
                .symbolRenderingMode(.multicolor)

                VStack(alignment: .leading, spacing: 0) {
                    Text(WeatherService.temperatureString(celsius: weather.temperatureCelsius))
                        .font(.system(size: sizing.temperatureSize, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundStyle(NotchTheme.inkPrimary)
                        // The card's one reading, and never negotiated: a Text
                        // squeezed below its own width wraps rather than
                        // shrinks, and a temperature broken over two lines is
                        // worse than a narrower card. `fixedSize` puts it in
                        // the card's minimum, which is what HomeDashboardSizing
                        // budgets for.
                        .fixedSize()
                        // Digits roll when the reading changes; without a
                        // value-bound animation the contentTransition is inert.
                        .contentTransition(.numericText())
                        .animation(NotchAnimations.content, value: weather.temperatureCelsius)

                    Text(state.weather.placeName ?? "Your Location")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(NotchTheme.inkPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: sizing.weatherTextWidth, alignment: .leading)

                    Text(WeatherService.condition(for: weather.weatherCode))
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(NotchTheme.inkSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: sizing.weatherTextWidth, alignment: .leading)
                }

                // The card's third register, and the widest thing on it. It
                // belongs to the roomy arrangement: the player card beside it
                // gives up the width for it, which is why the card is a chip
                // without it (see `HomeDashboardSizing.showsWeatherMetrics`).
                if sizing.showsWeatherMetrics {
                    VStack(alignment: .leading, spacing: 4) {
                        metric("wind", WeatherService.windString(kmh: weather.windKmh))
                        metric("drop.fill", "\(weather.precipitationChancePercent)%")
                        metric("humidity.fill", "\(weather.humidityPercent)%")
                    }
                }
            }
            .dashboardPane(padding: sizing.panePadding, opens: .weather, in: state, help: "Open the weather detail")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Weather")
            .accessibilityValue(
                WeatherService.temperatureString(celsius: weather.temperatureCelsius)
                + ", " + WeatherService.condition(for: weather.weatherCode)
            )
        } else {
            weatherPlaceholder
        }
    }

    private func metric(_ systemImage: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 13))
                .symbolRenderingMode(.multicolor)
                .frame(width: 18)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(NotchTheme.inkPrimary)
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }

    private var weatherPlaceholder: some View {
        HStack(spacing: 12) {
            Image(systemName: weatherPlaceholderIcon)
                .font(.system(size: 30))
                .foregroundStyle(NotchTheme.inkMuted)
            VStack(alignment: .leading, spacing: 2) {
                Text(weatherPlaceholderTitle)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(NotchTheme.inkSecondary)
                if !state.settings.showWeather || state.weather.failureMessage != nil {
                    Text("Click to retry")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(NotchTheme.inkMuted)
                }
            }
        }
        .dashboardPane(padding: sizing.panePadding, opens: .weather, in: state, help: "Open the weather detail")
    }

    private var weatherPlaceholderIcon: String {
        if !state.settings.showWeather { return "cloud.slash" }
        return state.weather.failureMessage == nil ? "cloud.sun.fill" : "exclamationmark.icloud"
    }

    private var weatherPlaceholderTitle: String {
        if !state.settings.showWeather { return "Weather off" }
        if let failure = state.weather.failureMessage { return failure }
        return "Getting weather…"
    }

    // MARK: - Calendar

    private var calendarSection: some View {
        let today = Date()
        let strip = (-2 ... 2).compactMap {
            Calendar.current.date(byAdding: .day, value: $0, to: today)
        }
        let next = state.calendar.items.first {
            !$0.isAllDay && $0.start > today && Calendar.current.isDateInToday($0.start)
        }

        // Centred on both axes, so the strip is the anchor of its own card.
        //
        // This used to hang off the right edge, trailing-aligned to share a
        // gutter with the cover art at the far left. Read on its own, though,
        // the block just looked shoved into a corner: the month and day
        // numbers sat hard against the right rim while the left half of the
        // pane stayed empty. Centre alignment gives the block the same poise
        // the weather and music panes already have.
        //
        // The padding is symmetric for the same reason — centre alignment only
        // centres anything if the space around it is even. The old
        // `.padding(.bottom, .l)` was deliberate while the block was trailing
        // (it nudged the ink up to sit level with its neighbours), but under
        // centre alignment that asymmetry just pushes the block off-centre
        // again.
        //
        // The two rungs stay modest, and for different reasons. The pane hugs
        // this block horizontally, so every point of *side* pad widens the
        // calendar card by exactly that and takes the width from the music
        // column beside it — kept at the same 8pt it already carried. The
        // *vertical* pad costs nothing: the row height is fixed, so it only
        // re-centres the ink inside its card, and it can carry the roomier
        // beat the event line wanted under it.
        //
        // Keep block + padding inside the tile's budget (the row height less
        // the pane's own 16), or the pane's minimum wins and its tile grows
        // past the row — which is what a 40pt pad did: the calendar card ran
        // 8pt above the other two.
        return VStack(alignment: .center, spacing: NotchTheme.Space.m) {
            HStack(alignment: .center, spacing: sizing.dayStrip.cellGap) {
                Text(today.formatted(.dateTime.month(.abbreviated)))
                    .font(.system(size: sizing.monthSize, weight: .heavy, design: .rounded))
                    .fixedSize()
                    .foregroundStyle(NotchTheme.inkPrimary)
                    .accessibilityHidden(true)

                HStack(alignment: .center, spacing: sizing.dayStrip.cellGap) {
                    ForEach(Array(strip.enumerated()), id: \.offset) { _, day in
                        dayCell(day)
                    }
                }
            }

            // The event line ("no more items today") sits a beat below the
            // strip — a touch more than the strip's own internal gaps, so the
            // block reads as two registers (the dates, then the note about
            // them) rather than one evenly-spaced row of them. It hugs its
            // content: without fixedSize the title's 180pt cap frame would
            // stretch the centred column and push the strip off-centre.
            nextEventLine(next)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, sizing.panePadding)
        .padding(.vertical, NotchTheme.Space.m)
        .dashboardPane(padding: sizing.panePadding, opens: .calendar, in: state, help: "Open the calendar")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Calendar")
        .accessibilityValue(next?.title ?? "Nothing left today")
    }

    /// Today is spelled out ("SAT") in blue over a large blue number; the days
    /// either side fade with distance, which is what gives the strip its
    /// centre of gravity in the reference.
    private func dayCell(_ day: Date) -> some View {
        let calendar = Calendar.current
        let isToday = calendar.isDateInToday(day)
        let distance = abs(calendar.dateComponents([.day], from: Date(), to: day).day ?? 0)
        let fade = 1.0 - Double(distance) * 0.28
        let strip = sizing.dayStrip

        return VStack(spacing: -1) {
            Text(isToday
                 ? day.formatted(.dateTime.weekday(.abbreviated)).uppercased()
                 : String(day.formatted(.dateTime.weekday(.narrow)).prefix(1)).uppercased())
                .font(.system(
                    size: isToday ? strip.todayWeekdaySize : strip.otherWeekdaySize,
                    weight: .heavy,
                    design: .rounded
                ))
                .fixedSize()
                .foregroundStyle(isToday ? .blue : NotchTheme.inkSecondary.opacity(fade))

            Text("\(calendar.component(.day, from: day))")
                .font(.system(
                    size: isToday ? strip.todayNumberSize : strip.otherNumberSize,
                    weight: isToday ? .heavy : .bold,
                    design: .rounded
                ).monospacedDigit())
                // Without this a squeezed column wraps "27" into a 2 above a 7.
                .fixedSize()
                .foregroundStyle(isToday ? .blue : NotchTheme.inkPrimary.opacity(fade))
        }
        // The arrangement's cell width, which is its content's width rounded
        // up — see `HomeDashboardSizing.DayStrip`.
        .frame(minWidth: isToday ? strip.todayCellWidth : strip.otherCellWidth)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
        .accessibilityAddTraits(isToday ? [.isSelected] : [])
    }

    @ViewBuilder
    private func nextEventLine(_ event: CalendarController.ScheduleItem?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: event == nil ? "calendar.badge.checkmark" : "calendar")
                .font(.system(size: 13))
                .foregroundStyle(NotchTheme.inkSecondary)
                .fixedSize()

            if let event {
                Text(event.start.formatted(date: .omitted, time: .shortened))
                    .font(.notchBody.weight(.heavy).monospacedDigit())
                    .foregroundStyle(NotchTheme.inkPrimary)
                    .fixedSize()
                Text(event.title)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(NotchTheme.inkSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: sizing.eventTitleWidth, alignment: .leading)
            } else {
                Text(state.calendar.accessState == .granted
                     ? "No more items today"
                     : "Calendar access off")
                    .font(.notchBody.weight(.medium))
                    .fixedSize()
                    .foregroundStyle(NotchTheme.inkSecondary)
            }
        }
    }
}
