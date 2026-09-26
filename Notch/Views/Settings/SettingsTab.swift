import SwiftUI

/// The Settings window's tab list — what the floating pill tab bar renders
/// and what the page switch below it switches between.
///
/// Glance's (`Settings/SettingsTab.swift`, MIT © Jonathan Zhou) shape with
/// this app's panes: the same `title`/`icon` pair per tab, minus Glance's
/// debug-only Face Lab, which has no equivalent here — this app's debug hook
/// for a pane is the `--debug-pane` launch argument below.
enum SettingsTab: String, CaseIterable, Identifiable, Hashable {
    case general
    case notch
    case media
    case weather
    case activities
    case system
    case faceID
    case privacy
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .notch: "Notch"
        case .media: "Media"
        case .weather: "Weather"
        case .activities: "Activities"
        case .system: "System"
        case .faceID: "Face ID"
        case .privacy: "Privacy"
        case .about: "About"
        }
    }

    /// Every tab is a built-in symbol; `SettingsTabIcon` keeps the asset case
    /// Glance uses for its custom "Face" mark, so a future tab can adopt one
    /// without touching the tab bar.
    var icon: SettingsTabIcon {
        switch self {
        case .general: .system("gearshape.fill")
        case .notch: .system("sparkles.rectangle.stack.fill")
        case .media: .system("music.note")
        case .weather: .system("cloud.sun.fill")
        case .activities: .system("bolt.badge.clock.fill")
        case .system: .system("gauge.with.dots.needle.50percent")
        case .faceID: .system("faceid")
        case .privacy: .system("hand.raised.fill")
        case .about: .system("info.circle.fill")
        }
    }

    /// Tabs in tab bar order.
    static var visibleTabs: [SettingsTab] { allCases }

    /// The tab Settings opens on. Always General in release; a debug launch
    /// flag can pick another, which is the only way to put a specific tab in
    /// front of a screenshot without driving the UI.
    static var initial: SettingsTab {
        #if DEBUG
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--debug-pane"), i + 1 < args.count,
           let tab = SettingsTab(rawValue: args[i + 1]) {
            return tab
        }
        #endif
        return .general
    }
}
