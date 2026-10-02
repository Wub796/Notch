import AppKit
import CoreAudio
import SwiftUI
import UniformTypeIdentifiers

/// The Mixer surface: every app's audio, with the controls that rewrite it.
///
/// The Audio screen's "Apps & Web" list answers "who is making sound"; this
/// answers "how loud, out of what, and shaped how". Rows are built from the same
/// pieces as the rest of the audio screen so the two read as one surface, and
/// the deep controls (boost past 100%, routing, EQ, loudness) live only here —
/// the app list stays a list of levels.
struct MixerView: View {
    let state: NotchState

    @State private var expandedEQAppID: String?
    @State private var displayVolumes: [CGDirectDisplayID: Double] = [:]

    private var mixer: MixerEngine { state.mixer }

    var body: some View {
        VStack(alignment: .leading, spacing: NotchTheme.Space.s) {
            masterRow

            if !mixer.isSupported {
                notice("Per-app mixing needs macOS 14.2 or later. The apps are shown below, but their audio cannot be changed on this macOS.")
            } else if !state.audioApps.canObserveProcesses {
                notice("This macOS can create mixer taps, but app audio processes are only available from macOS 14.4. Per-app controls are unavailable here.")
            }

            sectionLabel("Apps")
            if mixerAppIDs.isEmpty {
                emptyAppsRow
            } else {
                VStack(spacing: NotchTheme.Space.s) {
                    ForEach(mixerAppIDs, id: \.self) { appID in
                        appRow(appID)
                    }
                }
            }

            displayVolumeSection

            Text(!mixer.isEnabled
                 ? "Mixer is off. Turn it on above to apply per-app volume, mute, routing, and EQ."
                 : !state.audioApps.canObserveProcesses
                 ? "App audio processes can't be identified on this macOS, so per-app controls are unavailable."
                 : "Set app levels ahead of time; mixing starts when they play. Untouched apps keep the normal system audio path.")
                .font(.notchFootnote)
                .foregroundStyle(NotchTheme.inkMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
        }
        .padding(.bottom, 6)
        .animation(.notchSpring, value: mixer.activeAppIDs)
        .animation(.notchSpring, value: mixerAppIDs)
        .onAppear {
            refreshDisplayVolumes()
        }
    }

    private var emptyAppsRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No apps playing audio")
                .font(.notchBody.weight(.semibold))
                .foregroundStyle(NotchTheme.inkPrimary)
            Text("Start music, a video, or a call. Active apps appear here automatically.")
                .font(.notchFootnote)
                .foregroundStyle(NotchTheme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, NotchTheme.Space.m)
        .padding(.vertical, 12)
        .notchCard()
    }

    /// Every app with settings, plus the ones making sound right now — the
    /// second half is what makes the list usable before anything has been
    /// changed, and it is why this is computed from both sides.
    private var mixerAppIDs: [String] {
        var ids = Set(mixer.mixes.keys)
        ids.formUnion(state.audioApps.apps.map(\.id))
        return ids.sorted { lhs, rhs in
            let lhsPlaying = isPlaying(lhs)
            let rhsPlaying = isPlaying(rhs)
            if lhsPlaying != rhsPlaying { return lhsPlaying }
            return displayName(for: lhs).localizedCaseInsensitiveCompare(displayName(for: rhs)) == .orderedAscending
        }
    }

    private func isPlaying(_ appID: String) -> Bool {
        state.audioApps.apps.first { $0.id == appID }?.isPlaying ?? false
    }

    private func displayName(for appID: String) -> String {
        state.audioApps.apps.first { $0.id == appID }?.name ?? appID
    }

    // MARK: - Master

    private var masterRow: some View {
        HStack(spacing: NotchTheme.Space.s) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(NotchTheme.inkSecondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text("Mixer")
                    .font(.notchBody)
                    .foregroundStyle(NotchTheme.inkPrimary)
                Text(mixer.isEnabled
                     ? "Rewriting \(mixer.activeAppIDs.count) app\(mixer.activeAppIDs.count == 1 ? "" : "s")"
                     : "Off")
                    .font(.notchFootnote)
                    .foregroundStyle(NotchTheme.inkMuted)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: Binding(
                get: { mixer.isEnabled },
                set: { mixer.isEnabled = $0 }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)
        }
        .padding(.horizontal, NotchTheme.Space.m)
        .padding(.vertical, 9)
        .notchCard(isHighlighted: mixer.isEnabled)
    }

    // MARK: - One app

