import AppKit
import CoreAudio
import SwiftUI

/// Which output surface the audio screen is showing.
///
/// Declared alongside the view but outside it, so `NotchState` can hold the
/// selection without depending on a view type — a compile error anywhere in
/// the view would otherwise take the whole state object down with it.
enum AudioScreenTab: String, CaseIterable, Identifiable {
    /// Processes making sound on this Mac (Chrome, Safari, Spotify, Music, YouTube, etc.).
    case apps
    /// Every local CoreAudio output.
    case system
    /// Local outputs CoreAudio reports as AirPlay.
    case airplay
    /// Spotify Connect: the account's own devices, over the Web API.
    case spotify

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apps: "Apps & Web"
        case .system: "System"
        case .airplay: "AirPlay"
        case .spotify: "Spotify"
        }
    }

    var symbol: String {
        switch self {
        case .apps: "waveform"
        case .system: "speaker.wave.2.fill"
        case .airplay: "airplayaudio"
        case .spotify: "music.note"
        }
    }
}

/// The Audio screen's body: whichever of the four output surfaces is
/// selected. The switch itself lives in `DevicesScreenView`, alongside the
/// section pills, because the reference draws both in one capsule.
///
/// Every tab reports real state, from two different places. Spotify is the
/// account's Connect devices over the Web API — remote, and controllable
/// wherever they are. AirPlay and System are this Mac's own CoreAudio
/// outputs, fully interactive. Apps lists every process CoreAudio says is
/// running output — any device audio, not just the now-playing app — but its
/// level is read-only: macOS exposes observing a process's audio, never
/// setting its volume. Sapphire ships an audio HAL plug-in for that; drawing
/// a slider that moves and changes nothing would be worse than saying so.
struct AudioDevicesView: View {
    let state: NotchState

