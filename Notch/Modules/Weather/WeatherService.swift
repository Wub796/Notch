import AppKit
import CoreLocation
import Foundation
import Observation

/// Current conditions from the keyless Open-Meteo API with reduced-accuracy
/// location, plus a reverse-geocoded place name. Fetched only when the notch
/// expands and cached for 30 minutes.
@Observable
final class WeatherService: NSObject, CLLocationManagerDelegate {
    struct Hourly: Equatable {
        let time: Date
        let temperatureCelsius: Double
        let weatherCode: Int
        let isDay: Bool
    }

    struct Snapshot: Equatable {
        let temperatureCelsius: Double
        let apparentCelsius: Double
        let highCelsius: Double
        let lowCelsius: Double
        let weatherCode: Int
        let isDay: Bool
        let windKmh: Double
        let humidityPercent: Int
        let precipitationChancePercent: Int
        let hourly: [Hourly]
        let fetchedAt: Date
    }

    private(set) var snapshot: Snapshot?
    private(set) var placeName: String?

    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var isFetching = false
    private static let cacheLifetime: TimeInterval = 30 * 60

    override init() {
        super.init()
        locationManager.delegate = self
        // City-level accuracy is plenty for weather and kinder to privacy.
        locationManager.desiredAccuracy = kCLLocationAccuracyReduced
    }

    /// Requests location authorization explicitly by making the app active
    /// and issuing the authorization prompt.
    func requestAuthorization() {
        NSApp.activate(ignoringOtherApps: true)
        locationManager.requestWhenInUseAuthorization()
        locationManager.requestLocation()
    }

    /// Called when the notch expands; a no-op while the cache is fresh unless
    /// `force` is set (the weather header's refresh button).
    func refresh(force: Bool = false) {
        guard NotchSettings.shared.showWeather else { return }
        if !force, let snapshot,
           Date().timeIntervalSince(snapshot.fetchedAt) < Self.cacheLifetime {
            return
        }
        guard !isFetching else { return }

        switch locationManager.authorizationStatus {
        case .notDetermined:
            requestAuthorization()
        case .restricted, .denied:
            break
        default:
            locationManager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .notDetermined, .restricted, .denied:
            break
        default:
            if NotchSettings.shared.showWeather {
                manager.requestLocation()
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        fetch(for: location)
        reverseGeocode(location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Weather is a garnish: fail silently, retry on the next expand.
    }

    private func reverseGeocode(_ location: CLLocation) {
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            guard let name = placemarks?.first?.locality
                ?? placemarks?.first?.administrativeArea
            else { return }
            DispatchQueue.main.async {
                self?.placeName = name
            }
        }
    }

    // MARK: - Open-Meteo DTOs

    private struct Response: Decodable {
        struct Current: Decodable {
            let temperature2m: Double
            let apparentTemperature: Double?
            let weatherCode: Int
            let isDay: Int
            let windSpeed10m: Double?
            let relativeHumidity2m: Int?

            enum CodingKeys: String, CodingKey {
                case temperature2m = "temperature_2m"
                case apparentTemperature = "apparent_temperature"
                case weatherCode = "weather_code"
                case isDay = "is_day"
                case windSpeed10m = "wind_speed_10m"
                case relativeHumidity2m = "relative_humidity_2m"
            }
        }

        struct Hourly: Decodable {
            let time: [String]
            let temperature2m: [Double]
            let weatherCode: [Int]
            let isDay: [Int]

            enum CodingKeys: String, CodingKey {
                case time
                case temperature2m = "temperature_2m"
                case weatherCode = "weather_code"
                case isDay = "is_day"
            }
        }

        struct Daily: Decodable {
            let temperature2mMax: [Double]?
            let temperature2mMin: [Double]?
            let precipitationProbabilityMax: [Int?]?

            enum CodingKeys: String, CodingKey {
                case temperature2mMax = "temperature_2m_max"
                case temperature2mMin = "temperature_2m_min"
                case precipitationProbabilityMax = "precipitation_probability_max"
            }
        }

        let current: Current
        let hourly: Hourly?
        let daily: Daily?
    }

    private func fetch(for location: CLLocation) {
        guard !isFetching else { return }
        isFetching = true

        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            .init(name: "latitude", value: String(format: "%.2f", location.coordinate.latitude)),
            .init(name: "longitude", value: String(format: "%.2f", location.coordinate.longitude)),
            .init(
                name: "current",
                value: "temperature_2m,apparent_temperature,weather_code,is_day,wind_speed_10m,relative_humidity_2m"
            ),
            .init(name: "hourly", value: "temperature_2m,weather_code,is_day"),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            .init(name: "forecast_hours", value: "12"),
            .init(name: "forecast_days", value: "2"),
            .init(name: "temperature_unit", value: "celsius"),
            .init(name: "wind_speed_unit", value: "kmh"),
            .init(name: "timezone", value: "auto"),
        ]

        Task { [weak self] in
            let result: Snapshot?
            if let url = components.url,
               let (data, _) = try? await URLSession.shared.data(from: url),
               let response = try? JSONDecoder().decode(Response.self, from: data) {
                result = Snapshot(
                    temperatureCelsius: response.current.temperature2m,
                    apparentCelsius: response.current.apparentTemperature
                        ?? response.current.temperature2m,
                    highCelsius: response.daily?.temperature2mMax?.first
                        ?? response.current.temperature2m,
                    lowCelsius: response.daily?.temperature2mMin?.first
                        ?? response.current.temperature2m,
                    weatherCode: response.current.weatherCode,
                    isDay: response.current.isDay == 1,
                    windKmh: response.current.windSpeed10m ?? 0,
                    humidityPercent: response.current.relativeHumidity2m ?? 0,
                    precipitationChancePercent: response.daily?
                        .precipitationProbabilityMax?.first.flatMap { $0 } ?? 0,
                    hourly: Self.hourly(from: response.hourly),
                    fetchedAt: Date()
                )
            } else {
                result = nil
            }
            await MainActor.run { [weak self] in
                self?.isFetching = false
                if let result {
                    self?.snapshot = result
                }
            }
        }
    }

    // MARK: - Presentation

    /// Parses Open-Meteo's local-time hourly arrays into Hourly rows.
    private static func hourly(from response: Response.Hourly?) -> [Hourly] {
        guard let response else { return [] }
        let count = min(
            response.time.count,
            response.temperature2m.count,
            response.weatherCode.count,
            response.isDay.count
        )
        guard count > 0 else { return [] }

        return (0 ..< count).map { index in
            Hourly(
                time: Self.hourFormatter.date(from: response.time[index]) ?? Date(),
                temperatureCelsius: response.temperature2m[index],
                weatherCode: response.weatherCode[index],
                isDay: response.isDay[index] == 1
            )
        }
    }

    private static let hourFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return formatter
    }()

