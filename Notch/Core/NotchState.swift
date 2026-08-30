import SwiftUI
import Observation

/// Sapphire-style three-state interaction: hovering the notch makes it
/// "peek" (a subtle 1.10× grow), and a click — or a hover linger, when
/// enabled — springs it fully open.
enum NotchMode: Equatable {
    case collapsed
    case peek
    case expanded
}

enum NotchTab: String {
    /// Combined dashboard hosting music, weather, and calendar.
    case home
    /// Dedicated player with full lyrics — everything else goes away.
    case media
    /// Full-screen weather detail with an hourly forecast.
    case weather
    /// Week-at-a-glance calendar detail.
    case calendar
    case shelf
    case clipboard
    case tools
    case notes
    case telemetry
    /// Output devices and the apps playing through them.
    case audio
}

/// Root observable state for the notch UI. Owns every feature module and
/// starts/stops their polling so the app does no periodic work while the
/// notch is collapsed — the live-activity sources are all push-based.
@Observable
final class NotchState {
    var mode: NotchMode = .collapsed
    var tab: NotchTab = .home
    var isDropTargeted = false

    /// While pinned, the expanded panel ignores hover-out and outside clicks.
    var isPinned = false

    /// Whether the player is showing the full lyrics panel, which makes the
    /// panel taller. Held here because the size depends on it.
    var mediaShowsFullLyrics = false

    /// Whether the weather screen shows the five-day strip instead of hourly.
    /// Held here rather than in the view because the chips that toggle it sit
    /// in the header, which is a sibling of the module.
    var showsDailyForecast = false

    /// Notifies the window controller of mode transitions so it can manage
    /// key-window status (SwiftUI buttons in borderless panels only fire
    /// reliably once the panel is key).
    var onModeChange: ((NotchMode) -> Void)?

    /// Physical notch size, injected by NotchWindowController at launch.
    var notchSize: CGSize = NotchGeometry.fallbackSize

    /// The open slab, sized for the screen showing. Switching tabs resizes the
    /// panel, which the references avoid — but a month grid and a weather hero
    /// are genuinely different shapes, and forcing both into one box shrank
    /// each past legibility.
    var expandedSize: CGSize {
        var size = NotchSizing.openNotchSize(for: tab)
        // Full lyrics need a panel to live in, so the player grows for them
        // rather than squeezing a scrolling list into a 30pt strip.
        if tab == .media, mediaShowsFullLyrics {
            size.height += 110
        }
        return size
    }

    /// Room left for a module once the header and the slab's own insets are
    /// taken out. Module views are written to this budget.
    var moduleContentSize: CGSize {
        let open = expandedSize
        let horizontal = (NotchSizing.cornerRadiusInsets.opened.top
            + NotchSizing.openContentInset) * 2
        return CGSize(
            width: max(0, open.width - horizontal),
            height: max(0, open.height - topBarHeight - NotchSizing.openContentInset)
        )
    }

    /// The measured notch, with the user's manual trim applied. Clamped so a
    /// slider can never drive it to zero or past the slab.
    var adjustedNotchSize: CGSize {
        CGSize(
            width: max(notchSize.width + settings.notchWidthAdjustment, 40),
            height: max(notchSize.height + settings.notchHeightAdjustment, 20)
        )
    }

    /// How far the closed pill's wings ease outward on hover.
    ///
    /// The references pad by a fixed amount; deriving it from the user's
    /// "hover grow" preference keeps that slider meaningful now that peek is a
    /// padding rather than a scale. The 1.10 default lands on 6pt, which is
    /// what the fixed value was.
    var hoverExpansion: CGFloat {
        let scale = min(max(settings.peekScale, 1.0), 1.4)
        return (scale - 1) * 60
    }

    /// Height of the icon strip that flanks the hardware notch.
    var topBarHeight: CGFloat {
        max(adjustedNotchSize.height, 38)
    }

