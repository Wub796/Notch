import AppKit
import SwiftUI

/// The default slab: now playing on the left (with the app it's coming
/// from), weather in the middle, the day and next event on the right. One
/// continuous surface — no dividers, no boxes.
struct HomeDashboardView: View {
    let state: NotchState
    let namespace: Namespace.ID

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            mediaWidget
                .frame(maxWidth: .infinity, alignment: .leading)

            weatherWidget
                .frame(width: 168, alignment: .leading)

            calendarWidget
                .frame(width: 132, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Now playing

    private var mediaWidget: some View {
        HStack(spacing: 11) {
            artwork

            VStack(alignment: .leading, spacing: 2) {
                MarqueeText(
                    text: state.media.track?.title ?? "Nothing Playing",
                    font: .system(size: 12.5, weight: .semibold),
                    width: 200
                )
                .foregroundStyle(NotchTheme.inkPrimary)

                Text(state.media.track?.artist ?? "Play something to see it here")
                    .font(.system(size: 10.5))
                    .foregroundStyle(NotchTheme.inkSecondary)
                    .lineLimit(1)

                HStack(spacing: 16) {
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
                .padding(.top, 3)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { state.select(.media) }
        .accessibilityHint("Double-click to open the Media tab")
    }

    private var artwork: some View {
        Group {
            if let image = state.media.artwork {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(NotchTheme.surface)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 17))
                            .foregroundStyle(NotchTheme.inkMuted)
                    }
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.45), radius: 7, y: 3)
        // The source app badges the artwork, as in the reference.
        .overlay(alignment: .bottomLeading) {
            if let icon = state.media.sourceAppIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
                    .clipShape(Circle())
                    .overlay {
                        Circle().stroke(.black.opacity(0.55), lineWidth: 1.5)
                    }
                    .offset(x: -5, y: 5)
                    .help(state.media.sourceAppName ?? "")
                    .accessibilityLabel("Playing in \(state.media.sourceAppName ?? "another app")")
            }
        }
    }

    private func miniTransport(
        _ systemImage: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(state.media.hasTrack ? NotchTheme.inkPrimary : NotchTheme.inkMuted)
                .frame(width: 20, height: 20)
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
                Image(systemName: WeatherService.symbol(
                    for: weather.weatherCode,
                    isDay: weather.isDay
                ))
                .font(.system(size: 26))
                .symbolRenderingMode(.multicolor)

                VStack(alignment: .leading, spacing: 1) {
                    // temperatureWithoutUnit already carries the degree sign.
                    Text(WeatherService.temperatureString(celsius: weather.temperatureCelsius))
                        .font(.system(size: 25, weight: .bold).monospacedDigit())
                        .foregroundStyle(NotchTheme.inkPrimary)
                        .contentTransition(.numericText())

                    if let place = state.weather.placeName {
                        Text(place)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(NotchTheme.inkPrimary.opacity(0.85))
                            .lineLimit(1)
                    }

                    Text(WeatherService.condition(for: weather.weatherCode))
                        .font(.system(size: 10))
                        .foregroundStyle(NotchTheme.inkSecondary)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Weather")
            .accessibilityValue(
                WeatherService.temperatureString(celsius: weather.temperatureCelsius) + ", "
                + WeatherService.condition(for: weather.weatherCode)
                + (state.weather.placeName.map { ", \($0)" } ?? "")
            )
        } else {
            HStack(spacing: 9) {
                Image(systemName: "cloud.sun")
                    .font(.system(size: 22))
                    .foregroundStyle(NotchTheme.inkMuted)
                Text(state.settings.showWeather ? "Weather\nloading…" : "Weather off")
                    .font(.system(size: 10.5))
                    .foregroundStyle(NotchTheme.inkMuted)
            }
        }
    }

    // MARK: - Day and next event

    private var calendarWidget: some View {
        let next = state.calendar.items.first { !$0.isAllDay && $0.end > Date() }

        return HStack(spacing: 11) {
            VStack(spacing: -2) {
                Text(Date().formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(.red)
                Text(Date().formatted(.dateTime.day()))
                    .font(.system(size: 25, weight: .bold).monospacedDigit())
                    .foregroundStyle(NotchTheme.inkPrimary)
            }

            if let next {
                VStack(alignment: .leading, spacing: 1) {
                    Text(next.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(NotchTheme.inkPrimary.opacity(0.9))
                        .lineLimit(2)
                    Text(next.start.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(NotchTheme.inkSecondary)
                }
            } else {
                Text("No events\nscheduled")
                    .font(.system(size: 10.5))
                    .foregroundStyle(NotchTheme.inkMuted)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { state.select(.calendar) }
        .accessibilityHint("Double-click to open the Schedule tab")
    }
}
