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
    /// the gap between the two auxiliary menu bar areas plus a small bleed so
    /// the drawn pill fully covers the camera housing. Displays without a
    /// notch simulate one at menu bar height.
    var notchSize: CGSize {
        let topInset = screen.safeAreaInsets.top
        guard topInset > 0,
              let leftArea = screen.auxiliaryTopLeftArea,
              let rightArea = screen.auxiliaryTopRightArea
        else {
            let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
            return CGSize(
                width: Self.fallbackSize.width,
                height: menuBarHeight > 0 ? menuBarHeight : Self.fallbackSize.height
            )
        }
        let width = screen.frame.width - leftArea.width - rightArea.width + 4
        return CGSize(width: min(max(width, 120), screen.frame.width - 40), height: topInset)
    }

    /// The screen the panel should live on: prefer a display with a physical
    /// notch, otherwise the main display.
    static var preferredScreen: NSScreen? {
        // An explicit choice wins, when that display is still attached.
        let chosen = NotchSettings.shared.preferredScreenName
        if !chosen.isEmpty,
           let match = NSScreen.screens.first(where: { $0.localizedName == chosen }) {
            return match
        }
        return NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }
}