    let settings = NotchSettings.shared
    let media = MediaController()
    let calendar = CalendarController()
    let telemetry = TelemetryController()
    let shelf = ShelfController()
    let keepAwake = KeepAwakeController()
    let weather = WeatherService()
    let activities = LiveActivityManager()
    let clipboard = ClipboardManager()
    let notes = NotesManager()
    let timer = TimerManager()
    let eyeBreak = EyeBreakManager()
    let shortcuts = ShortcutsManager()
    let audio = AudioOutputManager()
    let bluetooth = BluetoothBatteryMonitor()
    let brightness = BrightnessController()
    let quickActions = QuickActions()
    let audioApps = AudioAppMonitor()
    let audioMeter = SystemAudioMeter()
    let spotify = SpotifyLibrary()

    /// Which screen of the Devices surface is showing.
    var devicesSection: DevicesSection = .now

    /// Which output surface the Audio screen is showing.
    var audioTab: AudioScreenTab = .apps

    private let focusMonitor = FocusModeMonitor()
    private let desktopMonitor = DesktopChangeMonitor()

    private var pendingHoverWork: DispatchWorkItem?
    private var hoverStartedAt: Date?

    /// Whether the pointer is over the notch. Read by the view for its hover
    /// affordances; there is deliberately only one copy of this.
    private(set) var isHovering = false

    /// Minimum dwell before a click counts as intentional rather than the tail
    /// of a fast pointer sweep across the menu bar.
    private static let minimumDwellForClick: TimeInterval = 0.06

    init() {
        // Personalization: reopen on the tab the user last used. Every tab is
        // reachable from the top bar, so any of them is a valid landing spot.
        if let restored = NotchTab(rawValue: settings.lastTab) {
            tab = restored
        }
        // Event-driven collapsed-notch features. Weather fetches at launch so
        // the collapsed wings have a temperature without the notch opening
        // first; refresh() is a no-op while the 30-minute cache is fresh.
        activities.start()

        settings.onBrightnessHUDSettingChanged = { [weak self] _ in
            self?.applyHUDSources()
        }
        settings.onHUDReplacementChanged = { [weak self] _ in
            self?.applyHUDSources()
        }
        installMediaKeyInterceptor()
        applyHUDSources()
        calendar.bootstrapIfAuthorized()
        weather.refresh()
        // One CoreAudio query at launch, then property listeners: the HUD has
        // to know the level before the notch has ever been opened, and this
        // adds no polling.
        audio.refresh()

        media.onTrackChange = { [weak self] track in
            self?.activities.showTrackChange(title: track.title, artist: track.artist)
        }

        // The output meter is a screen-capture stream, so it runs only while
        // something is actually playing and only if the user asked for it.
        media.onPlaybackStateChange = { [weak self] _ in
            self?.syncAudioMeter()
        }

        // Audio activity is push, not polled: CoreAudio says the moment any
        // process starts or stops making sound, so the Audio screen is right
        // before it is opened rather than up to a second later.
        audioApps.onAudioActivityChange = { [weak self] in
            guard let self else { return }
            withAnimation(NotchAnimations.content) {
                self.refreshAudioApps()
            }
            self.syncAudioMeter()
        }
        audioApps.startObserving()
        settings.onRealtimeAudioMeterChanged = { [weak self] _ in
            self?.syncAudioMeter()
        }
        syncAudioMeter()

        focusMonitor.onChange = { [weak self] mode in
            guard let mode else {
                self?.activities.showFocusChange(name: "Focus Off", symbol: "moon.zzz")
                return
            }
            self?.activities.showFocusChange(name: mode.name, symbol: mode.symbolName)
        }
        focusMonitor.start()

        desktopMonitor.onChange = { [weak self] in
            self?.activities.showDesktopChange()
        }
        desktopMonitor.start()

        eyeBreak.setEnabled(settings.eyeBreakEnabled)
        eyeBreak.onBreakChange = { [weak self] active in
            self?.activities.showEyeBreak(active: active)
        }
        settings.onEyeBreakSettingChanged = { [weak self] enabled in
            self?.eyeBreak.setEnabled(enabled)
        }

        timer.onFinished = { [weak self] in
            self?.activities.clearTransient()
        }

        if settings.clipboardHistoryEnabled {
            clipboard.start()
        }
        settings.onClipboardSettingChanged = { [weak self] enabled in
            if enabled {
                self?.clipboard.start()
            } else {
                self?.clipboard.stop()
            }
        }
    }

