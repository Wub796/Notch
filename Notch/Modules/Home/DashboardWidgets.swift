import SwiftUI

/// The Home dashboard's optional widgets — everything beyond the original
/// player, weather and calendar panes.
///
/// Each follows the same rules as those three, so a dashboard built from any
/// mix of them still reads as one system: the shared surface, content that
/// fits the fixed row height, and the whole pane as the way into its full
/// screen — except where the pane carries controls of its own, because a tap
/// meant for a button must never also navigate away.

extension View {
    /// The pane every dashboard widget sits in: the shared surface, filling its
    /// share of the row and the row's full height, content centred.
    ///
    /// Content keeps its natural width (`fixedSize`), and only the pane grows
    /// past it. Without that, the music pane's claim on spare width let the row
    /// squeeze a neighbour down to its *minimum* — and a Text's minimum is
    /// nothing, which is how the weather pane lost its temperature entirely.
    func dashboardPane() -> some View {
        fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, NotchTheme.Space.s)
            .padding(.vertical, NotchTheme.Space.s)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .notchTile(radius: NotchTheme.Radius.card)
    }

    /// A pane that is itself the way into a screen: tap anywhere on it.
    func dashboardPane(opens tab: NotchTab, in state: NotchState, help: String) -> some View {
        dashboardPane()
            .contentShape(Rectangle())
            .tileHover()
            .onTapGesture { state.select(tab) }
            .help(help)
    }
}

private func percentText(_ value: Double) -> String {
    "\(Int((min(max(value, 0), 1) * 100).rounded()))%"
}

// MARK: - System

/// CPU and memory as rings. Opens System Stats.
struct SystemWidget: View {
    let state: NotchState

    private var telemetry: TelemetryController { state.telemetry }

    var body: some View {
        HStack(spacing: NotchTheme.Space.l) {
            CircularGaugeView(
                value: telemetry.cpuUsage,
                title: "CPU",
                detail: percentText(telemetry.cpuUsage),
                systemImage: "cpu",
                tint: NotchTheme.cpu
            )
            // Honours the same switch as the System screen, so turning memory
            // off in Settings turns it off everywhere rather than in one place.
            if state.settings.showMemoryPressure {
                CircularGaugeView(
                    value: telemetry.memoryPressure,
                    title: "Memory",
                    detail: percentText(telemetry.memoryPressure),
                    systemImage: "memorychip",
                    tint: NotchTheme.memory
                )
            }
        }
        .dashboardPane(opens: .telemetry, in: state, help: "Open System Stats")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("System")
        .accessibilityValue(
            "CPU \(percentText(telemetry.cpuUsage))"
                + (state.settings.showMemoryPressure
                    ? ", memory \(percentText(telemetry.memoryPressure))"
                    : "")
        )
    }
}

// MARK: - Batteries

/// This Mac's battery, and the accessories running lowest. Opens System Stats,
/// where battery health and power draw live.
struct BatteryWidget: View {
    let state: NotchState

    private var telemetry: TelemetryController { state.telemetry }

    /// The two lowest accessories — the ones actually worth knowing about.
    private var accessories: [BluetoothBatteryMonitor.Device] {
        Array(
            state.bluetooth.devices
                .filter { $0.lowestPercent != nil }
                .sorted { ($0.lowestPercent ?? 100) < ($1.lowestPercent ?? 100) }
                .prefix(2)
        )
    }

    private var macPercent: Int {
        Int((min(max(telemetry.batteryPercent, 0), 1) * 100).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NotchTheme.Space.s) {
            if telemetry.hasBattery {
                mac
            }
            if !accessories.isEmpty {
                VStack(alignment: .leading, spacing: NotchTheme.Space.xs) {
                    ForEach(accessories) { device in
                        accessoryRow(device)
                    }
                }
            }
            if !telemetry.hasBattery && accessories.isEmpty {
                VStack(spacing: NotchTheme.Space.xs) {
                    Image(systemName: "battery.0percent")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(NotchTheme.inkMuted)
                    Text("No batteries")
                        .font(.notchCaption)
                        .foregroundStyle(NotchTheme.inkSecondary)
                }
            }
        }
        .dashboardPane(opens: .telemetry, in: state, help: "Open System Stats")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Batteries")
        .accessibilityValue(accessibilitySummary)
    }

