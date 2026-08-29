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

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $selection) { section in
                Label {
                    Text(section.title)
                } icon: {
                    Image(systemName: section.systemImage)
                        .foregroundStyle(section.tint)
                }
                .tag(section)
            }
            .navigationSplitViewColumnWidth(178)
        } detail: {
            detail
                .navigationTitle(selection.title)
        }
        .frame(width: 760, height: 560)
        // Match the notch's dark aesthetic.
        .preferredColorScheme(.dark)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
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

    @State private var refreshToken = 0

    private var locationStatus: IntegrationPermissions.Status {
        IntegrationPermissions.Integration.location.status
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

                if locationStatus != .granted {
                    Button("Grant Location Access") {
                        IntegrationPermissions.Integration.location.request {
                            refreshToken += 1
                        }
                    }
                }
            } header: {
                Text("Location")
            } footer: {
                Text("Weather works without location access — the notch falls back to an approximate position from your network connection. Granting access makes it accurate to your city.")
            }
        }
        .formStyle(.grouped)
        .id(refreshToken)
    }
}

// MARK: - General

private struct GeneralSettingsPane: View {
    @Bindable var settings = NotchSettings.shared

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                Toggle("Haptic feedback", isOn: $settings.hapticsEnabled)
                Toggle("Auto-collapse when mouse leaves", isOn: $settings.autoCollapseOnMouseExit)
            } header: {
                Label("Startup & Interaction", systemImage: "power")
            } footer: {
                Text("Haptics play on the trackpad when the notch opens, closes, or receives a file drop.")
            }

            Section {
                Picker("Animation style", selection: $settings.animationProfile) {
                    ForEach(AnimationProfile.allCases) { profile in
                        Text(profile.title).tag(profile)
                    }
                }
                .pickerStyle(.segmented)

                Text(animationDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Label("Animation Personality", systemImage: "wand.and.stars")
            }
        }
        .formStyle(.grouped)
    }

    private var animationDescription: String {
        switch settings.animationProfile {
        case .snappy:
            "Snappy is quick and responsive with an energetic micro-spring."
        case .bouncy:
            "Bouncy playfully overshoots on expansion for a fluid, lively feel."
        case .calm:
            "Calm smoothly glides open with gentle, fully-damped transitions."
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

// MARK: - Media

private struct MediaSettingsPane: View {
    @Bindable var settings = NotchSettings.shared

    var body: some View {
        Form {
            Section {
                Picker("Music source", selection: $settings.musicProvider) {
                    ForEach(MusicProvider.allCases) { provider in
                        Text(provider.title).tag(provider)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: settings.musicProvider) { _, newValue in
                    // Choosing a player asks for control permission up front
                    // so transport works on the first press.
                    guard newValue != .automatic else { return }
                    IntegrationPermissions.Integration.music.request {}
                }
            } header: {
                Label("Integration", systemImage: "music.note")
            } footer: {
                Text("The notch follows and controls this player. Choosing one asks for control permission; denied access can be re-enabled in the Privacy tab.")
            }

            Section {
                Toggle("Artwork and weather wings while playing", isOn: $settings.showMediaWings)
                Toggle("Live lyric line under the notch", isOn: $settings.lyricActivityEnabled)
                Toggle("Announce new tracks (sneak peek)", isOn: $settings.sneakPeekEnabled)

                if settings.sneakPeekEnabled {
                    HStack {
                        Text("Sneak peek duration")
                        Spacer()
                        Slider(value: $settings.sneakPeekDuration, in: 2.0 ... 8.0, step: 0.5)
                            .frame(width: 170)
                        Text(String(format: "%.1f s", settings.sneakPeekDuration))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .trailing)
                    }
                }
            } header: {
                Label("Collapsed Notch", systemImage: "music.note")
            } footer: {
                Text("New tracks briefly display the song title and artist in the closed notch wings.")
            }

            Section {
                Toggle("Fetch synchronized lyrics from LRCLIB", isOn: $settings.fetchLyrics)
                Toggle("Auto-scroll lyrics during playback", isOn: $settings.autoScrollLyrics)
            } header: {
                Label("Lyrics & Playback", systemImage: "quote.bubble")
            } footer: {
                Text("Lyrics are matched via track title and artist. Tap any line in the lyrics view to seek playback directly.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Activities

private struct ActivitiesSettingsPane: View {
    @Bindable var settings = NotchSettings.shared

    var body: some View {
        Form {
            Section {
                Toggle("Battery charging and power events", isOn: $settings.liveActivitiesEnabled)
                Toggle("Volume change HUD", isOn: $settings.volumeHUDEnabled)
                Toggle("Desktop & Spaces switches", isOn: $settings.desktopChangeEnabled)
                Toggle("Bluetooth accessories battery levels", isOn: $settings.showAccessoryBattery)
                Toggle("Eye break reminders (20-20-20)", isOn: $settings.eyeBreakEnabled)
                Toggle("Battery percentage beside the battery glyph", isOn: $settings.showBatteryPercentage)

                Picker("Low battery warning threshold", selection: $settings.lowBatteryThreshold) {
                    Text("10%").tag(10)
                    Text("15%").tag(15)
                    Text("20%").tag(20)
                    Text("25%").tag(25)
                }
            } header: {
                Label("Live Activities & Alerts", systemImage: "bolt.badge.clock")
            } footer: {
                Text("Live activities are event-driven and zero-polling. Monitor changes apply immediately.")
            }

            Section {
                Toggle("Clipboard history", isOn: $settings.clipboardHistoryEnabled)
                if settings.clipboardHistoryEnabled {
                    Picker("Maximum history entries", selection: $settings.clipboardMaxCapacity) {
                        Text("10 items").tag(10)
                        Text("25 items").tag(25)
                        Text("50 items").tag(50)
                        Text("100 items").tag(100)
                    }
                }
            } header: {
                Label("Clipboard", systemImage: "doc.on.clipboard")
            } footer: {
                Text("Concealed entries from password managers are excluded. Pinned entries persist across launches.")
            }

            Section {
                Toggle("AirDrop dropped files immediately", isOn: $settings.instantAirDrop)
                Toggle("Clear items from shelf after dragging out", isOn: $settings.autoClearShelf)
            } header: {
                Label("Shelf", systemImage: "tray.full")
            } footer: {
                Text(settings.instantAirDrop
                    ? "Files dropped on the notch immediately trigger the system AirDrop share picker."
                    : "Files dropped on the notch remain on the shelf for dragging, previewing, or AirDropping.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Privacy / Permissions

private struct PrivacySettingsPane: View {
    @State private var refreshToken = 0
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Form {
            Section {
                ForEach(IntegrationPermissions.Integration.allCases) { integration in
                    PermissionRow(integration: integration) {
                        integration.request {
                            refreshToken += 1
                        }
                    }
                }
            } header: {
                Label("Integrations & Permissions", systemImage: "hand.raised.fill")
            } footer: {
                Text("Each integration asks once. Denied access can be re-enabled in System Settings → Privacy & Security.")
            }
        }
        .formStyle(.grouped)
        .id(refreshToken)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshToken += 1
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                refreshToken += 1
            }
        }
    }
}

private struct PermissionRow: View {
    let integration: IntegrationPermissions.Integration
    let action: () -> Void

    var body: some View {
        let status = integration.status

        HStack(spacing: 10) {
            Image(systemName: integration.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(statusColor(status))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(integration.title)
                    .fontWeight(.medium)
                Text(integration.detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(status.title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(statusColor(status))

            Button(status == .denied ? "Open Settings" : "Allow") {
                if status == .denied, let url = integration.settingsURL {
                    NSWorkspace.shared.open(url)
                } else {
                    action()
                }
            }
        }
    }

    private func statusColor(_ status: IntegrationPermissions.Status) -> Color {
        switch status {
        case .granted: .green
        case .denied: .red
        case .undetermined: .secondary
        }
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
