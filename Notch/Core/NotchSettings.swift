import Foundation
import Observation
import ServiceManagement

/// Temperature unit choices for weather display.
enum TemperatureUnit: String, CaseIterable, Identifiable, Hashable, Sendable {
    case automatic
    case celsius
    case fahrenheit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "System Default"
        case .celsius: "Celsius (°C)"
        case .fahrenheit: "Fahrenheit (°F)"
        }
    }
}

/// Which player the notch's music features drive.
enum MusicProvider: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case appleMusic
    case spotify

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .appleMusic: "Apple Music"
        case .spotify: "Spotify"
        }
    }

    /// Bundle identifier used to decide whether the now-playing source is the
    /// chosen provider.
    var bundleID: String {
        switch self {
        case .automatic: ""
        case .appleMusic: "com.apple.Music"
        case .spotify: "com.spotify.client"
        }
    }

    /// AppleScript app name used to drive the app directly (nil for Automatic,
    /// which follows whatever is playing via MediaRemote). `tell application`
    /// launches the app if it isn't running.
    var appleScriptAppName: String? {
        switch self {
        case .automatic: nil
        case .appleMusic: "Music"
        case .spotify: "Spotify"
        }
    }
}

/// User preferences, persisted to UserDefaults, plus the launch-at-login
/// registration through SMAppService.
@Observable
final class NotchSettings {
    static let shared = NotchSettings()

    var expandOnHover = true { didSet { save(expandOnHover, "expandOnHover") } }
    /// Dwell required before a hover opens the notch.
    var openDelay = 0.22 { didSet { save(openDelay, "openDelay") } }

    /// Points of slack around the hardware notch that still count as hovering
    /// it. The probe is otherwise exactly the notch, which is precise but
    /// unforgiving — a pointer arriving from below has to land inside a 32pt
    /// strip. The slack is added to the sides and the bottom only, never the
    /// top: above the notch is the screen edge.
    var hoverTolerance = 8.0 { didSet { save(hoverTolerance, "hoverTolerance") } }
    var closeDelay = 0.2 { didSet { save(closeDelay, "closeDelay") } }

    /// When on, dropped files go straight to AirDrop; when off they land on
    /// the shelf first.
    var instantAirDrop = false { didSet { save(instantAirDrop, "instantAirDrop") } }
    var autoClearShelf = false { didSet { save(autoClearShelf, "autoClearShelf") } }

    /// Animation personality: snappy / bouncy / calm.
    var animationProfile: AnimationProfile = .snappy {
        didSet { save(animationProfile.rawValue, "animationProfile") }
    }

    /// Battery plug/unplug and meeting-soon activities in the collapsed notch.
    var liveActivitiesEnabled = true { didSet { save(liveActivitiesEnabled, "liveActivitiesEnabled") } }

    /// Show system volume changes as a HUD in the collapsed notch.
    var volumeHUDEnabled = true { didSet { save(volumeHUDEnabled, "volumeHUDEnabled") } }

    /// Show brightness changes as a HUD in the collapsed notch. Detecting a
    /// brightness key press requires sampling, so this is opt-out.
    var brightnessHUDEnabled = true {
        didSet {
            save(brightnessHUDEnabled, "brightnessHUDEnabled")
            onBrightnessHUDSettingChanged?(brightnessHUDEnabled)
        }
    }
    var onBrightnessHUDSettingChanged: ((Bool) -> Void)?

    /// Fired when HUD replacement is switched, so the state can start or stop
    /// the media-key tap.
    var onHUDReplacementChanged: ((Bool) -> Void)?

    /// Current conditions in the dashboard (Open-Meteo).
    var showWeather = true { didSet { save(showWeather, "showWeather") } }

    /// Temperature display unit.
    var temperatureUnit: TemperatureUnit = .automatic {
        didSet { save(temperatureUnit.rawValue, "temperatureUnit") }
    }

    /// Shows the weather glyph and a bold temperature in the compact notch.
    var showCompactWeather = true { didSet { save(showCompactWeather, "showCompactWeather") } }

    /// Show the numeric percentage beside the battery glyph.
    var showBatteryPercentage = true { didSet { save(showBatteryPercentage, "showBatteryPercentage") } }

    /// Low battery notification threshold.
    var lowBatteryThreshold = 20 { didSet { save(lowBatteryThreshold, "lowBatteryThreshold") } }

