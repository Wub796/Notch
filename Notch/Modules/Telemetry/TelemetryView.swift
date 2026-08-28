import SwiftUI

/// Hardware telemetry rendered as minimal animated circular gauges.
struct TelemetryView: View {
    let telemetry: TelemetryController

    var body: some View {
        HStack(spacing: 30) {
            CircularGaugeView(
                value: telemetry.cpuUsage,
                title: "CPU",
                detail: percentString(telemetry.cpuUsage),
                systemImage: "cpu",
                tint: .orange
            )

            CircularGaugeView(
                value: telemetry.memoryPressure,
                title: "Memory",
                detail: percentString(telemetry.memoryPressure),
                systemImage: "memorychip",
                tint: .purple
            )

            if telemetry.hasBattery {
                CircularGaugeView(
                    value: telemetry.batteryPercent,
                    title: "Battery",
                    detail: percentString(telemetry.batteryPercent),
                    systemImage: telemetry.isCharging ? "battery.100percent.bolt" : "battery.75percent",
                    tint: .green
                )

                batteryDetail
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var batteryDetail: some View {
        VStack(alignment: .leading, spacing: 9) {
            detailRow(
                label: telemetry.batteryWatts >= 0 ? "Charging power" : "Power draw",
                value: String(format: "%.1f W", abs(telemetry.batteryWatts)),
                systemImage: "bolt.fill",
                tint: .yellow
            )
            detailRow(
                label: "Battery health",
                value: percentString(telemetry.batteryHealth),
                systemImage: "heart.fill",
                tint: .pink
            )
        }
    }

    private func detailRow(
        label: String,
        value: String,
        systemImage: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 11))
                .foregroundStyle(tint)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 13, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                Text(label)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    private func percentString(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }
}

/// Ring gauge with the animated fill driven by the shared notch spring.
struct CircularGaugeView: View {
    let value: Double
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.12), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                Circle()
                    .trim(from: 0, to: max(0.001, min(value, 1)))
                    .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.notchSpring, value: value)

                VStack(spacing: 1) {
                    Image(systemName: systemImage)
                        .font(.system(size: 12))
                        .foregroundStyle(tint)
                    Text(detail)
                        .font(.system(size: 12, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 66, height: 66)

            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
        }
    }
}
