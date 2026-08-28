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

    /// Animation personality: snappy / bouncy / calm.
    var animationProfile = AnimationProfile.snappy.rawValue {
        didSet { save(animationProfile, "animationProfile") }
    }

    /// Battery plug/unplug and meeting-soon activities in the collapsed notch.
    var liveActivitiesEnabled = true { didSet { save(liveActivitiesEnabled, "liveActivitiesEnabled") } }

    /// Show system volume changes as a HUD in the collapsed notch.
    var volumeHUDEnabled = true { didSet { save(volumeHUDEnabled, "volumeHUDEnabled") } }

    /// Current conditions chip in the expanded header (Open-Meteo).
    var showWeather = true { didSet { save(showWeather, "showWeather") } }

    var showMediaWings = true { didSet { save(showMediaWings, "showMediaWings") } }

    /// Announce new tracks in the collapsed notch (boring.notch's sneak peek).
    var sneakPeekEnabled = true { didSet { save(sneakPeekEnabled, "sneakPeekEnabled") } }

    /// Show the current synced lyric line under the closed notch while
    /// playing.
    var lyricActivityEnabled = true { didSet { save(lyricActivityEnabled, "lyricActivityEnabled") } }

    /// Blinking idle face in the wing when nothing else is happening.
    var showIdleFace = true { didSet { save(showIdleFace, "showIdleFace") } }

    /// Two-finger scroll over the notch opens/closes it.
    var scrollToExpand = true { didSet { save(scrollToExpand, "scrollToExpand") } }
    var fetchLyrics = true { didSet { save(fetchLyrics, "fetchLyrics") } }
    var hapticsEnabled = true { didSet { save(hapticsEnabled, "hapticsEnabled") } }
    var telemetryInterval = 2.0 { didSet { save(telemetryInterval, "telemetryInterval") } }

    /// Raw value of the last tab the user opened; restored across launches.
    var lastTab = "" { didSet { save(lastTab, "lastTab") } }

    /// Welcome window has been shown and dismissed.
    var hasCompletedOnboarding = false { didSet { save(hasCompletedOnboarding, "hasCompletedOnboarding") } }

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
        if let profile = defaults.string(forKey: "animationProfile") {
            animationProfile = profile
        }
        if defaults.object(forKey: "liveActivitiesEnabled") != nil {
            liveActivitiesEnabled = defaults.bool(forKey: "liveActivitiesEnabled")
        }
        if defaults.object(forKey: "volumeHUDEnabled") != nil {
            volumeHUDEnabled = defaults.bool(forKey: "volumeHUDEnabled")
        }
        if defaults.object(forKey: "showWeather") != nil {
            showWeather = defaults.bool(forKey: "showWeather")
        }
        if defaults.object(forKey: "sneakPeekEnabled") != nil {
            sneakPeekEnabled = defaults.bool(forKey: "sneakPeekEnabled")
        }
        if defaults.object(forKey: "lyricActivityEnabled") != nil {
            lyricActivityEnabled = defaults.bool(forKey: "lyricActivityEnabled")
        }
        if defaults.object(forKey: "showIdleFace") != nil {
            showIdleFace = defaults.bool(forKey: "showIdleFace")
        }
        if defaults.object(forKey: "scrollToExpand") != nil {
            scrollToExpand = defaults.bool(forKey: "scrollToExpand")
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
        lastTab = defaults.string(forKey: "lastTab") ?? ""
        hasCompletedOnboarding = defaults.bool(forKey: "hasCompletedOnboarding")

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