    var showMediaWings = true { didSet { save(showMediaWings, "showMediaWings") } }

    /// Which player the notch follows and controls.
    var musicProvider: MusicProvider = .automatic {
        didSet { save(musicProvider.rawValue, "musicProvider") }
    }

    /// Announce new tracks in the collapsed notch.
    var sneakPeekEnabled = true { didSet { save(sneakPeekEnabled, "sneakPeekEnabled") } }

    /// Duration for track sneak peek in seconds.
    var sneakPeekDuration = 3.5 { didSet { save(sneakPeekDuration, "sneakPeekDuration") } }

    /// Show the current synced lyric line under the closed notch while playing.
    var lyricActivityEnabled = true { didSet { save(lyricActivityEnabled, "lyricActivityEnabled") } }

    /// Two-finger scroll over the notch opens/closes it.
    var scrollToExpand = true { didSet { save(scrollToExpand, "scrollToExpand") } }

    /// Automatically collapse the notch when the cursor leaves.
    var autoCollapseOnMouseExit = true { didSet { save(autoCollapseOnMouseExit, "autoCollapseOnMouseExit") } }

    /// Clipboard history.
    var clipboardHistoryEnabled = true {
        didSet {
            save(clipboardHistoryEnabled, "clipboardHistoryEnabled")
            onClipboardSettingChanged?(clipboardHistoryEnabled)
        }
    }
    var onClipboardSettingChanged: ((Bool) -> Void)?

    var clipboardMaxCapacity = 25 {
        didSet { save(clipboardMaxCapacity, "clipboardMaxCapacity") }
    }

    /// Announce Space switches in the notch.
    var desktopChangeEnabled = true {
        didSet { save(desktopChangeEnabled, "desktopChangeEnabled") }
    }

    /// Bluetooth accessories battery monitor.
    var showAccessoryBattery = true {
        didSet { save(showAccessoryBattery, "showAccessoryBattery") }
    }

    /// Eye break 20-20-20 reminders.
    var eyeBreakEnabled = false {
        didSet {
            save(eyeBreakEnabled, "eyeBreakEnabled")
            onEyeBreakSettingChanged?(eyeBreakEnabled)
        }
    }
    var onEyeBreakSettingChanged: ((Bool) -> Void)?

    var fetchLyrics = true { didSet { save(fetchLyrics, "fetchLyrics") } }

    /// Drive the visualiser from the real output mix rather than the volume.
    /// Off by default: it costs a Screen Recording permission.
    var realtimeAudioMeter = false {
        didSet {
            save(realtimeAudioMeter, "realtimeAudioMeter")
            onRealtimeAudioMeterChanged?(realtimeAudioMeter)
        }
    }
    var onRealtimeAudioMeterChanged: ((Bool) -> Void)?

    var autoScrollLyrics = true { didSet { save(autoScrollLyrics, "autoScrollLyrics") } }

    var hapticsEnabled = true { didSet { save(hapticsEnabled, "hapticsEnabled") } }
    var telemetryInterval = 1.0 { didSet { save(telemetryInterval, "telemetryInterval") } }

    /// Show telemetry gauges in System view.
    var showCPUSparkline = true { didSet { save(showCPUSparkline, "showCPUSparkline") } }
    var showMemoryPressure = true { didSet { save(showMemoryPressure, "showMemoryPressure") } }
    var showNetworkSpeed = true { didSet { save(showNetworkSpeed, "showNetworkSpeed") } }
    var showBatteryHealth = true { didSet { save(showBatteryHealth, "showBatteryHealth") } }

    /// System-wide shortcut that toggles the notch.
    var hotKey: String = HotKeyManager.Shortcut.optionCommandN.rawValue {
        didSet {
            save(hotKey, "hotKey")
            HotKeyManager.shared.apply(
                HotKeyManager.Shortcut(rawValue: hotKey) ?? .disabled
            )
        }
    }

    /// Which display hosts the notch. Empty means "wherever the notch is,
    /// else the main display".
    var preferredScreenName = "" {
        didSet {
            save(preferredScreenName, "preferredScreenName")
            onScreenPreferenceChanged?()
        }
    }
    var onScreenPreferenceChanged: (() -> Void)?

    /// The user's own Spotify app client ID. Notch cannot ship one: a public
    /// client ID in an open repository gets rate-limited and revoked, and the
    /// app registration belongs to whoever runs it.
    var spotifyClientID = "" { didSet { save(spotifyClientID, "spotifyClientID") } }

