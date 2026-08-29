import AppKit
import SwiftUI

/// Collapsed and peek states: glass, hugging the hardware notch, with
/// live-activity wings — the weather glyph on the left and its bold
/// temperature on the right, now playing, a volume HUD, battery events,
/// or an imminent meeting.
struct CollapsedNotchView: View {
    let state: NotchState

    var body: some View {
        ZStack {
            switch state.collapsedActivity {
            case .music:
                musicWings
            case let .lyrics(line):
                VStack(spacing: 0) {
                    musicWings
                        .frame(height: state.adjustedNotchSize.height)
                    Text(line)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(state.media.accent)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, 18)
                        .frame(maxWidth: .infinity)
                        .frame(height: 26)
                        .contentTransition(.opacity)
                        .animation(NotchAnimations.activity, value: line)
                        .accessibilityLabel("Lyric")
                        .accessibilityValue(line)
                }
            case let .trackChange(title, artist):
                TrackChangeActivityView(
                    notchWidth: state.adjustedNotchSize.width,
                    title: title,
                    artist: artist,
                    artwork: state.media.artwork,
                    accent: state.media.accent
                )
            case let .volume(level, muted):
                VolumeActivityView(
                    notchWidth: state.adjustedNotchSize.width,
                    level: level,
                    muted: muted
                )
            case let .brightness(level):
                BrightnessActivityView(
                    notchWidth: state.adjustedNotchSize.width,
                    level: level
                )
            case let .battery(percent, charging, low):
                BatteryActivityView(
                    notchWidth: state.adjustedNotchSize.width,
                    percent: percent,
                    charging: charging,
                    low: low
                )
            case let .screenLock(locked):
                ScreenLockActivityView(
                    notchWidth: state.adjustedNotchSize.width,
                    locked: locked
                )
            case let .timer(remaining, progress):
                TimerActivityView(
                    notchWidth: state.adjustedNotchSize.width,
                    remaining: remaining,
                    progress: progress
                )
            case let .focusMode(name, symbol):
                FocusActivityView(
                    notchWidth: state.adjustedNotchSize.width,
                    name: name,
                    symbol: symbol
                )
            case let .eyeBreak(active):
                EyeBreakActivityView(
                    notchWidth: state.adjustedNotchSize.width,
                    active: active
                )
            case .desktopChange:
                DesktopChangeActivityView(notchWidth: state.adjustedNotchSize.width)
            case let .accessoryBattery(name, symbol, percent):
                AccessoryBatteryActivityView(
                    notchWidth: state.adjustedNotchSize.width,
                    name: name,
                    symbol: symbol,
                    percent: percent
                )
            case let .meetingSoon(title, start):
                TimelineView(.everyMinute) { context in
                    MeetingActivityView(
                        notchWidth: state.adjustedNotchSize.width,
                        title: title,
                        start: start,
                        now: context.date
                    )
                }
            case nil:
                if state.settings.showCompactWeather {
                    compactWeatherWing
                } else {
                    Color.clear
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var compactWeatherWing: some View {
        ActivityWingLayout(
            notchWidth: state.adjustedNotchSize.width,
            leading: weatherIcon,
            trailing: weatherTemperature
        )
    }

    /// The condition glyph, on the left of the hardware notch.
    private var weatherIcon: some View {
        Group {
            if let weather = state.weather.snapshot {
                Image(systemName: WeatherService.symbol(
                    for: weather.weatherCode,
                    isDay: weather.isDay
                ))
                .font(.system(size: 15, weight: .semibold))
                .symbolRenderingMode(.multicolor)
            } else {
                Image(systemName: "cloud.sun.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(NotchTheme.inkMuted)
            }
        }
        .accessibilityHidden(true)
    }

    /// The bold temperature readout, on the right of the hardware notch.
    private var weatherTemperature: some View {
        Group {
            if let weather = state.weather.snapshot {
                Text(WeatherService.temperatureString(celsius: weather.temperatureCelsius))
                    .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(NotchTheme.inkPrimary)
                    .contentTransition(.numericText())
            } else {
                Text("--°")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(NotchTheme.inkMuted)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Current weather")
        .accessibilityValue(
            state.weather.snapshot.map {
                WeatherService.temperatureString(celsius: $0.temperatureCelsius)
                + ", " + WeatherService.condition(for: $0.weatherCode)
            } ?? "Unavailable"
        )
    }

    /// Weather always flanks the hardware notch — the glyph on the left, the
    /// temperature on the right — with the artwork joining the left wing
    /// while something is playing.
    private var musicWings: some View {
        ActivityWingLayout(
            notchWidth: state.adjustedNotchSize.width,
            leading: HStack(spacing: 9) {
                miniArtwork
                weatherIcon
            },
            trailing: weatherTemperature
        )
    }

    private var miniArtwork: some View {
        Group {
            if let artwork = state.media.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(NotchTheme.surfaceHover)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 10))
                            .foregroundStyle(NotchTheme.inkSecondary)
                    }
            }
        }
        .frame(width: 20, height: 20)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .accessibilityHidden(true)
    }
}