    private var activeAudioApp: AudioAppMonitor.App? {
        state.audioApps.apps.first(where: \.isPlaying)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: NotchTheme.Space.s) {
                meterFailureNotice

                nowPlayingBanner

                switch state.audioTab {
                case .apps: appRows
                case .system: deviceRows
                case .airplay: airplayRows
                case .spotify: spotifyRows
                }
            }
            .padding(.bottom, 2)
            // Rows arrive and leave as an app starts or stops making sound,
            // which now happens the instant CoreAudio says so — so they slide
            // rather than appear.
            .animation(.notchSpring, value: state.audioApps.apps)
            .animation(.notchSpring, value: state.audio.devices)
            .animation(.notchSpring, value: spotify.devices)
        }
        .notchScrollFade(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { state.audio.refresh() }
        // Apps needs no timer at all any more: `AudioAppMonitor` listens to
        // CoreAudio and the list is already current when this appears. A
        // Connect device waking on the other side of the house is the one
        // thing nothing pushes, so that tab — and only that tab — asks.
        .task(id: state.audioTab) {
            guard state.audioTab == .spotify else { return }
            while !Task.isCancelled {
                spotify.refreshDevices()
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }

    /// The real-time meter is opt-in and can fail for reasons the user can
    /// fix — the permission was revoked, or there is no display to capture.
    /// It used to fail silently, leaving the visualiser quietly back on its
    /// fallback with nothing to say why.
    @ViewBuilder
    private var meterFailureNotice: some View {
        if state.settings.realtimeAudioMeter, let reason = state.audioMeter.failureReason {
            HStack(spacing: NotchTheme.Space.s) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.orange)

                Text(reason)
                    .font(.notchCaption)
                    .foregroundStyle(NotchTheme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: NotchTheme.Space.s)

                Button("Open Settings") {
                    let path = "x-apple.systempreferences:com.apple.preference"
                        + ".security?Privacy_ScreenCapture"
                    if let url = URL(string: path) {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(PressableButtonStyle())
                .font(.notchCaption.weight(.bold))
                .foregroundStyle(NotchTheme.inkPrimary)
                .fixedSize()
            }
            .padding(.horizontal, NotchTheme.Space.m)
            .padding(.vertical, 10)
            .notchCard(radius: NotchTheme.Radius.tile, isHighlighted: true, tint: .orange)
            .transition(.opacity)
        }
    }

    private var spotify: SpotifyLibrary { state.spotify }

    @ViewBuilder
    private var nowPlayingBanner: some View {
        if state.media.isPlaying || activeAudioApp != nil {
            let title = !(state.media.track?.title.isEmpty ?? true) ? (state.media.track?.title ?? "Playing") : (activeAudioApp?.name ?? "Playing Audio")
            let artist = !(state.media.track?.artist.isEmpty ?? true) ? (state.media.track?.artist ?? "Active Media") : "Playing in \(activeAudioApp?.name ?? "Browser")"

            HStack(spacing: 12) {
                // Video thumbnail / Album art / App icon
                Group {
                    if let artwork = state.media.artwork {
                        Image(nsImage: artwork)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else if let icon = state.media.sourceAppIcon ?? activeAudioApp?.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(8)
                            .background(Color.white.opacity(0.08))
                    } else {
                        Image(systemName: "music.note")
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.notchBody.weight(.bold))
                            .foregroundStyle(NotchTheme.inkPrimary)
                            .lineLimit(1)

                        Image(systemName: "waveform")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.green)
                            .symbolEffect(.variableColor.iterative, options: .repeating)
                    }

                    Text(artist)
                        .font(.notchCaption)
                        .foregroundStyle(NotchTheme.inkSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                // Quick transport / Focus buttons
                HStack(spacing: 8) {
                    if let active = activeAudioApp {
                        RoundIconButton(
                            systemImage: "arrow.up.forward.app.fill",
                            help: "Bring \(active.name) to the front"
                        ) {
                            active.activate()
                        }
                    }

                    RoundIconButton(
                        systemImage: state.media.isPlaying ? "play.fill" : "pause.fill",
                        help: state.media.isPlaying ? "Play" : "Pause"
                    ) {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
                            state.media.togglePlayPause()
                        }
                    }
                }
            }
            .padding(10)
            .notchCard(radius: NotchTheme.Radius.tile, isHighlighted: true, tint: .green)
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    // MARK: - Spotify Connect

    @ViewBuilder
    private var spotifyRows: some View {
        if !spotify.isConnected {
            SpotifyConnectPrompt(
                message: "Connect Spotify to see and control the devices on your account."
            )
        } else if spotify.devices.isEmpty {
            emptyRow(spotify.isLoadingDevices
                     ? "Looking for devices…"
                     : "No Spotify devices are available. Open Spotify somewhere first.")
        } else {
            ForEach(spotify.devices) { device in
                SpotifyDeviceCard(
                    device: device,
                    onSelect: { spotify.transfer(to: device) },
                    onVolume: { spotify.setVolume($0, for: device) }
                )
            }

            if let error = spotify.lastError {
                Text(error)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - AirPlay

    /// Local AirPlay outputs, which is what CoreAudio calls an Apple TV or a
    /// HomePod once macOS has one selected. Spotify's own Connect speakers
    /// live on the Spotify tab — they are a different transport, and merging
    /// the two lists would make it impossible to tell which one a row means.
    @ViewBuilder
    private var airplayRows: some View {
        let outputs = state.audio.devices.filter {
            $0.transport == kAudioDeviceTransportTypeAirPlay
        }

        if outputs.isEmpty {
            emptyRow("No AirPlay outputs are connected")
        } else {
            ForEach(outputs) { device in
                let isCurrent = device.id == state.audio.currentDeviceID
                AudioRow(
                    icon: .symbol("airplayaudio"),
                    title: device.name,
                    status: isCurrent ? (state.audio.isMuted ? "Muted" : "Output") : nil,
                    statusIsLive: isCurrent && !state.audio.isMuted,
                    level: isCurrent ? Double(state.audio.volume) : nil,
                    isHighlighted: isCurrent,
                    onLevelChange: isCurrent ? { state.audio.setVolume(Float($0)) } : nil,
                    onSelect: { state.audio.select(device) }
                ) {
                    RoundIconButton(
                        systemImage: state.audio.isMuted
                            ? "speaker.slash.fill"
                            : "speaker.wave.2.fill",
                        help: state.audio.isMuted ? "Unmute" : "Mute",
                        isEnabled: isCurrent
                    ) {
                        state.audio.toggleMute()
                    }
                }
            }
        }
    }

    // MARK: - Devices

    @ViewBuilder
    private var deviceRows: some View {
        if state.audio.devices.isEmpty {
            emptyRow("No output devices")
        } else {
            ForEach(state.audio.devices) { device in
                let isCurrent = device.id == state.audio.currentDeviceID
                AudioRow(
                    icon: .symbol(device.symbolName),
                    title: device.name,
                    status: isCurrent ? (state.audio.isMuted ? "Muted" : "Output") : nil,
                    statusIsLive: isCurrent && !state.audio.isMuted,
                    level: isCurrent ? Double(state.audio.volume) : nil,
                    isHighlighted: isCurrent,
                    onLevelChange: isCurrent
                        ? { state.audio.setVolume(Float($0)) }
                        : nil,
                    onSelect: { state.audio.select(device) }
                ) {
                    RoundIconButton(
                        systemImage: state.audio.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                        help: state.audio.isMuted ? "Unmute" : "Mute",
                        isEnabled: isCurrent
                    ) {
                        state.audio.toggleMute()
                    }
                    RoundIconButton(
                        systemImage: "slider.horizontal.3",
                        help: "Sound settings"
                    ) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    RoundIconButton(
                        systemImage: "arrow.counterclockwise",
                        help: "Reset to full volume",
                        tint: .red,
                        isEnabled: isCurrent
                    ) {
                        state.audio.setVolume(1)
                    }
                }
            }
        }
    }

    // MARK: - Apps

    @ViewBuilder
    private var appRows: some View {
        if state.audioApps.apps.isEmpty {
            emptyRow("No apps are using audio")
        } else {
            ForEach(state.audioApps.apps) { app in
                AudioRow(
                    icon: .image(app.icon),
                    title: app.name,
                    status: app.isPlaying ? "Playing" : "Idle",
                    statusIsLive: app.isPlaying,
                    // Read-only: this is the system level the app plays
                    // through, because macOS exposes no per-process volume.
                    level: Double(state.audio.volume),
                    isHighlighted: app.isPlaying,
                    onLevelChange: nil,
                    onSelect: { app.activate() }
                ) {
                    RoundIconButton(
                        systemImage: app.isPlaying ? "play.fill" : "pause.fill",
                        help: app.isPlaying ? "Play audio/video" : "Pause audio/video"
                    ) {
                        state.media.togglePlayPause()
                    }
                    RoundIconButton(
                        systemImage: "arrow.up.forward.app.fill",
                        help: "Bring \(app.name) to the front"
                    ) {
                        app.activate()
                    }
                    RoundIconButton(
                        systemImage: "speaker.slash.fill",
                        help: "Mute all output",
                        tint: .red
                    ) {
                        state.audio.toggleMute()
                    }
                }
            }

            Text(state.audioApps.canObserveProcesses
                 ? "Playing is read from CoreAudio, so this covers any app "
                    + "making sound. The level is the system output — macOS "
                    + "has no per-application volume without an audio driver."
                 : "macOS 14.4 or later is needed to tell which apps are "
                    + "actually making sound; this lists media apps that are "
                    + "running.")
                .font(.notchFootnote)
                .foregroundStyle(NotchTheme.inkMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
        }
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(.notchBody)
            .foregroundStyle(NotchTheme.inkMuted)
            .frame(maxWidth: .infinity, minHeight: 64)
            .notchCard()
    }
}

/// One row of the audio list.
struct AudioRow<Actions: View>: View {
    enum Icon {
        case symbol(String)
        case image(NSImage?)
    }

    let icon: Icon
    let title: String
    let status: String?
    let statusIsLive: Bool
    /// nil draws no bar at all, for a device that is not the current output.
    let level: Double?
    let isHighlighted: Bool
    /// nil makes the bar read-only.
    let onLevelChange: ((Double) -> Void)?
    let onSelect: () -> Void
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onSelect) {
                HStack(spacing: 10) {
                    iconView
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(NotchTheme.surfaceHover))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 0) {
                        Text(title)
                            .font(.notchBody.weight(.bold))
                            .foregroundStyle(NotchTheme.inkPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if let status {
                            HStack(spacing: 5) {
                                Text(status)
                                    .font(.notchFootnote.weight(.bold))
                                    .foregroundStyle(statusIsLive ? .green : NotchTheme.inkMuted)

                                // A glyph that is actually moving while the
                                // row is live, so "Playing" is something you
                                // see rather than something you read.
                                if statusIsLive {
                                    Image(systemName: "waveform")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.green)
                                        .symbolEffect(
                                            .variableColor.iterative,
                                            options: .repeating
                                        )
                                        .transition(.opacity)
                                }
                            }
                        }
                    }
                    .frame(width: 110, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())

            if let level {
                LevelBar(
                    level: level,
                    isEditable: onLevelChange != nil,
                    onChange: onLevelChange
                )
            } else {
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                actions()
            }
        }
        .padding(.horizontal, NotchTheme.Space.m)
        .padding(.vertical, 10)
        .notchCard(isHighlighted: isHighlighted)
        .transition(
            .asymmetric(
                insertion: .scale(scale: 0.97).combined(with: .opacity),
                removal: .opacity
            )
        )
        .animation(.notchSpring, value: isHighlighted)
    }

    @ViewBuilder
    private var iconView: some View {
        switch icon {
        case let .symbol(name):
            Image(systemName: name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NotchTheme.inkPrimary)
        case let .image(image):
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(4)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NotchTheme.inkSecondary)
            }
        }
    }
}

/// The reference's wide filled bar with its label inside and the percentage on
/// the right, rather than a hairline track.
private struct LevelBar: View {
    let level: Double
    let isEditable: Bool
    let onChange: ((Double) -> Void)?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(NotchTheme.surfaceHover)

                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor)
                    .frame(width: max(0, min(geometry.size.width * level, geometry.size.width)))

                HStack {
                    Text("Volume")
                        .font(.notchCallout.weight(.bold))
                    Spacer(minLength: 8)
                    Text("\(Int((level * 100).rounded()))%")
                        .font(.notchCallout.weight(.bold).monospacedDigit())
                        .contentTransition(.numericText())
                }
                .foregroundStyle(NotchTheme.inkPrimary)
                .padding(.horizontal, 12)
            }
            .contentShape(Rectangle())
            .gesture(
                isEditable
                    ? DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard geometry.size.width > 0 else { return }
                            onChange?(min(max(value.location.x / geometry.size.width, 0), 1))
                        }
                    : nil
            )
        }
        .frame(height: 34)
        .frame(maxWidth: .infinity)
        .opacity(isEditable ? 1 : 0.7)
        .accessibilityElement()
        .accessibilityLabel("Volume")
        .accessibilityValue("\(Int((level * 100).rounded())) percent")
    }
}

/// A circular icon button, as in the reference's trailing cluster.
struct RoundIconButton: View {
    let systemImage: String
    let help: String
    var tint: Color?
    var isEnabled: Bool = true
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint ?? NotchTheme.inkPrimary)
                .frame(width: 30, height: 30)
                .background(
                    Circle().fill(
                        (tint ?? .white).opacity(isHovering ? 0.22 : 0.12)
                    )
                )
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .contentTransition(.symbolEffect(.replace))
        .onHover { hovering in
            withAnimation(NotchAnimations.content) { isHovering = hovering }
        }
        .help(help)
        .accessibilityLabel(help)
    }
}
