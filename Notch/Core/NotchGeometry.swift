import AppKit

/// Resolves the physical notch dimensions of a screen from its safe area,
/// with a simulated fallback for displays that have no notch.
struct NotchGeometry {
    let screen: NSScreen

    /// Simulated notch used on external / non-notched displays.
    static let fallbackSize = CGSize(width: 196, height: 32)

    var hasPhysicalNotch: Bool {
        screen.safeAreaInsets.top > 0
    }

    /// Exact hardware notch size: height from the safe area inset, width from
    /// the gap between the two auxiliary menu bar areas.
    var notchSize: CGSize {
        let topInset = screen.safeAreaInsets.top
        guard topInset > 0,
              let leftArea = screen.auxiliaryTopLeftArea,
              let rightArea = screen.auxiliaryTopRightArea
        else {
            return Self.fallbackSize
        }
        let width = screen.frame.width - leftArea.width - rightArea.width
        return CGSize(width: width, height: topInset)
    }

    /// The screen the panel should live on: prefer a display with a physical
    /// notch, otherwise the main display.
    static var preferredScreen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }
}
