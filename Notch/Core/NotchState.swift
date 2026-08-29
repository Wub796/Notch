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

    /// Notifies the window controller of mode transitions so it can manage
    /// key-window status (SwiftUI buttons in borderless panels only fire
    /// reliably once the panel is key).
    var onModeChange: ((NotchMode) -> Void)?

    /// Physical notch size, injected by NotchWindowController at launch.
    var notchSize: CGSize = NotchGeometry.fallbackSize

    /// Each tab sizes the slab to its own content, then the user's scale
    /// preference is applied on top.
    var expandedSize: CGSize {
        let base = baseExpandedSize
        let scale = min(max(settings.expandedScale, 0.8), 1.3)
        return CGSize(width: base.width * scale, height: base.height * scale)
    }

    private var baseExpandedSize: CGSize {
        switch tab {
        // height = top bar (38) + vertical padding (32) + the module's real
        // content height. These were previously guessed high, which left a
        // slab of dead black under every screen.
        case .home: CGSize(width: 980, height: 158)
        case .media: CGSize(width: 880, height: 296)
        case .weather: CGSize(width: 800, height: 272)
        case .calendar: CGSize(width: 760, height: 296)
        case .shelf: CGSize(width: 780, height: 206)
        case .clipboard: CGSize(width: 800, height: 190)
        case .tools: CGSize(width: 1000, height: 210)
        case .notes: CGSize(width: 720, height: 206)
        case .telemetry: CGSize(width: 800, height: 172)
        }
    }

    /// The measured notch, with the user's manual trim applied. Clamped so a
    /// slider can never drive it to zero or past the slab.
    var adjustedNotchSize: CGSize {
        CGSize(
            width: max(notchSize.width + settings.notchWidthAdjustment, 40),
            height: max(notchSize.height + settings.notchHeightAdjustment, 20)
        )
    }

    /// Height of the icon strip that flanks the hardware notch.
    var topBarHeight: CGFloat {
        max(adjustedNotchSize.height, 38)
    }

    /// Largest slab any tab can request; the panel window is sized to this.
    /// The panel window is sized once at launch, so it has to allow for the
    /// largest slab at the largest user scale (1.3x) — otherwise turning the
    /// size slider up would clip the panel against its own window.
    static let maxExpandedSize = CGSize(width: 980 * 1.3, height: 300 * 1.3)

    /// Hover is only detected over the physical notch (plus a small margin),
    /// never over the full slab — a wide detection radius made the notch open
    /// when the pointer was merely near the menu bar.
    var hoverProbeSize: CGSize {
        guard mode != .expanded else { return currentSize }
        let padding = min(max(settings.hoverPadding, 0), 80)
        return CGSize(
            width: adjustedNotchSize.width + padding,
            height: adjustedNotchSize.height + 4
        )
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

    private let focusMonitor = FocusModeMonitor()
    private let desktopMonitor = DesktopChangeMonitor()

    private var pendingHoverWork: DispatchWorkItem?
    private var hoverStartedAt: Date?
    private var isHovering = false

    /// Minimum dwell before a click counts as intentional rather than the tail
    /// of a fast pointer sweep across the menu bar.
    private static let minimumDwellForClick: TimeInterval = 0.06

    init() {
        // Personalization: reopen on the tab the user last used — but only a
        // tab the current UI can still reach; the top bar no longer exposes
        // every module, so restoring to a hidden one would strand the panel
        // with no way back home.
        if let restored = NotchTab(rawValue: settings.lastTab) {
            switch restored {
            case .home, .media, .weather, .calendar, .shelf:
                tab = restored
            default:
                tab = .home
            }
        }
        // Event-driven collapsed-notch features. Weather fetches at launch so
        // the collapsed wings have a temperature without the notch opening
        // first; refresh() is a no-op while the 30-minute cache is fresh.
        activities.start()

        // Brightness has no system notification, so the controller samples
        // while enabled and reports only changes it did not make itself.
        brightness.onExternalChange = { [weak self] level in
            self?.activities.showBrightness(level: level)
        }
        if settings.brightnessHUDEnabled {
            brightness.startHUDMonitoring()
        }
        settings.onBrightnessHUDSettingChanged = { [weak self] enabled in
            if enabled {
                self?.brightness.startHUDMonitoring()
            } else {
                self?.brightness.stopHUDMonitoring()
            }
        }
        calendar.bootstrapIfAuthorized()
        weather.refresh()

        media.onTrackChange = { [weak self] track in
            self?.activities.showTrackChange(title: track.title, artist: track.artist)
        }

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
        return nil
    }

    /// Extra width added around the hardware notch for the active activity —
    /// split evenly into two wings, so each side must fit half of this.
    private var activityWingWidth: CGFloat {
        switch collapsedActivity {
        case .music: 140
        case .lyrics: 150
        case .timer: 130
        case .trackChange: 240
        case .volume, .brightness: 176
        case .battery: 116
        case .screenLock: 180
        case .focusMode: 190
        case .eyeBreak: 210
        case .desktopChange: 150
        case .accessoryBattery: 240
        case .meetingSoon: 260
        case nil: settings.showCompactWeather ? 120 : 0
        }
    }

    var collapsedSize: CGSize {
        var size = adjustedNotchSize
        size.width += activityWingWidth
        // The lyric activity grows a slim bar under the hardware notch.
        if case .lyrics = collapsedActivity {
            size.height += 24
        }
        return size
    }

    var currentSize: CGSize {
        switch mode {
        case .collapsed:
            return collapsedSize
        case .peek:
            let peek = min(max(settings.peekScale, 1.0), 1.4)
            return CGSize(
                width: collapsedSize.width * peek,
                height: collapsedSize.height * peek
            )
        case .expanded:
            return expandedSize
        }
    }

    /// Corner radius per state, user-adjustable. Peek sits midway between
    /// the closed and open radii so the morph reads continuously.
    var cornerRadius: CGFloat {
        let closed = min(max(settings.collapsedCornerRadius, 0), 34)
        let open = min(max(settings.expandedCornerRadius, 8), 52)
        switch mode {
        case .collapsed: return closed
        case .peek: return closed + (open - closed) * 0.4
        case .expanded: return open
        }
    }

    // MARK: - Hover / expansion

    func hoverChanged(_ hovering: Bool) {
        guard hovering != isHovering else { return }
        isHovering = hovering
        pendingHoverWork?.cancel()

        if hovering {
            hoverStartedAt = Date()
            if mode == .collapsed {
                withAnimation(NotchAnimations.hover) {
                    mode = .peek
                }
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
                withAnimation(NotchAnimations.hover) {
                    mode = .collapsed
                }
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
        NotchTheme.Haptics.generic()
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
        NotchTheme.Haptics.alignment()
        withAnimation(NotchAnimations.expand) {
            mode = .expanded
        }
        onModeChange?(mode)
        wakeModules()
    }

    func collapse() {
        guard mode == .expanded else { return }
        NotchTheme.Haptics.alignment()
        withAnimation(NotchAnimations.collapse) {
            mode = .collapsed
            isDropTargeted = false
            isPinned = false
        }
        onModeChange?(mode)
        sleepModules()
    }

    func select(_ newTab: NotchTab) {
        withAnimation(NotchAnimations.content) {
            tab = newTab
        }
        settings.lastTab = newTab.rawValue
    }

    // MARK: - Module lifecycle (zero background work while collapsed)

    private func wakeModules() {
        media.setActive(true)
        calendar.refresh()
        telemetry.start()
        weather.refresh()
        audio.refresh()
        bluetooth.start()
        shortcuts.refresh()
    }

    private func sleepModules() {
        media.setActive(false)
        telemetry.stop()
        bluetooth.stop()
    }
}
