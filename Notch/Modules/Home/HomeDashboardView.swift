import AppKit
import SwiftUI

/// The home dashboard: three quiet columns — music (artwork, metadata, and
/// transport), weather (conditions plus metrics), and calendar (week strip and
/// remaining items). Each column drills into its detail screen on click,
/// matching the reference layout.
struct HomeDashboardView: View {
    let state: NotchState
    let namespace: Namespace.ID

    var body: some View {
        // Weather and calendar take exactly the width their content needs
        // (fixedSize), so a wider weekday or temperature can never be forced
        // past a hard frame and clipped by the slab. Music absorbs the rest.
        HStack(alignment: .center, spacing: 24) {
            mediaPlayerSection
                .frame(maxWidth: .infinity, alignment: .leading)

            weatherWidget
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)

            calendarWidget
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // MARK: - Music

    private var mediaPlayerSection: some View {
        // Artwork on the left; title, album, artist and the transport row all
        // share the text column, so the controls sit under the metadata
        // rather than under the artwork.
        HStack(alignment: .top, spacing: 14) {
            artwork
                .contentShape(Rectangle())
                .onTapGesture { state.select(.media) }

            VStack(alignment: .leading, spacing: 3) {
                VStack(alignment: .leading, spacing: 3) {
                    MarqueeText(
                        text: state.media.track?.title ?? "Nothing Playing",
                        font: .system(size: 15, weight: .black, design: .rounded),
                        width: 200
                    )
                    .foregroundStyle(NotchTheme.inkPrimary)

                    Text(state.media.track?.album ?? "Unknown Album")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(NotchTheme.inkPrimary.opacity(0.92))
                        .lineLimit(1)

                    Text(state.media.track?.artist ?? "Play music in Spotify or Apple Music")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(NotchTheme.inkSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { state.select(.media) }
                .help("Open the full player")

                HStack(spacing: 16) {
                    miniTransport("backward.fill", label: "Previous track") {
                        state.media.previousTrack()
                    }
                    playPauseButton
                    miniTransport("forward.fill", label: "Next track") {
                        state.media.nextTrack()
                    }
                }
                // Pull the first glyph out to the text's left edge, past the
                // button's own tap padding.
                .padding(.leading, -7)
                .padding(.top, 2)
            }
        }
    }

    private var artwork: some View {
        Group {
            if let image = state.media.artwork {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(NotchTheme.surface)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(NotchTheme.inkMuted)
                    }
            }
        }
        .frame(width: 58, height: 58)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .matchedGeometryEffect(id: "albumArt", in: namespace)
        .shadow(color: state.media.accent.opacity(0.45), radius: 10, y: 4)
        .overlay(alignment: .bottomLeading) {
            if let icon = state.media.sourceAppIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
                    .clipShape(Circle())
                    .overlay {
                        Circle().stroke(.black, lineWidth: 1.5)
                    }
                    .offset(x: -4, y: 4)
                    .help(state.media.sourceAppName ?? "")
                    .accessibilityLabel("Playing in \(state.media.sourceAppName ?? "another app")")
            }
        }
    }

    private var playPauseButton: some View {
        Button {
            state.media.togglePlayPause()
        } label: {
            Image(systemName: state.media.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(NotchTheme.inkPrimary)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .hoverLift(1.08)
        .disabled(!state.media.canControlTransport)
        .opacity(state.media.canControlTransport ? 1 : 0.4)
        .accessibilityLabel(state.media.isPlaying ? "Pause" : "Play")
    }

    private func miniTransport(
        _ systemImage: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(NotchTheme.inkPrimary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .modifier(HoverIconModifier())
        .disabled(!state.media.canControlTransport)
        .accessibilityLabel(label)
    }

    // MARK: - Weather

    private var weatherWidget: some View {
        Group {
            if let weather = state.weather.snapshot {
                // Icon beside a column of temperature / place / condition,
                // with the metric stack riding on the right.
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: WeatherService.symbol(
                        for: weather.weatherCode,
                        isDay: weather.isDay
                    ))
                    .font(.system(size: 30))
                    .symbolRenderingMode(.multicolor)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(WeatherService.temperatureString(celsius: weather.temperatureCelsius))
                            .font(.system(size: 30, weight: .heavy, design: .rounded).monospacedDigit())
                            .foregroundStyle(NotchTheme.inkPrimary)
                            .contentTransition(.numericText())

                        // Bounded so a long city name can't widen the whole
                        // column and squeeze the music section.
                        Text(state.weather.placeName ?? "Your Location")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundStyle(NotchTheme.inkPrimary.opacity(0.9))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: 116, alignment: .leading)

                        Text(WeatherService.condition(for: weather.weatherCode))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(NotchTheme.inkSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: 116, alignment: .leading)
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .leading, spacing: 4) {
                        metricRow("wind", text: WeatherService.windString(kmh: weather.windKmh))
                        metricRow("drop.fill", text: "\(weather.precipitationChancePercent)%")
                        metricRow("humidity", text: "\(weather.humidityPercent)%")
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
                HStack(spacing: 8) {
                    Image(systemName: weatherPlaceholderIcon)
                        .font(.system(size: 20))
                        .foregroundStyle(NotchTheme.inkMuted)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(weatherPlaceholderTitle)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(NotchTheme.inkSecondary)
                        if !state.settings.showWeather || state.weather.failureMessage != nil {
                            Text("Click to retry")
                                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                                .foregroundStyle(NotchTheme.inkMuted)
                        }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { state.select(.weather) }
                .help("Open the weather detail")
            }
        }
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

    private func metricRow(_ systemImage: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(NotchTheme.inkPrimary.opacity(0.85))
                .frame(width: 13)
            Text(text)
                .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(NotchTheme.inkPrimary)
        }
    }

    // MARK: - Calendar

    private var calendarWidget: some View {
        let today = Date()
        let strip = (-2 ... 2).compactMap { offset in
            Calendar.current.date(byAdding: .day, value: offset, to: today)
        }

        let remaining = state.calendar.items.first {
            !$0.isAllDay && $0.start > today
        }

        // Month beside the strip, with the next-item line spanning the full
        // column beneath so it has room to read without truncating.
        return VStack(alignment: .leading, spacing: 8) {
            monthAndStrip(today: today, strip: strip)

            HStack(spacing: 5) {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(NotchTheme.inkMuted)
                Text(remaining?.title ?? "No more items today")
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(NotchTheme.inkMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { state.select(.calendar) }
        .help("Open the calendar")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Calendar")
        .accessibilityValue(remaining?.title ?? "No more items today")
    }

    private func monthAndStrip(today: Date, strip: [Date]) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            Text(monthAbbreviation(Calendar.current.component(.month, from: today)))
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(NotchTheme.inkPrimary)
                .accessibilityHidden(true)

            HStack(alignment: .bottom, spacing: 7) {
                ForEach(Array(strip.enumerated()), id: \.offset) { _, day in
                    dayCell(day)
                }
            }
        }
    }

    /// Today is set in blue and spelled out ("FRI"); the surrounding days are
    /// single muted letters. No filled chip — the emphasis is typographic.
    private func dayCell(_ day: Date) -> some View {
        let calendar = Calendar.current
        let isToday = calendar.isDateInToday(day)

        return VStack(spacing: 0) {
            Text(isToday ? weekdayAbbreviation(for: day) : weekdayLetter(for: day))
                .font(.system(size: isToday ? 9 : 8, weight: .heavy, design: .rounded))
                .foregroundStyle(isToday ? .blue : weekdayColor(for: day).opacity(0.7))
            Text("\(calendar.component(.day, from: day))")
                .font(.system(
                    size: isToday ? 19 : 14,
                    weight: isToday ? .heavy : .semibold,
                    design: .rounded
                ).monospacedDigit())
                .foregroundStyle(isToday ? .blue : weekdayColor(for: day))
        }
        .frame(minWidth: isToday ? 27 : 17)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
        .accessibilityAddTraits(isToday ? [.isSelected] : [])
    }

    private func weekdayLetter(for day: Date) -> String {
        ["S", "M", "T", "W", "T", "F", "S"][Calendar.current.component(.weekday, from: day) - 1]
    }

    private func weekdayAbbreviation(for day: Date) -> String {
        day.formatted(.dateTime.weekday(.abbreviated)).uppercased()
    }

    /// Weekdays are neutral; only weekends pick up a warm tint. A colour per
    /// day read as noise rather than information.
    private func weekdayColor(for day: Date) -> Color {
        let weekday = Calendar.current.component(.weekday, from: day)
        let isWeekend = weekday == 1 || weekday == 7
        return isWeekend ? .red.opacity(0.75) : NotchTheme.inkSecondary
    }

    private func monthAbbreviation(_ month: Int) -> String {
        ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][month - 1]
    }
}
