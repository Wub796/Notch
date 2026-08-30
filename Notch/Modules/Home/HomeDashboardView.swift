import AppKit
import SwiftUI

/// The home dashboard, laid out to match the Sapphire reference: artwork and
/// player on the left, weather in the middle with its metric column, calendar
/// on the right over a single "what's next" line.
///
/// Budget: `NotchState.moduleContentSize`, about 838 x 122 at the default
/// panel size, and it has to be respected: the three columns are `fixedSize`,
/// so asking for more than the panel has does not clip, it *compresses* — and
/// a Text squeezed below its natural width wraps, which is what stacked the
/// calendar's day numbers one digit above another.
struct HomeDashboardView: View {
    let state: NotchState
    let namespace: Namespace.ID

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            musicSection
            Spacer(minLength: 20)
            weatherSection
            Spacer(minLength: 20)
            calendarSection
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // MARK: - Music

    private var activeAudioApp: AudioAppMonitor.App? {
        state.audioApps.apps.first(where: \.isPlaying)
    }

    private var displayTitle: String {
        if let title = state.media.track?.title, !title.isEmpty {
            return title
        }
        if let active = activeAudioApp {
            return active.name
        }
        return "Nothing Playing"
    }

    private var displayArtist: String {
        if let artist = state.media.track?.artist, !artist.isEmpty {
            return artist
        }
        if activeAudioApp != nil {
            return "Active Audio"
        }
        return "Nothing is playing"
    }

    private var isAudioActive: Bool {
        state.media.isPlaying || activeAudioApp != nil
    }

    private var musicSection: some View {
        HStack(alignment: .center, spacing: 16) {
            artwork
                .contentShape(Rectangle())
                .onTapGesture { state.select(.media) }

            VStack(alignment: .leading, spacing: 2) {
                // Uppercase and letterspaced, as in the reference: the title is
                // the loudest thing on the panel.
                Text(displayTitle.uppercased())
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .tracking(2.0)
                    .foregroundStyle(NotchTheme.inkPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 220, alignment: .leading)

                HStack(spacing: 5) {
                    Text(displayArtist)
                        .font(.system(size: 13.5, weight: .medium, design: .rounded))
                        .foregroundStyle(NotchTheme.inkSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 220, alignment: .leading)

                    if isAudioActive {
                        Image(systemName: "waveform")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.green)
                            .symbolEffect(.variableColor.iterative, options: .repeating)
                    }
                }

                // Transport sits centred under the text block rather than
                // flush left, which is what makes the column read as one unit.
                HStack(spacing: 18) {
                    transportButton("backward.fill", size: 15, label: "Previous track") {
                        state.media.previousTrack()
                    }
                    transportButton(
                        state.media.isPlaying ? "pause.fill" : "play.fill",
                        size: 18,
                        label: state.media.isPlaying ? "Pause" : "Play"
                    ) {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
                            state.media.togglePlayPause()
                        }
                    }
                    transportButton("forward.fill", size: 15, label: "Next track") {
                        state.media.nextTrack()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 4)
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
            } else if let icon = state.media.sourceAppIcon ?? activeAudioApp?.icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(14)
                    .background(Color.white.opacity(0.08))
            } else {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 26, weight: .medium))
                            .foregroundStyle(NotchTheme.inkMuted)
                    }
            }
        }
        .frame(width: 88, height: 88)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .matchedGeometryEffect(id: "albumArt", in: namespace)
        .shadow(color: state.media.accent.opacity(0.38), radius: 12, y: 4)
        .overlay(alignment: .bottomTrailing) {
            if let icon = state.media.sourceAppIcon ?? (state.media.artwork != nil ? activeAudioApp?.icon : nil) {
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
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.white.opacity(0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .modifier(HoverIconModifier())
        .disabled(!state.media.canControlTransport)
        .opacity(state.media.canControlTransport ? 1 : 0.4)
        .contentTransition(.symbolEffect(.replace))
        .accessibilityLabel(label)
    }

    // MARK: - Weather

    @ViewBuilder
    private var weatherSection: some View {
        if let weather = state.weather.snapshot {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: WeatherService.symbol(
                    for: weather.weatherCode,
                    isDay: weather.isDay
                ))
                .font(.system(size: 36))
                .symbolRenderingMode(.multicolor)

                VStack(alignment: .leading, spacing: 0) {
                    Text(WeatherService.temperatureString(celsius: weather.temperatureCelsius))
                        .font(.system(size: 38, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundStyle(NotchTheme.inkPrimary)
                        .contentTransition(.numericText())

                    Text(state.weather.placeName ?? "Your Location")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(NotchTheme.inkPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 120, alignment: .leading)

                    Text(WeatherService.condition(for: weather.weatherCode))
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(NotchTheme.inkSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 120, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 5) {
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
        .fixedSize()
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

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                Text(today.formatted(.dateTime.month(.abbreviated)))
                    .font(.system(size: 27, weight: .heavy, design: .rounded))
                    .fixedSize()
                    .foregroundStyle(NotchTheme.inkPrimary)
                    .accessibilityHidden(true)

                HStack(alignment: .center, spacing: 6) {
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
                .font(.system(size: isToday ? 12 : 10, weight: .heavy, design: .rounded))
                .fixedSize()
                .foregroundStyle(isToday ? .blue : NotchTheme.inkSecondary.opacity(fade))

            Text("\(calendar.component(.day, from: day))")
                .font(.system(
                    size: isToday ? 22 : 17,
                    weight: isToday ? .heavy : .bold,
                    design: .rounded
                ).monospacedDigit())
                // Without this a squeezed column wraps "27" into a 2 above a 7.
                .fixedSize()
                .foregroundStyle(isToday ? .blue : NotchTheme.inkPrimary.opacity(fade))
        }
        .frame(minWidth: isToday ? 32 : 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
        .accessibilityAddTraits(isToday ? [.isSelected] : [])
    }

    @ViewBuilder
    private func nextEventLine(_ event: CalendarController.ScheduleItem?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: event == nil ? "calendar.badge.checkmark" : "calendar")
                .font(.system(size: 13))
                .foregroundStyle(NotchTheme.inkSecondary)
                .fixedSize()

            if let event {
                Text(event.start.formatted(date: .omitted, time: .shortened))
                    .font(.notchBody.weight(.heavy).monospacedDigit())
                    .foregroundStyle(NotchTheme.inkPrimary)
                    .fixedSize()
                Text(event.title)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(NotchTheme.inkSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 180, alignment: .leading)
            } else {
                Text(state.calendar.accessState == .granted
                     ? "No more items today"
                     : "Calendar access off")
                    .font(.notchBody.weight(.medium))
                    .fixedSize()
                    .foregroundStyle(NotchTheme.inkSecondary)
            }
        }
    }
}
