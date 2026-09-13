import AppKit
import SwiftUI

/// The Settings window (⌘, from the menu bar item, or the gear in the notch).
/// A sidebar rather than a tab strip: eight tabs crowded the tab bar and left
/// each pane cramped, and the sidebar is the modern macOS settings idiom.
struct SettingsView: View {
    private enum Pane: String, CaseIterable, Identifiable {
        case general, notch, media, weather, activities, system, privacy, about

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
            case .about: "info.circle"
            }
        }

        /// What each pane actually contains, for the sidebar's search field.
        /// Keep in step with the panes below when settings move.
        var keywords: [String] {
            switch self {
            case .general:
                ["launch", "login", "startup", "hotkey", "shortcut", "menu bar",
                 "animation", "style", "motion", "display", "screen", "monitor"]
            case .notch:
                ["hover", "peek", "size", "width", "height", "corner", "radius",
                 "tolerance", "delay", "open", "close", "scroll", "pin",
                 "widget", "widgets", "dashboard", "home"]
            case .media:
                ["music", "spotify", "apple music", "lyrics", "player",
                 "provider", "sneak peek", "artwork", "visualizer", "wings"]
            case .weather:
                ["forecast", "temperature", "celsius", "fahrenheit", "location",
                 "city", "units"]
            case .activities:
                ["live activity", "battery", "volume", "brightness", "hud",
                 "clipboard", "shelf", "airdrop", "desktop", "space", "timer",
                 "eye break", "focus", "accessory", "download", "downloads",
                 "screenshot", "screenshots", "catch", "file"]
            case .system:
                ["cpu", "memory", "network", "telemetry", "stats", "gauge",
                 "sparkline", "battery health", "audio", "output", "input",
                 "device"]
            case .privacy:
                ["permission", "accessibility", "calendar", "automation",
                 "screen recording", "access"]
            case .about:
                ["version", "licence", "license", "credits", "acknowledgements"]
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
            case .about: .secondary
            }
        }
    }

    @State private var selection: Pane = Self.initialPane

    /// The pane Settings opens on. Always General in release; a debug launch
    /// flag can pick another, which is the only way to put a specific pane in
    /// front of a screenshot without driving the UI.
    private static var initialPane: Pane {
        #if DEBUG
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--debug-pane"), i + 1 < args.count,
           let pane = Pane(rawValue: args[i + 1]) {
            return pane
        }
        #endif
        return .general
    }
    @State private var search = ""

    /// The sidebar filters as you type.
    ///
    /// Matches each pane's own keywords as well as its title: searching
    /// "lyrics" or "hover" used to return an empty sidebar, because only the
    /// eight pane names were ever searched and none of them contain the words
    /// anyone would actually look for.
    private var visiblePanes: [Pane] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return Pane.allCases }
        return Pane.allCases.filter { pane in
            pane.title.localizedCaseInsensitiveContains(query)
                || pane.keywords.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 210)
                .background(.quaternary.opacity(0.5))

            Rectangle()
                .fill(.separator)
                .frame(width: 1)

            VStack(alignment: .leading, spacing: 0) {
                // Header bar with a hairline so the content begins on the
                // same baseline as the sidebar, whichever pane is selected.
                VStack(alignment: .leading, spacing: 10) {
                    Text(selection.title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.primary)

                    Rectangle()
                        .fill(.separator)
                        .frame(height: 1)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 8)

                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 780, idealWidth: 820, minHeight: 560, idealHeight: 620)
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
                    .fill(.quaternary.opacity(0.6))
            }
            .padding(12)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 3) {
                    ForEach(visiblePanes) { pane in
                        let isSelected = selection == pane
                        Button {
                            withAnimation(NotchAnimations.content) {
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
                                    .foregroundStyle(isSelected ? .white : .primary)
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
        // Crossfade on pane selection: panes swap in place, so a fade (never a
        // slide/scale, which would imply spatial movement) bridges the swap.
        // Driven by the sidebar's withAnimation(NotchAnimations.content);
        // transitions retarget, so rapid clicking never stutters.
        Group {
            switch selection {
            case .general: GeneralSettingsPane()
            case .notch: NotchSettingsPane()
            case .media: MediaSettingsPane()
            case .weather: WeatherSettingsPane()
            case .activities: ActivitiesSettingsPane()
            case .system: SystemSettingsPane()
            case .privacy: PrivacySettingsPane()
            case .about: AboutSettingsPane()
            }
        }
        .id(selection)
        .transition(.opacity)
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
            Text("These scale every screen together — each one keeps its own shape, so switching tabs does move the panel, but always between sizes you chose here. The width is capped to your display. Hovering is detected over the hardware notch itself, never over the wings beside it.")
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
                    .labelsHidden()
                    .toggleStyle(.switch)
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

    private func toggleRow(
        _ symbol: String,
        _ tint: Color,
        _ title: String,
        _ binding: Binding<Bool>
    ) -> some View {
        SettingsRow(systemImage: symbol, tint: tint, title: title) {
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
            } header: {
                Label("Audio", systemImage: "speaker.wave.2.fill")
            } footer: {
                Text("Alert volume controls the volume macOS uses for notification sounds, matching System Settings → Sound. Auto-switch routes output to a device the moment it connects.")
            }
            .onAppear {
                // AppleScript read is slow, so only refresh when the pane opens.
                AudioOutputManager.shared.refreshAlertVolume()
            }
        }
        .formStyle(.grouped)
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

            Text("A notch-extending utility for macOS.\nInspired by boring.notch, Sapphire, DynamicNotch, and Atoll.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
