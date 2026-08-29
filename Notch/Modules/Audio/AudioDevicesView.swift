import AppKit
import SwiftUI

/// The audio screen, laid out like the Sapphire reference: a segmented
/// Apps / Devices switch over a list of rows, each with an icon, a name and
/// status, a wide blue level bar, and a trailing cluster of round buttons.
///
/// Both tabs report real state. Devices is fully interactive. Apps lists every
/// process CoreAudio says is running output — any device audio, not just the
/// now-playing app — but its level is read-only: macOS exposes observing a
/// process's audio, never setting its volume. Sapphire ships an audio HAL
/// plug-in for that; drawing a slider that moves and changes nothing would be
/// worse than saying so.
struct AudioDevicesView: View {
    let state: NotchState

    enum Tab: String, CaseIterable, Identifiable {
        case apps, devices

        var id: String { rawValue }
        var title: String { self == .apps ? "Apps" : "Devices" }
        var symbol: String { self == .apps ? "square.grid.2x2.fill" : "hifispeaker.2.fill" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            tabSwitch

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    switch state.audioTab {
                    case .apps: appRows
                    case .devices: deviceRows
                    }
                }
                .padding(.bottom, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { state.audio.refresh() }
        // Whether a process is running output changes constantly, and CoreAudio
        // posts no notification for it. This polls only while the Apps tab is
        // on screen — the task is cancelled the moment the view goes away, so
        // the closed notch still does nothing.
        .task(id: state.audioTab) {
            guard state.audioTab == .apps else { return }
            while !Task.isCancelled {
                state.refreshAudioApps()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    // MARK: - Tab switch

    private var tabSwitch: some View {
        HStack(spacing: 10) {
            ForEach(Tab.allCases) { tab in
                let isActive = state.audioTab == tab
                Button {
                    withAnimation(NotchAnimations.content) { state.audioTab = tab }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 12, weight: .semibold))
                        Text(tab.title)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(isActive ? .white : NotchTheme.inkSecondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule().fill(isActive ? Color.accentColor : NotchTheme.surface)
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityAddTraits(isActive ? [.isSelected] : [])
            }
            Spacer(minLength: 0)
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
                        systemImage: "play.fill",
                        help: "Bring \(app.name) to the front"
                    ) {
                        app.activate()
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
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(NotchTheme.inkMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
        }
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(NotchTheme.inkMuted)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(NotchTheme.surface)
            }
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
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(NotchTheme.inkPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if let status {
                            Text(status)
                                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                .foregroundStyle(statusIsLive ? .green : NotchTheme.inkMuted)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(NotchTheme.surface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    isHighlighted ? Color.accentColor.opacity(0.8) : .clear,
                    lineWidth: 1.5
                )
        }
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
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(NotchTheme.surfaceHover)

                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.accentColor)
                    .frame(width: max(0, min(geometry.size.width * level, geometry.size.width)))

                HStack {
                    Text("Volume")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                    Spacer(minLength: 8)
                    Text("\(Int((level * 100).rounded()))%")
                        .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
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
        .onHover { hovering in
            withAnimation(NotchAnimations.content) { isHovering = hovering }
        }
        .help(help)
        .accessibilityLabel(help)
    }
}
