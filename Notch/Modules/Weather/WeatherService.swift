import CoreLocation
import Foundation
import Observation

/// Current conditions for the header chip, from the keyless Open-Meteo API
/// with reduced-accuracy location. Fetched only when the notch expands and
/// cached for 30 minutes.
@Observable
final class WeatherService: NSObject, CLLocationManagerDelegate {
    struct Snapshot: Equatable {
        let temperatureCelsius: Double
        let weatherCode: Int
        let isDay: Bool
        let fetchedAt: Date
    }

    private(set) var snapshot: Snapshot?

    private let locationManager = CLLocationManager()
    private var isFetching = false
    private static let cacheLifetime: TimeInterval = 30 * 60

    override init() {
        super.init()
        locationManager.delegate = self
        // City-level accuracy is plenty for weather and kinder to privacy.
        locationManager.desiredAccuracy = kCLLocationAccuracyReduced
    }

    /// Called when the notch expands; a no-op while the cache is fresh.
    func refresh() {
        guard NotchSettings.shared.showWeather else { return }
        if let snapshot, Date().timeIntervalSince(snapshot.fetchedAt) < Self.cacheLifetime {
            return
        }
        guard !isFetching else { return }

        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
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
            if NotchSettings.shared.showWeather, snapshot == nil {
                manager.requestLocation()
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        fetch(for: location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Weather is a garnish: fail silently, retry on the next expand.
    }

    private func fetch(for location: CLLocation) {
        guard !isFetching else { return }
        isFetching = true

        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            .init(name: "latitude", value: String(format: "%.2f", location.coordinate.latitude)),
            .init(name: "longitude", value: String(format: "%.2f", location.coordinate.longitude)),
            .init(name: "current", value: "temperature_2m,weather_code,is_day"),
            .init(name: "temperature_unit", value: "celsius"),
        ]

        struct Response: Decodable {
            struct Current: Decodable {
                let temperature2m: Double
                let weatherCode: Int
                let isDay: Int

                enum CodingKeys: String, CodingKey {
                    case temperature2m = "temperature_2m"
                    case weatherCode = "weather_code"
                    case isDay = "is_day"
                }
            }

            let current: Current
        }

        Task { [weak self] in
            var result: Snapshot?
            if let url = components.url,
               let (data, _) = try? await URLSession.shared.data(from: url),
               let response = try? JSONDecoder().decode(Response.self, from: data) {
                result = Snapshot(
                    temperatureCelsius: response.current.temperature2m,
                    weatherCode: response.current.weatherCode,
                    isDay: response.current.isDay == 1,
                    fetchedAt: Date()
                )
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

    /// Locale-aware "21°" (converts to Fahrenheit where the locale uses it).
    static func temperatureString(celsius: Double) -> String {
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .temperatureWithoutUnit
        formatter.numberFormatter.maximumFractionDigits = 0
        return formatter.string(from: Measurement(value: celsius, unit: UnitTemperature.celsius))
    }
}