    @ViewBuilder
    private func appRow(_ appID: String) -> some View {
        let mix = mixer.mix(for: appID)
        let app = state.audioApps.apps.first { $0.id == appID }
        let appName = app?.name ?? appID
        let canAdjust = canAdjustApp(appID, app: app)

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if let icon = app?.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 26, height: 26)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(NotchTheme.inkMuted)
                        .frame(width: 26, height: 26)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(appName)
                        .font(.notchBody.weight(.semibold))
                        .foregroundStyle(NotchTheme.inkPrimary)
                        .lineLimit(1)
                    Text(statusLine(for: appID, mix: mix, app: app))
                        .font(.notchFootnote)
                        .foregroundStyle(statusTint(for: appID, app: app))
                        .lineLimit(1)
                }
                .frame(minWidth: 90, maxWidth: 170, alignment: .leading)

                RoundIconButton(
                    systemImage: mix.isMuted ? "speaker.wave.2.fill" : "speaker.slash.fill",
                    help: mix.isMuted ? "Unmute \(appName)" : "Mute \(appName)",
                    tint: mix.isMuted ? nil : .red,
                    isEnabled: canAdjust
                ) {
                    mixer.toggleMute(for: appID)
                }

                Slider(
                    value: Binding(
                        get: { Double(mix.gain) },
                        set: { mixer.setGain(Float($0), for: appID) }
                    ),
                    in: 0...4
                )
                .tint(mix.gain > 1 ? .orange : .accentColor)
                .disabled(!canAdjust)
                .accessibilityLabel("\(appName) volume")
                .frame(minWidth: 110, maxWidth: 230)

                Text(mix.isMuted ? "Muted" : percentLabel(mix.gain))
                    .font(.notchFootnote.monospacedDigit())
                    .foregroundStyle(NotchTheme.inkSecondary)
                    .frame(width: 52, alignment: .trailing)

                Menu {
                    Button("System output") { mixer.route(nil, for: appID) }
                    Divider()
                    ForEach(MixerEngine.outputDevices(), id: \.uid) { device in
                        Button(device.name) { mixer.route(device.uid, for: appID) }
                    }
                } label: {
                    Image(systemName: "hifispeaker.2.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(mix.routeDeviceUID == nil ? NotchTheme.inkSecondary : .accentColor)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(NotchTheme.surfaceHover))
                        .contentShape(Circle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .disabled(!canAdjust)
                .help("Route \(appName) audio: \(routeLabel(for: mix))")

                RoundIconButton(
                    systemImage: "slider.vertical.3",
                    help: expandedEQAppID == appID ? "Close EQ for \(appName)" : "Equalizer for \(appName)",
                    tint: expandedEQAppID == appID ? .blue : nil,
                    isEnabled: canAdjust
                ) {
                    withAnimation(.notchSpring) {
                        expandedEQAppID = expandedEQAppID == appID ? nil : appID
                    }
                }
            }

            HStack(spacing: NotchTheme.Space.s) {
                Button {
                    mixer.setLoudnessCompensation(!mix.loudnessCompensation, for: appID)
                } label: {
                    chip(
                        title: "Loudness",
                        systemImage: "waveform.path.ecg",
                        isActive: mix.loudnessCompensation
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canAdjust)

                if mixer.mixes[appID] != nil {
                    Button {
                        withAnimation(.notchSpring) {
                            expandedEQAppID = nil
                            mixer.reset(appID)
                        }
                    } label: {
                        chip(title: "Reset", systemImage: "arrow.uturn.backward", isActive: false)
                    }
                    .buttonStyle(.plain)
                    .disabled(!mixer.isEnabled)
                }

                Spacer(minLength: 0)
            }
            .padding(.leading, 34)

            if expandedEQAppID == appID {
                EqualizerPanel(appID: appID, mix: mix, mixer: mixer)
                    .disabled(!canAdjust)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, NotchTheme.Space.m)
        .padding(.vertical, 8)
        .notchCard(isHighlighted: app?.isPlaying == true || mixer.isActive(appID))
        .accessibilityElement(children: .contain)
    }

    /// Settings can be prepared for an inactive app, but an active process
    /// needs a real CoreAudio handle before its controls are enabled.
    private func canAdjustApp(_ appID: String, app: AudioAppMonitor.App?) -> Bool {
        guard mixer.isEnabled, mixer.isSupported, state.audioApps.canObserveProcesses else { return false }
        guard app?.isPlaying == true else { return true }
        return mixer.canControl(appID)
    }

    private func statusLine(for appID: String, mix: MixerEngine.AppMix, app: AudioAppMonitor.App?) -> String {
        if !mixer.isSupported { return "Needs macOS 14.2 or later" }
        if !mixer.isEnabled { return "Mixer off" }
        if !state.audioApps.canObserveProcesses { return "App mixing needs macOS 14.4 or later" }
        if let failure = mixer.failures[appID] { return failure }
        if app?.isPlaying == true && !mixer.canControl(appID) {
            return "Audio process is unavailable to mix"
        }
        if mixer.mixes[appID] == nil { return app?.isPlaying == true ? "Playing" : "Idle" }
        switch (mix.isMuted, mix.gain > 1) {
        case (true, _): return "Muted"
        case (_, true): return "Boosted \(percentLabel(mix.gain))"
        default: return "Set to \(percentLabel(mix.gain))"
        }
    }

    private func statusTint(for appID: String, app: AudioAppMonitor.App?) -> Color {
        if !mixer.isEnabled { return NotchTheme.inkMuted }
        if mixer.failures[appID] != nil || !mixer.isSupported
            || !state.audioApps.canObserveProcesses
            || (app?.isPlaying == true && !mixer.canControl(appID)) {
            return .orange
        }
        return app?.isPlaying == true ? .green : NotchTheme.inkMuted
    }

    private func routeLabel(for mix: MixerEngine.AppMix) -> String {
        guard let uid = mix.routeDeviceUID,
              let device = MixerEngine.outputDevices().first(where: { $0.uid == uid })
        else { return "Output" }
        return device.name
    }

    private func percentLabel(_ gain: Float) -> String {
        "\(Int((gain * 100).rounded()))%"
    }

    // MARK: - Display volume

    /// Speakers inside an external display, which no audio device slider can
    /// reach: they are set over the display's own control channel.
    @ViewBuilder
    private var displayVolumeSection: some View {
        let displays = DisplayVolumeController.shared.controllableDisplays()
        if !displays.isEmpty {
            VStack(alignment: .leading, spacing: NotchTheme.Space.s) {
                sectionLabel("Display speakers")

                ForEach(displays) { display in
                    HStack(spacing: NotchTheme.Space.s) {
                        Image(systemName: "display")
                            .font(.system(size: 13))
                            .foregroundStyle(NotchTheme.inkSecondary)
                            .frame(width: 18)

                        Text(display.name)
                            .font(.notchBody)
                            .foregroundStyle(NotchTheme.inkPrimary)
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        Slider(
                            value: Binding(
                                get: { displayVolumes[display.id] ?? Double(DisplayVolumeController.shared.volume(for: display.id) ?? 0.5) },
                                set: { newValue in
                                    displayVolumes[display.id] = newValue
                                    DisplayVolumeController.shared.setVolume(Float(newValue), for: display.id)
                                }
                            ),
                            in: 0...1
                        )
                        .frame(width: 150)
                    }
                    .padding(.horizontal, NotchTheme.Space.m)
                    .padding(.vertical, 9)
                    .notchTile()
                }
            }
        }
    }

    private func refreshDisplayVolumes() {
        for display in DisplayVolumeController.shared.controllableDisplays() {
            if let volume = DisplayVolumeController.shared.volume(for: display.id) {
                displayVolumes[display.id] = Double(volume)
            }
        }
    }

    // MARK: - Pieces

    private func notice(_ text: String) -> some View {
        Text(text)
            .font(.notchFootnote)
            .foregroundStyle(NotchTheme.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, NotchTheme.Space.m)
            .padding(.vertical, 10)
            .notchTile()
    }

    /// The same marker the Audio screen uses for its own sections, so the mixer
    /// reads as part of that surface rather than a panel bolted onto it.
    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.notchEyebrow)
            .tracking(0.8)
            .foregroundStyle(NotchTheme.inkMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.top, 2)
    }

    private func chip(title: String, systemImage: String, isActive: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
            Text(title)
                .font(.notchFootnote)
                .lineLimit(1)
        }
        .foregroundStyle(isActive ? NotchTheme.inkPrimary : NotchTheme.inkSecondary)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(isActive ? Color.accentColor.opacity(0.22) : NotchTheme.surfaceHover))
        .contentShape(Capsule())
    }
}

