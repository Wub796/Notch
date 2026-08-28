import SwiftUI

/// The Settings window (⌘, from the menu bar item, or the gear in the notch).
struct SettingsView: View {
    @Bindable var settings = NotchSettings.shared

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                Toggle("Haptic feedback", isOn: $settings.hapticsEnabled)
            }

            Section("Expansion") {
                Toggle("Expand on hover", isOn: $settings.expandOnHover)
                if settings.expandOnHover {
                    LabeledContent("Open delay") {
                        Slider(value: $settings.openDelay, in: 0 ... 0.5, step: 0.05) {
                            EmptyView()
                        } minimumValueLabel: {
                            Text("0 s")
                        } maximumValueLabel: {
                            Text("0.5 s")
                        }
                        .frame(width: 200)
                    }
                    LabeledContent("Close delay") {
                        Slider(value: $settings.closeDelay, in: 0.2 ... 1.0, step: 0.05) {
                            EmptyView()
                        } minimumValueLabel: {
                            Text("0.2 s")
                        } maximumValueLabel: {
                            Text("1 s")
                        }
                        .frame(width: 200)
                    }
                } else {
                    Text("With hover expansion off, click the notch to open it.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Media") {
                Toggle("Show artwork and equalizer around the notch", isOn: $settings.showMediaWings)
                Toggle("Fetch synchronized lyrics", isOn: $settings.fetchLyrics)
                Text("Lyrics are looked up on lrclib.net using the track title and artist.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Shelf") {
                Toggle("AirDrop dropped files immediately", isOn: $settings.instantAirDrop)
                Text(settings.instantAirDrop
                    ? "Files dropped on the notch go straight to AirDrop."
                    : "Files dropped on the notch are kept on the shelf until you send or clear them.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("System monitor") {
                Picker("Refresh every", selection: $settings.telemetryInterval) {
                    Text("1 second").tag(1.0)
                    Text("2 seconds").tag(2.0)
                    Text("5 seconds").tag(5.0)
                }
                Text("Sampling only runs while the notch is open — the collapsed notch uses no CPU.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 540)
    }
}
