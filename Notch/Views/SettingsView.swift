import AppKit
import SwiftUI

/// The Settings window (⌘, from the menu bar item, or the gear in the notch).
///
/// Glance's layout, not this app's old sidebar: one `.sidebar` material behind
/// the whole window, the selected page scrolling beneath a transparent header
/// (AppKit's own traffic lights on the leading side, the session lock button on
/// the trailing side), and a floating pill tab bar pinned to the bottom.
///
/// Ported from Glance (`Settings/SettingsWindowView.swift`, MIT © Jonathan
/// Zhou). The sidebar it replaces had a search field, which has no equivalent
/// here: nine named tabs with icons are the navigation, and the pill bar is
/// where Glance's identity lives.
struct SettingsView: View {
    @Bindable private var credentials = FaceIDCredentialController.shared

    @State private var selection: SettingsTab = SettingsTab.initial
    @State private var headerTrailingAction: HeaderAction?

    var body: some View {
        ZStack {
            VisualEffectView()
            SettingsMetrics.windowTintColor
            contentPage
        }
        // No `.clipShape`, manual stroke, or `.shadow` on the outer window —
        // deliberately: the window keeps its native background (see
        // `WindowConfigurator`), so AppKit masks it to the real macOS corner
        // and draws its own edge highlight and shadow for free.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .background(WindowConfigurator())
        // Cascades to every native control so nothing falls back to the
        // system accent. Only takes effect because the window can become
        // key; see `WindowConfiguringView.configure`.
        .tint(SettingsMetrics.accent)
    }