    /// Starts or stops the real-time meter to match the setting and playback.
    func syncAudioMeter() {
        // Any audio, not only the now-playing track: a video in a browser or
        // a game is exactly what the meter should be following too.
        if settings.realtimeAudioMeter, media.isPlaying || audioApps.isAnyAudioPlaying {
            audioMeter.start()
        } else {
            audioMeter.stop()
        }
    }

    /// What the collapsed visualiser should draw: the measured bands when the
    /// meter is live, and nil when the volume-driven fallback should be used.
    var visualizerBands: [Float]? {
        guard settings.realtimeAudioMeter, audioMeter.isLive else { return nil }
        return audioMeter.bands
    }

    // MARK: - HUD sources

    /// Hands the media-key tap everything it needs to read and write the
    /// system values, and to raise the notch's HUD — the arrangement
    /// boring.notch uses, where the key press itself is the event and nothing
    /// polls.
    private func installMediaKeyInterceptor() {
        let interceptor = MediaKeyInterceptor.shared
        interceptor.volumeSource = { [weak self] in self?.audio.currentVolume() ?? 0 }
        interceptor.setVolume = { [weak self] level in self?.audio.setVolume(level) }
        interceptor.isMuted = { [weak self] in self?.audio.isMuted ?? false }
        interceptor.toggleMute = { [weak self] in self?.audio.toggleMute() }
        interceptor.brightnessSource = { [weak self] in
            self?.brightness.refresh()
            return self?.brightness.brightness ?? 0
        }
        interceptor.setBrightness = { [weak self] level in self?.brightness.setBrightness(level) }
        interceptor.onVolume = { [weak self] level, muted in
            guard self?.settings.volumeHUDEnabled == true else { return }
            self?.activities.showVolume(level: level, muted: muted)
        }
        interceptor.onBrightness = { [weak self] level in
            guard self?.settings.brightnessHUDEnabled == true else { return }
            self?.activities.showBrightness(level: level)
        }
    }

    /// Starts or stops the media-key tap, which is the only thing that raises
    /// the brightness HUD.
    ///
    /// There used to be a sampler as a fallback, polling the level and showing
    /// the HUD on any change it had not made itself. It could not tell a key
    /// press from ambient auto-brightness, so the notch lit up every time you
    /// walked past a window. Only a key press is a user action, and only the
    /// tap can see one.
    func applyHUDSources() {
        let interceptor = MediaKeyInterceptor.shared
        if settings.hudReplacement, interceptor.start() {
            return
        }
        interceptor.stop()
    }

    /// Re-reads which apps are putting audio out. Cheap — one CoreAudio
    /// property read plus a process lookup each — and only called while the
    /// audio screen is open or the notch is being woken.
    func refreshAudioApps() {
        audioApps.refresh(
            nowPlayingBundleID: media.sourceAppBundleID,
            isPlaying: media.isPlaying
        )
    }

    /// The focus mode currently active, for the dashboard.
    var activeFocus: FocusModeMonitor.Mode? {
        focusMonitor.activeMode
    }

    // MARK: - Live activity resolution

