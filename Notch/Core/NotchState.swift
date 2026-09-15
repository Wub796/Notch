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
    /// The player, plus audio devices and per-app volume. Opened from the
    /// Home media card; its "Now" section is the full-size player.
    case audio
    /// Full-screen weather detail with an hourly forecast.
    case weather
    /// Week-at-a-glance calendar detail.
    case calendar
    case shelf
    case tools
    case notes
    case telemetry
    /// A live mirror for checking yourself before a call.
    case camera
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

    /// Whether the Now player is showing its lyrics row, which affects panel
    /// height. Held here because the window size depends on it.
    var mediaShowsFullLyrics = false {
        didSet {
            guard oldValue != mediaShowsFullLyrics, mode == .expanded else { return }
            onModeChange?(mode)
        }
    }

    /// Whether the weather screen shows the five-day strip instead of hourly.
    /// Held here rather than in the view because the chips that toggle it sit
    /// in the header, which is a sibling of the module.
    var showsDailyForecast = false

    /// Notifies the window controller of mode transitions so it can manage
    /// key-window status (SwiftUI buttons in borderless panels only fire
    /// reliably once the panel is key).
    var onModeChange: ((NotchMode) -> Void)?

    /// Called synchronously just before the notch opens, so the window can
    /// grow ahead of the first animation frame. See `expand()`.
    var onWillExpand: (() -> Void)?

    /// Called just before a tab switch lands, with the incoming tab, so the
    /// window can grow for it first. See `select(_:)`.
    var onWillShowTab: ((NotchTab) -> Void)?

    /// Physical notch size, injected by NotchWindowController at launch.
    var notchSize: CGSize = NotchGeometry.fallbackSize

    /// The open slab, sized for the screen showing. Switching tabs resizes the
    /// panel, which the references avoid — but a month grid and a weather hero
    /// are genuinely different shapes, and forcing both into one box shrank
    /// each past legibility.
    var expandedSize: CGSize {
        expandedSize(for: tab)
    }

    /// The open slab for a given tab — the one showing, or one about to be, so
    /// the window can be grown for a screen before it arrives.
    func expandedSize(for tab: NotchTab) -> CGSize {
        var size = NotchSizing.openNotchSize(for: tab, showsLyrics: mediaShowsFullLyrics)
        // The Now page reveals or hides its compact synced lyric line. Keep
        // the panel fitted to that state so the blank area below the bar is
        // removed when lyrics are off and restored when they are on.
        // Tabs whose content is a fixed column report their natural height
        // so the slab hugs whatever is showing instead of carrying a black
        // band under it. The measured height is clamped to the budget the
        // tab already had — the panel may shrink to its content, never grow
        // past today's size — and the width stays on the tuned per-tab value.
        if tab == .audio, devicesSection == .now {
            // Now is a short fixed column; the default Audio budget is sized
            // for Library and Audio, so it top-aligns and leaves a band of
            // empty panel beneath the heart/shuffle row. Hug the page instead
            // (growing when the synced lyric line is toggled on) while keeping
            // a thick safe inset below the row so it never sits on the slab's
            // rounded bottom edge. The height is set outright, not bumped up
            // with max, so the slab can shrink down to Now rather than being
            // locked to the taller Audio budget.
            let header = topBarHeight + 6 + NotchSizing.contentBottomInset(for: tab)
            let moduleHeight = DevicesScreenMetrics.naturalNowHeight(
                showsLyrics: mediaShowsFullLyrics
            ) + DevicesScreenMetrics.bottomSafePadding
            size.height = moduleHeight + header
        } else if NotchSizing.fitsHeight(for: tab) {
            let header = topBarHeight + 6 + NotchSizing.contentBottomInset(for: tab)
            let budget = max(size.height - header, NotchSizing.minimumFittedModuleHeight)
            // Home's natural height is derived from its content rather than
            // the runtime measurement: the artwork column plus the optional
            // other-audio chips row. The preference-based measurement never
            // reliably landed here, leaving the slab on its full budget —
            // the black band under the dashboard this fitting exists to
            // remove.
            let natural: CGFloat
            if tab == .home {
                natural = HomeDashboardMetrics.naturalHeight(
                    hasOtherAudioChips: settings.dashboardWidgets.contains(.music)
                    && !otherAudioApps.isEmpty
                )
            } else if let measured = measuredHeights[tab] {
                natural = measured
            } else {
                natural = budget
            }
            let clamped = min(max(natural, NotchSizing.minimumFittedModuleHeight), budget)
            size.height = clamped + header
        }

        // Tabs that draw the full module rail must never be narrower than the
        // rail + hardware notch + insets, or a switch to a narrow module (e.g.
        // Notes) would slide the rightmost rail icons under the notch. Floor
        // the slab's width so every rail control stays visible and clickable.
        if NotchSizing.usesFullTopRail(for: tab) {
            let insets = (NotchSizing.cornerRadiusInsets.opened.top
                + NotchSizing.openContentInset) * 2
            let minWidth = safeNotchSize.width
                + NotchSizing.topBarRailWidth(
                    controlCount: NotchSizing.topBarRailControlCount
                ) * 2
                + insets
            size.width = max(size.width, minWidth)
        }
        return size
    }

    /// True while a volume/brightness HUD is dropping below the open module.
    /// The expanded slab grows by a band to hold it rather than covering the
    /// module (see `NotchSizing.expandedHUDDropHeight`).
    var isShowingExpandedHUD: Bool {
        guard let transient = activities.transient else { return false }
        switch transient {
        case .volume, .brightness: return true
        default: return false
        }
    }

    /// The full height the open slab occupies: `expandedSize` plus, while a
    /// HUD is dropping below the module, the band that holds it. Shared by the
    /// view (which frames the slab) and the window controller (which sizes the
    /// interactive region), so click and drag hit-testing always covers the
    /// whole panel including the dropped bar.
    var expandedTotalHeight: CGFloat {
        expandedTotalHeight(for: tab)
    }

    func expandedTotalHeight(for tab: NotchTab) -> CGFloat {
        expandedSize(for: tab).height
            + (isShowingExpandedHUD ? NotchSizing.expandedHUDDropHeight : 0)
    }

    /// Apps currently putting audio out besides the one the dashboard's
    /// music card shows — the row of chips beneath it. The slab sizes
    /// itself to this and HomeDashboardView renders it, so there is one
    /// source of truth rather than two copies that can drift.
    var otherAudioApps: [AudioAppMonitor.App] {
        // While a real music app (or a probed browser video) owns the
        // now-playing session, the hero card already identifies the source —
        // listing Chrome next to a Spotify cover is noise. The chips row is
        // for when nothing tracked is showing and the hero falls back to
        // "whatever is making sound".
        guard !(media.hasTrack || media.isBrowserVideo) else { return [] }
        let playing = audioApps.apps.filter(\.isPlaying)
        guard !playing.isEmpty else { return [] }
        let heroID = media.sourceAppBundleID ?? playing[0].id
        return playing.filter { $0.id != heroID }
    }

    /// Natural module heights, remembered per tab once measured. Re-opening a
    /// tab therefore lands directly on its fitted height instead of opening at
    /// the fixed budget and then settling down to the measured height — which
    /// is what made icon clicks animate in two steps.
    private var measuredHeights: [NotchTab: CGFloat] = [:]

    /// The open module's natural height for the current tab, reported by
    /// NotchLayoutView's hidden size pass. nil until the module has laid out
    /// once, so the slab falls back to the fixed per-tab budget before the
    /// measurement lands.
    var measuredModuleHeight: CGFloat? {
        measuredHeights[tab]
    }

    /// Records the module's natural height from the layout pass. Rounded and
    /// change-guarded so a sub-point wobble in text metrics can never ping-pong
    /// the slab size; animated so the settle from the budget to the fitted
    /// height eases instead of snapping. The tab is passed explicitly because
    /// the measurement is deferred off the layout pass and the selection can
    /// have moved on by the time it lands.
    func updateMeasuredModuleHeight(_ height: CGFloat, for tab: NotchTab) {
        guard height > 0 else { return }
        let rounded = height.rounded()
        #if DEBUG
        // Home's slab height comes from `HomeDashboardMetrics`, a hand-written
        // copy of the dashboard's own arithmetic, because the measurement
        // below never reliably lands for that tab. Hand-written copies drift:
        // change a padding in HomeDashboardView and the slab quietly regrows
        // the black band the fitting exists to remove. When a measurement
        // *does* arrive, check the constant against it and say so.
        if tab == .home {
            let declared = HomeDashboardMetrics.naturalHeight(
                hasOtherAudioChips: settings.dashboardWidgets.contains(.music)
                    && !otherAudioApps.isEmpty
            )
            if abs(declared - rounded) > 4 {
                print(
                    "[Notch] HomeDashboardMetrics.naturalHeight is \(declared)pt "
                    + "but the dashboard measured \(rounded)pt — update the "
                    + "constants in HomeDashboardMetrics."
                )
            }
        }
        #endif
        guard abs((measuredHeights[tab] ?? 0) - rounded) >= 1 else { return }
        withAnimation(NotchAnimations.content) {
            measuredHeights[tab] = rounded
        }
    }

    /// Room left for a module once the header and the slab's own insets are
    /// taken out. Module views are written to this budget.
    var moduleContentSize: CGSize {
        let open = expandedSize
        let horizontal = NotchSizing.contentSideInset(for: tab) * 2
        let vertical = topBarHeight + 6 + NotchSizing.contentBottomInset(for: tab)
        return CGSize(
            width: max(0, open.width - horizontal),
            height: max(0, open.height - vertical)
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

    /// The notch size guaranteed to fully cover the real hardware cutout:
    /// the measured size plus a coverage bleed. Everything laid out beside
    /// the notch — the header flanks, the collapsed wings, the hover probe —
    /// is sized against this, so a notch measured a point or two narrow can
    /// never crop, cover, or hide what sits next to it.
    var safeNotchSize: CGSize {
        CGSize(
            width: adjustedNotchSize.width + NotchSizing.notchCoverageBleed,
            height: adjustedNotchSize.height
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
        // 1.0 -> 0pt, the 1.10 default -> 6pt, the 1.4 maximum -> 24pt. The
        // ceiling keeps the widest setting from pushing the wings out past
        // the menu bar items either side of the notch.
        return min((scale - 1) * 60, 24)
    }

    /// Height of the icon strip that flanks the hardware notch.
    var topBarHeight: CGFloat {
        max(adjustedNotchSize.height + 8, 44)
    }

    let settings = NotchSettings.shared
    let media = MediaController()
    let calendar = CalendarController()
    let telemetry = TelemetryController()
    let shelf = ShelfController()
    /// Downloads and screenshots as they land — see `FileCatcher`.
    let fileCatcher = FileCatcher()
    let keepAwake = KeepAwakeController()
    let weather = WeatherService()
    let activities = LiveActivityManager()
    let clipboard = ClipboardManager()
    let notes = NotesManager()
    let timer = TimerManager()
    let eyeBreak = EyeBreakManager()
    let shortcuts = ShortcutsManager()
    let audio = AudioOutputManager.shared
    /// Microphone devices and levels — the Audio screen's input control.
    let audioInput = AudioInputManager()
    let bluetooth = BluetoothBatteryMonitor()
    let brightness = BrightnessController()
    let quickActions = QuickActions()
    /// The webcam preview. Strictly bound to its screen being visible.
    let camera = CameraController()
    /// The Spotify sign-in behind the Canvas feature.
    let spotifyCanvasSession = SpotifyCanvasSession.shared
    /// The current track's Spotify Canvas video, when signed in and enabled.
    let spotifyCanvas: SpotifyCanvasController
    let audioApps = AudioAppMonitor()
    let audioMeter = SystemAudioMeter()

    /// Which screen of the Devices surface is showing.
    var devicesSection: DevicesSection = .now {
        didSet {
            // The Now page's lyric visibility is local to that page.
            if oldValue == .now, devicesSection != .now {
                mediaShowsFullLyrics = false
            }
            // The Devices subsections have different vertical budgets; keep
            // the top edge fixed while the window grows or shrinks below it.
            if mode == .expanded {
                onModeChange?(mode)
            }
        }
    }

    /// Which output surface the Audio screen is showing.
    var audioTab: AudioScreenTab = .apps

    private let focusMonitor = FocusModeMonitor()
    private let desktopMonitor = DesktopChangeMonitor()

    private var pendingHoverWork: DispatchWorkItem?

    /// An open scheduled by `expand()`; a collapse that lands first cancels it.
    private var pendingExpandWork: DispatchWorkItem?

    /// A tab switch scheduled by `select(_:)`; a newer one replaces it.
    private var pendingSelectWork: DispatchWorkItem?
    private var hoverStartedAt: Date?

    /// Whether the pointer is over the notch. Read by the view for its hover
    /// affordances; there is deliberately only one copy of this.
    private(set) var isHovering = false

    /// Minimum dwell before a click counts as intentional rather than the tail
    /// of a fast pointer sweep across the menu bar.
    private static let minimumDwellForClick: TimeInterval = 0.06

    init() {
        spotifyCanvas = SpotifyCanvasController(
            session: spotifyCanvasSession,
            media: media
        )
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
        audio.startListening()
        audio.refreshAlertVolume()
        // startListening does the initial refresh, then keeps it current.
        audioInput.startListening()

        activities.onActivityChange = { [weak self] in
            guard let self else { return }
            self.onModeChange?(self.mode)
        }

        timer.onStateChange = { [weak self] in
            guard let self else { return }
            self.onModeChange?(self.mode)
        }

        media.onTrackChange = { [weak self] track in
            guard let self else { return }
            self.activities.showTrackChange(title: track.title, artist: track.artist)
            self.spotifyCanvas.trackChanged()
        }
        settings.onSpotifyCanvasSettingChanged = { [weak self] _ in
            self?.spotifyCanvas.refresh()
        }
        spotifyCanvasSession.onStatusChange = { [weak self] _ in
            self?.spotifyCanvas.refresh()
        }

        // The visualizer is data-only and does not capture screen pixels.
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
        // Pinning an app keeps it listed; the monitor re-reads the list with
        // the pinned set applied.
        settings.onPinnedAudioAppsChanged = { [weak self] _ in
            self?.refreshAudioApps()
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

        desktopMonitor.onChange = { [weak self] index in
            self?.activities.showDesktopChange(index: index)
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

        fileCatcher.onCatch = { [weak self] caught in
            guard let self else { return }
            // Also shelve it, so it is still reachable once the notch has
            // moved on — the activity is a six-second window, the shelf is not.
            if self.settings.caughtFilesJoinShelf {
                self.shelf.add([caught.url])
            }
            self.onModeChange?(self.mode)
        }
        settings.onFileCatcherSettingChanged = { [weak self] _ in
            self?.fileCatcher.syncWatchers()
        }
        fileCatcher.start()

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
        if settings.realtimeAudioMeter {
            if media.isPlaying || audioApps.isAnyAudioPlaying {
                audioMeter.start()
            } else {
                audioMeter.stop()
            }
        } else {
            audioMeter.stop()
        }
    }

    /// What the collapsed visualiser should draw: the measured bands when the
    /// meter is live, and nil when the volume-driven fallback should be used.
    var visualizerBands: [Float]? {
        guard audioMeter.isLive else { return nil }
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
        interceptor.setBrightness = { [weak self] level in
            self?.brightness.setBrightness(level) ?? level
        }
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
    /// transient HUD events, a running timer, an imminent meeting, the live
    /// lyric line, active music playback / sound, then idle weather wings.
    var collapsedActivity: LiveActivity? {
        if let transient = activities.transient {
            return transient
        }
        // A file that just landed is a moment worth interrupting for — it is
        // the one activity the user can act on by dragging it straight out.
        if let caught = fileCatcher.latest {
            return .fileCaught(name: caught.name, source: caught.source)
        }
        // A running timer owns the notch until it finishes or is cancelled.
        if timer.isRunning {
            return .timer(remaining: timer.remaining, progress: timer.progress)
        }
        if settings.liveActivitiesEnabled, let event = calendar.upcomingSoon {
            return .meetingSoon(title: event.title, start: event.start)
        }
        if settings.lyricActivityEnabled, media.isPlaying,
           let lyric = media.collapsedLyric {
            return .lyrics(line: lyric.text, duration: lyric.end - lyric.start)
        }
        // Any active music playback or app audio replaces the weather wings
        // next to the notch.
        if isAudioActive {
            return .music
        }
        return nil
    }

    /// Whether the closed notch should be wearing its music wings — the cover
    /// on the left and the visualiser on the right.
    ///
    /// The single source of truth for that question: `collapsedActivity`
    /// decides whether to *return* `.music`, and `CollapsedNotchView` decides
    /// what to draw on the notch's own row while some other activity is
    /// dropped beneath it. Those two used to carry separate copies of this
    /// expression, and only one of them was ever updated.
    ///
    /// `showWingsForAnyAudio` gates the CoreAudio "something is making sound"
    /// signal specifically: that reports an open stream rather than audible
    /// sound, so an app that holds one keeps the wings up. Playback the notch
    /// can actually see is never gated by it.
    var isAudioActive: Bool {
        if media.isPlaying { return true }
        if media.hasTrack, settings.showMediaWings { return true }
        return settings.showWingsForAnyAudio && audioApps.isAnyAudioPlaying
    }

    /// Extra width added around the hardware notch for the active activity —
    /// split evenly into two wings, so each side must fit half of this.
    private var activityWingWidth: CGFloat {
        switch collapsedActivity {
        // Each side is `NotchSizing.closedWingInset` of margin, the content,
        // and ~10pt clear of the camera housing, so a wing needs roughly its
        // content's width plus 23pt. The cover and visualiser are 22pt.
        case .music: 96
        // The lyric line lives under the notch and wants room to read; the
        // wings only carry the cover and the visualiser.
        case .lyrics: 120
        // Volume and brightness should not make the closed notch narrower
        // than the music pill while their bar is dropped beneath it.
        case .volume, .brightness: max(flankWingWidth, 96)
        // Everything else drops its reading beneath the notch, so the wings
        // only carry what stays on the notch's own row.
        case .battery, .timer, .trackChange, .screenLock, .focusMode, .eyeBreak,
             .accessoryBattery, .meetingSoon, .fileCaught:
            flankWingWidth
        // An 18pt glyph and a one- or two-digit number.
        case .desktopChange: 82
        case nil: settings.showCompactWeather ? Self.weatherWingWidth : 0
        }
    }

    /// The wings `CollapsedNotchView.notchRowFlank` draws beside a dropped
    /// activity: media while something is playing, otherwise the weather.
    private var flankWingWidth: CGFloat {
        if isAudioActive { return 96 }
        return settings.showCompactWeather ? Self.weatherWingWidth : 82
    }

    /// The weather glyph is 23pt and the temperature up to ~38pt ("100°"), so
    /// the temperature sets it. The old 82–108 left it touching the camera.
    private static let weatherWingWidth: CGFloat = 124

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
        // Unplugged: an ordinary dropped row.
        case .battery: 36
        case .timer: 42
        // Taller than a plain row: this one carries a thumbnail and is a drag
        // target, so it needs to be worth aiming at.
        case .fileCaught: 54
        case .screenLock, .focusMode, .eyeBreak, .accessoryBattery, .meetingSoon: 36
        default: 0
        }
    }

    var collapsedSize: CGSize {
        var size = safeNotchSize
        size.width += activityWingWidth
        size.height += activityDropHeight
        return size
    }

    /// The closed notch's hover target: the live measured notch, plus the Hover
    /// Side Tolerance on the sides only.
    ///
    /// The height stays exactly the notch, so raising the tolerance can never
    /// make the notch peek while the cursor merely rests beneath it — it only
    /// widens the side catch for fast crossings. The wings and any dropped
    /// activity bar are deliberately not part of it, and the tolerance defaults
    /// to 0, so out of the box this is exactly the notch and nothing more.
    ///
    /// Read fresh on every hit-test and every cursor sample rather than cached:
    /// a display change or a notch-size trim has to land on the hit target at
    /// once, not on the next rebuild of the panel.
    var hoverProbeSize: CGSize {
        let slack = min(max(settings.hoverTolerance, 0), 32)
        return CGSize(
            width: adjustedNotchSize.width + slack * 2,
            height: adjustedNotchSize.height
        )
    }

    /// True while the closed notch is showing something you can drag — the
    /// volume and brightness bars. The closed slab is otherwise inert so the
    /// wings are not a hover target; these need it back, and they sit below
    /// the notch where the hover probe is not, so the two do not collide.
    var collapsedActivityIsInteractive: Bool {
        switch collapsedActivity {
        // The HUD bars are draggable; a caught file is draggable *out*, which
        // is the whole point of showing it.
        case .volume, .brightness, .fileCaught: true
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
        guard mode != .expanded, pendingExpandWork == nil else { return }
        pendingHoverWork?.cancel()
        // Opened on the next turn of the run loop, never inline. Opening
        // resizes the panel window, and a click reaches here from inside
        // SwiftUI's tap handling: resizing the hosting window there re-entered
        // SwiftUI's update and corrupted its view graph, and the app crashed a
        // moment later with EXC_BAD_ACCESS while building the Home dashboard.
        // One turn later nothing is mid-update.
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingExpandWork = nil
            guard self.mode != .expanded else { return }
            // The window is sized for the open slab *before* the flip renders.
            // Resizing from `onModeChange` let the spring's first frames draw
            // into the closed notch's window: a hard, flat edge that crossed
            // the panel for the first ~100ms of every open.
            self.onWillExpand?()
            // No withAnimation here: NotchContainerView drives the open/close
            // springs. Two animations on the same transition fight each other.
            self.mode = .expanded
            self.onModeChange?(self.mode)
            self.wakeModules()
        }
        pendingExpandWork = work
        DispatchQueue.main.async(execute: work)
    }

    func collapse() {
        // A close that arrives before a scheduled open has run cancels it,
        // rather than the open landing afterwards.
        pendingExpandWork?.cancel()
        pendingExpandWork = nil
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
        settings.lastTab = newTab.rawValue
        pendingSelectWork?.cancel()
        // Applied on the next turn of the run loop, like `expand()`. The window
        // grows for the incoming screen before the switch renders — resizing
        // only afterwards, from `onModeChange`, let a taller screen's first
        // frames draw into the old window — and a tab button reaches here from
        // inside SwiftUI's event handling, where resizing the hosting window
        // re-enters SwiftUI's update.
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingSelectWork = nil
            if self.mode == .expanded { self.onWillShowTab?(newTab) }
            withAnimation(NotchAnimations.content) {
                self.tab = newTab
                // Leaving the player resets its lyric visibility, so returning
                // to it does not reopen with a stale preference unexpectedly.
                if newTab != .audio { self.mediaShowsFullLyrics = false }
            }
            self.onModeChange?(self.mode)
        }
        pendingSelectWork = work
        DispatchQueue.main.async(execute: work)
    }

    // MARK: - Action feedback

    /// A brief in-panel confirmation for a user action ("Copied", "Pinned"…).
    /// Shown as a small capsule at the bottom of the open panel and dismissed
    /// automatically; firing another replaces it rather than stacking.
    struct NotchToast {
        let message: String
        let symbol: String
    }

    private(set) var toast: NotchToast?
    private var toastDismissWork: DispatchWorkItem?

    /// Raises a confirmation toast for the action just performed. Small and
    /// brief on purpose — it exists so a click that changed something unseen
    /// (copied to the clipboard, cleared a list) visibly landed, not to shout
    /// over the action itself.
    func showToast(_ message: String, symbol: String) {
        toastDismissWork?.cancel()
        withAnimation(NotchAnimations.content) {
            toast = NotchToast(message: message, symbol: symbol)
        }
        let work = DispatchWorkItem { [weak self] in
            withAnimation(NotchAnimations.content) {
                self?.toast = nil
            }
        }
        toastDismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
    }

    // MARK: - App lifecycle

    /// Everything this app holds that the system would rather it gave back:
    /// the audio listeners, the event tap and the
    /// module timers. Called on termination — a screen-capture stream that
    /// outlives the app keeps the recording indicator lit, and an event tap
    /// left enabled is a keystroke the next app does not get.
    func shutdown() {
        audioMeter.stop()
        audioApps.stopObserving()
        audio.stopListening()
        audioInput.stopListening()
        activities.stop()
        focusMonitor.stop()
        desktopMonitor.stop()
        eyeBreak.setEnabled(false)
        MediaKeyInterceptor.shared.stop()
        clipboard.stop()
        camera.stop()
        fileCatcher.stop()
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
        fileCatcher.syncWatchers()
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
        // Belt and braces with CameraView's own onDisappear: a collapse should
        // never leave the capture device open and the hardware light on.
        camera.stop()
        media.setActive(false)
        telemetry.stop()
        bluetooth.stop()
    }
}
