import SwiftUI

/// Full weather detail: a hero band (illustration, temperature, place and a
/// six-cell metric grid), then hourly and five-day forecast strips.
///
/// Every tab shares one open panel (as in boring.notch and Atoll), which at
/// Budget: `NotchState.moduleContentSize`, about 538 x 240. Hero 104 + label
/// 16 + strip 74 with 10 and 8pt gaps. The hourly and five-day forecasts share
/// the strip; the chips that swap between them live in the header.
struct WeatherDetailView: View {
    let state: NotchState

    var body: some View {
        Group {
            if let weather = state.weather.snapshot {
                VStack(alignment: .leading, spacing: 10) {
                    hero(weather)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(state.showsDailyForecast ? "5-DAY FORECAST" : "HOURLY FORECAST")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .tracking(1.1)
                            .foregroundStyle(NotchTheme.inkSecondary)

                        if state.showsDailyForecast {
                            dailyStrip(weather)
                        } else {
                            hourlyStrip(weather)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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

    // MARK: - Hero

    private func hero(_ weather: WeatherService.Snapshot) -> some View {
        HStack(alignment: .center, spacing: 20) {
            illustration(for: weather)

            VStack(alignment: .leading, spacing: 0) {
                Text(state.weather.placeName ?? "Your Location")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(NotchTheme.inkPrimary)
                    .lineLimit(1)

                Text(WeatherService.temperatureString(celsius: weather.temperatureCelsius))
                    .font(.system(size: 46, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(NotchTheme.inkPrimary)
                    .contentTransition(.numericText())
                    .fixedSize()

                Text(WeatherService.condition(for: weather.weatherCode))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(NotchTheme.inkPrimary)
                    .lineLimit(1)
                    .padding(.top, 2)

                Text("H: \(WeatherService.temperatureString(celsius: weather.highCelsius))  "
                     + "L: \(WeatherService.temperatureString(celsius: weather.lowCelsius))")
                    .font(.notchBody.monospacedDigit())
                    .foregroundStyle(NotchTheme.inkSecondary)
                    .fixedSize()
                    .padding(.top, 6)

                HStack(spacing: 16) {
                    metric("thermometer.medium",
                           "Feels: " + WeatherService.temperatureString(celsius: weather.apparentCelsius))
                    metric("wind", "Wind: " + WeatherService.windString(kmh: weather.windKmh))
                    metric("humidity.fill", "Humidity: \(weather.humidityPercent)%")
                }
                .padding(.top, 4)
            }

            Spacer(minLength: 0)
        }
    }

    private func metric(_ systemImage: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 12))
                .symbolRenderingMode(.multicolor)
            Text(text)
                .font(.notchCallout.weight(.semibold).monospacedDigit())
                .foregroundStyle(NotchTheme.inkSecondary)
                .fixedSize()
        }
        // Glyph and label travel together: an Image cannot shrink, so a tight
        // column wraps it onto its own line instead.
        .fixedSize()
        .accessibilityElement(children: .combine)
    }

    /// The reference's illustration: a large flat sun with separate rays for
    /// clear weather, the multicolor symbol for everything else.
    @ViewBuilder
    private func illustration(for weather: WeatherService.Snapshot) -> some View {
        Image(systemName: WeatherService.symbol(
            for: weather.weatherCode,
            isDay: weather.isDay
        ))
        .font(.system(size: 74))
        .symbolRenderingMode(.multicolor)
        .frame(width: 112, height: 104)
        .accessibilityHidden(true)
    }

    // MARK: - Forecast strips

    private func hourlyStrip(_ weather: WeatherService.Snapshot) -> some View {
        forecastCard {
            ForEach(Array(weather.hourly.prefix(8).enumerated()), id: \.offset) { _, hour in
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
        HStack(alignment: .top, spacing: 0) {
            content()
        }
        .frame(height: 74)
        .frame(maxWidth: .infinity)
    }

    private func forecastColumn(
        caption: String,
        symbol: String,
        value: String,
        secondary: String?
    ) -> some View {
        VStack(spacing: 6) {
            Text(caption)
                .font(.notchBody.weight(.bold))
                .foregroundStyle(NotchTheme.inkPrimary)
                .fixedSize()

            Image(systemName: symbol)
                .font(.system(size: 21))
                .symbolRenderingMode(.multicolor)
                .frame(height: 24)

            HStack(spacing: 5) {
                Text(value)
                    .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(NotchTheme.inkPrimary)
                    .fixedSize()
                if let secondary {
                    Text(secondary)
                        .font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(NotchTheme.inkMuted)
                        .fixedSize()
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caption)
        .accessibilityValue(secondary.map { "\(value), \($0)" } ?? value)
    }
}
