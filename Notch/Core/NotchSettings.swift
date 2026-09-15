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

/// A pane the Home dashboard can show. The user picks up to
/// `maximumVisible` of these, in order, left to right.
enum DashboardWidget: String, CaseIterable, Identifiable, Sendable {
    case music
    case weather
    case calendar
    case system
    case battery
    case timer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .music: "Now Playing"
        case .weather: "Weather"
        case .calendar: "Calendar"
        case .system: "System"
        case .battery: "Batteries"
        case .timer: "Timer"
        }
    }

    var symbol: String {
        switch self {
        case .music: "music.note"
        case .weather: "cloud.sun.fill"
        case .calendar: "calendar"
        case .system: "gauge.with.dots.needle.50percent"
        case .battery: "battery.75percent"
        case .timer: "timer"
        }
    }

    /// Three is what fits beside each other in the open panel. The picker in
    /// Settings enforces it openly rather than the dashboard quietly dropping
    /// a fourth.
    static let maximumVisible = 3

    /// The layout the dashboard shipped with, so nobody's panel changes until
    /// they change it.
    static let defaults: [DashboardWidget] = [.music, .weather, .calendar]

    /// Known widgets only, no duplicates, no more than fit, and never empty —
    /// an empty dashboard is a broken panel, not a preference.
    static func sanitized(_ widgets: [DashboardWidget]) -> [DashboardWidget] {
        var seen = Set<DashboardWidget>()
        let unique = widgets.filter { seen.insert($0).inserted }
        let capped = Array(unique.prefix(maximumVisible))
        return capped.isEmpty ? defaults : capped
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

    /// Points of slack on each SIDE of the notch that still count as
    /// hovering it. The probe's height stays exactly the notch — vertical
    /// slack made the notch peek whenever the cursor merely rested beneath
    /// the menu bar — so this knob only widens the sides, catching fast
    /// crossings. Defaults to 0: the hover target is exactly the notch and
    /// nothing beside it, which is what the panel is meant to occupy.
    var hoverTolerance = 0.0 { didSet { save(hoverTolerance, "hoverTolerance") } }
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
            notify(onBrightnessHUDSettingChanged, brightnessHUDEnabled)
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

    /// Whether weather may fall back to a coarse location looked up from the
    /// network (`ipapi.co`) when CoreLocation has no fix to give.
    ///
    /// This leaves the Mac — it is the one thing in the app that hands a third
    /// party anything — so it is a switch rather than a silent fallback, and
    /// it is never used when the user has *explicitly denied* Location. A
    /// denial is an answer, and answering it with an IP lookup is not an
    /// approximation of consent.
    var approximateLocationFallback = true {
        didSet { save(approximateLocationFallback, "approximateLocationFallback") }
    }

    /// Shows the weather glyph and a bold temperature in the compact notch.
    var showCompactWeather = true { didSet { save(showCompactWeather, "showCompactWeather") } }

    /// Show the numeric percentage beside the battery glyph.
    var showBatteryPercentage = true { didSet { save(showBatteryPercentage, "showBatteryPercentage") } }

    /// Low battery notification threshold.
    var lowBatteryThreshold = 20 { didSet { save(lowBatteryThreshold, "lowBatteryThreshold") } }

    var showMediaWings = true { didSet { save(showMediaWings, "showMediaWings") } }

    /// Whether the closed notch also wears the cover-and-visualiser wings for
    /// audio that has no now-playing session — a video in a browser, a game,
    /// a call. CoreAudio reports the stream, not the sound, so an app that
    /// holds one open keeps this on; turn it off if that gets in the way.
    var showWingsForAnyAudio = true {
        didSet { save(showWingsForAnyAudio, "showWingsForAnyAudio") }
    }

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

    /// Play the Spotify Canvas (the looping video behind a track) in place of
    /// the album art, when signed in. Off by default: it needs a Spotify
    /// sign-in and reaches Spotify's private endpoints.
    var spotifyCanvasEnabled = false {
        didSet {
            save(spotifyCanvasEnabled, "spotifyCanvasEnabled")
            notify(onSpotifyCanvasSettingChanged, spotifyCanvasEnabled)
        }
    }
    var onSpotifyCanvasSettingChanged: ((Bool) -> Void)?

    /// Two-finger scroll over the closed notch opens it. (Only opens —
    /// closing is hover-out, the hotkey, or a click outside.)
    var scrollToExpand = true { didSet { save(scrollToExpand, "scrollToExpand") } }

    /// Automatically collapse the notch when the cursor leaves.
    var autoCollapseOnMouseExit = true { didSet { save(autoCollapseOnMouseExit, "autoCollapseOnMouseExit") } }

    /// Show finished downloads in the notch as they land.
    var catchDownloads = true {
        didSet {
            save(catchDownloads, "catchDownloads")
            notify(onFileCatcherSettingChanged, catchDownloads)
        }
    }

    /// Show new screenshots in the notch as they are taken.
    var catchScreenshots = true {
        didSet {
            save(catchScreenshots, "catchScreenshots")
            notify(onFileCatcherSettingChanged, catchScreenshots)
        }
    }

    /// Whether a caught file is also added to the shelf, so it is still
    /// reachable after the notch has moved on.
    var caughtFilesJoinShelf = true {
        didSet { save(caughtFilesJoinShelf, "caughtFilesJoinShelf") }
    }

    var onFileCatcherSettingChanged: ((Bool) -> Void)?

    /// Clipboard history.
    var clipboardHistoryEnabled = true {
        didSet {
            save(clipboardHistoryEnabled, "clipboardHistoryEnabled")
            notify(onClipboardSettingChanged, clipboardHistoryEnabled)
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
            notify(onEyeBreakSettingChanged, eyeBreakEnabled)
        }
    }
    var onEyeBreakSettingChanged: ((Bool) -> Void)?

    var fetchLyrics = true { didSet { save(fetchLyrics, "fetchLyrics") } }

    /// Drive the visualiser from the real output mix rather than the volume.
    /// Off by default: it costs a Screen Recording permission.
    var realtimeAudioMeter = false {
        didSet {
            save(realtimeAudioMeter, "realtimeAudioMeter")
            notify(onRealtimeAudioMeterChanged, realtimeAudioMeter)
        }
    }
    var onRealtimeAudioMeterChanged: ((Bool) -> Void)?

    var autoScrollLyrics = true { didSet { save(autoScrollLyrics, "autoScrollLyrics") } }

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
            guard !isLoading else { return }
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
            guard !isLoading else { return }
            onScreenPreferenceChanged?()
        }
    }
    var onScreenPreferenceChanged: (() -> Void)?

    /// Percentage beside the volume / brightness HUD bar
    /// (`showClosedNotchHUDPercentage` in the references).
    var showHUDPercentage = true { didSet { save(showHUDPercentage, "showHUDPercentage") } }

    /// Replace the system's volume and brightness overlay with the notch's
    /// own. Needs Accessibility access to intercept the media keys, which is
    /// how both references do it — enabled by default so native HUD is suppressed.
    var hudReplacement = true {
        didSet {
            save(hudReplacement, "hudReplacement")
            notify(onHUDReplacementChanged, hudReplacement)
        }
    }

    /// Quick action row on the Tools screen.
    var showQuickActions = true { didSet { save(showQuickActions, "showQuickActions") } }

    /// The Home dashboard's widgets, left to right. Sanitized on every write,
    /// so no code path — a stale default, a bad import, a buggy picker — can
    /// leave the dashboard empty, duplicated, or wider than the panel.
    var dashboardWidgets: [DashboardWidget] = DashboardWidget.defaults {
        didSet {
            let clean = DashboardWidget.sanitized(dashboardWidgets)
            if clean != dashboardWidgets { dashboardWidgets = clean }
            save(dashboardWidgets.map(\.rawValue), "dashboardWidgets")
        }
    }

    /// When a new output device connects (a headset pairing, a USB DAC),
    /// switch the system default to it automatically. Off by default: many
    /// people prefer their desktop speakers to stay put.
    var autoSwitchOutputOnConnect = false {
        didSet { save(autoSwitchOutputOnConnect, "autoSwitchOutputOnConnect") }
    }

    /// Bundle IDs the user has pinned in the Audio screen; pinned apps stay
    /// listed even while they are not making sound, so their volume can be
    /// set up in advance.
    var pinnedAudioApps: [String] = [] {
        didSet {
            save(pinnedAudioApps, "pinnedAudioApps")
            notify(onPinnedAudioAppsChanged, pinnedAudioApps)
        }
    }
    var onPinnedAudioAppsChanged: (([String]) -> Void)?

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
        hoverTolerance = 0
        openNotchWidth = NotchSizing.defaultOpenWidth
        openNotchHeight = NotchSizing.defaultOpenHeight
        peekScale = 1.10
        cornerRadiusScaling = true
    }

    /// Raw value of the last tab the user opened; restored across launches.
    var lastTab = "" { didSet { save(lastTab, "lastTab") } }

    /// Welcome window has been shown and dismissed.
    var hasCompletedOnboarding = false { didSet { save(hasCompletedOnboarding, "hasCompletedOnboarding") } }

    /// Start at login. `SMAppService` is the native path — it shows up in
    /// System Settings → Login Items — but it throws for unsigned builds and
    /// apps not running from /Applications, so a LaunchAgent fallback keeps
    /// the feature working from development builds too.
    var launchAtLogin = false { didSet { applyLaunchAtLogin() } }

    /// Why the last enable/disable attempt failed — shown under the toggle
    /// instead of the switch silently flipping back.
    private(set) var launchAtLoginError: String?

    private var isApplyingLoginItem = false
    private static let launchAgentLabel = "com.notchapp.Notch.launchAtLogin"
    private static let launchAgentURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(
            "Library/LaunchAgents/com.notchapp.Notch.launchAtLogin.plist"
        )

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
        if defaults.object(forKey: "showWingsForAnyAudio") != nil {
            showWingsForAnyAudio = defaults.bool(forKey: "showWingsForAnyAudio")
        }
        if defaults.object(forKey: "showMediaWings") != nil {
            showMediaWings = defaults.bool(forKey: "showMediaWings")
        }
        if defaults.object(forKey: "spotifyCanvasEnabled") != nil {
            spotifyCanvasEnabled = defaults.bool(forKey: "spotifyCanvasEnabled")
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
        if defaults.object(forKey: "approximateLocationFallback") != nil {
            approximateLocationFallback = defaults.bool(forKey: "approximateLocationFallback")
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
        if defaults.object(forKey: "catchDownloads") != nil {
            catchDownloads = defaults.bool(forKey: "catchDownloads")
        }
        if defaults.object(forKey: "catchScreenshots") != nil {
            catchScreenshots = defaults.bool(forKey: "catchScreenshots")
        }
        if defaults.object(forKey: "caughtFilesJoinShelf") != nil {
            caughtFilesJoinShelf = defaults.bool(forKey: "caughtFilesJoinShelf")
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
        if defaults.object(forKey: "autoSwitchOutputOnConnect") != nil {
            autoSwitchOutputOnConnect = defaults.bool(forKey: "autoSwitchOutputOnConnect")
        }
        pinnedAudioApps = defaults.stringArray(forKey: "pinnedAudioApps") ?? []
        if let stored = defaults.stringArray(forKey: "dashboardWidgets") {
            dashboardWidgets = DashboardWidget.sanitized(
                stored.compactMap(DashboardWidget.init(rawValue:))
            )
        }
        lastTab = defaults.string(forKey: "lastTab") ?? ""
        hasCompletedOnboarding = defaults.bool(forKey: "hasCompletedOnboarding")

        // Login-item state lives in the system, not in defaults. The cheap
        // half is read inline; the LaunchAgent check shells out to
        // `launchctl print`, which is slow enough that running it here put a
        // blocking subprocess on the main thread during app launch.
        isApplyingLoginItem = true
        launchAtLogin = SMAppService.mainApp.status == .enabled
        isApplyingLoginItem = false

        isLoading = false

        if !launchAtLogin {
            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard Self.launchAgentIsBootstrapped() else { return }
                DispatchQueue.main.async {
                    guard let self, !self.launchAtLogin else { return }
                    self.isApplyingLoginItem = true
                    self.launchAtLogin = true
                    self.isApplyingLoginItem = false
                }
            }
        }
    }

    /// True while `init` is restoring values from UserDefaults.
    ///
    /// Every property here has a `didSet`, and Swift runs those for
    /// assignments in an initializer's body once the type is fully
    /// initialized — which it is, since they all have defaults. So loading
    /// wrote all forty-odd values straight back to UserDefaults, and fired the
    /// change callbacks as a side effect of construction. `hotKey`'s in
    /// particular registered the global shortcut from inside settings
    /// construction, which `AppDelegate.installHotKey()` then did again.
    private var isLoading = true

    private func save(_ value: Any, _ key: String) {
        guard !isLoading else { return }
        UserDefaults.standard.set(value, forKey: key)
    }

    /// Runs a change callback unless we are mid-load.
    private func notify<T>(_ callback: ((T) -> Void)?, _ value: T) {
        guard !isLoading else { return }
        callback?(value)
    }

    private func applyLaunchAtLogin() {
        guard !isApplyingLoginItem else { return }
        isApplyingLoginItem = true
        defer { isApplyingLoginItem = false }
        launchAtLoginError = nil

        if launchAtLogin {
            // Native first: `register()` throws when the app isn't signed or
            // isn't running from /Applications — typical for dev builds. On
            // failure, fall through to the LaunchAgent below.
            do {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
                if SMAppService.mainApp.status == .enabled {
                    // Drop any stale LaunchAgent from an earlier dev build so
                    // the app can't launch twice at login.
                    Self.removeLaunchAgent()
                    return
                }
            } catch {
                // Fall through to the LaunchAgent.
            }

            do {
                try Self.installLaunchAgent()
            } catch {
                launchAtLogin = false
                launchAtLoginError = "macOS refused to add Notch to your login "
                    + "items — \(error.localizedDescription)"
            }
        } else {
            if SMAppService.mainApp.status == .enabled {
                try? SMAppService.mainApp.unregister()
            }
            Self.removeLaunchAgent()
        }
    }

    // MARK: - LaunchAgent fallback

    /// Writes a LaunchAgent that runs the app at login and loads it with
    /// launchctl. Unlike `SMAppService`, this works from any location and
    /// without code signing — it is what keeps launch-at-login usable from
    /// development builds.
    private static func installLaunchAgent() throws {
        guard let executable = Bundle.main.executableURL?.path else {
            throw LaunchAtLoginError.missingExecutable
        }

        let directory = launchAgentURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )

        let plist: [String: Any] = [
            "Label": launchAgentLabel,
            "ProgramArguments": [executable],
            "RunAtLoad": true,
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0
        )
        try data.write(to: launchAgentURL, options: .atomic)

        // Re-register cleanly even if an earlier run left it loaded.
        bootoutLaunchAgent()
        guard launchctl(["bootstrap", "gui/\(getuid())", launchAgentURL.path]) == 0 else {
            throw LaunchAtLoginError.launchctlFailed
        }
    }

    private static func removeLaunchAgent() {
        bootoutLaunchAgent()
        try? FileManager.default.removeItem(at: launchAgentURL)
    }

    private static func bootoutLaunchAgent() {
        launchctl(["bootout", "gui/\(getuid())/\(launchAgentLabel)"])
    }

    private static func launchAgentIsBootstrapped() -> Bool {
        launchctl(["print", "gui/\(getuid())/\(launchAgentLabel)"]) == 0
    }

    @discardableResult
    private static func launchctl(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return -1
        }
        return process.terminationStatus
    }

    private enum LaunchAtLoginError: LocalizedError {
        case missingExecutable
        case launchctlFailed

        var errorDescription: String? {
            switch self {
            case .missingExecutable:
                "the app's executable couldn't be located"
            case .launchctlFailed:
                "launchctl rejected the launch agent"
            }
        }
    }
}