    /// Percentage beside the volume / brightness HUD bar
    /// (`showClosedNotchHUDPercentage` in the references).
    var showHUDPercentage = true { didSet { save(showHUDPercentage, "showHUDPercentage") } }

    /// Replace the system's volume and brightness overlay with the notch's
    /// own. Needs Accessibility access to intercept the media keys, which is
    /// how both references do it — hence opt-in.
    var hudReplacement = false {
        didSet {
            save(hudReplacement, "hudReplacement")
            onHUDReplacementChanged?(hudReplacement)
        }
    }

    /// Quick action row on the Tools screen.
    var showQuickActions = true { didSet { save(showQuickActions, "showQuickActions") } }

    // MARK: - Notch dimensions (manual overrides)

    /// Trims or extends the detected notch width, in points. Useful when the
    /// measured hardware notch does not match what the display reports.
    var notchWidthAdjustment = 0.0 { didSet { save(notchWidthAdjustment, "notchWidthAdjustment") } }

    /// Trims or extends the detected notch height, in points.
    var notchHeightAdjustment = 0.0 { didSet { save(notchHeightAdjustment, "notchHeightAdjustment") } }

    /// The open slab, shared by every tab (boring.notch and Atoll both open
    /// to one fixed panel rather than resizing per screen). Clamped in
    /// `NotchSizing`, so a slider can never produce a slab wider than the
    /// display or shorter than its content.
    var openNotchWidth = NotchSizing.defaultOpenWidth {
        didSet { save(openNotchWidth, "openNotchWidth") }
    }
    var openNotchHeight = NotchSizing.defaultOpenHeight {
        didSet { save(openNotchHeight, "openNotchHeight") }
    }

    /// How much the closed pill grows on hover.
    var peekScale = 1.10 { didSet { save(peekScale, "peekScale") } }

    /// Scales the open corner radii; off gives the closed radii in both
    /// states, which is the references' `cornerRadiusScaling` switch.
    var cornerRadiusScaling = true {
        didSet { save(cornerRadiusScaling, "cornerRadiusScaling") }
    }