    /// "6 PM" / "12 AM" for an hourly row, in the local timezone.
    static func hourLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        return formatter.string(from: date).replacingOccurrences(of: " ", with: "")
    }

    /// SF Symbol for a WMO weather code.
    static func symbol(for code: Int, isDay: Bool) -> String {
        switch code {
        case 0: isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51 ... 57: "cloud.drizzle.fill"
        case 61 ... 67, 80 ... 82: "cloud.rain.fill"
        case 71 ... 77, 85, 86: "cloud.snow.fill"
        case 95 ... 99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }

    /// Short condition wording for a WMO weather code.
    static func condition(for code: Int) -> String {
        switch code {
        case 0: "Clear"
        case 1: "Mostly Clear"
        case 2: "Partly Cloudy"
        case 3: "Overcast"
        case 45, 48: "Fog"
        case 51 ... 57: "Drizzle"
        case 61 ... 67: "Rain"
        case 71 ... 77: "Snow"
        case 80 ... 82: "Showers"
        case 85, 86: "Snow Showers"
        case 95 ... 99: "Thunderstorm"
        default: "Cloudy"
        }
    }

    /// Formatted temperature (e.g. "21°" or "70°") respecting user unit preferences.
    static func temperatureString(celsius: Double) -> String {
        let unit = NotchSettings.shared.temperatureUnit
        switch unit {
        case .celsius:
            return "\(Int(round(celsius)))°"
        case .fahrenheit:
            let fahrenheit = (celsius * 9 / 5) + 32
            return "\(Int(round(fahrenheit)))°"
        case .automatic:
            let formatter = MeasurementFormatter()
            formatter.unitOptions = .temperatureWithoutUnit
            formatter.numberFormatter.maximumFractionDigits = 0
            return formatter.string(from: Measurement(value: celsius, unit: UnitTemperature.celsius))
        }
    }

    /// Locale-aware wind speed ("13 km/h" / "8 mph").
    static func windString(kmh: Double) -> String {
        let formatter = MeasurementFormatter()
        formatter.unitStyle = .short
        formatter.numberFormatter.maximumFractionDigits = 0
        return formatter.string(from: Measurement(value: kmh, unit: UnitSpeed.kilometersPerHour))
    }
}
