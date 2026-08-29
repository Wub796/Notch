import SwiftUI

/// Full weather detail: a hero band (illustration, temperature, place and a
/// six-cell metric grid), then hourly and five-day forecast strips.
///
/// Every tab now shares one open panel (as in boring.notch and Atoll), which
/// at the default size leaves about 160pt for a module. Hero 72 + one 70pt
/// strip + a 12pt gap fits that, so the hourly and five-day forecasts share
/// the strip and a segmented control swaps between them rather than stacking
/// and overrunning the slab.
struct WeatherDetailView: View {
    let state: NotchState

    @State private var showsDaily = false

    var body: some View {
        Group {
            if let weather = state.weather.snapshot {
                VStack(alignment: .leading, spacing: 10) {
                    hero(weather)
                    forecastSwitcher
                    if showsDaily {
                        dailyStrip(weather)
                    } else {
                        hourlyStrip(weather)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                unavailable
            }
        }
        .onAppear {
            state.weather.refresh()
        }
    }

    // MARK: - Empty state

    private var unavailable: some View {
        VStack(spacing: 10) {
            Image(systemName: state.weather.isLoading ? "cloud.sun.fill" : "exclamationmark.icloud")
                .font(.system(size: 38))
                .foregroundStyle(NotchTheme.inkMuted)
                .symbolEffect(.pulse, isActive: state.weather.isLoading)

            Text(emptyStateTitle)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(NotchTheme.inkSecondary)

            if state.settings.showWeather, !state.weather.isLoading {
                Button("Try Again") {
                    state.weather.refresh(force: true)
                }
                .buttonStyle(PressableButtonStyle())
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.blue)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateTitle: String {
        if !state.settings.showWeather { return "Weather is off" }
        if state.weather.isLoading { return "Getting weather…" }
        return state.weather.failureMessage ?? "Weather unavailable"
    }

    /// Two flat chips rather than a segmented picker: the picker's chrome
    /// reads as a form control in a panel that has none.
    private var forecastSwitcher: some View {
        HStack(spacing: 6) {
            forecastTab("Hourly", isActive: !showsDaily) { showsDaily = false }
            forecastTab("5 Days", isActive: showsDaily) { showsDaily = true }
            Spacer(minLength: 0)
        }
    }

    private func forecastTab(
        _ title: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(isActive ? NotchTheme.inkPrimary : NotchTheme.inkMuted)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(Capsule().fill(.white.opacity(isActive ? 0.14 : 0)))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    // MARK: - Hero

    private func hero(_ weather: WeatherService.Snapshot) -> some View {
        HStack(alignment: .center, spacing: 22) {
            illustration(for: weather)

            VStack(alignment: .leading, spacing: 0) {
                Text(WeatherService.temperatureString(celsius: weather.temperatureCelsius))
                    .font(.system(size: 40, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(NotchTheme.inkPrimary)
                    .contentTransition(.numericText())

                Text((state.weather.placeName ?? "Your Location")
                     + " · " + WeatherService.condition(for: weather.weatherCode))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(NotchTheme.inkSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: 12)

            metrics(weather)
        }
        .frame(height: 66)
        .accessibilityElement(children: .combine)
    }

    /// Two rows of three chips. A grid keeps the six readings on one glance
    /// without a scrolling column of labelled rows.
    private func metrics(_ weather: WeatherService.Snapshot) -> some View {
        Grid(horizontalSpacing: 20, verticalSpacing: 8) {
            GridRow {
                metric("thermometer.medium", "Feels",
                       WeatherService.temperatureString(celsius: weather.apparentCelsius))
                metric("arrow.up.arrow.down", "High / Low",
                       WeatherService.temperatureString(celsius: weather.highCelsius)
                       + " / " + WeatherService.temperatureString(celsius: weather.lowCelsius))
                metric("wind", "Wind", WeatherService.windString(kmh: weather.windKmh))
            }
            GridRow {
                metric("humidity.fill", "Humidity", "\(weather.humidityPercent)%")
                metric("umbrella.fill", "Rain", "\(weather.precipitationChancePercent)%")
                if let sunset = weather.sunset {
                    metric("sunset.fill", "Sunset", WeatherService.timeLabel(for: sunset))
                } else {
                    metric("sun.max.trianglebadge.exclamationmark.fill", "UV Index",
                           "\(Int(weather.uvIndex.rounded()))")
                }
            }
        }
    }

    private func metric(_ systemImage: String, _ label: String, _ value: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NotchTheme.inkSecondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: -1) {
                Text(label)
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .tracking(0.5)
                    .foregroundStyle(NotchTheme.inkMuted)
                Text(value)
                    .font(.system(size: 12.5, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(NotchTheme.inkPrimary)
                    .lineLimit(1)
            }
        }
        .gridColumnAlignment(.leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }

    /// The reference's illustration: a yellow sun with rays and a white cloud
    /// overlapping it. Other conditions fall back to the large multicolor
    /// symbol for the code.
    @ViewBuilder
    private func illustration(for weather: WeatherService.Snapshot) -> some View {
        switch weather.weatherCode {
        case 1, 2:
            ZStack {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(.yellow)
                Image(systemName: "cloud.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(.white)
                    .offset(x: 12, y: 9)
            }
            .symbolRenderingMode(.multicolor)
            .frame(width: 58)
            .accessibilityHidden(true)
        default:
            Image(systemName: WeatherService.symbol(
                for: weather.weatherCode,
                isDay: weather.isDay
            ))
            .font(.system(size: 42))
            .symbolRenderingMode(.multicolor)
            .frame(width: 58)
            .accessibilityHidden(true)
        }
    }

    // MARK: - Forecast strips

    private func hourlyStrip(_ weather: WeatherService.Snapshot) -> some View {
        forecastCard {
            ForEach(Array(weather.hourly.prefix(9).enumerated()), id: \.offset) { _, hour in
                forecastColumn(
                    caption: WeatherService.hourLabel(for: hour.time),
                    symbol: WeatherService.symbol(for: hour.weatherCode, isDay: hour.isDay),
                    value: WeatherService.temperatureString(celsius: hour.temperatureCelsius),
                    secondary: nil
                )
            }
        }
    }

    private func dailyStrip(_ weather: WeatherService.Snapshot) -> some View {
        forecastCard {
            if weather.daily.isEmpty {
                Text("No extended forecast available")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(NotchTheme.inkMuted)
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(Array(weather.daily.prefix(5).enumerated()), id: \.offset) { _, day in
                    forecastColumn(
                        caption: WeatherService.dayLabel(for: day.date),
                        symbol: WeatherService.symbol(for: day.weatherCode, isDay: true),
                        value: WeatherService.temperatureString(celsius: day.highCelsius),
                        secondary: WeatherService.temperatureString(celsius: day.lowCelsius)
                    )
                }
            }
        }
    }

    private func forecastCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 0) {
            content()
        }
        .frame(height: 66)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(NotchTheme.surface)
        }
    }

    private func forecastColumn(
        caption: String,
        symbol: String,
        value: String,
        secondary: String?
    ) -> some View {
        VStack(spacing: 4) {
            Text(caption)
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .foregroundStyle(NotchTheme.inkSecondary)

            Image(systemName: symbol)
                .font(.system(size: 16))
                .symbolRenderingMode(.multicolor)
                .frame(height: 20)

            HStack(spacing: 4) {
                Text(value)
                    .font(.system(size: 11.5, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(NotchTheme.inkPrimary)
                if let secondary {
                    Text(secondary)
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(NotchTheme.inkMuted)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caption)
        .accessibilityValue(secondary.map { "\(value), \($0)" } ?? value)
    }
}
