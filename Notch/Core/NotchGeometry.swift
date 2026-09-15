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

    /// The horizontal centre of the hardware notch in screen coordinates.
    /// Auxiliary areas are the authoritative anchors; the screen midpoint can
    /// be wrong on displays whose menu bar/notch is not geometrically centred.
    var notchCenterX: CGFloat {
        guard let leftArea = screen.auxiliaryTopLeftArea,
              let rightArea = screen.auxiliaryTopRightArea else {
            return screen.frame.midX
        }
        return (leftArea.maxX + rightArea.minX) / 2
    }

    /// Exact hardware notch size: height from the safe area inset, width from
    /// the gap between the two auxiliary menu bar areas. Displays without a
    /// notch simulate one at menu bar height.
    ///
    /// This is the *measurement* and carries no coverage margin of its own.
    /// Everything drawn around the notch adds `NotchSizing.notchCoverageBleed`
    /// via `NotchState.safeNotchSize`, which is the single place that margin
    /// is decided — a second, undocumented `+ 4` here made the real bleed the
    /// sum of two numbers written down in different files.
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
        let width = rightArea.minX - leftArea.maxX
        return CGSize(width: min(max(width, 120), screen.frame.width - 40), height: topInset)
    }

    /// The screen the panel should live on: prefer a display with a physical
    /// notch, otherwise the main display.
    static var preferredScreen: NSScreen? {
        // An explicit choice wins, when that display is still attached. Two
        // identical monitors share a localizedName, so this can only ever pick
        // the first of a matching pair — which is why the notched display is
        // preferred ahead of `NSScreen.main` below rather than relying on it.
        let chosen = NotchSettings.shared.preferredScreenName
        if !chosen.isEmpty,
           let match = NSScreen.screens.first(where: { $0.localizedName == chosen }) {
            return match
        }
        return NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }
}
