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
        VStack(alignment: .leading, spacing: NotchTheme.Space.m) {
            ScreenHeader("System", subtitle: subtitle)

            gauges
                .padding(.horizontal, NotchTheme.Space.l)
                .padding(.vertical, NotchTheme.Space.m)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .notchCard()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// CPU, memory and battery at a glance, with the numbers that only make
    /// sense as text beside them.
    private var subtitle: String {
        var parts = ["CPU \(percentString(telemetry.cpuUsage))",
                     "Memory \(percentString(telemetry.memoryPressure))"]
        if telemetry.hasBattery {
            parts.append("Battery \(percentString(telemetry.batteryPercent))")
        }
        return parts.joined(separator: " · ")
    }

    private var gauges: some View {
        HStack(alignment: .center, spacing: 0) {
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

            Spacer(minLength: NotchTheme.Space.m)

            CircularGaugeView(
                value: telemetry.memoryPressure,
                title: "Memory",
                detail: percentString(telemetry.memoryPressure),
                systemImage: "memorychip",
                tint: NotchTheme.memory
            )

            if telemetry.hasBattery {
                Spacer(minLength: NotchTheme.Space.m)

                CircularGaugeView(
                    value: telemetry.batteryPercent,
                    title: "Battery",
                    detail: percentString(telemetry.batteryPercent),
                    systemImage: telemetry.isCharging
                        ? "battery.100percent.bolt"
                        : "battery.75percent",
                    tint: NotchTheme.battery
                )

                Spacer(minLength: NotchTheme.Space.m)

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
                .frame(width: 130, alignment: .leading)
            }

            Spacer(minLength: NotchTheme.Space.m)

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
            .frame(width: 130, alignment: .leading)
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
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.notchBody.weight(.bold).monospacedDigit())
                    .foregroundStyle(NotchTheme.inkPrimary)
                    .contentTransition(.numericText())
                    .animation(.notchSpring, value: value)
                    .lineLimit(1)
                Text(label)
                    .font(.notchFootnote)
                    .foregroundStyle(NotchTheme.inkSecondary)
                    .lineLimit(1)
            }
            // Fixed width, because these strings change width as they change
            // value — "9.8 W" to "10.1 W", "980 KB/s" to "1.2 MB/s" — and a
            // row that re-lays-out on every sample is the twitch.
            .frame(width: 96, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }

    private func percentString(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    /// Always one decimal and a two-letter unit, so the string's width is
    /// stable across the whole range. ByteCountFormatter drops decimals and
    /// switches between "bytes"/"KB"/"MB", which makes it jump.
    static func speedString(_ bytesPerSecond: Double) -> String {
        let rate = max(bytesPerSecond, 0)
        switch rate {
        case ..<(1_024 * 1_024):
            return String(format: "%.1f KB/s", rate / 1_024)
        case ..<(1_024 * 1_024 * 1_024):
            return String(format: "%.1f MB/s", rate / (1_024 * 1_024))
        default:
            return String(format: "%.1f GB/s", rate / (1_024 * 1_024 * 1_024))
        }
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
