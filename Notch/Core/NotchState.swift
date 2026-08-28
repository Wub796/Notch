import SwiftUI
import Observation

enum NotchMode: Equatable {
    case collapsed
    case expanded
}

enum NotchTab: String, CaseIterable, Identifiable {
    case media
    case shelf
    case calendar
    case telemetry

    var id: String { rawValue }

    var title: String {
        switch self {
        case .media: "Media"
        case .shelf: "Shelf"
        case .calendar: "Schedule"
        case .telemetry: "System"
        }
    }

    var systemImage: String {
        switch self {
        case .media: "music.note"
        case .shelf: "tray.full"
        case .calendar: "calendar"
        case .telemetry: "gauge.with.dots.needle.50percent"
        }
    }
}

/// Root observable state for the notch UI. Owns every feature module and
/// starts/stops their polling so the app does no periodic work while the
/// notch is collapsed.
@Observable
final class NotchState {
    var mode: NotchMode = .collapsed
    var tab: NotchTab = .media
    var isDropTargeted = false

    /// Physical notch size, injected by NotchWindowController at launch.
    var notchSize: CGSize = NotchGeometry.fallbackSize
    let expandedSize = CGSize(width: 670, height: 310)

    let settings = NotchSettings.shared
    let media = MediaController()
    let calendar = CalendarController()
    let telemetry = TelemetryController()
    let shelf = ShelfController()
    let keepAwake = KeepAwakeController()

    private var pendingHoverWork: DispatchWorkItem?

    init() {
        // Personalization: reopen on the tab the user last used.
        if let restored = NotchTab(rawValue: settings.lastTab) {
            tab = restored
        }
    }

    /// Collapsed width grows a pair of "wings" around the hardware notch when
    /// a track is loaded, to fit the mini artwork and the audio visualizer.
    var showsMediaWings: Bool {
        media.hasTrack && settings.showMediaWings
    }

    var collapsedSize: CGSize {
        var size = notchSize
        if showsMediaWings {
            size.width += 120
        }
        return size
    }

    var currentSize: CGSize {
        mode == .expanded ? expandedSize : collapsedSize
    }

    // MARK: - Hover / expansion

    func hoverChanged(_ hovering: Bool) {
        // Hover can only open the notch when the preference allows it;
        // hover-out always closes, however it was opened.
        if hovering, !settings.expandOnHover, mode == .collapsed {
            return
        }

        pendingHoverWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            hovering ? self?.expand() : self?.collapse()
        }
        pendingHoverWork = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + (hovering ? settings.openDelay : settings.closeDelay),
            execute: work
        )
    }

    /// Click-to-open, used when hover expansion is disabled (and harmless
    /// alongside it).
    func handleTap() {
        if mode == .collapsed {
            expand()
        }
    }

    func expand() {
        guard mode != .expanded else { return }
        NotchTheme.Haptics.alignment()
        withAnimation(.notchSpring) {
            mode = .expanded
        }
        wakeModules()
    }

    func collapse() {
        guard mode != .collapsed else { return }
        NotchTheme.Haptics.alignment()
        withAnimation(.notchSpring) {
            mode = .collapsed
            isDropTargeted = false
        }
        sleepModules()
    }

    func select(_ newTab: NotchTab) {
        withAnimation(.notchSpring) {
            tab = newTab
        }
        settings.lastTab = newTab.rawValue
    }

    // MARK: - Module lifecycle (zero background work while collapsed)

    private func wakeModules() {
        media.setActive(true)
        calendar.refresh()
        telemetry.start()
    }

    private func sleepModules() {
        media.setActive(false)
        telemetry.stop()
    }
}
