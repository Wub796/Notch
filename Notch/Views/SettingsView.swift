import AppKit
import SwiftUI

/// The Settings window (⌘, from the menu bar item, or the gear in the notch):
/// native macOS preferences style — one tab per concern, grouped forms with
/// explanatory footers.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsPane()
                .tabItem { Label("General", systemImage: "gearshape") }
            NotchSettingsPane()
                .tabItem { Label("Notch", systemImage: "sparkles.rectangle.stack") }
            MediaSettingsPane()
                .tabItem { Label("Media", systemImage: "music.note") }
            ActivitiesSettingsPane()
                .tabItem { Label("Activities", systemImage: "bolt.badge.clock") }
            SystemSettingsPane()
                .tabItem { Label("System", systemImage: "gauge.with.dots.needle.50percent") }
            AboutSettingsPane()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 560, height: 470)
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
            } footer: {
                Text("Haptics play on the trackpad when the notch opens, closes, or receives a drop.")
            }

            Section("Animation") {
                Picker("Animation style", selection: $settings.animationProfile) {
                    ForEach(AnimationProfile.allCases) { profile in
                        Text(profile.title).tag(profile.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                Text("Snappy is quick with a little spring, Bouncy overshoots playfully, Calm glides. The system Reduce Motion setting overrides all three.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Notch behavior

private struct NotchSettingsPane: View {
    @Bindable var settings = NotchSettings.shared

    var body: some View {
        Form {
            Section {
                Toggle("Expand on hover", isOn: $settings.expandOnHover)
                Toggle("Scroll on the notch to open it", isOn: $settings.scrollToExpand)
            } footer: {
                Text("Hovering always makes the notch peek. A click opens it fully; with hover expansion on, lingering does too.")
            }

            if settings.expandOnHover {
                Section("Timing") {
                    delaySlider(
                        "Open delay",
                        value: $settings.openDelay,
                        range: 0 ... 0.5
                    )
                    delaySlider(
                        "Close delay",
                        value: $settings.closeDelay,
                        range: 0.2 ... 1.0
                    )
                }
            }

            Section {
                Toggle("Idle face", isOn: $settings.showIdleFace)
            } footer: {
                Text("A tiny blinking companion in the notch wing when nothing else is happening.")
            }
        }
        .formStyle(.grouped)
    }

    private func delaySlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        LabeledContent {
            HStack(spacing: 10) {
                Slider(value: value, in: range, step: 0.05)
                    .frame(width: 180)
                Text(String(format: "%.2f s", value.wrappedValue))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .trailing)
            }
        } label: {
            Text(title)
        }
    }
}

// MARK: - Media

private struct MediaSettingsPane: View {
    @Bindable var settings = NotchSettings.shared

    var body: some View {
        Form {
            Section("Collapsed notch") {
                Toggle("Artwork and equalizer while playing", isOn: $settings.showMediaWings)
                Toggle("Announce new tracks", isOn: $settings.sneakPeekEnabled)
                Text("New tracks scroll their title and artist through the notch for a few seconds, even while it's closed.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Fetch synchronized lyrics", isOn: $settings.fetchLyrics)
            } footer: {
                Text("Lyrics are looked up on lrclib.net using the track title and artist. Tap a line to jump playback there.")
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
                Toggle("Battery, lock, and meeting alerts", isOn: $settings.liveActivitiesEnabled)
                Toggle("Volume changes", isOn: $settings.volumeHUDEnabled)
                Toggle("Weather in the header", isOn: $settings.showWeather)
            } header: {
                Text("Live activities")
            } footer: {
                Text("All sources are event-driven — nothing polls in the background. Weather uses your approximate location via Open-Meteo. Monitor changes apply on next launch.")
            }

            Section {
                Toggle("AirDrop dropped files immediately", isOn: $settings.instantAirDrop)
            } header: {
                Text("Shelf")
            } footer: {
                Text(settings.instantAirDrop
                    ? "Files dropped on the notch go straight to AirDrop."
                    : "Files dropped on the notch stay on the shelf: drag them out, AirDrop them, or double-click to open.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - System

private struct SystemSettingsPane: View {
    @Bindable var settings = NotchSettings.shared

    var body: some View {
        Form {
            Section {
                Picker("Refresh every", selection: $settings.telemetryInterval) {
                    Text("1 second").tag(1.0)
                    Text("2 seconds").tag(2.0)
                    Text("5 seconds").tag(5.0)
                }
            } header: {
                Text("System monitor")
            } footer: {
                Text("CPU, memory, battery, and network sampling only runs while the notch is open — the collapsed notch uses no CPU.")
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