    private var mac: some View {
        let low = macPercent <= state.settings.lowBatteryThreshold && !telemetry.isCharging
        return HStack(spacing: NotchTheme.Space.s) {
            Image(systemName: telemetry.isCharging
                ? "battery.100percent.bolt"
                : Self.symbol(for: macPercent))
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(low
                    ? Color.red
                    : (telemetry.isCharging ? NotchTheme.battery : NotchTheme.inkPrimary))

            VStack(alignment: .leading, spacing: 0) {
                Text("\(macPercent)%")
                    .font(.notchTitle.monospacedDigit())
                    .foregroundStyle(NotchTheme.inkPrimary)
                    .contentTransition(.numericText())
                    .animation(NotchAnimations.content, value: macPercent)
                Text(telemetry.isCharging ? "Charging" : "This Mac")
                    .font(.notchCaption)
                    .foregroundStyle(NotchTheme.inkSecondary)
            }
            .fixedSize()
        }
    }

    private func accessoryRow(_ device: BluetoothBatteryMonitor.Device) -> some View {
        let percent = device.lowestPercent ?? 0
        return HStack(spacing: NotchTheme.Space.xs) {
            Image(systemName: device.symbolName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(NotchTheme.inkSecondary)
                .frame(width: 16)
            Text(device.name)
                .font(.notchCaption)
                .foregroundStyle(NotchTheme.inkSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 110, alignment: .leading)
            Text("\(percent)%")
                .font(.notchCaption.weight(.bold).monospacedDigit())
                .foregroundStyle(percent <= 20 ? Color.red : NotchTheme.inkPrimary)
                .fixedSize()
        }
    }

    private var accessibilitySummary: String {
        var parts: [String] = []
        if telemetry.hasBattery {
            parts.append("This Mac \(macPercent) percent" + (telemetry.isCharging ? ", charging" : ""))
        }
        parts += accessories.map { "\($0.name) \($0.lowestPercent ?? 0) percent" }
        return parts.isEmpty ? "No batteries" : parts.joined(separator: "; ")
    }

    private static func symbol(for percent: Int) -> String {
        switch percent {
        case ..<13: "battery.0percent"
        case ..<38: "battery.25percent"
        case ..<63: "battery.50percent"
        case ..<88: "battery.75percent"
        default: "battery.100percent"
        }
    }
}

// MARK: - Timer

/// A countdown you can start without leaving the dashboard. It carries its own
/// controls, so the pane is deliberately not a tap target.
struct TimerWidget: View {
    let state: NotchState

    private var timer: TimerManager { state.timer }

    private static let presets = [5, 15, 25]

    var body: some View {
        Group {
            if timer.isRunning {
                running
            } else {
                idle
            }
        }
        .animation(NotchAnimations.content, value: timer.isRunning)
        .dashboardPane()
    }

    private var idle: some View {
        VStack(alignment: .leading, spacing: NotchTheme.Space.s) {
            Label("Timer", systemImage: "timer")
                .font(.notchBody)
                .foregroundStyle(NotchTheme.inkSecondary)

            HStack(spacing: NotchTheme.Space.xs) {
                ForEach(Self.presets, id: \.self) { minutes in
                    Button {
                        timer.start(minutes: minutes)
                    } label: {
                        Text("\(minutes)m")
                            .font(.notchBody.monospacedDigit())
                            .foregroundStyle(NotchTheme.inkPrimary)
                            .padding(.horizontal, NotchTheme.Space.s)
                            .padding(.vertical, NotchTheme.Space.xs)
                            .background(Capsule().fill(NotchTheme.surfaceHover))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressableButtonStyle())
                    .help("Start a \(minutes)-minute timer")
                    .accessibilityLabel("Start a \(minutes)-minute timer")
                }
            }
        }
        .transition(.opacity)
    }

    private var running: some View {
        HStack(spacing: NotchTheme.Space.m) {
            // No animation on the ring: it steps four times a second, and
            // animating each step would just trail the real value.
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.12), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: max(0.001, timer.progress))
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 40, height: 40)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Text(TimerManager.timeString(timer.remaining))
                    .font(.notchTitle.monospacedDigit())
                    .foregroundStyle(NotchTheme.inkPrimary)
                Text(timer.isPaused ? "Paused" : "Remaining")
                    .font(.notchCaption)
                    .foregroundStyle(NotchTheme.inkSecondary)
            }
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Timer")
            .accessibilityValue(
                TimerManager.timeString(timer.remaining) + (timer.isPaused ? ", paused" : " remaining")
            )

            Spacer(minLength: 0)

            VStack(spacing: NotchTheme.Space.xs) {
                NotchIconButton(
                    systemImage: timer.isPaused ? "play.fill" : "pause.fill",
                    help: timer.isPaused ? "Resume timer" : "Pause timer",
                    size: 24
                ) {
                    timer.togglePause()
                }
                NotchIconButton(systemImage: "xmark", help: "Cancel timer", size: 24) {
                    timer.cancel()
                }
            }
        }
        .transition(.opacity)
    }
}
