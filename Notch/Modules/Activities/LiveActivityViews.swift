import AppKit
import SwiftUI

/// Wing content for each live activity: a leading glyph on the left of the
/// hardware notch and a trailing readout on the right. Content is sized to
/// stay inside its wing — see ActivityWingLayout.

struct VolumeActivityView: View {
    let notchWidth: CGFloat
    let level: Float
    let muted: Bool

    private var symbol: String {
        if muted || level == 0 { return "speaker.slash.fill" }
        if level < 0.34 { return "speaker.wave.1.fill" }
        if level < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    var body: some View {
        ActivityWingLayout(
            notchWidth: notchWidth,
            leading: Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NotchTheme.inkPrimary)
                .contentTransition(.symbolEffect(.replace)),
            trailing: ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.22))
                Capsule()
                    .fill(.white)
                    .frame(width: 44 * CGFloat(muted ? 0 : level))
            }
            .frame(width: 44, height: 5)
            .animation(NotchAnimations.activity, value: level)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Volume")
        .accessibilityValue(muted ? "Muted" : "\(Int((level * 100).rounded())) percent")
    }
}

struct BatteryActivityView: View {
    let notchWidth: CGFloat
    let percent: Int
    let charging: Bool
    let low: Bool

    private var tint: Color {
        low ? .red : NotchTheme.battery
    }

    var body: some View {
        ActivityWingLayout(
            notchWidth: notchWidth,
            leading: Image(systemName: charging ? "battery.100percent.bolt" : "battery.25percent")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint),
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
    let notchWidth: CGFloat
    let title: String
    let start: Date
    let now: Date

    private var countdown: String {
        let minutes = Int(start.timeIntervalSince(now) / 60)
        return minutes < 1 ? "now" : "\(minutes)m"
    }

    var body: some View {
        ActivityWingLayout(
            notchWidth: notchWidth,
            leading: Image(systemName: "calendar.badge.clock")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.orange),
            trailing: HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(NotchTheme.inkPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 78, alignment: .trailing)
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
    let notchWidth: CGFloat
    let title: String
    let artist: String
    let artwork: NSImage?
    let accent: Color

    var body: some View {
        ActivityWingLayout(
            notchWidth: notchWidth,
            leading: Group {
                if let artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 18, height: 18)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(accent)
                }
            },
            trailing: MarqueeText(
                text: artist.isEmpty ? title : "\(title) — \(artist)",
                font: .system(size: 10.5, weight: .semibold),
                width: 100
            )
            .foregroundStyle(NotchTheme.inkPrimary)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Now playing")
        .accessibilityValue(artist.isEmpty ? title : "\(title) by \(artist)")
    }
}

/// Lyric live activity: the closed notch grows a slim bar underneath showing
/// the current synced lyric line in the artwork accent (the reference demo's
/// signature moment).
struct LyricActivityView: View {
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let line: String
    let artwork: NSImage?
    let accent: Color

    var body: some View {
        VStack(spacing: 0) {
            ActivityWingLayout(
                notchWidth: notchWidth,
                leading: Group {
                    if let artwork {
                        Image(nsImage: artwork)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 18, height: 18)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    } else {
                        Image(systemName: "music.note")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(accent)
                    }
                },
                trailing: Circle()
                    .fill(accent)
                    .frame(width: 6, height: 6)
            )
            .frame(height: notchHeight)

            Text(line)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(accent)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .contentTransition(.opacity)
                .animation(NotchAnimations.activity, value: line)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Lyric")
        .accessibilityValue(line)
    }
}

/// Session lock/unlock moment.
struct ScreenLockActivityView: View {
    let notchWidth: CGFloat
    let locked: Bool