    /// What the collapsed/peek notch is currently showing, by priority:
    /// transient HUD events, an imminent meeting, the live lyric line, then
    /// plain now-playing wings.
    var collapsedActivity: LiveActivity? {
        if let transient = activities.transient {
            return transient
        }
        // A running timer owns the notch until it finishes or is cancelled.
        if timer.isRunning {
            return .timer(remaining: timer.remaining, progress: timer.progress)
        }
        if settings.liveActivitiesEnabled, let event = calendar.upcomingSoon {
            return .meetingSoon(title: event.title, start: event.start)
        }
        if settings.lyricActivityEnabled, media.isPlaying,
           let line = media.collapsedLyricLine {
            return .lyrics(line: line)
        }
        if media.hasTrack, settings.showMediaWings {
            return .music
        }
        // Nothing holds the now-playing session, but something is making
        // sound — a video in a browser, a game, a call. The wings show it
        // too: CoreAudio tells us the instant it starts, and the visualiser
        // beside the notch is the honest answer to "what is that noise".
        if settings.showMediaWings, settings.showWingsForAnyAudio,
           audioApps.isAnyAudioPlaying,
           audioApps.apps.contains(where: \.isPlaying) {
            return .music
        }
        return nil
    }

    /// Extra width added around the hardware notch for the active activity —
    /// split evenly into two wings, so each side must fit half of this.
    private var activityWingWidth: CGFloat {
        switch collapsedActivity {
        // Cover on one side, visualiser on the other: neither needs the width
        // the old glyph-and-temperature pair did.
        case .music: 112
        // The lyric line lives under the notch and wants room to read; the
        // wings only carry the cover and the visualiser.
        case .lyrics: 190
        // The charging popup drops a band beneath the notch (like the volume
        // HUD), so the wings only carry the notch's own row content.
        case .battery(_, true, _): 132
        // These all drop a bar beneath the notch rather than splitting across
        // the wings, so the wings only carry what stays on the notch's own
        // row — the weather glyph and its temperature.
        case .timer, .trackChange, .volume, .brightness,
             .screenLock, .focusMode, .eyeBreak, .accessoryBattery, .meetingSoon:
            132
        // Stays in the wings, so it needs room for the label and the readout.
        case .battery: 210
        case .desktopChange: 150
        case nil: settings.showCompactWeather ? 120 : 0
        }
    }

    /// Extra height an activity adds beneath the hardware notch. The volume
    /// and brightness HUDs live here rather than in the wings: a level bar
    /// squeezed beside the camera housing is unreadable, and dropping the
    /// notch down to hold it is what the system overlay does too.
    private var activityDropHeight: CGFloat {
        switch collapsedActivity {
        case .lyrics: 26
        case .volume, .brightness: 34
        // The charging popup drops beneath the notch, iOS-style.
        case .battery(_, true, _): 46
        default: 0
        }
    }

    var collapsedSize: CGSize {
        var size = adjustedNotchSize
        size.width += activityWingWidth
        size.height += activityDropHeight
        return size
    }

    /// The closed notch's hover target: the notch itself, plus the tolerance
    /// on the sides and below. Fixed geometry, not derived from the animating
    /// slab — that is what used to make the region balloon after a collapse.
    var hoverProbeSize: CGSize {
        let slack = min(max(settings.hoverTolerance, 0), 24)
        return CGSize(
            width: adjustedNotchSize.width + slack * 2,
            // A draggable HUD hangs directly below the notch, so the probe
            // keeps off its bar while one is up.
            height: adjustedNotchSize.height + (collapsedActivityIsInteractive ? 0 : slack)
        )
    }

    /// True while the closed notch is showing something you can drag — the
    /// volume and brightness bars. The closed slab is otherwise inert so the
    /// wings are not a hover target; these need it back, and they sit below
    /// the notch where the hover probe is not, so the two do not collide.
    var collapsedActivityIsInteractive: Bool {
        switch collapsedActivity {
        case .volume, .brightness: true
        default: false
        }
    }

    /// The two radii the notch shape is drawn with. Closed and peek keep the
    /// tight pill radii so the shape stays welded to the hardware notch; only
    /// the open slab takes the larger pair, and `cornerRadiusScaling` off
    /// keeps the closed pair throughout, as in the references.
    var cornerRadii: (top: CGFloat, bottom: CGFloat) {
        let insets = NotchSizing.cornerRadiusInsets
        guard mode == .expanded, settings.cornerRadiusScaling else { return insets.closed }
        return insets.opened
    }

    // MARK: - Hover / expansion

