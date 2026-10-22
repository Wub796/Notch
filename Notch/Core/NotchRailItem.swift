/// A control on the open notch's left rail.
///
/// Home is deliberately not one of these: it is always first and cannot be
/// removed, so the list is the *modules* only and every screen keeps a way
/// back to it. The order here is the order on the rail, left to right.
enum NotchRailItem: String, CaseIterable, Identifiable, Sendable {
    case audio
    case shelf
    case tools
    case telemetry
    case notes
    case camera
    case faceID

    var id: String { rawValue }

    var title: String {
        switch self {
        case .audio: "Media"
        case .shelf: "Shelf"
        case .tools: "Tools"
        case .telemetry: "System Stats"
        case .notes: "Notes"
        case .camera: "Camera"
        case .faceID: "Face ID"
        }
    }

    var symbol: String {
        switch self {
        case .audio: "play.circle"
        case .shelf: "tray"
        case .tools: "timer"
        case .telemetry: "chart.xyaxis.line"
        case .notes: "doc.text"
        case .camera: "video"
        case .faceID: "faceid"
        }
    }

    var tab: NotchTab {
        switch self {
        case .audio: .audio
        case .shelf: .shelf
        case .tools: .tools
        case .telemetry: .telemetry
        case .notes: .notes
        case .camera: .camera
        case .faceID: .faceID
        }
    }

    /// Every module, in the order the rail shipped with, so nobody's panel
    /// changes until they change it.
    static let defaults: [NotchRailItem] = allCases

    /// Known items only, no duplicates, and never empty — a rail with no
    /// modules on it would leave every screen but Home unreachable from the
    /// panel, which is a broken notch rather than a preference.
    static func sanitized(_ items: [NotchRailItem]) -> [NotchRailItem] {
        var seen = Set<NotchRailItem>()
        let unique = items.filter { seen.insert($0).inserted }
        return unique.isEmpty ? defaults : unique
    }
}
