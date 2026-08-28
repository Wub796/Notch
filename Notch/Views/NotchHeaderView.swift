import AppKit
import SwiftUI

/// Top strip of the expanded notch: clock + date, battery pill, keep-awake
/// toggle, and the settings gear. The clock refreshes only while expanded.
struct NotchHeaderView: View {
    let state: NotchState

    @Environment(\.openSettings) private var openSettings

    var body: some View {
        TimelineView(.everyMinute) { context in
            HStack(spacing: 10) {
                Text(context.date.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 13, weight: .bold).monospacedDigit())
                    .foregroundStyle(NotchTheme.inkPrimary)
                    .contentTransition(.numericText())
                Text(context.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(.system(size: 10.5))
                    .foregroundStyle(NotchTheme.inkMuted)

                Spacer()

                if state.telemetry.hasBattery {
                    batteryPill
                }

                headerButton(
                    systemImage: state.keepAwake.isActive ? "cup.and.saucer.fill" : "cup.and.saucer",
                    isHighlighted: state.keepAwake.isActive,
                    help: state.keepAwake.isActive
                        ? "Mac is being kept awake — click to allow sleep"
                        : "Keep Mac awake"
                ) {
                    NotchTheme.Haptics.generic()
                    withAnimation(.notchSpring) {
                        state.keepAwake.toggle()
                    }
                }

                headerButton(systemImage: "gearshape.fill", isHighlighted: false, help: "Notch Settings") {
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                }
            }
        }
        .frame(height: 20)
    }

    private var batteryPill: some View {
        HStack(spacing: 4) {
            Image(systemName: state.telemetry.isCharging ? "bolt.fill" : "battery.75percent")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(NotchTheme.battery)
            Text("\(Int((state.telemetry.batteryPercent * 100).rounded()))%")
                .font(.system(size: 10, weight: .bold).monospacedDigit())
                .foregroundStyle(NotchTheme.inkPrimary)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(NotchTheme.surface))
    }

    private func headerButton(
        systemImage: String,
        isHighlighted: Bool,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isHighlighted ? NotchTheme.inkPrimary : NotchTheme.inkSecondary)
                .frame(width: 24, height: 24)
                .background {
                    Circle().fill(isHighlighted ? NotchTheme.surfaceHover : .clear)
                }
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .hoverLift(1.1)
        .help(help)
    }
}
