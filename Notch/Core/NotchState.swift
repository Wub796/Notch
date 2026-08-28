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

enum NotchTab: String, CaseIterable, Identifiable {
    case home
    case media
    case shelf
    case calendar
    case telemetry

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .media: "Media"
        case .shelf: "Shelf"
        case .calendar: "Schedule"
        case .telemetry: "System"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "square.grid.2x2.fill"
        case .media: "music.note"
        case .shelf: "tray.full"
        case .calendar: "calendar"
        case .telemetry: "gauge.with.dots.needle.50percent"
        }
    }
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

    /// Physical notch size, injected by NotchWindowController at launch.
    var notchSize: CGSize = NotchGeometry.fallbackSize

    /// Each tab sizes the slab to its own content — the dashboard is wide and
    /// short, detail tabs are narrower and a little taller.
    var expandedSize: CGSize {
        switch tab {
        case .home: CGSize(width: 780, height: 150)
        case .media: CGSize(width: 600, height: 208)
        case .shelf: CGSize(width: 620, height: 190)
        case .calendar: CGSize(width: 560, height: 214)
        case .telemetry: CGSize(width: 700, height: 178)
        }
    }

    /// Largest slab any tab can request; the panel window is sized to this.
    static let maxExpandedSize = CGSize(width: 780, height: 214)

    /// Hover is only detected over the physical notch (plus a small margin),
    /// never over the full slab — a wide detection radius made the notch open
    /// when the pointer was merely near the menu bar.
    var hoverProbeSize: CGSize {
        guard mode != .expanded else { return currentSize }
        return CGSize(width: notchSize.width + 16, height: notchSize.height + 4)
    }

    /// Hover peek grows the closed pill by this factor (Sapphire's scale).
    static let peekScale: CGFloat = 1.10

    let settings = NotchSettings.shared
    let media = MediaController()
    let calendar = CalendarController()
    let telemetry = TelemetryController()
    let shelf = ShelfController()
    let keepAwake = KeepAwakeController()
    let weather = WeatherService()
    let activities = LiveActivityManager()

    private var pendingHoverWork: DispatchWorkItem?
    private var hoverStartedAt: Date?

    /// Minimum dwell before a click counts as intentional rather than the tail
    /// of a fast pointer sweep across the menu bar.
    private static let minimumDwellForClick: TimeInterval = 0.06

    init() {
        // Personalization: reopen on the tab the user last used.
        if let restored = NotchTab(rawValue: settings.lastTab) {
            tab = restored
        }
        // Event-driven collapsed-notch features.
        activities.start()
        calendar.bootstrapIfAuthorized()

        media.onTrackChange = { [weak self] track in
            self?.activities.showTrackChange(title: track.title, artist: track.artist)
        }
    }

    // MARK: - Live activity resolution

    /// What the collapsed/peek notch is currently showing, by priority:
    /// transient HUD events, an imminent meeting, the live lyric line, then
    /// plain now-playing wings.
    var collapsedActivity: LiveActivity? {
        if let transient = activities.transient {
            return transient
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
        case .music: 120
        case .lyrics: 150
        case .trackChange: 240
        case .volume: 130
        case .battery: 116
        case .screenLock: 180
        case .meetingSoon: 260
        case nil: settings.showIdleFace ? 96 : 0
        }
    }

    var collapsedSize: CGSize {
        var size = notchSize
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
            return CGSize(
                width: collapsedSize.width * Self.peekScale,
                height: collapsedSize.height * Self.peekScale
            )
        case .expanded:
            return expandedSize
        }
    }

    /// Corner radius per state (Sapphire's closed/hover/click values).
    var cornerRadius: CGFloat {
        switch mode {
        case .collapsed: 10
        case .peek: 16
        case .expanded: 26
        }
    }

    // MARK: - Hover / expansion

    func hoverChanged(_ hovering: Bool) {
        pendingHoverWork?.cancel()

        if hovering {
            hoverStartedAt = Date()
            if mode == .collapsed {
                withAnimation(NotchAnimations.hover) {
                    mode = .peek
                }
            }
            // Linger past the open delay to expand fully (when enabled). The
            // work item is cancelled the moment the pointer leaves, so a
            // quick pass over the notch never opens it.
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
                guard !isPinned else { return }
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
    }

    private func sleepModules() {
        media.setActive(false)
        telemetry.stop()
    }
}
