import SwiftUI
import Observation

enum NotchMode: Equatable {
    case collapsed
    case expanded
}

enum NotchTab: String, CaseIterable, Identifiable {
    case media
    case calendar
    case telemetry

    var id: String { rawValue }

    var title: String {
        switch self {
        case .media: "Media"
        case .calendar: "Schedule"
        case .telemetry: "System"
        }
    }

    var systemImage: String {
        switch self {
        case .media: "music.note"
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
    let expandedSize = CGSize(width: 640, height: 280)

    let media = MediaController()
    let calendar = CalendarController()
    let telemetry = TelemetryController()
    let airDrop = AirDropController()

    private var pendingHoverWork: DispatchWorkItem?

    /// Collapsed width grows a pair of "wings" around the hardware notch when
    /// media is playing, to fit the mini artwork and the audio visualizer.
    var collapsedSize: CGSize {
        var size = notchSize
        if media.hasActiveTrack {
            size.width += 120
        }
        return size
    }

    var currentSize: CGSize {
        mode == .expanded ? expandedSize : collapsedSize
    }

    // MARK: - Hover / expansion

    func hoverChanged(_ hovering: Bool) {
        pendingHoverWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            hovering ? self?.expand() : self?.collapse()
        }
        pendingHoverWork = work
        // Slight open delay avoids expanding on accidental fly-bys; the close
        // delay keeps the panel open while the pointer crosses internal gaps.
        DispatchQueue.main.asyncAfter(deadline: .now() + (hovering ? 0.1 : 0.35), execute: work)
    }

    func expand() {
        guard mode != .expanded else { return }
        withAnimation(.notchSpring) {
            mode = .expanded
        }
        wakeModules()
    }

    func collapse() {
        guard mode != .collapsed else { return }
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
