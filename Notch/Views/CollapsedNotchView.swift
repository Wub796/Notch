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
                        .font(.notchBody.weight(.bold))
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
                dropped {
                    droppedRow(
                        symbol: "music.note",
                        tint: state.media.accent,
                        label: artist.isEmpty ? title : "\(title) — \(artist)",
                        value: nil
                    )
                }
            case let .volume(level, muted):
                droppedHUD(
                    kind: .volume(muted: muted),
                    value: Binding(
                        get: { CGFloat(muted ? 0 : level) },
                        set: { newValue in
                            let level = Float(newValue)
                            state.audio.setVolume(level)
                            // Re-raise the activity so the bar shows where the
                            // drag put it, and so the dismiss timer restarts —
                            // otherwise the HUD reads the value from before the
                            // drag and snaps back under the finger.
                            state.activities.showVolume(level: level, muted: level == 0)
                        }
                    )
                )
            case let .brightness(level):
                droppedHUD(
                    kind: .brightness,
                    value: Binding(
                        get: { CGFloat(level) },
                        set: { newValue in
                            let level = Float(newValue)
                            state.brightness.setBrightness(level)
                            state.activities.showBrightness(level: level)
                        }
                    )
                )
            case let .battery(percent, charging, low):
                // Back in the wings rather than dropped: this is a moment, and
                // a word beside the notch with the matching glyph on the other
                // side reads faster than a bar unfolding below it.
                ActivityWingLayout(
                    notchWidth: state.adjustedNotchSize.width,
                    leading: Text(charging
                                  ? "Charging"
                                  : (low ? "Low Battery" : "On Battery"))
                        .font(.notchBody.weight(.bold))
                        .foregroundStyle(low ? .red : NotchTheme.inkPrimary)
                        .fixedSize(),
                    trailing: HStack(spacing: 5) {
                        Text("\(percent)%")
                            .font(.notchBody.weight(.bold)
                                .monospacedDigit())
                            .contentTransition(.numericText())
                            .fixedSize()
                        Image(systemName: charging
                              ? "battery.100percent.bolt"
                              : (low ? "battery.25percent" : "battery.75percent"))
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(low ? .red : NotchTheme.battery)
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(charging ? "Charging" : "On battery")
                .accessibilityValue("\(percent) percent")
            case let .screenLock(locked):
                dropped {
                    droppedRow(
                        symbol: locked ? "lock.fill" : "lock.open.fill",
                        label: locked ? "Locked" : "Unlocked",
                        value: nil
                    )
                }
            case let .timer(remaining, progress):
                dropped {
                    VStack(spacing: 5) {
                        droppedRow(
                            symbol: "timer",
                            tint: .orange,
                            label: "Timer",
                            value: TimerManager.timeString(remaining)
                        )
                        DraggableProgressBar(
                            value: .constant(CGFloat(progress)),
                            tint: .orange,
                            inline: true
                        )
                    }
                }
            case let .focusMode(name, symbol):
                dropped {
                    droppedRow(symbol: symbol, tint: .purple, label: name, value: nil)
                }
            case let .eyeBreak(active):
                dropped {
                    droppedRow(
                        symbol: active ? "eye.fill" : "eye",
                        tint: .green,
                        label: active ? "Look 20 feet away" : "Eye break over",
                        value: nil
                    )
                }
            case .desktopChange:
                DesktopChangeActivityView(notchWidth: state.adjustedNotchSize.width)
            case let .accessoryBattery(name, symbol, percent):
                dropped {
                    droppedRow(
                        symbol: symbol,
                        tint: percent <= 20 ? .red : NotchTheme.battery,
                        label: name,
                        value: "\(percent)%"
                    )
                }
            case let .meetingSoon(title, start):
                TimelineView(.everyMinute) { context in
                    dropped {
                        droppedRow(
                            symbol: "calendar",
                            tint: .blue,
                            label: title,
                            value: Self.countdown(to: start, from: context.date)
                        )
                    }
                }
            case nil:
                if state.settings.showCompactWeather {
                    compactWeatherWing
                        .transition(NotchAnimations.activitySwap)
                } else {
                    Color.clear
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// "in 12m" / "now", for the meeting activity's trailing reading.
    private static func countdown(to start: Date, from now: Date) -> String {
        let minutes = Int(start.timeIntervalSince(now) / 60)
        if minutes <= 0 { return "now" }
        if minutes < 60 { return "in \(minutes)m" }
        return "in \(minutes / 60)h \(minutes % 60)m"
    }

    /// Wraps any activity content in the dropped form: the notch's own row
    /// keeps its weather wings, and the activity gets the full width beneath.
    private func dropped<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            notchRowFlank
                .frame(height: state.adjustedNotchSize.height)

            content()
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
        }
    }

    /// The shape every dropped activity uses: glyph, label, trailing reading.
    private func droppedRow(
        symbol: String,
        tint: Color = NotchTheme.inkPrimary,
        label: String,
        value: String?
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 20)

            Text(label)
                .font(.notchBody.weight(.bold))
                .foregroundStyle(NotchTheme.inkPrimary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            if let value {
                Text(value)
                    .font(.notchBody.weight(.bold).monospacedDigit())
                    .foregroundStyle(tint)
                    .contentTransition(.numericText())
                    .fixedSize()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value ?? "")
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
            // The notch's own row keeps whatever it was already wearing, so
            // the pill does not appear to lose it for the second the HUD is up.
            notchRowFlank
                .frame(height: state.adjustedNotchSize.height)

            DroppedHUDBar(
                kind: kind,
                value: value,
                showsPercentage: state.settings.showHUDPercentage
            )
            .frame(height: 34)
        }
    }

    /// What flanks the hardware notch on its own row while an activity is
    /// dropped beneath it. Media owns the wings whenever something is
    /// playing — cover on the left, visualiser on the right, and the weather
    /// stays out of the way until playback stops.
    @ViewBuilder
    private var notchRowFlank: some View {
        if state.media.hasTrack, state.settings.showMediaWings {
            musicWings
        } else if state.settings.showCompactWeather {
            weatherFlank
        } else {
            ActivityWingLayout(
                notchWidth: state.adjustedNotchSize.width,
                leading: Color.clear.frame(width: 1, height: 1),
                trailing: Color.clear.frame(width: 1, height: 1)
            )
        }
    }

    /// The weather glyph and temperature either side of the notch, shared by
    /// the idle pill and the dropped HUD.
    private var weatherFlank: some View {
        ActivityWingLayout(
            notchWidth: state.adjustedNotchSize.width,
            leading: weatherIcon,
            trailing: weatherTemperature
        )
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
                    .font(.notchHeadline.monospacedDigit())
                    .foregroundStyle(NotchTheme.inkPrimary)
                    .contentTransition(.numericText())
            } else {
                Text("--°")
                    .font(.notchHeadline)
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
            trailing: MusicVisualizerView(
                accent: state.media.accent,
                isPlaying: state.media.isPlaying,
                level: state.audio.isMuted ? 0 : state.audio.volume,
                bands: state.visualizerBands
            )
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