    var body: some View {
        ActivityWingLayout(
            notchWidth: notchWidth,
            leading: Image(systemName: locked ? "lock.fill" : "lock.open.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(locked ? NotchTheme.inkSecondary : NotchTheme.battery)
                .contentTransition(.symbolEffect(.replace)),
            trailing: Text(locked ? "Locked" : "Welcome back")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(NotchTheme.inkPrimary)
                .lineLimit(1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(locked ? "Screen locked" : "Screen unlocked")
    }
}

/// Countdown timer running in the collapsed notch, with a progress ring.
struct TimerActivityView: View {
    let notchWidth: CGFloat
    let remaining: TimeInterval
    let progress: Double

    var body: some View {
        ActivityWingLayout(
            notchWidth: notchWidth,
            leading: ZStack {
                Circle()
                    .stroke(.white.opacity(0.18), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: max(0.001, min(progress, 1)))
                    .stroke(.orange, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "timer")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.orange)
            }
            .frame(width: 17, height: 17)
            .animation(NotchAnimations.activity, value: progress),
            trailing: Text(TimerManager.timeString(remaining))
                .font(.system(size: 12, weight: .bold).monospacedDigit())
                .foregroundStyle(.orange)
                .contentTransition(.numericText())
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Timer")
        .accessibilityValue(TimerManager.timeString(remaining) + " remaining")
    }
}

/// Focus mode turned on or off.
struct FocusActivityView: View {
    let notchWidth: CGFloat
    let name: String
    let symbol: String

    var body: some View {
        ActivityWingLayout(
            notchWidth: notchWidth,
            leading: Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.purple),
            trailing: Text(name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(NotchTheme.inkPrimary)
                .lineLimit(1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Focus")
        .accessibilityValue(name)
    }
}

/// The 20-20-20 eye break.
struct EyeBreakActivityView: View {
    let notchWidth: CGFloat
    let active: Bool

    var body: some View {
        ActivityWingLayout(
            notchWidth: notchWidth,
            leading: Image(systemName: active ? "eye.fill" : "eye.slash.fill")
                .font(.system(size: 12))
                .foregroundStyle(active ? NotchTheme.battery : NotchTheme.inkSecondary),
            trailing: Text(active ? "Look 20 ft away" : "Break over")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(NotchTheme.inkPrimary)
                .lineLimit(1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(active ? "Eye break started" : "Eye break over")
    }
}

/// A Space switch.
struct DesktopChangeActivityView: View {
    let notchWidth: CGFloat

    var body: some View {
        ActivityWingLayout(
            notchWidth: notchWidth,
            leading: Image(systemName: "macwindow.on.rectangle")
                .font(.system(size: 12))
                .foregroundStyle(NotchTheme.inkSecondary),
            trailing: Text("Desktop")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(NotchTheme.inkPrimary)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Switched desktop")
    }
}

/// A connected accessory reporting its battery level.
struct AccessoryBatteryActivityView: View {
    let notchWidth: CGFloat
    let name: String
    let symbol: String
    let percent: Int

    var body: some View {
        ActivityWingLayout(
            notchWidth: notchWidth,
            leading: Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(NotchTheme.inkPrimary),
            trailing: HStack(spacing: 5) {
                Text(name)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(NotchTheme.inkSecondary)
                    .lineLimit(1)
                    .frame(maxWidth: 74, alignment: .trailing)
                Text("\(percent)%")
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .foregroundStyle(percent <= 20 ? .red : NotchTheme.battery)
            }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue("\(percent) percent")
    }
}

/// Shared wing layout: leading glyph, an exact reserved dead zone for the
/// hardware notch (content under the camera housing is invisible), trailing
/// readout. Both wings are equal flexible widths so the dead zone stays
/// centered whatever each side contains.
struct ActivityWingLayout<Leading: View, Trailing: View>: View {
    let notchWidth: CGFloat
    let leading: Leading
    let trailing: Trailing

    init(notchWidth: CGFloat, leading: Leading, trailing: Trailing) {
        self.notchWidth = notchWidth
        self.leading = leading
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 0) {
            leading
                .padding(.leading, 13)
                .frame(maxWidth: .infinity, alignment: .leading)
            Color.clear
                .frame(width: notchWidth)
            trailing
                .padding(.trailing, 14)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
