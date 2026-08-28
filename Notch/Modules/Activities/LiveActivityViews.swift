import AppKit
import SwiftUI

/// Wing content for each live activity: a leading glyph on the left of the
/// hardware notch and a trailing readout on the right.

struct VolumeActivityView: View {
    let level: Float
    let muted: Bool

    private var symbol: String {
        if muted || level == 0 { return "speaker.slash.fill" }
        if level < 0.34 { return "speaker.wave.1.fill" }
        if level < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    var leading: some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(NotchTheme.inkPrimary)
            .frame(width: 20, alignment: .leading)
            .contentTransition(.symbolEffect(.replace))
    }

    var trailing: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(.white.opacity(0.22))
            Capsule()
                .fill(.white)
                .frame(width: 46 * CGFloat(muted ? 0 : level))
        }
        .frame(width: 46, height: 5)
        .animation(NotchAnimations.activity, value: level)
    }

    var body: some View {
        ActivityWingLayout(leading: leading, trailing: trailing)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Volume")
            .accessibilityValue(muted ? "Muted" : "\(Int((level * 100).rounded())) percent")
    }
}

struct BatteryActivityView: View {
    let percent: Int
    let charging: Bool
    let low: Bool

    private var tint: Color {
        low ? .red : NotchTheme.battery
    }

    var body: some View {
        ActivityWingLayout(
            leading: Image(systemName: charging ? "battery.100percent.bolt" : "battery.25percent")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24, alignment: .leading),
            trailing: Text("\(percent)%")
                .font(.system(size: 12, weight: .bold).monospacedDigit())
                .foregroundStyle(tint)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(charging ? "Charging" : (low ? "Low battery" : "Battery"))
        .accessibilityValue("\(percent) percent")
    }
}

struct MeetingActivityView: View {
    let title: String
    let start: Date
    let now: Date

    private var countdown: String {
        let minutes = Int(start.timeIntervalSince(now) / 60)
        return minutes < 1 ? "now" : "\(minutes)m"
    }

    var body: some View {
        ActivityWingLayout(
            leading: Image(systemName: "calendar.badge.clock")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 22, alignment: .leading),
            trailing: HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(NotchTheme.inkPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: 86, alignment: .trailing)
                Text(countdown)
                    .font(.system(size: 10.5, weight: .heavy).monospacedDigit())
                    .foregroundStyle(.orange)
                    .contentTransition(.numericText())
            }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Upcoming: \(title)")
        .accessibilityValue("starts in \(countdown)")
    }
}

/// Sneak peek: a freshly started track announces itself with a marquee.
struct TrackChangeActivityView: View {
    let title: String
    let artist: String
    let artwork: NSImage?
    let accent: Color

    var body: some View {
        ActivityWingLayout(
            leading: Group {
                if let artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 18, height: 18)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(accent)
                }
            },
            trailing: MarqueeText(
                text: artist.isEmpty ? title : "\(title) — \(artist)",
                font: .system(size: 10.5, weight: .semibold),
                width: 132
            )
            .foregroundStyle(NotchTheme.inkPrimary)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Now playing")
        .accessibilityValue(artist.isEmpty ? title : "\(title) by \(artist)")
    }
}

/// Session lock/unlock moment.
struct ScreenLockActivityView: View {
    let locked: Bool

    var body: some View {
        ActivityWingLayout(
            leading: Image(systemName: locked ? "lock.fill" : "lock.open.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(locked ? NotchTheme.inkSecondary : NotchTheme.battery)
                .frame(width: 20, alignment: .leading)
                .contentTransition(.symbolEffect(.replace)),
            trailing: Text(locked ? "Locked" : "Welcome back")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(NotchTheme.inkPrimary)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(locked ? "Screen locked" : "Screen unlocked")
    }
}

/// Shared wing layout: leading glyph, dead zone for the hardware notch,
/// trailing readout.
struct ActivityWingLayout<Leading: View, Trailing: View>: View {
    let leading: Leading
    let trailing: Trailing

    init(leading: Leading, trailing: Trailing) {
        self.leading = leading
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 0) {
            leading
                .padding(.leading, 13)
            Spacer(minLength: 0)
            trailing
                .padding(.trailing, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
