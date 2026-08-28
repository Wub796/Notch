import SwiftUI

/// Hardware telemetry: ring gauges for CPU / memory / battery, a rolling CPU
/// sparkline, battery power + health, and live network throughput.
///
/// Palette is the validated dark-surface set from NotchTheme; every metric is
/// identified by icon + direct label (never color alone), and all values wear
/// ink tokens rather than series colors.
struct TelemetryView: View {
    let telemetry: TelemetryController

    var body: some View {
        HStack(alignment: .center, spacing: 22) {
            VStack(spacing: 6) {
                CircularGaugeView(
                    value: telemetry.cpuUsage,
                    title: "CPU",
                    detail: percentString(telemetry.cpuUsage),
                    systemImage: "cpu",
                    tint: NotchTheme.cpu
                )
                SparklineView(values: telemetry.cpuHistory, tint: NotchTheme.cpu)
                    .frame(width: 64, height: 14)
            }

            CircularGaugeView(
                value: telemetry.memoryPressure,
                title: "Memory",
                detail: percentString(telemetry.memoryPressure),
                systemImage: "memorychip",
                tint: NotchTheme.memory
            )

            if telemetry.hasBattery {
                CircularGaugeView(
                    value: telemetry.batteryPercent,
                    title: "Battery",
                    detail: percentString(telemetry.batteryPercent),
                    systemImage: telemetry.isCharging
                        ? "battery.100percent.bolt"
                        : "battery.75percent",
                    tint: NotchTheme.battery
                )

                VStack(alignment: .leading, spacing: 10) {
                    statTile(
                        value: String(format: "%.1f W", abs(telemetry.batteryWatts)),
                        label: telemetry.batteryWatts >= 0 ? "Charging power" : "Power draw",
                        systemImage: "bolt.fill",
                        tint: NotchTheme.battery
                    )
                    statTile(
                        value: percentString(telemetry.batteryHealth),
                        label: "Battery health",
                        systemImage: "heart.fill",
                        tint: NotchTheme.battery
                    )
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                statTile(
                    value: Self.speedString(telemetry.downloadBytesPerSecond),
                    label: "Download",
                    systemImage: "arrow.down",
                    tint: NotchTheme.network
                )
                statTile(
                    value: Self.speedString(telemetry.uploadBytesPerSecond),
                    label: "Upload",
                    systemImage: "arrow.up",
                    tint: NotchTheme.network
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func statTile(
        value: String,
        label: String,
        systemImage: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 13, weight: .bold).monospacedDigit())
                    .foregroundStyle(NotchTheme.inkPrimary)
                    .contentTransition(.numericText())
                    .animation(.notchSpring, value: value)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(NotchTheme.inkSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }

    private func percentString(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter
    }()

    static func speedString(_ bytesPerSecond: Double) -> String {
        byteFormatter.string(fromByteCount: Int64(max(bytesPerSecond, 0))) + "/s"
    }
}

/// Ring gauge with the animated fill driven by the shared notch spring.
/// The value inside wears ink; the colored ring + icon carry identity.
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
                    .stroke(
                        AngularGradient(
                            colors: [tint.opacity(0.55), tint],
                            center: .center,
                            startAngle: .degrees(0),
                            endAngle: .degrees(360)
                        ),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: tint.opacity(0.35), radius: 4)
                    .animation(.notchSpring, value: value)

                VStack(spacing: 1) {
                    Image(systemName: systemImage)
                        .font(.system(size: 12))
                        .foregroundStyle(tint)
                    Text(detail)
                        .font(.system(size: 12, weight: .bold).monospacedDigit())
                        .foregroundStyle(NotchTheme.inkPrimary)
                        .contentTransition(.numericText())
                        .animation(.notchSpring, value: detail)
                }
            }
            .frame(width: 58, height: 58)

            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(NotchTheme.inkSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(detail)
    }
}

/// Rolling single-series sparkline: 2pt round-capped line over a faint area
/// fill, no grid or axes (the tile above names and quantifies it).
struct SparklineView: View {
    let values: [Double] // 0...1, most recent last
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let points = Self.points(for: values, in: CGSize(width: width, height: height))

            if points.count > 1 {
                ZStack {
                    Path { path in
                        path.move(to: CGPoint(x: points[0].x, y: height))
                        points.forEach { path.addLine(to: $0) }
                        path.addLine(to: CGPoint(x: points[points.count - 1].x, y: height))
                        path.closeSubpath()
                    }
                    .fill(tint.opacity(0.15))

                    Path { path in
                        path.move(to: points[0])
                        points.dropFirst().forEach { path.addLine(to: $0) }
                    }
                    .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .accessibilityHidden(true)
    }

    private static func points(for values: [Double], in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let stepX = size.width / CGFloat(values.count - 1)
        // Inset vertically by the line width so round caps aren't clipped.
        let usableHeight = max(size.height - 2, 1)
        return values.enumerated().map { index, value in
            CGPoint(
                x: CGFloat(index) * stepX,
                y: 1 + usableHeight * (1 - CGFloat(min(max(value, 0), 1)))
            )
        }
    }
}
