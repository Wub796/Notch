import AppKit
import SwiftUI

/// The home dashboard: three quiet columns — music (artwork, metadata,
/// transport and a live scrubber), weather (conditions, place, high/low), and
/// calendar (month, week strip and what's next). Each column drills into its
/// detail screen on click.
///
/// Budget: `NotchState.moduleContentSize`, about 698 x 160 at the default
/// panel size. The music column is the tallest at roughly 100pt, and weather
/// and calendar take only the width their content needs so a long city name
/// or a wide weekday can never be forced past a hard frame.
struct HomeDashboardView: View {
    let state: NotchState
    let namespace: Namespace.ID

    var body: some View {
        // Weather and calendar take exactly the width their content needs
        // (fixedSize), so a wider weekday or temperature can never be forced
        // past a hard frame and clipped by the slab. Music absorbs the rest.
        HStack(alignment: .center, spacing: 20) {
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
        // Artwork on the left; title, artist, the transport row and the
        // scrubber all share the text column, so the controls sit under the
        // metadata rather than under the artwork.
        HStack(alignment: .top, spacing: 12) {
            artwork
                .contentShape(Rectangle())
                .onTapGesture { state.select(.media) }

            VStack(alignment: .leading, spacing: 3) {
                // Title and artist only — the album line was a third string
                // competing for the same glance.
                MarqueeText(
                    text: state.media.track?.title ?? "Nothing Playing",
                    font: .system(size: 17, weight: .black, design: .rounded),
                    width: 180
                )
                .foregroundStyle(NotchTheme.inkPrimary)

                Text(state.media.track?.artist ?? "Nothing is playing")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(NotchTheme.inkSecondary)
                    .lineLimit(1)

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

                scrubber
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { state.select(.media) }
            .help("Open the full player")
        }
    }

    /// A hairline position bar with elapsed and remaining times. Read-only
    /// here — dragging to seek lives in the full player, where the bar is big
    /// enough to hit reliably.
    @ViewBuilder
    private var scrubber: some View {
        if let track = state.media.track, track.duration > 1 {
            let elapsed = min(max(state.media.displayedElapsed, 0), track.duration)
            let progress = elapsed / track.duration

            HStack(spacing: 8) {
                Text(Self.timeString(elapsed))
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(NotchTheme.inkMuted)

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.16))
                        Capsule()
                            .fill(state.media.accent)
                            .frame(width: max(proxy.size.width * progress, 2))
                    }
                    .frame(height: 3)
                    .frame(maxHeight: .infinity, alignment: .center)
                }
                .frame(height: 10)

                Text("-" + Self.timeString(track.duration - elapsed))
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(NotchTheme.inkMuted)
            }
            .padding(.trailing, 6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Playback position")
            .accessibilityValue(Self.timeString(elapsed) + " of " + Self.timeString(track.duration))
        } else {
            // Hold the row's height so the column doesn't jump when a track
            // arrives or its duration is unknown.
            Color.clear.frame(height: 10)
        }
    }

    private static func timeString(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
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
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(NotchTheme.inkMuted)
                    }
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: WeatherService.symbol(
                        for: weather.weatherCode,
                        isDay: weather.isDay
                    ))
                    .font(.system(size: 32))
                    .symbolRenderingMode(.multicolor)

                    VStack(alignment: .leading, spacing: -1) {
                        Text(WeatherService.temperatureString(celsius: weather.temperatureCelsius))
                            .font(.system(size: 32, weight: .heavy, design: .rounded).monospacedDigit())
                            .foregroundStyle(NotchTheme.inkPrimary)
                            .contentTransition(.numericText())

                        Text(state.weather.placeName ?? "Your Location")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(NotchTheme.inkSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: 112, alignment: .leading)

                        Text("H " + WeatherService.temperatureString(celsius: weather.highCelsius)
                             + "   L " + WeatherService.temperatureString(celsius: weather.lowCelsius))
                            .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(NotchTheme.inkMuted)
                            .padding(.top, 2)
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
                HStack(spacing: 10) {
                    Image(systemName: weatherPlaceholderIcon)
                        .font(.system(size: 24))
                        .foregroundStyle(NotchTheme.inkMuted)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(weatherPlaceholderTitle)
                            .font(.system(size: 12.5, weight: .bold, design: .rounded))
                            .foregroundStyle(NotchTheme.inkSecondary)
                        if !state.settings.showWeather || state.weather.failureMessage != nil {
                            Text("Click to retry")
                                .font(.system(size: 10.5, weight: .medium, design: .rounded))
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
        let next = state.calendar.items.first { !$0.isAllDay && $0.start > today }

        return VStack(alignment: .leading, spacing: 4) {
            monthAndStrip(today: today, strip: strip)
            nextEventLine(next)
        }
        .contentShape(Rectangle())
        .onTapGesture { state.select(.calendar) }
        .help("Open the calendar")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Calendar")
        .accessibilityValue(next?.title ?? "Nothing left today")
    }

    /// One line for what is next, so the dashboard answers "am I free?"
    /// without opening the calendar screen.
    @ViewBuilder
    private func nextEventLine(_ event: CalendarController.ScheduleItem?) -> some View {
        if let event {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(cgColor: event.calendarColor ?? .init(gray: 0.7, alpha: 1)))
                    .frame(width: 6, height: 6)
                Text(event.start.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 11, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(NotchTheme.inkPrimary)
                Text(event.title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(NotchTheme.inkSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 128, alignment: .leading)
            }
        } else {
            Text(state.calendar.accessState == .granted
                 ? "Nothing left today"
                 : "Calendar access off")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(NotchTheme.inkMuted)
        }
    }

    private func monthAndStrip(today: Date, strip: [Date]) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            Text(monthAbbreviation(Calendar.current.component(.month, from: today)))
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(NotchTheme.inkPrimary)
                .accessibilityHidden(true)

            HStack(alignment: .bottom, spacing: 5) {
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
                    size: isToday ? 20 : 16,
                    weight: isToday ? .heavy : .semibold,
                    design: .rounded
                ).monospacedDigit())
                .foregroundStyle(isToday ? .blue : weekdayColor(for: day))
        }
        .frame(minWidth: isToday ? 30 : 19)
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
