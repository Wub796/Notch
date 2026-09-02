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
/// running output and exposes each process's independent volume level.
struct AudioDevicesView: View {
    let state: NotchState

    private var activeAudioApp: AudioAppMonitor.App? {
        state.audioApps.apps.first(where: \.isPlaying)
    }

    @State private var appVolumes: [String: Float] = [:]
    @State private var mutedApps: Set<String> = []
    @State private var priorVolumeBeforeMute: [String: Float] = [:]
    @State private var pairedBluetoothDevices: [BluetoothAudioDevices.PairedDevice] = []

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

                inputSection

                bluetoothSection
            }
            .padding(.bottom, 6)
            // Rows arrive and leave as an app starts or stops making sound,
            // which now happens the instant CoreAudio says so — so they slide
            // rather than appear.
            .animation(.notchSpring, value: state.audioApps.apps)
            .animation(.notchSpring, value: state.audio.devices)
            .animation(.notchSpring, value: spotify.devices)
        }
        .notchScrollFade(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            state.audio.refresh()
            state.audioInput.refresh()
            refreshPairedBluetooth()
        }
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

    /// The data-only meter has no permission-gated failure path; retain this
    /// hook for compatibility with the shared layout.
    @ViewBuilder
    private var meterFailureNotice: some View {
        if let reason = state.audioMeter.failureReason {
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

    private var audioBannerTitle: String {
        if let activeAudioApp { return activeAudioApp.name }
        if let title = state.media.track?.title, !title.isEmpty { return title }
        return "Playing Audio"
    }

    private var audioBannerArtist: String {
        if activeAudioApp != nil { return "Active audio" }
        if let artist = state.media.track?.artist, !artist.isEmpty { return artist }
        return "Playing audio"
    }

    @ViewBuilder
    private var nowPlayingBanner: some View {
        // On the Apps tab the active app already appears as its own row (with
        // the same transport buttons and its volume bar), so a banner on top
        // would render the same app twice. Keep it for every other surface —
        // the device lists there have no "now playing" row of their own — and
        // for media with no app row at all (browser audio when per-process
        // observation is unavailable).
        let hasAppRow = state.audioTab == .apps && activeAudioApp != nil
        if (state.media.isPlaying || activeAudioApp != nil) && !hasAppRow {
            HStack(spacing: 12) {
                // Video thumbnail / Album art / App icon
                Group {
                    if activeAudioApp == nil, let artwork = state.media.artwork {
                        Image(nsImage: artwork)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else if let icon = activeAudioApp?.icon ?? state.media.sourceAppIcon {
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
                        MarqueeText(
                            text: audioBannerTitle,
                            font: .notchBody.weight(.bold),
                            width: 240
                        )
                        .foregroundStyle(NotchTheme.inkPrimary)
                    }

                    Text(audioBannerArtist)
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
                        systemImage: state.media.isPlaying ? "pause.fill" : "play.fill",
                        help: state.media.isPlaying ? "Pause" : "Play"
                    ) {
                        // No spring wrapper: the icon crossfades via
                        // contentTransition, press feedback via
                        // PressableButtonStyle. Bounce on a frequent
                        // transport control reads as jitter.
                        state.media.togglePlayPause()
                    }
                }
            }
            .padding(10)
            .notchCard(radius: NotchTheme.Radius.tile, isHighlighted: true, tint: .green)
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    // MARK: - Spotify Connect

struct SpotifyDeviceCard: View {
    let device: SpotifyClient.Device
    let onSelect: () -> Void
    let onVolume: (Double) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: device.symbolName).font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(device.isActive ? Color.green : NotchTheme.inkSecondary).frame(width: 30)
                Text(device.name).font(.notchHeadline).foregroundStyle(NotchTheme.inkPrimary).lineLimit(1)
                Spacer(minLength: 8)
                if device.isActive { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                else { Button("Switch", action: onSelect).buttonStyle(PressableButtonStyle()) }
            }
            if device.supportsVolume { SpotifyVolumeBar(percent: device.volumePercent ?? 0, onChange: onVolume) }
        }.padding(NotchTheme.Space.l).frame(maxWidth: .infinity, alignment: .leading)
            .notchCard(isHighlighted: device.isActive, tint: .green)
    }
}

struct SpotifyVolumeBar: View {
    let percent: Int
    let onChange: (Double) -> Void
    @State private var dragFraction: Double?
    var body: some View {
        GeometryReader { proxy in
            let fraction = dragFraction ?? min(max(Double(percent) / 100, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(NotchTheme.surfaceHover)
                Capsule().fill(Color.accentColor).frame(width: max(proxy.size.width * fraction, 120))
                HStack { Text("Volume").font(.notchHeadline); Spacer(); Text("\(Int((fraction * 100).rounded())) %").font(.notchHeadline.monospacedDigit()) }
                    .foregroundStyle(.white).padding(.horizontal, 22)
            }.contentShape(Capsule()).gesture(DragGesture(minimumDistance: 0).onChanged { value in
                guard proxy.size.width > 0 else { return }
                let next = min(max(value.location.x / proxy.size.width, 0), 1)
                dragFraction = next; onChange(next)
            }.onEnded { _ in dragFraction = nil })
        }.frame(height: 52)
    }
}

struct SpotifyConnectPrompt: View {
    let message: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note.house.fill").font(.system(size: 28)).foregroundStyle(.green)
            Text(message).font(.notchBody).multilineTextAlignment(.center)
            Text("Settings → Media → Spotify Account. Playback works without it; "
                 + "this is what fills the Library, Discover and Connect screens.")
                .font(.notchFootnote).foregroundStyle(NotchTheme.inkMuted).multilineTextAlignment(.center)
            Button("Open Media Settings") { SettingsWindowController.shared.show() }.buttonStyle(PressableButtonStyle())
        }.padding(.vertical, 20).frame(maxWidth: .infinity)
    }
}


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
                    level: Double(appVolumes[app.id] ?? app.volume() ?? 1),
                    isHighlighted: app.isPlaying,
                    onLevelChange: { level in
                        let value = Float(level)
                        appVolumes[app.id] = value
                        app.setVolume(value)
                    },
                    onSelect: { app.activate() }
                ) {
                    RoundIconButton(
                        systemImage: app.isPlaying ? "pause.fill" : "play.fill",
                        help: app.isPlaying ? "Pause audio/video" : "Play audio/video"
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
                        systemImage: isPinned(app.id) ? "pin.fill" : "pin",
                        help: isPinned(app.id) ? "Unpin \(app.name)" : "Pin \(app.name)",
                        tint: isPinned(app.id) ? .blue : nil
                    ) {
                        togglePin(app.id)
                    }
                    RoundIconButton(
                        systemImage: isAppMuted(app.id)
                            ? "speaker.wave.2.fill"
                            : "speaker.slash.fill",
                        help: isAppMuted(app.id)
                            ? "Unmute \(app.name)"
                            : "Mute \(app.name)",
                        tint: isAppMuted(app.id) ? nil : .red
                    ) {
                        toggleAppMute(app)
                    }
                }
            }

            Text(state.audioApps.canObserveProcesses
                 ? "Adjust each app independently. Changes use CoreAudio's "
                    + "per-process output level."
                 : "macOS 14.4 or later is needed to tell which apps are "
                    + "actually making sound; this lists media apps that are "
                    + "running.")
                .font(.notchFootnote)
                .foregroundStyle(NotchTheme.inkMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
        }
    }

    // MARK: - Input (microphone) control

    /// The input (mic) surface: every input device with a level slider on the
    /// current one and a mute toggle — the FineTune-style mic control.
    @ViewBuilder
    private var inputSection: some View {
        if !state.audioInput.devices.isEmpty {
            VStack(alignment: .leading, spacing: NotchTheme.Space.s) {
                sectionLabel("Microphone")

                ForEach(state.audioInput.devices) { device in
                    let isCurrent = device.id == state.audioInput.currentDeviceID
                    AudioRow(
                        icon: .symbol(device.symbolName),
                        title: device.name,
                        status: isCurrent
                            ? (state.audioInput.isMuted ? "Muted" : "Input")
                            : nil,
                        statusIsLive: isCurrent && !state.audioInput.isMuted,
                        level: isCurrent ? Double(state.audioInput.volume) : nil,
                        isHighlighted: isCurrent,
                        onLevelChange: isCurrent
                            ? { state.audioInput.setVolume(Float($0)) }
                            : nil,
                        onSelect: { state.audioInput.select(device) }
                    ) {
                        RoundIconButton(
                            systemImage: state.audioInput.isMuted
                                ? "mic.slash.fill"
                                : "mic.fill",
                            help: state.audioInput.isMuted
                                ? "Unmute microphone"
                                : "Mute microphone",
                            isEnabled: isCurrent
                        ) {
                            state.audioInput.toggleMute()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Paired Bluetooth devices

    /// Paired-but-disconnected Bluetooth audio devices, offered so they can
    /// be connected from the notch without opening System Settings.
    @ViewBuilder
    private var bluetoothSection: some View {
        if !pairedBluetoothDevices.isEmpty {
            VStack(alignment: .leading, spacing: NotchTheme.Space.s) {
                sectionLabel("Paired Bluetooth")

                ForEach(pairedBluetoothDevices) { device in
                    HStack(spacing: 12) {
                        Image(systemName: device.symbolName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(NotchTheme.inkPrimary)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(NotchTheme.surfaceHover))
                            .clipShape(Circle())

                        Text(device.name)
                            .font(.notchBody.weight(.bold))
                            .foregroundStyle(NotchTheme.inkPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Spacer(minLength: 8)

                        Button("Connect") {
                            BluetoothAudioDevices.connect(device)
                            // Connection is asynchronous; refresh after a
                            // beat so the device leaves the list once it
                            // appears in CoreAudio.
                            Task {
                                try? await Task.sleep(for: .seconds(3))
                                refreshPairedBluetooth()
                            }
                        }
                        .buttonStyle(PressableButtonStyle())
                        .font(.notchCallout.weight(.semibold))
                        .foregroundStyle(NotchTheme.inkPrimary)
                    }
                    .padding(.horizontal, NotchTheme.Space.m)
                    .padding(.vertical, 10)
                    .notchCard()
                }
            }
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.notchEyebrow)
            .tracking(0.8)
            .foregroundStyle(NotchTheme.inkMuted)
            .padding(.horizontal, 4)
    }

    private func refreshPairedBluetooth() {
        BluetoothAudioDevices.pairedAudioDevices { devices in
            // @State's wrappedValue setter is nonmutating, so writing through
            // the value-captured view struct still reaches the shared storage.
            pairedBluetoothDevices = devices
        }
    }

    // MARK: - Pinned apps

    private var audioSettings: NotchSettings { .shared }

    private func isPinned(_ id: String) -> Bool {
        audioSettings.pinnedAudioApps.contains(id)
    }

    private func togglePin(_ id: String) {
        var pinned = audioSettings.pinnedAudioApps
        if let index = pinned.firstIndex(of: id) {
            pinned.remove(at: index)
        } else {
            pinned.append(id)
        }
        audioSettings.pinnedAudioApps = pinned
    }

    // MARK: - Per-app mute

    /// Muting is per-app, on the app's own process volume: remember the level
    /// it was at, drop it to zero, and put it back on unmute. This is what
    /// makes one row's mute button silent *that* app (and only that app)
    /// instead of every output on the Mac.
    private func isAppMuted(_ id: String) -> Bool {
        mutedApps.contains(id)
    }

    private func toggleAppMute(_ app: AudioAppMonitor.App) {
        let current = appVolumes[app.id] ?? app.volume() ?? 1
        if mutedApps.contains(app.id) {
            // Unmute: restore the level it was silenced from.
            mutedApps.remove(app.id)
            let restore = priorVolumeBeforeMute[app.id] ?? 1
            appVolumes[app.id] = restore
            app.setVolume(restore)
        } else {
            // Mute: remember where it is, then zero this app's own volume.
            priorVolumeBeforeMute[app.id] = current
            appVolumes[app.id] = 0
            app.setVolume(0)
            mutedApps.insert(app.id)
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
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(NotchTheme.surfaceHover)

                RoundedRectangle(cornerRadius: 14, style: .continuous)
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
