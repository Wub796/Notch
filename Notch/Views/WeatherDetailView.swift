import SwiftUI

/// Full weather detail per the reference: a large condition illustration with
/// city/current conditions beside it, then an 8-column hourly forecast.
struct WeatherDetailView: View {
    let state: NotchState

    var body: some View {
        Group {
            if let weather = state.weather.snapshot {
                VStack(alignment: .leading, spacing: 12) {
                    currentConditions(weather)
                    hourlyForecast(weather)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "cloud.sun.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(NotchTheme.inkMuted)
                    Text(state.settings.showWeather ? "Weather loading…" : "Weather is off")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(NotchTheme.inkMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            state.weather.refresh()
        }
    }

    // MARK: - Current conditions

    private func currentConditions(_ weather: WeatherService.Snapshot) -> some View {
        HStack(alignment: .center, spacing: 32) {
            illustration(for: weather)

            VStack(alignment: .leading, spacing: 3) {
                Text(state.weather.placeName ?? "Your Location")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(NotchTheme.inkPrimary)
                    .lineLimit(1)

                Text(WeatherService.temperatureString(celsius: weather.temperatureCelsius))
                    .font(.system(size: 44, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(NotchTheme.inkPrimary)
                    .contentTransition(.numericText())

                Text(WeatherService.condition(for: weather.weatherCode))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(NotchTheme.inkPrimary.opacity(0.9))

                Text("H: \(WeatherService.temperatureString(celsius: weather.highCelsius))  "
                     + "L: \(WeatherService.temperatureString(celsius: weather.lowCelsius))")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(NotchTheme.inkSecondary)

                HStack(spacing: 16) {
                    detailRow("thermometer.medium", text: "Feels: \(WeatherService.temperatureString(celsius: weather.apparentCelsius))")
                    detailRow("wind", text: "Wind: \(WeatherService.windString(kmh: weather.windKmh))")
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
                    .font(.system(size: 52))
                    .foregroundStyle(.yellow)
                Image(systemName: "cloud.fill")
                    .font(.system(size: 58))
                    .foregroundStyle(.white)
                    .offset(x: 14, y: 10)
            }
            .symbolRenderingMode(.multicolor)
            .accessibilityHidden(true)
        default:
            Image(systemName: WeatherService.symbol(
                for: weather.weatherCode,
                isDay: weather.isDay
            ))
            .font(.system(size: 58))
            .symbolRenderingMode(.multicolor)
            .accessibilityHidden(true)
        }
    }

    private func detailRow(_ systemImage: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(NotchTheme.inkSecondary)
            Text(text)
                .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(NotchTheme.inkSecondary)
        }
    }

    // MARK: - Hourly forecast

    private func hourlyForecast(_ weather: WeatherService.Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HOURLY FORECAST")
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .tracking(0.9)
                .foregroundStyle(NotchTheme.inkPrimary)

            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(weather.hourly.prefix(8).enumerated()), id: \.offset) { _, hour in
                    VStack(spacing: 5) {
                        Text(WeatherService.hourLabel(for: hour.time))
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(NotchTheme.inkSecondary)

                        Image(systemName: WeatherService.symbol(
                            for: hour.weatherCode,
                            isDay: hour.isDay
                        ))
                        .font(.system(size: 15))
                        .symbolRenderingMode(.multicolor)
                        .frame(height: 20)

                        Text(WeatherService.temperatureString(celsius: hour.temperatureCelsius))
                            .font(.system(size: 10.5, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(NotchTheme.inkPrimary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(NotchTheme.surface)
            }
        }
    }
}