    func hoverChanged(_ hovering: Bool) {
        guard hovering != isHovering else { return }
        isHovering = hovering
        pendingHoverWork?.cancel()

        if hovering {
            hoverStartedAt = Date()
            if mode == .collapsed {
                mode = .peek
            }
            // Linger past the open delay to expand fully (when enabled).
            guard settings.expandOnHover, mode == .peek else { return }
            let work = DispatchWorkItem { [weak self] in
                self?.expand()
            }
            pendingHoverWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + settings.openDelay, execute: work)
        } else {
            hoverStartedAt = nil
            switch mode {
            case .peek:
                mode = .collapsed
            case .expanded:
                guard !isPinned, settings.autoCollapseOnMouseExit else { return }
                let work = DispatchWorkItem { [weak self] in
                    self?.collapse()
                }
                pendingHoverWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + settings.closeDelay, execute: work)
            case .collapsed:
                break
            }
        }
    }

    func togglePin() {
        withAnimation(NotchAnimations.content) {
            isPinned.toggle()
        }
    }

    /// Click always opens fully, from collapsed or peek — but ignores a click
    /// that lands in the first instants of a hover, which is characteristic of
    /// a pointer sweeping through rather than aiming at the notch.
    func handleTap() {
        guard mode != .expanded else { return }
        if let started = hoverStartedAt,
           Date().timeIntervalSince(started) < Self.minimumDwellForClick {
            return
        }
        expand()
    }

    func expand() {
        guard mode != .expanded else { return }
        pendingHoverWork?.cancel()
        // No withAnimation here: NotchContainerView drives the open/close
        // springs. Two animations on the same transition fight each other.
        mode = .expanded
        onModeChange?(mode)
        wakeModules()
    }

    func collapse() {
        guard mode == .expanded else { return }
        mode = .collapsed
        isDropTargeted = false
        isPinned = false
        // A collapse can arrive from an outside click or the hotkey, with the
        // pointer nowhere near the notch; leaving this set would make the next
        // genuine hover a no-op.
        isHovering = false
        pendingHoverWork?.cancel()
        onModeChange?(mode)
        sleepModules()
    }

    func select(_ newTab: NotchTab) {
        withAnimation(NotchAnimations.content) {
            tab = newTab
            // Leaving the player resets its lyrics panel, so returning to it
            // does not reopen at the taller size unexpectedly.
            if newTab != .media { mediaShowsFullLyrics = false }
        }
        settings.lastTab = newTab.rawValue
    }

    // MARK: - App lifecycle

    /// Everything this app holds that the system would rather it gave back:
    /// the capture stream, the CoreAudio listeners, the event tap and the
    /// module timers. Called on termination — a screen-capture stream that
    /// outlives the app keeps the recording indicator lit, and an event tap
    /// left enabled is a keystroke the next app does not get.
    func shutdown() {
        audioMeter.stop()
        audioApps.stopObserving()
        activities.stop()
        MediaKeyInterceptor.shared.stop()
        timer.cancel()
        sleepModules()
    }

    /// After a sleep/wake cycle the world has moved: CoreAudio re-enumerates
    /// its devices, so listeners attached before the sleep are pointed at
    /// objects that no longer exist, and the weather is however old the sleep
    /// was. Everything that is normally push-driven is re-armed here.
    func refreshAfterWake() {
        audioApps.restartObserving()
        audio.refresh()
        weather.refresh()
        calendar.refresh()
        shortcuts.refresh()
        syncAudioMeter()
        media.updateLyricActivityTimer()
        if mode == .expanded {
            wakeModules()
        }
    }

    // MARK: - Module lifecycle (zero background work while collapsed)

    private func wakeModules() {
        media.setActive(true)
        calendar.refresh()
        telemetry.start()
        weather.refresh()
        audio.refresh()
        refreshAudioApps()
        bluetooth.start()
        shortcuts.refresh()
    }

    private func sleepModules() {
        media.setActive(false)
        telemetry.stop()
        bluetooth.stop()
    }
}
