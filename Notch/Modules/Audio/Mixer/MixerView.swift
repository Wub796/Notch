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
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: NotchTheme.Space.s) {
                masterRow

                if mixer.isEnabled {
                    if !mixer.isSupported {
                        notice("Per-app volume needs macOS 14.2 or later. On this macOS the app's own output level can't be changed by anything but the app itself.")
                    } else if mixer.mixes.isEmpty {
                        notice("Move a slider to take over an app's audio. Nothing runs for apps you leave alone.")
                    } else {
                        ForEach(mixerAppIDs, id: \.self) { appID in
                            appRow(appID)
                        }
                    }

                    displayVolumeSection
                }

                Text(mixer.isEnabled
                     ? "Boost is up to 4x (+12 dB). Apps you don't change keep playing through the system, untouched."
                     : "The mixer is off: no app's audio is being rewritten.")
                    .font(.notchFootnote)
                    .foregroundStyle(NotchTheme.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
            }
            .padding(.bottom, 6)
            .animation(.notchSpring, value: mixer.activeAppIDs)
        }
        .notchScrollFade(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { refreshDisplayVolumes() }
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

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: NotchTheme.Space.s) {
                if let icon = app?.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 20, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                } else {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 13))
                        .foregroundStyle(NotchTheme.inkMuted)
                        .frame(width: 20, height: 20)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(app?.name ?? appID)
                        .font(.notchBody)
                        .foregroundStyle(NotchTheme.inkPrimary)
                        .lineLimit(1)
                    Text(statusLine(for: appID, mix: mix, isPlaying: app?.isPlaying ?? false))
                        .font(.notchFootnote)
                        .foregroundStyle(mixer.failures[appID] == nil ? NotchTheme.inkMuted : .orange)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Text(mix.isMuted ? "muted" : percentLabel(mix.gain))
                    .font(.notchFootnote.monospacedDigit())
                    .foregroundStyle(NotchTheme.inkSecondary)
                    .frame(width: 54, alignment: .trailing)

                RoundIconButton(
                    systemImage: mix.isMuted ? "speaker.wave.2.fill" : "speaker.slash.fill",
                    help: mix.isMuted ? "Unmute \(app?.name ?? appID)" : "Mute \(app?.name ?? appID)",
                    tint: mix.isMuted ? nil : .red
                ) {
                    mixer.toggleMute(for: appID)
                }

                RoundIconButton(
                    systemImage: "slider.vertical.3",
                    help: "Equalizer for \(app?.name ?? appID)",
                    tint: expandedEQAppID == appID ? .blue : nil
                ) {
                    withAnimation(.notchSpring) {
                        expandedEQAppID = expandedEQAppID == appID ? nil : appID
                    }
                }
            }

            if mixer.canControl(appID) || !mixer.activeAppIDs.contains(appID) {
                levelControls(appID: appID, mix: mix)
            }

            if expandedEQAppID == appID {
                EqualizerPanel(appID: appID, mix: mix, mixer: mixer)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, NotchTheme.Space.m)
        .padding(.vertical, 10)
        .notchCard(isHighlighted: mixer.isActive(appID))
    }

    /// Level, boost, routing and loudness for one app. The slider runs to 4x
    /// because that is the point of a boost: material mastered quietly, or a
    /// call recorded low, has room above unity that a 100% ceiling would deny.
    private func levelControls(appID: String, mix: MixerEngine.AppMix) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("100%")
                    .font(.notchFootnote)
                    .foregroundStyle(NotchTheme.inkMuted)

                Slider(
                    value: Binding(
                        get: { Double(mix.gain) },
                        set: { mixer.setGain(Float($0), for: appID) }
                    ),
                    in: 0...4
                )
                .tint(mix.gain > 1 ? .orange : .accentColor)

                Text("400%")
                    .font(.notchFootnote)
                    .foregroundStyle(NotchTheme.inkMuted)
            }

            HStack(spacing: NotchTheme.Space.s) {
                Menu {
                    Button("System output") { mixer.route(nil, for: appID) }
                    Divider()
                    ForEach(MixerEngine.outputDevices(), id: \.uid) { device in
                        Button(device.name) { mixer.route(device.uid, for: appID) }
                    }
                } label: {
                    chip(
                        title: routeLabel(for: mix),
                        systemImage: "hifispeaker.2.fill",
                        isActive: mix.routeDeviceUID != nil
                    )
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()

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
                }

                Spacer(minLength: 0)
            }
        }
    }

    private func statusLine(for appID: String, mix: MixerEngine.AppMix, isPlaying: Bool) -> String {
        if let failure = mixer.failures[appID] { return failure }
        if !mixer.isSupported { return "Unsupported on this macOS" }
        if mixer.mixes[appID] == nil { return isPlaying ? "Playing" : "Idle" }
        switch (mix.isMuted, mix.gain > 1) {
        case (true, _): return "Muted"
        case (_, true): return "Boosted \(percentLabel(mix.gain))"
        default: return "Set to \(percentLabel(mix.gain))"
        }
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
                        .rotationEffect(.degrees(-90))
                        .frame(width: 14, height: 66)

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
                if let profile = AutoEQLibrary.shared.importProfile(from: url) {
                    mixer.setAutoEQProfile(profile.id, for: appID)
                    importMessage = nil
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
