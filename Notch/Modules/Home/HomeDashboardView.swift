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
        HStack(alignment: .center, spacing: 26) {
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

            VStack(alignment: .leading, spacing: 5) {
                // Title and artist only — the album line was a third string
                // competing for the same glance.
                VStack(alignment: .leading, spacing: 2) {
                    MarqueeText(
                        text: state.media.track?.title ?? "Nothing Playing",
                        font: .system(size: 18, weight: .black, design: .rounded),
                        width: 210
                    )
                    .foregroundStyle(NotchTheme.inkPrimary)

                    Text(state.media.track?.artist ?? "Nothing is playing")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
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
        .frame(width: 66, height: 66)
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
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(NotchTheme.inkPrimary)
                .frame(width: 32, height: 32)
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
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(NotchTheme.inkPrimary)
                .frame(width: 30, height: 30)
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
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: WeatherService.symbol(
                        for: weather.weatherCode,
                        isDay: weather.isDay
                    ))
                    .font(.system(size: 38))
                    .symbolRenderingMode(.multicolor)

                    VStack(alignment: .leading, spacing: -2) {
                        Text(WeatherService.temperatureString(celsius: weather.temperatureCelsius))
                            .font(.system(size: 38, weight: .heavy, design: .rounded).monospacedDigit())
                            .foregroundStyle(NotchTheme.inkPrimary)
                            .contentTransition(.numericText())

                        Text(state.weather.placeName ?? "Your Location")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(NotchTheme.inkSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: 130, alignment: .leading)
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


    // MARK: - Calendar

    private var calendarWidget: some View {
        let today = Date()
        let strip = (-2 ... 2).compactMap { offset in
            Calendar.current.date(byAdding: .day, value: offset, to: today)
        }

        let remaining = state.calendar.items.first {
            !$0.isAllDay && $0.start > today
        }

        // Month and the day strip only; the next-event line moved to the
        // Calendar screen where there is room to read it.
        return monthAndStrip(today: today, strip: strip)
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
                .font(.system(size: 28, weight: .heavy, design: .rounded))
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
                .font(.system(size: isToday ? 11 : 10, weight: .heavy, design: .rounded))
                .foregroundStyle(isToday ? .blue : weekdayColor(for: day).opacity(0.7))
            Text("\(calendar.component(.day, from: day))")
                .font(.system(
                    size: isToday ? 23 : 18,
                    weight: isToday ? .heavy : .semibold,
                    design: .rounded
                ).monospacedDigit())
                .foregroundStyle(isToday ? .blue : weekdayColor(for: day))
        }
        .frame(minWidth: isToday ? 32 : 22)
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
