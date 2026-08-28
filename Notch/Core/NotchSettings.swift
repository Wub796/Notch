import Foundation
import Observation
import ServiceManagement

/// User preferences, persisted to UserDefaults, plus the launch-at-login
/// registration through SMAppService.
@Observable
final class NotchSettings {
    static let shared = NotchSettings()

    var expandOnHover = true { didSet { save(expandOnHover, "expandOnHover") } }
    var openDelay = 0.1 { didSet { save(openDelay, "openDelay") } }
    var closeDelay = 0.35 { didSet { save(closeDelay, "closeDelay") } }

    /// When on, dropped files go straight to AirDrop; when off they land on
    /// the shelf first.
    var instantAirDrop = false { didSet { save(instantAirDrop, "instantAirDrop") } }

    var showMediaWings = true { didSet { save(showMediaWings, "showMediaWings") } }
    var fetchLyrics = true { didSet { save(fetchLyrics, "fetchLyrics") } }
    var hapticsEnabled = true { didSet { save(hapticsEnabled, "hapticsEnabled") } }
    var telemetryInterval = 2.0 { didSet { save(telemetryInterval, "telemetryInterval") } }

    var launchAtLogin = false { didSet { applyLaunchAtLogin() } }

    private var isApplyingLoginItem = false

    private init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "expandOnHover") != nil {
            expandOnHover = defaults.bool(forKey: "expandOnHover")
        }
        if defaults.object(forKey: "openDelay") != nil {
            openDelay = defaults.double(forKey: "openDelay")
        }
        if defaults.object(forKey: "closeDelay") != nil {
            closeDelay = defaults.double(forKey: "closeDelay")
        }
        if defaults.object(forKey: "instantAirDrop") != nil {
            instantAirDrop = defaults.bool(forKey: "instantAirDrop")
        }
        if defaults.object(forKey: "showMediaWings") != nil {
            showMediaWings = defaults.bool(forKey: "showMediaWings")
        }
        if defaults.object(forKey: "fetchLyrics") != nil {
            fetchLyrics = defaults.bool(forKey: "fetchLyrics")
        }
        if defaults.object(forKey: "hapticsEnabled") != nil {
            hapticsEnabled = defaults.bool(forKey: "hapticsEnabled")
        }
        if defaults.object(forKey: "telemetryInterval") != nil {
            telemetryInterval = defaults.double(forKey: "telemetryInterval")
        }

        // Login-item state lives in the system, not in defaults.
        isApplyingLoginItem = true
        launchAtLogin = SMAppService.mainApp.status == .enabled
        isApplyingLoginItem = false
    }

    private func save(_ value: Any, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    private func applyLaunchAtLogin() {
        guard !isApplyingLoginItem else { return }
        isApplyingLoginItem = true
        defer { isApplyingLoginItem = false }

        let service = SMAppService.mainApp
        do {
            if launchAtLogin {
                if service.status != .enabled {
                    try service.register()
                }
            } else if service.status == .enabled {
                try service.unregister()
            }
        } catch {
            // Registration failed (e.g. unsigned dev build) — reflect reality.
            launchAtLogin = service.status == .enabled
        }
    }
}
