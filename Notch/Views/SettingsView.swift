import AppKit
import SwiftUI

/// The Settings window (⌘, from the menu bar item, or the gear in the notch).
/// A sidebar rather than a tab strip: eight tabs crowded the tab bar and left
/// each pane cramped, and the sidebar is the modern macOS settings idiom.
struct SettingsView: View {
    private enum Pane: String, CaseIterable, Identifiable {
        case general, notch, media, weather, activities, system, privacy, pro, about

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: "General"
            case .notch: "Notch"
            case .media: "Media"
            case .weather: "Weather"
            case .activities: "Activities"
            case .system: "System"
            case .privacy: "Privacy"
            case .pro: "Pro"
            case .about: "About"
            }
        }

        var systemImage: String {
            switch self {
            case .general: "gearshape"
            case .notch: "sparkles.rectangle.stack"
            case .media: "music.note"
            case .weather: "cloud.sun"
            case .activities: "bolt.badge.clock"
            case .system: "gauge.with.dots.needle.50percent"
            case .privacy: "hand.raised"
            case .pro: "sparkles"
            case .about: "info.circle"
            }
        }

        var tint: Color {
            switch self {
            case .general: .gray
            case .notch: .indigo
            case .media: .pink
            case .weather: .cyan
            case .activities: .orange
            case .system: .green
            case .privacy: .blue
            case .pro: .purple
            case .about: .secondary
            }
        }
    }

    @State private var selection: Pane = .general
    @State private var search = ""

    /// The sidebar filters as you type, which is what the reference's search
    /// field is for.
    private var visiblePanes: [Pane] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return Pane.allCases }
        return Pane.allCases.filter {
            $0.title.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 210)
                .background(Color.black.opacity(0.3))

            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(width: 1)

            VStack(alignment: .leading, spacing: 0) {
                // Header bar
                HStack {
                    Text(selection.title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(NotchTheme.inkPrimary)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 12)

                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 780, idealWidth: 820, minHeight: 560, idealHeight: 620)
        .preferredColorScheme(.dark)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("Search", text: $search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            }
            .padding(12)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 3) {
                    ForEach(visiblePanes) { pane in
                        let isSelected = selection == pane
                        Button {
                            withAnimation(.easeInOut(duration: 0.12)) {
                                selection = pane
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: pane.systemImage)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 24, height: 24)
                                    .background {
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(pane.tint)
                                    }
                                Text(pane.title)
                                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                                    .foregroundStyle(isSelected ? .white : NotchTheme.inkPrimary)
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background {
                                if isSelected {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.accentColor.opacity(0.35))
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 10)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .general: GeneralSettingsPane()
        case .notch: NotchSettingsPane()
        case .media: MediaSettingsPane()
        case .weather: WeatherSettingsPane()
        case .activities: ActivitiesSettingsPane()
        case .system: SystemSettingsPane()
        case .privacy: PrivacySettingsPane()
        case .pro: ProSettingsPane()
        case .about: AboutSettingsPane()
        }
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
            } header: {
                Text("Location")
            } footer: {
                Text("Weather works without location access — the notch falls back to an approximate position from your network connection. Granting access makes it accurate to your city.")
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
                    title: "Hover Tolerance",
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

            DimensionSliders()
        }
        .formStyle(.grouped)
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
            Text("Width and height trim the notch the app measured from your display — useful if the drawn pill doesn't quite cover the hardware.")
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
            Text("Every screen opens to this one panel, so switching tabs never resizes the notch, and the width is capped to your display. Hovering is detected over the hardware notch itself, never over the wings beside it.")
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
    private var auth = SpotifyAuth.shared
    private var permissions = IntegrationPermissions.shared
    @State private var hasCopiedURI = false

    var body: some View {
        SettingsPane {
            musicProvidersSection

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

            SettingsCard(title: "Closed Notch") {
                toggleRow("rectangle.on.rectangle", .blue,
                          "Cover and Visualiser While Playing", $settings.showMediaWings)
                if settings.showMediaWings {
                    SettingsRow(
                        systemImage: "waveform",
                        tint: .green,
                        title: "For Any App Making Sound",
                        subtitle: "Browsers, YouTube, games and calls too — not only the "
                            + "player holding the now-playing session."
                    ) {
                        Toggle("", isOn: $settings.showWingsForAnyAudio)
                            .labelsHidden().toggleStyle(.switch)
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
                        .labelsHidden().toggleStyle(.switch)
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

            visualizerCard

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
                        .labelsHidden().toggleStyle(.switch)
                }
            }
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

    /// Redesigned Music Providers section with direct authorization buttons and live connection status.
    private var musicProvidersSection: some View {
        SettingsCard(title: "Music Providers") {
            spotifyProviderRow
            Divider().padding(.leading, 58)
            appleMusicProviderRow
        }
    }

    /// Spotify Provider Row: Shows live Web API connection and native integration.
    private var spotifyProviderRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(red: 29/255, green: 185/255, blue: 84/255))
                        .frame(width: 34, height: 34)
                    Image(systemName: "music.note.list")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("Spotify")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(NotchTheme.inkPrimary)

                        if auth.state == .signedIn {
                            Text("Connected")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.green.opacity(0.18)))
                                .foregroundStyle(.green)
                        }
                    }

                    if auth.state == .signedIn {
                        if let name = auth.userProfile?.displayName {
                            Text("Signed in as \(name) • Connected across all devices")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else {
                            Text("Connected to Spotify Web API • Works even when app is closed")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    } else {
                        Text("Native macOS playback works with zero login. Connect Web API for Spotify Connect & remote control.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 8)

                if auth.state == .signedIn {
                    Button("Disconnect") {
                        withAnimation { auth.signOut() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else if auth.state == .authorizing {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Authorizing…")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if auth.state != .signedIn {
                VStack(alignment: .leading, spacing: 8) {
                    if case let .failed(msg) = auth.state {
                        Text(msg)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.red)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Connect Spotify Web API (3 Quick Steps):")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(NotchTheme.inkPrimary)

                        HStack(spacing: 8) {
                            Button {
                                NSWorkspace.shared.open(URL(string: "https://developer.spotify.com/dashboard")!)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.up.right.square")
                                        .font(.system(size: 10))
                                    Text("1. Open Developer Dashboard")
                                        .font(.system(size: 11))
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(SpotifyAuth.redirectURI, forType: .string)
                                hasCopiedURI = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    hasCopiedURI = false
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: hasCopiedURI ? "checkmark" : "doc.on.doc")
                                        .font(.system(size: 10))
                                        .foregroundStyle(hasCopiedURI ? .green : .primary)
                                    Text(hasCopiedURI ? "Copied URI!" : "2. Copy Redirect URI")
                                        .font(.system(size: 11))
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        HStack(spacing: 8) {
                            TextField("3. Paste App Client ID here", text: Binding(
                                get: { settings.spotifyClientID },
                                set: { auth.clientID = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11).monospaced())

                            Button("Connect Spotify") {
                                auth.signIn()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color(red: 29/255, green: 185/255, blue: 84/255))
                            .controlSize(.small)
                            .disabled(auth.clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .padding(10)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.quaternary.opacity(0.35))
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// Apple Music Provider Row: Direct authorization and status.
    private var appleMusicProviderRow: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LinearGradient(
                        colors: [
                            Color(red: 250/255, green: 45/255, blue: 72/255),
                            Color(red: 254/255, green: 74/255, blue: 104/255),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 34, height: 34)
                Image(systemName: "apple.logo")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Apple Music")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(NotchTheme.inkPrimary)

                    if permissions.musicStatus(for: .appleMusic) == .granted {
                        Text("Authorized")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.green.opacity(0.18)))
                            .foregroundStyle(.green)
                    }
                }

                if permissions.musicStatus(for: .appleMusic) == .granted {
                    Text("Ready • Controls playback, library tracks & artwork automatically.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("Authorize to let Notch display and control Apple Music playback.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if permissions.musicStatus(for: .appleMusic) == .granted {
                Button("Open Music") {
                    NSWorkspace.shared.open(URL(string: "music://")!)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else if permissions.pending.contains(.music) {
                ProgressView().controlSize(.small)
            } else {
                Button("Allow / Connect") {
                    permissions.grantMusicAccess(for: .appleMusic)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 250/255, green: 45/255, blue: 72/255))
                .controlSize(.small)
                .help("Opens Apple Music and requests system permission")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// The visualiser's source. The measured option is a real capture of the
    /// output mix, so it costs a Screen Recording permission.
    @ViewBuilder
    private var visualizerCard: some View {
        SettingsCard(title: "Visualiser") {
            SettingsRow(
                systemImage: "waveform",
                tint: .indigo,
                title: "Real-Time Audio Meter",
                subtitle: settings.realtimeAudioMeter
                    ? "Bars follow the actual output mix."
                    : "Bars follow the output volume.",
                showsDivider: settings.realtimeAudioMeter
            ) {
                Toggle("", isOn: $settings.realtimeAudioMeter)
                    .labelsHidden().toggleStyle(.switch)
                    .onChange(of: settings.realtimeAudioMeter) { _, enabled in
                        guard enabled, !SystemAudioMeter.hasPermission else { return }
                        _ = SystemAudioMeter.requestPermission()
                    }
            }

            if settings.realtimeAudioMeter {
                SettingsRow(
                    systemImage: "record.circle",
                    tint: .indigo,
                    title: "Screen Recording Permission",
                    subtitle: SystemAudioMeter.hasPermission
                        ? "Granted. Reading the output mix while music plays."
                        : "macOS only lets an app read other apps' audio with "
                            + "this permission. Nothing is recorded or stored.",
                    showsDivider: false
                ) {
                    if SystemAudioMeter.hasPermission {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.green)
                    } else {
                        Button("Open Settings") {
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
    }

    private func toggleRow(
        _ symbol: String, _ tint: Color, _ title: String, _ binding: Binding<Bool>
    ) -> some View {
        SettingsRow(systemImage: symbol, tint: tint, title: title) {
            Toggle("", isOn: binding).labelsHidden().toggleStyle(.switch)
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
                        .labelsHidden().toggleStyle(.switch)
                }
                SettingsRow(
                    systemImage: "percent",
                    tint: .teal,
                    title: "Show the Percentage",
                    showsDivider: !needsAccessibility
                ) {
                    Toggle("", isOn: $settings.showHUDPercentage)
                        .labelsHidden().toggleStyle(.switch)
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
                            Button("Grant") { MediaKeyInterceptor.requestAccessibility() }
                            Button("Open Settings") {
                                if let url = URL(string: "x-apple.systempreferences:"
                                    + "com.apple.preference.security?Privacy_Accessibility") {
                                    NSWorkspace.shared.open(url)
                                }
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

            SettingsCard(title: "Live Activities") {
                toggleRow("bolt.badge.clock", .yellow, "Battery and Power Events",
                          $settings.liveActivitiesEnabled)
                toggleRow("speaker.wave.2.fill", .blue, "Volume Changes",
                          $settings.volumeHUDEnabled)
                toggleRow("sun.max.fill", .orange, "Brightness Changes",
                          $settings.brightnessHUDEnabled)
                toggleRow("macwindow.on.rectangle", .purple, "Desktop and Spaces Switches",
                          $settings.desktopChangeEnabled)
                toggleRow("airpodspro", .cyan, "Accessory Battery Levels",
                          $settings.showAccessoryBattery)
                toggleRow("eye.fill", .green, "Eye Break Reminders",
                          $settings.eyeBreakEnabled)
                toggleRow("wrench.and.screwdriver.fill", .gray, "Quick Actions in Tools",
                          $settings.showQuickActions)
                toggleRow("battery.75percent", .green, "Battery Percentage in the Notch",
                          $settings.showBatteryPercentage)
                SettingsRow(
                    systemImage: "exclamationmark.triangle.fill",
                    tint: .red,
                    title: "Low Battery Warning",
                    showsDivider: false
                ) {
                    Picker("", selection: $settings.lowBatteryThreshold) {
                        ForEach([10, 15, 20, 25], id: \.self) { Text("\($0)%").tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 90)
                }
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
                toggleRow("airplane.circle.fill", .blue, "AirDrop Dropped Files Immediately",
                          $settings.instantAirDrop)
                SettingsRow(
                    systemImage: "tray.full.fill",
                    tint: .indigo,
                    title: "Clear the Shelf After Dragging Out",
                    showsDivider: false
                ) {
                    Toggle("", isOn: $settings.autoClearShelf)
                        .labelsHidden().toggleStyle(.switch)
                }
            }
        }
    }

    private var needsAccessibility: Bool {
        settings.hudReplacement && !MediaKeyInterceptor.isAccessibilityTrusted
    }

    private func toggleRow(
        _ symbol: String,
        _ tint: Color,
        _ title: String,
        _ binding: Binding<Bool>
    ) -> some View {
        SettingsRow(systemImage: symbol, tint: tint, title: title) {
            Toggle("", isOn: binding).labelsHidden().toggleStyle(.switch)
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
                Text("Status is read from the system each time this pane appears. Apple Events access can only be verified while the target app is running, so Music control reads Unavailable until Music or Spotify is open.")
            }

            Section {
                Button("Re-check Now") {
                    permissions.refresh()
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { permissions.refresh() }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            permissions.refresh()
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
                    Button("Allow") {
                        // Music needs to know which player before it can ask
                        // for anything: the Automation prompt is per target
                        // app, so "allow music" is not a single permission.
                        if integration == .music {
                            isChoosingPlayer = true
                        } else {
                            permissions.request(integration)
                        }
                    }
                }

                // System Settings is always available, not only once macOS has
                // recorded a denial: a prompt that never appears leaves the
                // status at "Not requested" with no other way forward.
                Button("Open Settings") {
                    if let url = integration.settingsURL {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link)
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
                Text("Telemetry hardware sensors only sample while the notch is expanded — zero CPU is consumed when collapsed.")
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
        }
        .formStyle(.grouped)
    }
}

// MARK: - Pro

private struct ProSettingsPane: View {
    private var license = LicenseManager.shared

    @State private var keyInput = ""
    @State private var showInvalidKey = false

    private static let ctaGradient = LinearGradient(
        colors: [
            Color(red: 0.36, green: 0.53, blue: 1.0),
            Color(red: 0.83, green: 0.45, blue: 0.94),
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if license.isPro {
                    activeCard
                } else {
                    tierCards
                    activationField
                }

                Text("License keys are validated locally in this build — connect a licensing backend before selling.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }
            .padding(20)
        }
    }

    private var tierCards: some View {
        HStack(alignment: .top, spacing: 12) {
            tierCard(
                chip: "FREE TIER", chipTint: .green,
                name: "Free", price: "$0", cadence: "forever",
                features: [
                    "Media hub & synced lyrics",
                    "Shelf & AirDrop",
                    "24-hour schedule",
                    "Live activities & HUD",
                    "System telemetry",
                ],
                highlighted: false
            )

            VStack(spacing: 0) {
                Text("RECOMMENDED")
                    .font(.system(size: 8.5, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(.blue))
                    .offset(y: 9)
                    .zIndex(1)

                tierCard(
                    chip: "PRO", chipTint: .blue,
                    name: "Pro", price: "$14.99", cadence: "one-time",
                    features: [
                        "Everything in Free",
                        "Priority feature requests",
                        "Early access to new modules",
                        "Supports development",
                    ],
                    highlighted: true
                )
            }
        }
    }

    private func tierCard(
        chip: String, chipTint: Color,
        name: String, price: String, cadence: String,
        features: [String],
        highlighted: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(chip)
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(chipTint)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(chipTint.opacity(0.15)))

            Text(name)
                .font(.system(size: 20, weight: .bold))

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(price)
                    .font(.system(size: 24, weight: .heavy).monospacedDigit())
                Text("/ \(cadence)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(features, id: \.self) { feature in
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(highlighted ? .blue : .green)
                        Text(feature)
                            .font(.system(size: 10.5))
                    }
                }
            }
            .padding(.top, 2)

            Spacer(minLength: 4)

            if highlighted {
                Button {
                    NSWorkspace.shared.open(LicenseManager.purchaseURL)
                } label: {
                    Text("GET NOTCH PRO")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(Capsule().fill(Self.ctaGradient))
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 230, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(highlighted ? .blue.opacity(0.6) : Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var activationField: some View {
        HStack(spacing: 8) {
            TextField("NOTCH-XXXX-XXXX-XXXX", text: $keyInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11).monospaced())
            Button("Activate") {
                switch LicenseManager.shared.activate(keyInput) {
                case .activated:
                    showInvalidKey = false
                    keyInput = ""
                case .invalidFormat:
                    showInvalidKey = true
                }
            }
            .disabled(keyInput.isEmpty)
        }
        .overlay(alignment: .bottomLeading) {
            if showInvalidKey {
                Text("That doesn't look like a valid key.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.red)
                    .offset(y: 16)
            }
        }
        .padding(.top, 2)
    }

    private var activeCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 34))
                .foregroundStyle(.blue)
                .padding(.top, 20)
            Text("Notch Pro is active")
                .font(.system(size: 17, weight: .bold))
            if let key = license.maskedKey {
                Text(key)
                    .font(.system(size: 11).monospaced())
                    .foregroundStyle(.secondary)
            }
            Text("Thank you for supporting development.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Button("Deactivate License") {
                LicenseManager.shared.deactivate()
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, minHeight: 230)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        }
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
                        colors: [.white, .white.opacity(0.5)],
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

            Text("A notch-extending utility for macOS.\nInspired by boring.notch, Sapphire, DynamicNotch, and Atoll.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
