import AppKit
import SwiftUI

/// The home dashboard, laid out to match the Sapphire reference: artwork and
/// player on the left, weather in the middle with its metric column, calendar
/// on the right over a single "what's next" line.
///
/// Budget: `NotchState.moduleContentSize`, about 818 x 140 at the default
/// panel size. The artwork column is the tallest at 104.
struct HomeDashboardView: View {
    let state: NotchState
    let namespace: Namespace.ID

    var body: some View {
        HStack(alignment: .center, spacing: 30) {
            musicSection
            weatherSection
            calendarSection
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // MARK: - Music

    private var musicSection: some View {
        HStack(alignment: .center, spacing: 20) {
            artwork
                .contentShape(Rectangle())
                .onTapGesture { state.select(.media) }

            VStack(alignment: .leading, spacing: 2) {
                // Uppercase and letterspaced, as in the reference: the title is
                // the loudest thing on the panel.
                Text((state.media.track?.title ?? "Nothing Playing").uppercased())
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .tracking(3.5)
                    .foregroundStyle(NotchTheme.inkPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 260, alignment: .leading)

                Text(state.media.track?.artist ?? "Nothing is playing")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(NotchTheme.inkSecondary)
                    .lineLimit(1)

                // Transport sits centred under the text block rather than
                // flush left, which is what makes the column read as one unit.
                HStack(spacing: 22) {
                    transportButton("backward.fill", size: 16, label: "Previous track") {
                        state.media.previousTrack()
                    }
                    transportButton(
                        state.media.isPlaying ? "pause.fill" : "play.fill",
                        size: 20,
                        label: state.media.isPlaying ? "Pause" : "Play"
                    ) {
                        state.media.togglePlayPause()
                    }
                    transportButton("forward.fill", size: 16, label: "Next track") {
                        state.media.nextTrack()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 8)
            }
            .fixedSize(horizontal: true, vertical: false)
            .contentShape(Rectangle())
            .onTapGesture { state.select(.media) }
            .help("Open the full player")
        }
    }

    private var artwork: some View {
        Group {
            if let image = state.media.artwork {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(NotchTheme.surface)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 30, weight: .medium))
                            .foregroundStyle(NotchTheme.inkMuted)
                    }
            }
        }
        .frame(width: 104, height: 104)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .matchedGeometryEffect(id: "albumArt", in: namespace)
        // The reference rings the art in its own accent rather than dropping a
        // shadow behind it, which is what gives it the lit-from-within look.
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(state.media.accent.opacity(0.55), lineWidth: 2.5)
        }
        .shadow(color: state.media.accent.opacity(0.5), radius: 14)
        .overlay(alignment: .bottomTrailing) {
            if let icon = state.media.sourceAppIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 20, height: 20)
                    .clipShape(Circle())
                    .overlay { Circle().stroke(.black, lineWidth: 1.5) }
                    .offset(x: 4, y: 4)
                    .help(state.media.sourceAppName ?? "")
                    .accessibilityLabel("Playing in \(state.media.sourceAppName ?? "another app")")
            }
        }
    }

    private func transportButton(
        _ systemImage: String,
        size: CGFloat,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(NotchTheme.inkPrimary)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .modifier(HoverIconModifier())
        .disabled(!state.media.canControlTransport)
        .opacity(state.media.canControlTransport ? 1 : 0.4)
        .accessibilityLabel(label)
    }

    // MARK: - Weather

    @ViewBuilder
    private var weatherSection: some View {
        if let weather = state.weather.snapshot {
            HStack(alignment: .center, spacing: 18) {
                Image(systemName: WeatherService.symbol(
                    for: weather.weatherCode,
                    isDay: weather.isDay
                ))
                .font(.system(size: 42))
                .symbolRenderingMode(.multicolor)

                VStack(alignment: .leading, spacing: 0) {
                    Text(WeatherService.temperatureString(celsius: weather.temperatureCelsius))
                        .font(.system(size: 44, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundStyle(NotchTheme.inkPrimary)
                        .contentTransition(.numericText())

                    Text(state.weather.placeName ?? "Your Location")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(NotchTheme.inkPrimary)
                        .lineLimit(1)

                    Text(WeatherService.condition(for: weather.weatherCode))
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(NotchTheme.inkSecondary)
                        .lineLimit(1)
                }

                VStack(alignment: .leading, spacing: 7) {
                    metric("wind", WeatherService.windString(kmh: weather.windKmh))
                    metric("drop.fill", "\(weather.precipitationChancePercent)%")
                    metric("humidity.fill", "\(weather.humidityPercent)%")
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { state.select(.weather) }
            .help("Open the weather detail")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Weather")
            .accessibilityValue(
                WeatherService.temperatureString(celsius: weather.temperatureCelsius)
                + ", " + WeatherService.condition(for: weather.weatherCode)
            )
        } else {
            weatherPlaceholder
        }
    }

    private func metric(_ systemImage: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 13))
                .symbolRenderingMode(.multicolor)
                .frame(width: 18)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(NotchTheme.inkPrimary)
        }
        .accessibilityElement(children: .combine)
    }

    private var weatherPlaceholder: some View {
        HStack(spacing: 12) {
            Image(systemName: weatherPlaceholderIcon)
                .font(.system(size: 30))
                .foregroundStyle(NotchTheme.inkMuted)
            VStack(alignment: .leading, spacing: 2) {
                Text(weatherPlaceholderTitle)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(NotchTheme.inkSecondary)
                if !state.settings.showWeather || state.weather.failureMessage != nil {
                    Text("Click to retry")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(NotchTheme.inkMuted)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { state.select(.weather) }
        .help("Open the weather detail")
    }

    private var weatherPlaceholderIcon: String {
        if !state.settings.showWeather { return "cloud.slash" }
        return state.weather.failureMessage == nil ? "cloud.sun.fill" : "exclamationmark.icloud"
    }

    private var weatherPlaceholderTitle: String {
        if !state.settings.showWeather { return "Weather off" }
        if let failure = state.weather.failureMessage { return failure }
        return "Getting weather…"
    }

    // MARK: - Calendar

    private var calendarSection: some View {
        let today = Date()
        let strip = (-2 ... 2).compactMap {
            Calendar.current.date(byAdding: .day, value: $0, to: today)
        }
        let next = state.calendar.items.first {
            !$0.isAllDay && $0.start > today && Calendar.current.isDateInToday($0.start)
        }

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 16) {
                Text(today.formatted(.dateTime.month(.abbreviated)))
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundStyle(NotchTheme.inkPrimary)
                    .accessibilityHidden(true)

                HStack(alignment: .center, spacing: 8) {
                    ForEach(Array(strip.enumerated()), id: \.offset) { _, day in
                        dayCell(day)
                    }
                }
            }

            nextEventLine(next)
        }
        .contentShape(Rectangle())
        .onTapGesture { state.select(.calendar) }
        .help("Open the calendar")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Calendar")
        .accessibilityValue(next?.title ?? "Nothing left today")
    }

    /// Today is spelled out ("SAT") in blue over a large blue number; the days
    /// either side fade with distance, which is what gives the strip its
    /// centre of gravity in the reference.
    private func dayCell(_ day: Date) -> some View {
        let calendar = Calendar.current
        let isToday = calendar.isDateInToday(day)
        let distance = abs(calendar.dateComponents([.day], from: Date(), to: day).day ?? 0)
        let fade = 1.0 - Double(distance) * 0.28

        return VStack(spacing: -1) {
            Text(isToday
                 ? day.formatted(.dateTime.weekday(.abbreviated)).uppercased()
                 : String(day.formatted(.dateTime.weekday(.narrow)).prefix(1)).uppercased())
                .font(.system(size: isToday ? 13 : 11, weight: .heavy, design: .rounded))
                .foregroundStyle(isToday ? .blue : NotchTheme.inkSecondary.opacity(fade))

            Text("\(calendar.component(.day, from: day))")
                .font(.system(
                    size: isToday ? 26 : 19,
                    weight: isToday ? .heavy : .bold,
                    design: .rounded
                ).monospacedDigit())
                .foregroundStyle(isToday ? .blue : NotchTheme.inkPrimary.opacity(fade))
        }
        .frame(minWidth: isToday ? 38 : 24)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
        .accessibilityAddTraits(isToday ? [.isSelected] : [])
    }

    @ViewBuilder
    private func nextEventLine(_ event: CalendarController.ScheduleItem?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: event == nil ? "calendar.badge.checkmark" : "calendar")
                .font(.system(size: 14))
                .foregroundStyle(NotchTheme.inkSecondary)

            if let event {
                Text(event.start.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 14, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(NotchTheme.inkPrimary)
                Text(event.title)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(NotchTheme.inkSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 190, alignment: .leading)
            } else {
                Text(state.calendar.accessState == .granted
                     ? "No more items today"
                     : "Calendar access off")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(NotchTheme.inkSecondary)
            }
        }
    }
}