    /// Restores every dimension above to its shipped value.
    func resetNotchDimensions() {
        notchWidthAdjustment = 0
        notchHeightAdjustment = 0
        openNotchWidth = NotchSizing.defaultOpenWidth
        openNotchHeight = NotchSizing.defaultOpenHeight
        peekScale = 1.10
        cornerRadiusScaling = true
    }

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
        if defaults.object(forKey: "hoverTolerance") != nil {
            hoverTolerance = defaults.double(forKey: "hoverTolerance")
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
        if defaults.object(forKey: "autoClearShelf") != nil {
            autoClearShelf = defaults.bool(forKey: "autoClearShelf")
        }
        if defaults.object(forKey: "showMediaWings") != nil {
            showMediaWings = defaults.bool(forKey: "showMediaWings")
        }
        if let providerString = defaults.string(forKey: "musicProvider"),
           let provider = MusicProvider(rawValue: providerString) {
            musicProvider = provider
        }
        if let profileString = defaults.string(forKey: "animationProfile"),
           let profile = AnimationProfile(rawValue: profileString) {
            animationProfile = profile
        }
        if let unitString = defaults.string(forKey: "temperatureUnit"),
           let unit = TemperatureUnit(rawValue: unitString) {
            temperatureUnit = unit
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
        if defaults.object(forKey: "showCompactWeather") != nil {
            showCompactWeather = defaults.bool(forKey: "showCompactWeather")
        }
        if defaults.object(forKey: "showBatteryPercentage") != nil {
            showBatteryPercentage = defaults.bool(forKey: "showBatteryPercentage")
        }
        if defaults.object(forKey: "lowBatteryThreshold") != nil {
            lowBatteryThreshold = defaults.integer(forKey: "lowBatteryThreshold")
        }
        if defaults.object(forKey: "sneakPeekEnabled") != nil {
            sneakPeekEnabled = defaults.bool(forKey: "sneakPeekEnabled")
        }
        if defaults.object(forKey: "sneakPeekDuration") != nil {
            sneakPeekDuration = defaults.double(forKey: "sneakPeekDuration")
        }
        if defaults.object(forKey: "lyricActivityEnabled") != nil {
            lyricActivityEnabled = defaults.bool(forKey: "lyricActivityEnabled")
        }
        if defaults.object(forKey: "scrollToExpand") != nil {
            scrollToExpand = defaults.bool(forKey: "scrollToExpand")
        }
        if defaults.object(forKey: "autoCollapseOnMouseExit") != nil {
            autoCollapseOnMouseExit = defaults.bool(forKey: "autoCollapseOnMouseExit")
        }
        if defaults.object(forKey: "clipboardHistoryEnabled") != nil {
            clipboardHistoryEnabled = defaults.bool(forKey: "clipboardHistoryEnabled")
        }
        if defaults.object(forKey: "clipboardMaxCapacity") != nil {
            clipboardMaxCapacity = defaults.integer(forKey: "clipboardMaxCapacity")
        }
        if defaults.object(forKey: "desktopChangeEnabled") != nil {
            desktopChangeEnabled = defaults.bool(forKey: "desktopChangeEnabled")
        }
        if defaults.object(forKey: "showAccessoryBattery") != nil {
            showAccessoryBattery = defaults.bool(forKey: "showAccessoryBattery")
        }
        if defaults.object(forKey: "eyeBreakEnabled") != nil {
            eyeBreakEnabled = defaults.bool(forKey: "eyeBreakEnabled")
        }
        if defaults.object(forKey: "fetchLyrics") != nil {
            fetchLyrics = defaults.bool(forKey: "fetchLyrics")
        }
        if defaults.object(forKey: "realtimeAudioMeter") != nil {
            realtimeAudioMeter = defaults.bool(forKey: "realtimeAudioMeter")
        }
        if defaults.object(forKey: "autoScrollLyrics") != nil {
            autoScrollLyrics = defaults.bool(forKey: "autoScrollLyrics")
        }
        if defaults.object(forKey: "hapticsEnabled") != nil {
            hapticsEnabled = defaults.bool(forKey: "hapticsEnabled")
        }
        if defaults.object(forKey: "telemetryInterval") != nil {
            telemetryInterval = defaults.double(forKey: "telemetryInterval")
        }
        if defaults.object(forKey: "showCPUSparkline") != nil {
            showCPUSparkline = defaults.bool(forKey: "showCPUSparkline")
        }
        if defaults.object(forKey: "showMemoryPressure") != nil {
            showMemoryPressure = defaults.bool(forKey: "showMemoryPressure")
        }
        if defaults.object(forKey: "showNetworkSpeed") != nil {
            showNetworkSpeed = defaults.bool(forKey: "showNetworkSpeed")
        }
        if defaults.object(forKey: "showBatteryHealth") != nil {
            showBatteryHealth = defaults.bool(forKey: "showBatteryHealth")
        }
        for (key, apply) in [
            ("notchWidthAdjustment", { (v: Double) in self.notchWidthAdjustment = v }),
            ("notchHeightAdjustment", { v in self.notchHeightAdjustment = v }),
            ("openNotchWidth", { v in self.openNotchWidth = v }),
            ("openNotchHeight", { v in self.openNotchHeight = v }),
            ("peekScale", { v in self.peekScale = v }),
        ] where defaults.object(forKey: key) != nil {
            apply(defaults.double(forKey: key))
        }
        spotifyClientID = defaults.string(forKey: "spotifyClientID") ?? ""
        hotKey = defaults.string(forKey: "hotKey")
            ?? HotKeyManager.Shortcut.optionCommandN.rawValue
        if defaults.object(forKey: "showHUDPercentage") != nil {
            showHUDPercentage = defaults.bool(forKey: "showHUDPercentage")
        }
        if defaults.object(forKey: "hudReplacement") != nil {
            hudReplacement = defaults.bool(forKey: "hudReplacement")
        }
        if defaults.object(forKey: "cornerRadiusScaling") != nil {
            cornerRadiusScaling = defaults.bool(forKey: "cornerRadiusScaling")
        }
        if defaults.object(forKey: "brightnessHUDEnabled") != nil {
            brightnessHUDEnabled = defaults.bool(forKey: "brightnessHUDEnabled")
        }
        preferredScreenName = defaults.string(forKey: "preferredScreenName") ?? ""
        if defaults.object(forKey: "showQuickActions") != nil {
            showQuickActions = defaults.bool(forKey: "showQuickActions")
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
