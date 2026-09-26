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
    /// The per-app mixer: volume past unity, mute, routing, EQ and loudness.
    case mixer
    /// Every local CoreAudio output.
    case system
    /// Local outputs CoreAudio reports as AirPlay.
    case airplay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apps: "Apps & Web"
        case .mixer: "Mixer"
        case .system: "System"
        case .airplay: "AirPlay"
        }
    }

    var symbol: String {
        switch self {
        case .apps: "waveform"
        case .mixer: "slider.horizontal.3"
        case .system: "speaker.wave.2.fill"
        case .airplay: "airplayaudio"
        }
    }
}

/// The Audio screen's body: whichever of the four output surfaces is selected,
/// with the pill strip that switches between them sitting above the content
/// (`DevicesScreenView` is what draws the header this hangs under).
///
/// Every tab reports real state, all of it this Mac's own. AirPlay and System
/// are its CoreAudio outputs, fully interactive; Apps lists every process
/// CoreAudio says is running output; Mixer is where an app is actually taken
/// over, because moving one app's level above the others' needs a tap —
/// current macOS no longer lets a client set another process's volume, which
/// is what the sliders on the Apps tab were written against.
struct AudioDevicesView: View {
    let state: NotchState

    private var activeAudioApp: AudioAppMonitor.App? {
        state.audioApps.apps.first(where: \.isPlaying)
    }

    @State private var appVolumes: [String: Float] = [:]
    @State private var pairedBluetoothDevices: [BluetoothAudioDevices.PairedDevice] = []

    var body: some View {
        VStack(spacing: NotchTheme.Space.s) {
            // Outside the scroll view on purpose: which surface you are on is
            // chrome, and chrome that scrolls away with the list is how a
            // four-way switch becomes a one-way trip.
            tabSwitch

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: NotchTheme.Space.s) {
                    meterFailureNotice

                    nowPlayingBanner

                    switch state.audioTab {
                    case .apps: appRows
                    case .mixer: MixerView(state: state)
                    case .system: deviceRows
                    case .airplay: airplayRows
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
            }
            .notchScrollFade(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            #if DEBUG
            print("[Notch] audio: surface appeared (tab=\(state.audioTab.rawValue))")
            #endif
            state.audio.refresh()
            state.audioInput.refresh()
            refreshPairedBluetooth()
        }
    }

    // MARK: - Which output surface

    /// The audio surface's own switch.
    ///
    /// These four existed as data before they existed as a control: the picker
    /// that drove `audioTab` was gone, which left System and AirPlay written but
    /// unreachable, and left the per-app mixer with nowhere to live. One row
    /// answers both, and it is deliberately not a `Picker` — the notch's
    /// controls are its own, and a segmented control here would sit a system
    /// grey capsule next to the app's own pills.
    private var tabSwitch: some View {
        HStack(spacing: 3) {
            ForEach(AudioScreenTab.allCases) { tab in
                tabPill(tab)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tabPill(_ tab: AudioScreenTab) -> some View {
        let isActive = state.audioTab == tab
        return Button {
            withAnimation(NotchAnimations.content) {
                state.audioTab = tab
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 10.5, weight: .semibold))
                Text(tab.title)
                    .font(.notchCaption.weight(.bold))
                    .fixedSize()
            }
            .foregroundStyle(isActive ? .white : NotchTheme.inkSecondary)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background {
                if isActive {
                    // Deliberately *not* a `matchedGeometryEffect`. That pill was
                    // geometry-matched across a panel whose window is resized and
                    // animated around it, so its frame was re-resolved on every
                    // layout pass — half of how a resize becomes an endless
                    // "needs another Layout Window pass" loop, which AppKit ends
                    // by raising. A plain capsule says the same thing without
                    // asking the layout engine a question per pass.
                    Capsule().fill(Color.accentColor)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
        .accessibilityLabel("\(tab.title) audio surface")
    }

    /// Why the visualiser is not measuring, when it isn't.
    ///
    /// The meter is a CoreAudio tap, and a tap is a permission-gated object:
    /// macOS can refuse to create it (and macOS before 14.2 has no API at
    /// all). That refusal is the difference between bars that follow the music
    /// and bars that only follow the volume, so it belongs on the audio
    /// surface the user is already looking at rather than in a log.
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

                // Audio access lives in the same pane as screen recording on
                // current macOS, which is why one link covers both.
                Button("Open Audio Access") {
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

    // MARK: - AirPlay

    /// Local AirPlay outputs, which is what CoreAudio calls an Apple TV or a
    /// HomePod once macOS has one selected.
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
            ForEach(Array(state.audioApps.apps.enumerated()), id: \.element.id) { index, app in
                AudioRow(
                    icon: .image(app.icon),
                    title: app.name,
                    status: app.isPlaying ? "Playing" : "Idle",
                    statusIsLive: app.isPlaying,
                    level: state.audioApps.canControlAppVolume
                        ? Double(appVolumes[app.id] ?? app.volume() ?? 1)
                        : nil,
                    isHighlighted: app.isPlaying,
                    onLevelChange: state.audioApps.canControlAppVolume
                        ? { level in
                            let value = Float(level)
                            appVolumes[app.id] = value
                            app.setVolume(value)
                        }
                        : nil,
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
                        help: state.audioApps.canControlAppVolume
                            ? (isAppMuted(app.id)
                                ? "Unmute \(app.name)"
                                : "Mute \(app.name)")
                            : "Per-app muting isn't available on this macOS",
                        tint: isAppMuted(app.id) ? nil : .red,
                        isEnabled: state.audioApps.canControlAppVolume
                    ) {
                        toggleAppMute(app)
                    }
                }
                .notchRowEntrance(index)
            }

            Text(!state.audioApps.canObserveProcesses
                 ? "macOS 14.4 or later is needed to tell which apps are "
                    + "actually making sound; this lists media apps that are "
                    + "running."
                 : state.audioApps.canControlAppVolume
                 ? "Adjust each app independently. Changes use CoreAudio's "
                    + "per-process output level."
                 : "This macOS no longer lets apps set another app's volume "
                    + "(CoreAudio removed the per-process level), so only the "
                    + "system output is adjustable.")
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

    /// Mute state lives on AudioAppMonitor, not here: the audio screen is
    /// torn down whenever the notch collapses, so @State mute flags were
    /// forgotten the moment the notch closed even though the app's volume
    /// stayed zero — the UI showed it unmuted and the restore level was
    /// lost. The monitor lives for the app's lifetime, so the mute state
    /// does too.
    private func isAppMuted(_ id: String) -> Bool {
        state.audioApps.canControlAppVolume && state.audioApps.isAppMuted(id)
    }

    /// Per-app mute is a per-process volume write (to zero and back), so it
    /// exists only where that property does. Where it doesn't, the button is
    /// disabled rather than silently doing nothing.
    private func toggleAppMute(_ app: AudioAppMonitor.App) {
        guard state.audioApps.canControlAppVolume else { return }
        // Keep the row's level mirror in step so the bar sits at the new
        // value (0 while muted, the restored level after).
        appVolumes[app.id] = state.audioApps.toggleAppMute(app)
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
