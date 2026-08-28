import AppKit
import SwiftUI

/// The default expanded view (modeled on the reference dashboard): now
/// playing, weather, and the next event side by side. Each widget is a
/// tap-target that jumps to its full tab.
struct HomeDashboardView: View {
    let state: NotchState
    let namespace: Namespace.ID

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            widgetButton(tab: .media) {
                mediaWidget
            }
            .frame(maxWidth: .infinity)

            widgetDivider

            weatherWidget
                .frame(width: 176)

            widgetDivider

            widgetButton(tab: .calendar) {
                calendarWidget
            }
            .frame(width: 148)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var widgetDivider: some View {
        Rectangle()
            .fill(NotchTheme.hairline)
            .frame(width: 1)
            .padding(.vertical, 16)
    }

    private func widgetButton(tab: NotchTab, @ViewBuilder content: () -> some View) -> some View {
        Button {
            state.select(tab)
        } label: {
            content()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the \(tab.title) tab")
    }

    // MARK: - Now playing

    private var mediaWidget: some View {
        HStack(spacing: 12) {
            Group {
                if let artwork = state.media.artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(NotchTheme.surface)
                        .overlay {
                            Image(systemName: "music.note")
                                .font(.system(size: 20))
                                .foregroundStyle(NotchTheme.inkMuted)
                        }
                }
            }
            // No matchedGeometryEffect here: the collapsed↔media pairing must
            // keep a single source per id during tab transitions.
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.4), radius: 7, y: 3)

            VStack(alignment: .leading, spacing: 4) {
                Text(state.media.track?.title ?? "Nothing Playing")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(NotchTheme.inkPrimary)
                    .lineLimit(1)
                Text(state.media.track?.artist ?? "Open Media for controls")
                    .font(.system(size: 11))
                    .foregroundStyle(NotchTheme.inkSecondary)
                    .lineLimit(1)

                HStack(spacing: 18) {
                    miniTransport("backward.fill", label: "Previous track") {
                        state.media.previousTrack()
                    }
                    miniTransport(
                        state.media.isPlaying ? "pause.fill" : "play.fill",
                        label: state.media.isPlaying ? "Pause" : "Play"
                    ) {
                        state.media.togglePlayPause()
                    }
                    miniTransport("forward.fill", label: "Next track") {
                        state.media.nextTrack()
                    }
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func miniTransport(
        _ systemImage: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(state.media.hasTrack ? NotchTheme.inkPrimary : NotchTheme.inkMuted)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!state.media.hasTrack)
        .accessibilityLabel(label)
    }

    // MARK: - Weather

    @ViewBuilder
    private var weatherWidget: some View {
        if let weather = state.weather.snapshot {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: WeatherService.symbol(
                            for: weather.weatherCode,
                            isDay: weather.isDay
                        ))
                        .font(.system(size: 17))
                        .symbolRenderingMode(.multicolor)

                        Text(WeatherService.temperatureString(celsius: weather.temperatureCelsius))
                            .font(.system(size: 26, weight: .bold).monospacedDigit())
                            .foregroundStyle(NotchTheme.inkPrimary)
                            .contentTransition(.numericText())
                    }
                    if let place = state.weather.placeName {
                        Text(place)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(NotchTheme.inkPrimary.opacity(0.85))
                            .lineLimit(1)
                    }
                    Text(WeatherService.condition(for: weather.weatherCode))
                        .font(.system(size: 10))
                        .foregroundStyle(NotchTheme.inkSecondary)
                        .lineLimit(1)
                }

                VStack(alignment: .leading, spacing: 5) {
                    weatherStat("wind", WeatherService.windString(kmh: weather.windKmh))
                    weatherStat("drop.fill", "\(weather.precipitationChancePercent)%")
                    weatherStat("humidity.fill", "\(weather.humidityPercent)%")
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Weather")
            .accessibilityValue(
                "\(WeatherService.temperatureString(celsius: weather.temperatureCelsius)), "
                + WeatherService.condition(for: weather.weatherCode)
            )
        } else {
            VStack(spacing: 4) {
                Image(systemName: "cloud.sun")
                    .font(.system(size: 18))
                    .foregroundStyle(NotchTheme.inkMuted)
                Text(state.settings.showWeather ? "Weather loading…" : "Weather off")
                    .font(.system(size: 10))
                    .foregroundStyle(NotchTheme.inkMuted)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func weatherStat(_ icon: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 8.5))
                .foregroundStyle(NotchTheme.inkSecondary)
                .frame(width: 11)
            Text(value)
                .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(NotchTheme.inkPrimary.opacity(0.9))
        }
    }

    // MARK: - Next event

    private var calendarWidget: some View {
        let next = state.calendar.items.first { !$0.isAllDay && $0.end > Date() }

        return VStack(alignment: .leading, spacing: 3) {
            Text(Date().formatted(.dateTime.weekday(.abbreviated)).uppercased())
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(.red)
            Text(Date().formatted(.dateTime.day()))
                .font(.system(size: 24, weight: .bold).monospacedDigit())
                .foregroundStyle(NotchTheme.inkPrimary)

            if let next {
                Text(next.title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(NotchTheme.inkPrimary.opacity(0.9))
                    .lineLimit(1)
                Text(next.start.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 9.5).monospacedDigit())
                    .foregroundStyle(NotchTheme.inkSecondary)
            } else {
                Text("No events scheduled")
                    .font(.system(size: 10))
                    .foregroundStyle(NotchTheme.inkMuted)
                    .padding(.top, 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