/// The equalizer for one app: a ten band graphic curve, the presets, and the
/// imported headphone corrections.
private struct EqualizerPanel: View {
    let appID: String
    let mix: MixerEngine.AppMix
    let mixer: MixerEngine

    @State private var isImportingProfile = false
    @State private var importMessage: String?

    private var bands: [EQBand] {
        if let custom = mix.equalizerBands, mix.equalizerPresetID == EqualizerPreset.customID {
            return custom
        }
        if let preset = EqualizerPreset.preset(for: mix.equalizerPresetID) {
            return preset.bands
        }
        // A parametric curve (an AutoEQ profile's own shape, or a preset that
        // is not one of the graphic ones) is drawn on the same ten sliders.
        let gains = EqualizerPreset.graphicGains(from: mix.equalizerBands ?? [])
        return EqualizerPreset.graphicGains(gains)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(EqualizerPreset.builtIns) { preset in
                        Button(preset.title) {
                            mixer.setEqualizer(preset.id, bands: nil, for: appID)
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(currentPresetTitle)
                            .font(.notchFootnote)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(NotchTheme.inkPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(NotchTheme.surfaceHover))
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()

                Menu {
                    Button("No correction") { mixer.setAutoEQProfile(nil, for: appID) }
                    Divider()
                    ForEach(AutoEQLibrary.shared.profiles) { profile in
                        Button(profile.name) { mixer.setAutoEQProfile(profile.id, for: appID) }
                    }
                    Divider()
                    Button("Import from file…") { isImportingProfile = true }
                } label: {
                    chip(
                        title: autoEQTitle,
                        systemImage: "headphones",
                        isActive: mix.autoEQProfileID != nil
                    )
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()

                Spacer(minLength: 0)

                Button("Flat") {
                    mixer.setEqualizer(EqualizerPreset.flat.id, bands: nil, for: appID)
                }
                .buttonStyle(.plain)
                .font(.notchFootnote)
                .foregroundStyle(NotchTheme.inkSecondary)
            }

            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(bands.enumerated()), id: \.offset) { index, band in
                    VStack(spacing: 4) {
                        Slider(
                            value: Binding(
                                get: { Double(band.gain) },
                                set: { newValue in
                                    var updated = bands
                                    updated[index].gain = Float(newValue)
                                    mixer.setEqualizer(EqualizerPreset.customID, bands: updated, for: appID)
                                }
                            ),
                            in: -12...12
                        )
                        // Give the native horizontal slider its full track width
                        // before rotating it. Framing to 14pt before rotation
                        // squeezed the actual control to a tiny hotspot while its
                        // transformed drawing overflowed into neighboring bands.
                        .frame(width: 66)
                        .rotationEffect(.degrees(-90))
                        .frame(width: 14, height: 66)
                        .accessibilityLabel("\(frequencyLabel(band.frequency)) Hz equalizer band")
                        .accessibilityValue(String(format: "%+.1f dB", band.gain))

                        Text(frequencyLabel(band.frequency))
                            .font(.system(size: 9))
                            .foregroundStyle(NotchTheme.inkMuted)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let importMessage {
                Text(importMessage)
                    .font(.notchFootnote)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 4)
        .padding(.leading, 26)
        .fileImporter(isPresented: $isImportingProfile, allowedContentTypes: [.plainText, .text]) { result in
            switch result {
            case .success(let url):
                importMessage = nil
                if let profile = AutoEQLibrary.shared.importProfile(from: url) {
                    mixer.setAutoEQProfile(profile.id, for: appID)
                } else {
                    importMessage = AutoEQLibrary.shared.lastImportFailure
                }
            case .failure(let error):
                importMessage = error.localizedDescription
            }
        }
    }

    private var currentPresetTitle: String {
        if mix.equalizerPresetID == EqualizerPreset.customID { return "Custom" }
        return EqualizerPreset.preset(for: mix.equalizerPresetID)?.title ?? "Flat"
    }

    private var autoEQTitle: String {
        guard let id = mix.autoEQProfileID, let profile = AutoEQLibrary.shared.profile(id: id) else {
            return "AutoEQ"
        }
        return profile.name
    }

    private func frequencyLabel(_ frequency: Double) -> String {
        frequency >= 1_000 ? "\(Int(frequency / 1_000))k" : "\(Int(frequency))"
    }

    private func chip(title: String, systemImage: String, isActive: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
            Text(title)
                .font(.notchFootnote)
                .lineLimit(1)
        }
        .foregroundStyle(isActive ? NotchTheme.inkPrimary : NotchTheme.inkSecondary)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(isActive ? Color.accentColor.opacity(0.22) : NotchTheme.surfaceHover))
        .contentShape(Capsule())
    }
}