    /// The header and tab bar float over the scroll content as overlays so
    /// scrolled rows pass underneath them rather than being pushed aside.
    private var contentPage: some View {
        ScrollView(.vertical, showsIndicators: false) {
            pageBody
                .padding(.horizontal, SettingsMetrics.contentHorizontalPadding)
                .padding(.top, SettingsMetrics.headerHeight + 4)
                .padding(.bottom, SettingsMetrics.pageBottomInset)
                // Without an explicit top alignment the scroll view centers
                // short pages vertically, leaving a large gap between the
                // header and the first row.
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .overlay(alignment: .top) {
            // Blur first, header content on top — so it fades whatever
            // scrolls beneath both without ever softening the buttons
            // themselves.
            ZStack(alignment: .top) {
                ProgressiveHeaderBlur(height: SettingsMetrics.headerBlurHeight)
                header
            }
        }
        .overlay(alignment: .bottom) {
            SettingsTabBar(selection: $selection)
                .padding(.bottom, SettingsMetrics.tabBarBottomInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onPreferenceChange(HeaderTrailingActionKey.self) { headerTrailingAction = $0 }
    }

    /// Leading side stays empty — the window's real traffic lights are drawn
    /// there by AppKit (see `WindowConfiguringView`). No background of its
    /// own; `ProgressiveHeaderBlur` sits behind it in `contentPage`.
    private var header: some View {
        HStack(spacing: 8) {
            Spacer()

            if let headerTrailingAction {
                // Glance's symbol here is `arrow.trianglehead.clockwise.rotate.90`,
                // which needs macOS 15 — this app targets 14, so it uses the
                // older equivalent.
                Button(action: headerTrailingAction.perform) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13))
                        .foregroundStyle(SettingsMetrics.textPrimary)
                        .frame(width: SettingsMetrics.headerButtonHeight, height: SettingsMetrics.headerButtonHeight)
                        .background(Circle().fill(SettingsMetrics.rowColor))
                        .overlay(
                            Circle()
                                .strokeBorder(SettingsMetrics.rowBorder, lineWidth: SettingsMetrics.rowBorderWidth)
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Refresh camera list")
            }

            SessionLockButton(credentials: credentials)
        }
        .padding(.horizontal, SettingsMetrics.contentHorizontalPadding)
        .frame(height: SettingsMetrics.headerHeight)
    }

    @ViewBuilder
    private var pageBody: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.rowSpacing) {
            switch selection {
            case .general: GeneralSettingsPane()
            case .notch: NotchSettingsPane()
            case .media: MediaSettingsPane()
            case .weather: WeatherSettingsPane()
            case .activities: ActivitiesSettingsPane()
            case .system: SystemSettingsPane()
            case .faceID: FaceIDSettingsPane()
            case .privacy: PrivacySettingsPane()
            case .about: AboutSettingsPane()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A closure `onPreferenceChange` can actually consume — that API requires
/// `Value: Equatable`, which a bare closure can never be. Equality is by
/// identity (a fresh `id` per instance), so this is deliberately never equal
/// to a previous instance.
struct HeaderAction: Equatable {
    private let id = UUID()
    let perform: () -> Void

    static func == (lhs: HeaderAction, rhs: HeaderAction) -> Bool { lhs.id == rhs.id }
}

/// Lets one page (today, Face ID's "Refresh camera list") publish a trailing
/// action into the shared header without the header needing to know that
/// page's state. Switching away resolves back to `defaultValue`.
struct HeaderTrailingActionKey: PreferenceKey {
    static var defaultValue: HeaderAction? { nil }
    static func reduce(value: inout HeaderAction?, nextValue: () -> HeaderAction?) {
        value = nextValue() ?? value
    }
}

// MARK: - Weather

/// Weather options, split out of Activities so the unit picker and the
/// location controls sit together with a live status line.
private struct WeatherSettingsPane: View {
    @Bindable var settings = NotchSettings.shared

    private var locationStatus: IntegrationPermissions.Status {
        IntegrationPermissions.shared.status(for: .location)
    }

    var body: some View {
        Form {
            Section {
                Toggle("Show weather", isOn: $settings.showWeather)
                Toggle("Weather in the compact notch", isOn: $settings.showCompactWeather)
                Picker("Temperature unit", selection: $settings.temperatureUnit) {
                    ForEach(TemperatureUnit.allCases) { unit in
                        Text(unit.title).tag(unit)
                    }
                }
            } header: {
                Text("Display")
            }

            Section {
                LabeledContent("Location access") {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(locationStatus == .granted ? .green : .orange)
                            .frame(width: 7, height: 7)
                        Text(locationStatus.title)
                            .foregroundStyle(.secondary)
                    }
                }

                if IntegrationPermissions.shared.pending.contains(.location) {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Waiting for macOS…").foregroundStyle(.secondary)
                    }
                } else if locationStatus != .granted {
                    Button("Grant Location Access") {
                        IntegrationPermissions.shared.request(.location)
                    }
                }

                Button("Open Location Settings") {
                    if let url = IntegrationPermissions.Integration.location.settingsURL {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link)

                if let note = IntegrationPermissions.shared.notes[.location] {
                    Text(note)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Toggle(
                    "Use an approximate location from my network",
                    isOn: $settings.approximateLocationFallback
                )
            } header: {
                Text("Location")
            } footer: {
                Text("Granting location access makes the forecast accurate to your city. Without it, Notch can ask ipapi.co to estimate your rough position from your network — the one request this app makes to anyone but the forecast service. If you have explicitly denied location access, that estimate is never requested.")
            }
        }
        .formStyle(.grouped)
        .onAppear { IntegrationPermissions.shared.refresh() }
    }
}

// MARK: - General

private struct GeneralSettingsPane: View {
    @Bindable var settings = NotchSettings.shared

    var body: some View {
        SettingsPane {
            SettingsCard(title: "Behavior") {
                SettingsRow(
                    systemImage: "cursorarrow.click.2",
                    tint: .cyan,
                    title: "Expand on Hover"
                ) {
                    Toggle("", isOn: $settings.expandOnHover)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                if settings.expandOnHover {
                    SettingsSliderRow(
                        title: "Hover Delay",
                        value: $settings.openDelay,
                        range: 0 ... 0.5,
                        step: 0.01,
                        format: { String(format: "%.2fs", $0) }
                    )
                    SettingsSliderRow(
                        title: "Close Delay",
                        value: $settings.closeDelay,
                        range: 0.2 ... 1.0,
                        step: 0.01,
                        format: { String(format: "%.2fs", $0) }
                    )
                }

                SettingsSliderRow(
                    title: "Hover Side Tolerance",
                    value: $settings.hoverTolerance,
                    range: 0 ... 24,
                    step: 1,
                    format: { String(format: "%.0f pt", $0) }
                )

                SettingsRow(
                    systemImage: "hand.draw.fill",
                    tint: .orange,
                    title: "Scroll to Open and Close"
                ) {
                    Toggle("", isOn: $settings.scrollToExpand)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                SettingsRow(
                    systemImage: "arrow.up.left.and.arrow.down.right",
                    tint: .blue,
                    title: "Auto-Collapse when Mouse Leaves",
                    showsDivider: false
                ) {
                    Toggle("", isOn: $settings.autoCollapseOnMouseExit)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }

            SettingsCard(title: "Motion") {
                SettingsRow(
                    systemImage: "wand.and.stars",
                    tint: .purple,
                    title: "Animation Style",
                    subtitle: animationDescription,
                    showsDivider: false
                ) {
                    Picker("", selection: $settings.animationProfile) {
                        ForEach(AnimationProfile.allCases) { profile in
                            Text(profile.title).tag(profile)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
            }

            SettingsCard(title: "System") {
                SettingsRow(
                    systemImage: "power",
                    tint: .green,
                    title: "Launch at Login",
                    subtitle: "Start Notch automatically when you log in to your Mac.",
                    showsDivider: false
                ) {
                    Toggle("", isOn: $settings.launchAtLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                if let error = settings.launchAtLoginError {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                }
            }
        }
    }

    private var animationDescription: String {
        switch settings.animationProfile {
        case .snappy: "Quick and responsive, fully damped."
        case .bouncy: "Overshoots a little on the way open."
        case .calm: "The slowest and softest of the three."
        }
    }
}

// MARK: - Notch behavior

private struct NotchSettingsPane: View {
    @Bindable var settings = NotchSettings.shared

    var body: some View {
        Form {
            Section {
                Toggle("Expand on hover", isOn: $settings.expandOnHover)
                Toggle("Scroll on the notch to open/close", isOn: $settings.scrollToExpand)
            } header: {
                Label("Expansion Gestures", systemImage: "cursorarrow.click.2")
            } footer: {
                Text("Hovering peeks the notch. A click opens it fully; with hover expansion on, lingering does too.")
            }

            if settings.expandOnHover {
                Section {
                    sliderRow(
                        title: "Open delay",
                        value: $settings.openDelay,
                        range: 0 ... 0.5,
                        format: "%.2f s"
                    )
                    sliderRow(
                        title: "Close delay",
                        value: $settings.closeDelay,
                        range: 0.2 ... 1.0,
                        format: "%.2f s"
                    )
                } header: {
                    Label("Hover Timing", systemImage: "timer")
                } footer: {
                    Text("Configures dwell time before the notch opens or closes on pointer hover.")
                }
            }

            Section {
                Picker("Toggle shortcut", selection: $settings.hotKey) {
                    ForEach(HotKeyManager.Shortcut.allCases) { shortcut in
                        Text(shortcut.title).tag(shortcut.rawValue)
                    }
                }

                Picker("Show notch on", selection: $settings.preferredScreenName) {
                    Text("Automatic").tag("")
                    ForEach(NSScreen.screens, id: \.localizedName) { screen in
                        Text(screen.localizedName).tag(screen.localizedName)
                    }
                }
            } header: {
                Label("Shortcut & Display", systemImage: "keyboard")
            } footer: {
                Text("The shortcut works system-wide without Accessibility access. Automatic picks the display with a real notch, falling back to the main display.")
            }

            Section {
                ForEach(widgetRows) { widget in
                    widgetRow(widget)
                }
            } header: {
                Label("Home Dashboard", systemImage: "rectangle.3.group")
            } footer: {
                Text("Choose up to \(DashboardWidget.maximumVisible) widgets for the Home screen. They appear left to right in this order.")
            }

            DimensionSliders()
        }
        .formStyle(.grouped)
    }

    /// Enabled widgets first, in dashboard order, then the rest — so the list
    /// reads top to bottom the way the dashboard reads left to right.
    private var widgetRows: [DashboardWidget] {
        let enabled = settings.dashboardWidgets
        return enabled + DashboardWidget.allCases.filter { !enabled.contains($0) }
    }

    private func widgetRow(_ widget: DashboardWidget) -> some View {
        let enabled = settings.dashboardWidgets
        let index = enabled.firstIndex(of: widget)
        let isOn = index != nil
        // A fourth won't fit, and removing the last would leave an empty panel.
        let canToggle = isOn
            ? enabled.count > 1
            : enabled.count < DashboardWidget.maximumVisible

        return LabeledContent {
            HStack(spacing: 8) {
                if let index {
                    Button { move(widget, by: -1) } label: {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.borderless)
                    .disabled(index == 0)
                    .help("Move \(widget.title) left")
                    .accessibilityLabel("Move \(widget.title) left")

                    Button { move(widget, by: 1) } label: {
                        Image(systemName: "chevron.down")
                    }
                    .buttonStyle(.borderless)
                    .disabled(index == enabled.count - 1)
                    .help("Move \(widget.title) right")
                    .accessibilityLabel("Move \(widget.title) right")
                }

                Toggle("", isOn: Binding(
                    get: { isOn },
                    set: { on in
                        withAnimation {
                            if on {
                                settings.dashboardWidgets.append(widget)
                            } else {
                                settings.dashboardWidgets.removeAll { $0 == widget }
                            }
                        }
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(!canToggle)
                .accessibilityLabel("Show \(widget.title)")
            }
        } label: {
            Label(widget.title, systemImage: widget.symbol)
        }
    }

    private func move(_ widget: DashboardWidget, by offset: Int) {
        var list = settings.dashboardWidgets
        guard let from = list.firstIndex(of: widget) else { return }
        let to = from + offset
        guard list.indices.contains(to) else { return }
        list.swapAt(from, to)
        withAnimation { settings.dashboardWidgets = list }
    }

    private func sliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: String
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            Slider(value: value, in: range, step: 0.05)
                .frame(width: 170)
            Text(String(format: format, value.wrappedValue))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
        }
    }
}

// MARK: - Dimension sliders

/// Manual control over the notch's measured size and shape. Every value is
/// clamped in NotchState, so a slider can't produce an unusable notch.
private struct DimensionSliders: View {
    @Bindable var settings = NotchSettings.shared

    /// Two sibling sections, so this needs the builder for the same reason
    /// `spotifyCard` does: without it the first is discarded and the property
    /// returns nothing.
    @ViewBuilder
    var body: some View {
        Section {
            slider(
                "Notch width",
                value: $settings.notchWidthAdjustment,
                range: -40 ... 80,
                step: 1,
                format: { String(format: "%+.0f pt", $0) }
            )
            slider(
                "Notch height",
                value: $settings.notchHeightAdjustment,
                range: -10 ... 30,
                step: 1,
                format: { String(format: "%+.0f pt", $0) }
            )
            slider(
                "Hover grow",
                value: $settings.peekScale,
                range: 1.0 ... 1.4,
                step: 0.02,
                format: { String(format: "%.0f%%", $0 * 100) }
            )
        } header: {
            Label("Closed Notch", systemImage: "ruler")
        } footer: {
            Text("Width and height trim the notch the app measured from your display. Use them if the drawn pill doesn't quite cover the hardware.")
        }

        Section {
            slider(
                "Open width",
                value: $settings.openNotchWidth,
                range: NotchSizing.minimumOpenWidth ... NotchSizing.maxAllowedOpenWidth(),
                step: 10,
                format: { String(format: "%.0f pt", $0) }
            )
            slider(
                "Open height",
                value: $settings.openNotchHeight,
                range: NotchSizing.minimumOpenHeight ... NotchSizing.maximumOpenHeight,
                step: 5,
                format: { String(format: "%.0f pt", $0) }
            )

            Toggle("Round the open corners further", isOn: $settings.cornerRadiusScaling)

            Button("Reset Dimensions") {
                settings.resetNotchDimensions()
            }
        } header: {
            Label("Open Panel", systemImage: "square.on.circle")
        } footer: {
            Text("These scale every screen together — each one keeps its own shape, so switching tabs does move the panel, but always between sizes you chose here. The width is capped to your display. Hovering is detected over the closed pill exactly as it is drawn: the notch and whatever it is wearing beside it, and nothing else.")
        }
    }

    private func slider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        format: @escaping (Double) -> String
    ) -> some View {
        LabeledContent {
            HStack(spacing: 10) {
                Slider(value: value, in: range, step: step)
                    .frame(width: 190)
                Text(format(value.wrappedValue))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 62, alignment: .trailing)
            }
        } label: {
            Text(title)
        }
    }
}

// MARK: - Media

private struct MediaSettingsPane: View {
    @Bindable var settings = NotchSettings.shared
    private var permissions = IntegrationPermissions.shared

    private var isSpotifyConnected: Bool {
        permissions.musicStatus(for: .spotify) == .granted
    }

    private var isAppleMusicConnected: Bool {
        permissions.musicStatus(for: .appleMusic) == .granted
    }

    var body: some View {
        SettingsPane {
            spotifyCard
            appleMusicCard
            preferredPlayerCard
            closedNotchCard
            visualizerCard
            lyricsCard
        }
        .onAppear {
            permissions.refresh()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            // Re-read authorization status when the app regains focus
            permissions.refresh()
        }
    }

    private var spotifyStatusLine: String {
        if isSpotifyConnected {
            return "Ready. Controlling Spotify on this Mac."
        }
        if !IntegrationPermissions.isInstalled(.spotify) {
            return "Spotify isn't installed on this Mac."
        }
        return "Not connected yet. Allow Notch to control Spotify."
    }

    @ViewBuilder
    private var spotifyPrimaryButton: some View {
        if isSpotifyConnected {
            Button("Open Spotify") {
                if let url = NSWorkspace.shared
                    .urlForApplication(withBundleIdentifier: MusicProvider.spotify.bundleID) {
                    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        } else if !IntegrationPermissions.isInstalled(.spotify) {
            Button("Get Spotify") {
                if let url = IntegrationPermissions.downloadURL(for: .spotify) {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        } else if permissions.pending.contains(.music) {
            ProgressView().controlSize(.small)
        } else {
            Button("Allow") {
                permissions.grantMusicAccess(for: .spotify)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 29/255, green: 185/255, blue: 84/255))
            .controlSize(.small)
            .help("Opens Spotify and lets Notch control it")
        }
    }

    /// Spotify connects entirely through macOS Automation — system media keys,
    /// MediaRemote and AppleScript. No Premium, no developer account, no OAuth.
    private var spotifyCard: some View {
        SettingsCard(title: "Spotify") {
            providerHeader(
                icon: "music.note.list",
                iconColor: Color(red: 29/255, green: 185/255, blue: 84/255),
                name: "Spotify",
                isConnected: isSpotifyConnected,
                status: spotifyStatusLine,
                showsDivider: false
            ) {
                spotifyPrimaryButton
            }

            SettingsCallout(
                text: "Free, local: Notch reads and controls the Spotify app on this Mac. Tap Allow once.",
                systemImage: "checkmark.shield.fill",
                tint: .green
            )
        }
    }

    @ViewBuilder
    private var appleMusicPrimaryButton: some View {
        if isAppleMusicConnected {
            Button("Open Music") {
                if let url = NSWorkspace.shared
                    .urlForApplication(withBundleIdentifier: MusicProvider.appleMusic.bundleID) {
                    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        } else if permissions.pending.contains(.music) {
            ProgressView().controlSize(.small)
        } else {
            Button("Allow") {
                permissions.grantMusicAccess(for: .appleMusic)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 250/255, green: 45/255, blue: 72/255))
            .controlSize(.small)
            .help("Opens Apple Music and lets Notch control it")
        }
    }

    /// Apple Music needs no account or token — just Automation consent to read
    /// and control the Music app on this Mac.
    private var appleMusicCard: some View {
        SettingsCard(title: "Apple Music") {
            providerHeader(
                icon: "apple.logo",
                iconColor: Color(red: 250/255, green: 45/255, blue: 72/255),
                name: "Apple Music",
                isConnected: isAppleMusicConnected,
                status: isAppleMusicConnected
                    ? "Ready. Controls playback, library tracks and artwork automatically."
                    : "Not connected yet. Allow Notch to read and control Apple Music.",
                showsDivider: false
            ) {
                appleMusicPrimaryButton
            }

            SettingsCallout(
                text: "Free, local: Notch reads and controls the Music app on this Mac. Tap Allow once.",
                systemImage: "checkmark.shield.fill",
                tint: .blue
            )
        }
    }

    private func providerHeader<Action: View>(
        icon: String,
        iconColor: Color,
        name: String,
        isConnected: Bool,
        status: String,
        showsDivider: Bool,
        // Escaping: the view built here is stored in SettingsRow's `trailing`
        // closure property (stored closures are implicitly escaping) and
        // rendered later, so the builder must outlive this call.
        @ViewBuilder action: @escaping () -> Action
    ) -> some View {
        SettingsRow(systemImage: icon, tint: iconColor, title: name, subtitle: status, showsDivider: showsDivider) {
            HStack(spacing: 8) {
                if isConnected {
                    Text("Connected")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.green.opacity(0.18)))
                        .foregroundStyle(.green)
                }
                action()
            }
        }
    }

    private var preferredPlayerCard: some View {
        SettingsCard(title: "Preferred Player") {
            SettingsRow(
                systemImage: "music.note.house.fill",
                tint: .pink,
                title: "Active Music Source",
                subtitle: "The notch follows and controls this music player.",
                showsDivider: false
            ) {
                Picker("", selection: $settings.musicProvider) {
                    ForEach(MusicProvider.allCases) { provider in
                        Text(provider.title).tag(provider)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
                .onChange(of: settings.musicProvider) { _, newValue in
                    guard newValue != .automatic else { return }
                    IntegrationPermissions.shared.request(.music)
                }
            }
        }
    }

    private var closedNotchCard: some View {
        SettingsCard(title: "Closed Notch") {
            toggleRow("rectangle.on.rectangle", .blue,
                      "Cover and Visualiser While Playing", $settings.showMediaWings)
            if settings.showMediaWings {
                SettingsRow(
                    systemImage: "waveform",
                    tint: .green,
                    title: "For Any App Making Sound",
                    subtitle: "Browsers, YouTube, games and calls too, not only the "
                        + "player holding the now-playing session."
                ) {
                    Toggle("", isOn: $settings.showWingsForAnyAudio)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
            toggleRow("quote.bubble.fill", .purple,
                      "Live Lyric Line", $settings.lyricActivityEnabled)
            SettingsRow(
                systemImage: "sparkles",
                tint: .orange,
                title: "Announce New Tracks",
                showsDivider: settings.sneakPeekEnabled
            ) {
                Toggle("", isOn: $settings.sneakPeekEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            if settings.sneakPeekEnabled {
                SettingsSliderRow(
                    title: "Announcement Duration",
                    value: $settings.sneakPeekDuration,
                    range: 2 ... 8,
                    step: 0.5,
                    format: { String(format: "%.1fs", $0) },
                    showsDivider: false
                )
            }
        }
    }

    private var lyricsCard: some View {
        SettingsCard(title: "Lyrics") {
            toggleRow("text.quote", .teal,
                      "Fetch Synchronised Lyrics from LRCLIB", $settings.fetchLyrics)
            SettingsRow(
                systemImage: "arrow.down.circle",
                tint: .teal,
                title: "Auto-Scroll During Playback",
                showsDivider: false
            ) {
                Toggle("", isOn: $settings.autoScrollLyrics)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
    }

    /// The visualiser's source. The measured option is a genuine reading of
    /// the output mix — a CoreAudio tap, split into the three bands the bars
    /// draw — which macOS gates behind audio access, so the row under it says
    /// what that costs and where to change the answer.
    @ViewBuilder
    private var visualizerCard: some View {
        SettingsCard(title: "Visualiser") {
            SettingsRow(
                systemImage: "waveform",
                tint: .indigo,
                title: "Real-Time Audio Meter",
                subtitle: settings.realtimeAudioMeter
                    ? "Bars follow the low, mid and high energy of the output mix."
                    : "Bars follow the output volume.",
                showsDivider: settings.realtimeAudioMeter
            ) {
                Toggle("", isOn: $settings.realtimeAudioMeter)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            if settings.realtimeAudioMeter {
                SettingsRow(
                    systemImage: "record.circle",
                    tint: .indigo,
                    title: "Audio Access",
                    subtitle: meterAccessSubtitle,
                    showsDivider: false
                ) {
                    Button("Open Settings") {
                        // Audio access sits in the same privacy pane as screen
                        // recording on current macOS, which is why one link
                        // covers both.
                        let path = "x-apple.systempreferences:com.apple.preference"
                            + ".security?Privacy_ScreenCapture"
                        if let url = URL(string: path) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
    }

    /// What the meter can and cannot do here, in order of specificity: the
    /// version floor, then a real CoreAudio refusal, then the general rule.
    /// Only the middle one is about this Mac, so it wins when present rather
    /// than being averaged away with the others.
    private var meterAccessSubtitle: String {
        guard SystemAudioMeter.isSupported else {
            return "Measuring the output mix needs macOS 14.2 or later. Below that "
                + "the bars follow the output volume instead."
        }
        if let reason = SystemAudioMeter.lastFailureReason {
            return reason
        }
        return "macOS gates reading other apps' audio behind this permission. While "
            + "something is playing, the meter taps the output mix, measures three "
            + "frequency ranges, keeps nothing and stops with the music."
    }

    private func toggleRow(
        _ symbol: String, _ tint: Color, _ title: String, _ binding: Binding<Bool>
    ) -> some View {
        SettingsRow(systemImage: symbol, tint: tint, title: title) {
            Toggle("", isOn: binding)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

// MARK: - Activities

private struct ActivitiesSettingsPane: View {
    @Bindable var settings = NotchSettings.shared

    var body: some View {
        SettingsPane {
            SettingsCard(title: "System HUD") {
                SettingsRow(
                    systemImage: "slider.horizontal.below.rectangle",
                    tint: .indigo,
                    title: "Replace the System Overlay",
                    subtitle: "Show volume and brightness in the notch instead."
                ) {
                    Toggle("", isOn: $settings.hudReplacement)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                SettingsRow(
                    systemImage: "percent",
                    tint: .teal,
                    title: "Show the Percentage",
                    showsDivider: !needsAccessibility
                ) {
                    Toggle("", isOn: $settings.showHUDPercentage)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                if needsAccessibility {
                    SettingsRow(
                        systemImage: "hand.raised.fill",
                        tint: .orange,
                        title: "Accessibility Access Required",
                        subtitle: "Intercepting the media keys needs it.",
                        showsDivider: false
                    ) {
                        HStack(spacing: 8) {
                            // Through the permissions type rather than the
                            // interceptor's own prompt call: that one can only
                            // *raise* the system alert, so once macOS has
                            // recorded a denial it does nothing at all. This
                            // path raises the prompt while the answer is still
                            // open and opens the pane when it is not.
                            Button("Grant") {
                                IntegrationPermissions.shared.request(.accessibility)
                            }
                            Button("Open Settings") {
                                IntegrationPermissions.shared.openSettings(for: .accessibility)
                            }
                            .buttonStyle(.link)
                        }
                    }
                }
            }

            SettingsCallout(
                text: "The notch can only draw the volume and brightness levels "
                    + "if it sees the key presses first, and an event tap needs "
                    + "Accessibility access. Left off, macOS keeps drawing its "
                    + "own overlay and the notch shows brightness by sampling."
            )

            // Everything in this card is the same kind of thing: a system
            // event that interrupts the closed notch. The master switch at the
            // top silences all of them; the rows beneath pick them off one
            // app at a time.
            SettingsCard(title: "Live Activities") {
                SettingsRow(
                    systemImage: "bell.badge.fill",
                    tint: .indigo,
                    title: "All Live Activities",
                    subtitle: "One switch for every event below."
                ) {
                    Toggle("", isOn: $settings.liveActivitiesEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                toggleRow("calendar", .red, "Calendar Events",
                          $settings.calendarActivityEnabled)
                if settings.calendarActivityEnabled {
                    reminderLeadsRow
                }

                toggleRow("bolt.fill", .yellow, "Battery and Power Events",
                          $settings.powerEventEnabled)
                SettingsRow(
                    systemImage: "exclamationmark.triangle.fill",
                    tint: .red,
                    title: "Low Battery Warning",
                    subtitle: "When the plug-in popup and the low-battery note appear."
                ) {
                    Picker("", selection: $settings.lowBatteryThreshold) {
                        ForEach([10, 15, 20, 25], id: \.self) { Text("\($0)%").tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 90)
                }

                toggleRow("moon.fill", .purple, "Focus Mode Changes",
                          $settings.focusChangeEnabled)
                toggleRow("lock.fill", .gray, "Lock and Unlock",
                          $settings.screenLockActivityEnabled)
                toggleRow("airpodspro", .cyan, "Accessory Battery Levels",
                          $settings.showAccessoryBattery,
                          showsDivider: false)
            }

            // The notch's own indicators: each has its own switch rather than
            // being part of the live-activity master, because none of them is a
            // notification about something that happened elsewhere.
            SettingsCard(title: "Indicators and HUDs") {
                toggleRow("speaker.wave.2.fill", .blue, "Volume Changes",
                          $settings.volumeHUDEnabled)
                toggleRow("sun.max.fill", .orange, "Brightness Changes",
                          $settings.brightnessHUDEnabled)
                toggleRow("macwindow.on.rectangle", .purple, "Desktop and Spaces Switches",
                          $settings.desktopChangeEnabled)
                toggleRow("eye.fill", .green, "Eye Break Reminders",
                          $settings.eyeBreakEnabled)
                toggleRow("wrench.and.screwdriver.fill", .gray, "Quick Actions in Tools",
                          $settings.showQuickActions)
                toggleRow("battery.75percent", .green, "Battery Percentage in the Notch",
                          $settings.showBatteryPercentage,
                          showsDivider: false)
            }

            SettingsCard(title: "Clipboard and Shelf") {
                toggleRow("doc.on.clipboard.fill", .pink, "Clipboard History",
                          $settings.clipboardHistoryEnabled)
                if settings.clipboardHistoryEnabled {
                    SettingsRow(
                        systemImage: "number",
                        tint: .pink,
                        title: "History Size"
                    ) {
                        Picker("", selection: $settings.clipboardMaxCapacity) {
                            ForEach([10, 25, 50, 100], id: \.self) {
                                Text("\($0) items").tag($0)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 110)
                    }
                }
                toggleRow("arrow.down.circle.fill", .teal, "Catch Finished Downloads",
                          $settings.catchDownloads)
                toggleRow("camera.viewfinder", .pink, "Catch New Screenshots",
                          $settings.catchScreenshots)
                toggleRow("tray.and.arrow.down.fill", .indigo, "Caught Files Join the Shelf",
                          $settings.caughtFilesJoinShelf)
                toggleRow("airplane.circle.fill", .blue, "AirDrop Dropped Files Immediately",
                          $settings.instantAirDrop)
                SettingsRow(
                    systemImage: "tray.full.fill",
                    tint: .indigo,
                    title: "Clear the Shelf After Dragging Out",
                    showsDivider: false
                ) {
                    Toggle("", isOn: $settings.autoClearShelf)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
        }
    }

    private var needsAccessibility: Bool {
        settings.hudReplacement && !MediaKeyInterceptor.isAccessibilityTrusted
    }

    /// One chip per lead time, in any combination. Each rings once, a little
    /// while before the event, and then the notch goes back to whatever it was
    /// showing — which is the whole point of telling the user when it rings.
    private var reminderLeadsRow: some View {
        SettingsChipRow(
            systemImage: "clock.fill",
            tint: .red,
            title: "Remind Me Before",
            subtitle: settings.calendarReminderLeads.isEmpty
                ? "Nothing selected, so events do not reach the notch. "
                    + "Pick at least one time to be reminded."
                : "Each time rings once and then hands the notch back."
        ) {
            HStack(spacing: 6) {
                ForEach(CalendarReminderLead.allCases) { lead in
                    reminderLeadChip(lead)
                }
            }
        }
    }

    private func reminderLeadChip(_ lead: CalendarReminderLead) -> some View {
        let isOn = settings.calendarReminderLeads.contains(lead)

        return Button {
            var leads = settings.calendarReminderLeads
            if isOn {
                leads.removeAll { $0 == lead }
            } else {
                leads.append(lead)
            }
            settings.calendarReminderLeads = leads
        } label: {
            Text(lead.title)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background {
                    Capsule().fill(
                        isOn
                            ? Color.accentColor.opacity(0.85)
                            : Color.primary.opacity(0.08)
                    )
                }
                .foregroundStyle(isOn ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .help(lead.help)
        .accessibilityLabel(lead.help)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    private func toggleRow(
        _ symbol: String,
        _ tint: Color,
        _ title: String,
        _ binding: Binding<Bool>,
        showsDivider: Bool = true
    ) -> some View {
        SettingsRow(
            systemImage: symbol,
            tint: tint,
            title: title,
            showsDivider: showsDivider
        ) {
            Toggle("", isOn: binding)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

// MARK: - Privacy / Permissions

private struct PrivacySettingsPane: View {
    private var permissions = IntegrationPermissions.shared

    var body: some View {
        Form {
            Section {
                ForEach(IntegrationPermissions.Integration.allCases) { integration in
                    PermissionRow(integration: integration)
                }
            } header: {
                Label("Integrations & Permissions", systemImage: "hand.raised.fill")
            } footer: {
                Text("Everything Notch can ask for, in the order System Settings lists it. "
                    + "macOS asks once per permission: while the answer is still open these "
                    + "rows raise the system prompt, and once it has been answered they open "
                    + "the exact pane instead, because macOS will not ask a second time. "
                    + "Apple Events access can only be verified while the target app is "
                    + "running, so Music control reads Unavailable until Music or Spotify is "
                    + "open.")
            }

            Section {
                Button("Re-check Now") {
                    permissions.refresh(probeFolders: true)
                }
            }
        }
        .formStyle(.grouped)
        // `probeFolders` only from here. Checking access to the folders the file
        // catcher watches means reading them, and that read is the one check in
        // this type that can put a consent prompt on screen — so it is tied to
        // somebody actually looking at the permissions page, not to app launch.
        .onAppear { permissions.refresh(probeFolders: true) }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            // Also probed: the usual reason the app becomes active again from
            // this pane is that the user just changed something in System
            // Settings, and a stale row would read as "nothing happened".
            permissions.refresh(probeFolders: true)
        }
    }
}

private struct PermissionRow: View {
    let integration: IntegrationPermissions.Integration

    private var permissions = IntegrationPermissions.shared

    @State private var isChoosingPlayer = false

    init(integration: IntegrationPermissions.Integration) {
        self.integration = integration
    }

    var body: some View {
        let status = permissions.status(for: integration)
        let canPrompt = permissions.canPrompt(for: integration)
        let isPending = permissions.pending.contains(integration)

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: integration.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(status.tint)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(integration.title)
                        .fontWeight(.medium)
                    Text(integration.detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 6) {
                    Circle()
                        .fill(status.tint)
                        .frame(width: 7, height: 7)
                    Text(status.title)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(status.tint)
                }

                if isPending {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 60)
                } else if status != .granted {
                    // The label says which of the two things the click will do,
                    // because they are not the same thing: one raises the
                    // system prompt, the other opens the pane that owns the
                    // switch. `request` itself enforces the same rule.
                    Button(canPrompt ? "Allow" : "Allow in Settings…") {
                        // Music needs to know which player before it can ask
                        // for anything: the Automation prompt is per target
                        // app, so "allow music" is not a single permission.
                        if integration == .music, canPrompt {
                            isChoosingPlayer = true
                        } else {
                            permissions.request(integration)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                // Only when the button above does not already lead there: two
                // controls doing the same thing in one row reads as a bug.
                // Granted rows keep it, so access can still be revoked.
                if status == .granted || canPrompt {
                    Button("Open Settings") {
                        permissions.openSettings(for: integration)
                    }
                    .buttonStyle(.link)
                }
            }

            // Say what still works without it, and why it can't be read.
            Text(permissions.notes[integration] ?? integration.fallbackNote)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.leading, 32)

            if isChoosingPlayer {
                playerChooser
                    .padding(.leading, 32)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 2)
    }

    /// Picks the player, then hands off to the permission request, which
    /// launches it and addresses it so macOS raises the Automation prompt.
    private var playerChooser: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Which player should Notch control?")
                .font(.system(size: 11, weight: .semibold))

            HStack(spacing: 8) {
                ForEach([MusicProvider.appleMusic, .spotify]) { provider in
                    playerButton(provider)
                }
                Button("Cancel") { isChoosingPlayer = false }
                    .buttonStyle(.link)
            }
        }
    }

    @ViewBuilder
    private func playerButton(_ provider: MusicProvider) -> some View {
        let installed = IntegrationPermissions.isInstalled(provider)

        Button(installed ? provider.title : "Get \(provider.title)") {
            isChoosingPlayer = false
            guard installed else {
                if let url = IntegrationPermissions.downloadURL(for: provider) {
                    NSWorkspace.shared.open(url)
                }
                return
            }
            NotchSettings.shared.musicProvider = provider
            permissions.request(.music)
        }
        .help(installed
              ? "Open \(provider.title) and ask for permission to control it"
              : "\(provider.title) isn't installed")
    }
}

// MARK: - System

private struct SystemSettingsPane: View {
    @Bindable var settings = NotchSettings.shared
    @State private var isImportingProfile = false
    /// Why a file could not be read at all — a folder that moved, a file macOS
    /// will not hand over. The library has its own reason for the files it read
    /// and refused, and the row below shows whichever of the two applies.
    @State private var importFailure: String?

    /// The mixer the app is running. Reached through the bridge rather than
    /// built here: a second engine would tap the same apps the first one is
    /// already processing, and the later tap wins.
    private var mixer: MixerEngine? { MixerBridge.shared.mixer }

    private var mixerEnabled: Binding<Bool> {
        Binding(
            get: { mixer?.isEnabled ?? false },
            set: { mixer?.isEnabled = $0 }
        )
    }

    private var displayVolumeEnabled: Binding<Bool> {
        Binding(
            get: { DisplayVolumeController.shared.isEnabled },
            set: { DisplayVolumeController.shared.isEnabled = $0 }
        )
    }

    var body: some View {
        Form {
            Section {
                Picker("Refresh every", selection: $settings.telemetryInterval) {
                    Text("0.5 seconds").tag(0.5)
                    Text("1 second").tag(1.0)
                    Text("2 seconds").tag(2.0)
                    Text("5 seconds").tag(5.0)
                }
            } header: {
                Label("Sampling Rate", systemImage: "gauge.with.dots.needle.50percent")
            } footer: {
                Text("Telemetry hardware sensors only sample while the notch is expanded. Zero CPU is consumed when collapsed.")
            }

            Section {
                Toggle("Show CPU rolling sparkline", isOn: $settings.showCPUSparkline)
                Toggle("Show Memory pressure ring", isOn: $settings.showMemoryPressure)
                Toggle("Show Network throughput speeds", isOn: $settings.showNetworkSpeed)
                Toggle("Show Battery health and power draw", isOn: $settings.showBatteryHealth)
            } header: {
                Label("Metrics Display", systemImage: "chart.line.uptrend.xyaxis")
            } footer: {
                Text("Customizes which telemetry components appear in the System tab and main dashboard.")
            }

            Section {
                Toggle("Switch to newly connected output devices", isOn: $settings.autoSwitchOutputOnConnect)

                Slider(
                    value: Binding(
                        get: { Double(AudioOutputManager.shared.alertVolume) },
                        set: { AudioOutputManager.shared.setAlertVolume(Float($0)) }
                    ),
                    in: 0...1
                ) {
                    Text("Alert Volume")
                } minimumValueLabel: {
                    Image(systemName: "speaker.fill")
                } maximumValueLabel: {
                    Image(systemName: "speaker.wave.3.fill")
                }
                Toggle("Control external display speakers", isOn: displayVolumeEnabled)
            } header: {
                Label("Audio", systemImage: "speaker.wave.2.fill")
            } footer: {
                Text("Alert volume controls the volume macOS uses for notification sounds, matching System Settings → Sound. Auto-switch routes output to a device the moment it connects. Display speakers are set over the display's own control channel, because they are not an audio device macOS lists at all.")
            }
            .onAppear {
                // AppleScript read is slow, so only refresh when the pane opens.
                AudioOutputManager.shared.refreshAlertVolume()
            }

            // The mixer's per-app controls live in the notch — that is where you
            // can hear what you are changing. What belongs in a window is the
            // switch, the corrections it can apply, and what happens when a tap
            // is refused.
            Section {
                Toggle("Enable the per-app mixer", isOn: mixerEnabled)
                    .disabled(mixer == nil)

                if mixer == nil {
                    Text("The mixer starts with the app; reopen Settings if this stays off.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                } else if mixer?.isSupported == false {
                    Text("Per-app volume needs macOS 14.2 or later. On this macOS an app's own level cannot be changed by anything but the app itself, so the mixer stays off.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            } header: {
                Label("Per-App Mixer", systemImage: "slider.horizontal.3")
            } footer: {
                Text("Gives each app its own level — above 100%, up to 4x — plus mute, output routing, an equalizer and loudness compensation. Nothing runs for an app you have not changed: each one is taken over only once you move its slider, and it returns to the system's own audio path the moment you reset it. If taking over an app fails with a CoreAudio error, a newer macOS may be holding back the audio-capture permission — allow Notch under Privacy & Security, then switch this off and on again.")
            }

            Section {
                if profiles.isEmpty {
                    Text("No corrections imported yet. An AutoEQ profile is a text file describing how one pair of headphones deviates from a target curve — parametric or graphic, both read here.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(profiles) { profile in
                        profileRow(profile)
                    }
                }

                HStack {
                    Button("Import from File…") { isImportingProfile = true }
                    Spacer()
                    Button("Show Folder") { revealLibraryFolder() }
                }

                if let failure = importFailure ?? AutoEQLibrary.shared.lastImportFailure {
                    Text(failure)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Label("Headphone Corrections", systemImage: "headphones")
            } footer: {
                Text("Import a measured correction here, then choose it for an app in the notch's Mixer. Corrections are per app rather than per device, because the one that applies is the one for the headphones that app is playing into.")
            }
        }
        .formStyle(.grouped)
        .fileImporter(
            isPresented: $isImportingProfile,
            allowedContentTypes: [.plainText, .text]
        ) { result in
            switch result {
            case .success(let url):
                _ = AutoEQLibrary.shared.importProfile(from: url)
            case .failure(let error):
                importFailure = error.localizedDescription
            }
        }
    }

    /// Read in `body`, so an import or a removal redraws the list without the
    /// pane holding the library itself.
    private var profiles: [AutoEQProfile] { AutoEQLibrary.shared.profiles }

    private func profileRow(_ profile: AutoEQProfile) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "headphones")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .fontWeight(.medium)

                Text(detail(for: profile))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            Button("Remove") {
                AutoEQLibrary.shared.remove(profile.id)
                importFailure = nil
            }
        }
    }

    private func detail(for profile: AutoEQProfile) -> String {
        let filters = "\(profile.filters.count) filter\(profile.filters.count == 1 ? "" : "s")"
        let preamp = String(format: "%+.1f dB preamp", profile.preampDB)
        return profile.source.isEmpty
            ? "\(filters) · \(preamp)"
            : "\(filters) · \(preamp) · \(profile.source)"
    }

    private func revealLibraryFolder() {
        let url = AutoEQLibrary.shared.directoryURL
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

// MARK: - About

private struct AboutSettingsPane: View {
    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.primary, .primary.opacity(0.5)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .padding(.top, 24)

            Text("Notch")
                .font(.title2.bold())

            Text(version)
                .font(.callout)
                .foregroundStyle(.secondary)

            Divider()
                .frame(width: 240)
                .padding(.vertical, 6)

            Button("Check for Updates…") {
                UpdateController.shared.checkForUpdates()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .padding(.bottom, 4)

            Text("A notch-extending utility for macOS.\nInspired by boring.notch, Sapphire, DynamicNotch, and Atoll.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
