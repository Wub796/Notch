import AppKit
import SwiftUI

/// Collapsed and peek states: glass, hugging the hardware notch, with
/// live-activity wings — the weather glyph on the left and its bold
/// temperature on the right, now playing, a volume HUD, battery events,
/// or an imminent meeting.
struct CollapsedNotchView: View {
    let state: NotchState

    /// Passed down so the HUD wings ease outward as the pill grows, matching
    /// the references' hover behaviour.
    var isHovering: Bool = false

    var body: some View {
        ZStack {
            switch state.collapsedActivity {
            case .music:
                musicWings
                    .transition(NotchAnimations.activitySwap)
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
                droppedHUD(
                    kind: .volume(muted: muted),
                    value: Binding(
                        get: { CGFloat(muted ? 0 : level) },
                        set: { state.audio.setVolume(Float($0)) }
                    )
                )
            case let .brightness(level):
                droppedHUD(
                    kind: .brightness,
                    value: Binding(
                        get: { CGFloat(level) },
                        set: { state.brightness.setBrightness(Float($0)) }
                    )
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
                        .transition(NotchAnimations.activitySwap)
                } else {
                    // Weather off still leaves the charging badge, which is a
                    // condition of the machine rather than a weather readout.
                    ActivityWingLayout(
                        notchWidth: state.adjustedNotchSize.width,
                        leading: Color.clear.frame(width: 0),
                        trailing: chargingBadge
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Volume and brightness drop a full-width bar beneath the hardware notch
    /// instead of splitting themselves across the wings. A level bar cut in
    /// half by the camera housing cannot be read at a glance; giving it the
    /// whole width, with the glyph and percentage flanking it, can.
    private func droppedHUD(
        kind: InlineHUD.Kind,
        value: Binding<CGFloat>
    ) -> some View {
        VStack(spacing: 0) {
            // The notch's own row keeps the weather wings so the pill does not
            // appear to lose them for the second the HUD is up.
            weatherFlank
                .frame(height: state.adjustedNotchSize.height)

            DroppedHUDBar(
                kind: kind,
                value: value,
                showsPercentage: state.settings.showHUDPercentage
            )
            .frame(height: 34)
        }
    }

    /// The weather glyph and temperature either side of the notch, shared by
    /// the idle pill and the dropped HUD.
    private var weatherFlank: some View {
        ActivityWingLayout(
            notchWidth: state.adjustedNotchSize.width,
            leading: weatherIcon,
            trailing: HStack(spacing: 9) {
                chargingBadge
                weatherTemperature
            }
        )
    }

    private var compactWeatherWing: some View {
        ActivityWingLayout(
            notchWidth: state.adjustedNotchSize.width,
            leading: weatherIcon,
            trailing: HStack(spacing: 9) {
                chargingBadge
                weatherTemperature
            }
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

    /// A bolt on the trailing wing for as long as the Mac is plugged in.
    ///
    /// Distinct from the plug/unplug activity, which is a moment that passes.
    /// Being on power is a condition, so it stays up — and it distinguishes
    /// charging from merely connected, which is what you see at 100% or under
    /// optimised charging.
    @ViewBuilder
    private var chargingBadge: some View {
        if state.settings.showChargingIndicator,
           let power = state.activities.power,
           power.onACPower {
            HStack(spacing: 3) {
                Image(systemName: power.isCharging ? "bolt.fill" : "powerplug.fill")
                    .font(.system(size: 10, weight: .black))
                Text("\(power.percent)%")
                    .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
            }
            .foregroundStyle(NotchTheme.battery)
            .transition(NotchAnimations.activitySwap)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(power.isCharging ? "Charging" : "Plugged in")
            .accessibilityValue("\(power.percent) percent")
        }
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

    /// While music is playing the wings belong to the music: the cover on the
    /// left, a visualiser tinted from it on the right. The weather takes them
    /// back the moment playback stops.
    private var musicWings: some View {
        ActivityWingLayout(
            notchWidth: state.adjustedNotchSize.width,
            leading: miniArtwork,
            trailing: HStack(spacing: 9) {
                chargingBadge
                MusicVisualizerView(
                    accent: state.media.accent,
                    isPlaying: state.media.isPlaying
                )
            }
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
        .frame(width: 22, height: 22)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(state.media.accent.opacity(0.5), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}
