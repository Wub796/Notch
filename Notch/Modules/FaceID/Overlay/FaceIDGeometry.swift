import AppKit
import CoreGraphics
import SwiftUI

/// Which silhouette the Face ID panel wears on a given screen.
enum FaceIDPanelStyle: Equatable {
    /// Inverted top corners, flush with the screen's top edge, sitting on the
    /// physical notch. The scan hides behind hardware that is already there.
    case notch
    /// A fully-rounded pill, detached from the edge, for Macs without a notch.
    case pill
}

/// The geometry the Face ID panel is drawn to — pure numbers, no window
/// knowledge.
///
/// Ported from Glance (`NotchOverlay/NotchGeometry.swift`, MIT © Jonathan Zhou).
/// Deliberately separate from this app's `NotchGeometry`, which describes the
/// interactive panel: this one sizes the scan around the hardware cutout and
/// places a separate now-playing surface above macOS's lock-screen account UI.
struct FaceIDGeometry: Equatable {
    /// The physical notch's own dimensions, or `pillClosedSize`.
    let closedSize: CGSize
    /// Whether this screen has a real physical notch rather than the pill fallback.
    let isPhysicalNotch: Bool

    var style: FaceIDPanelStyle { isPhysicalNotch ? .notch : .pill }

    /// The fixed footprint of expanded scan content in notch style, sized for the
    /// square scan animation plus breathing room. The pill has its own size.
    static let notchOpenSize = CGSize(width: 220, height: 200)
    static let pillOpenSize = CGSize(width: 180, height: 180)

    /// Larger, detached lock-screen media surface positioned above the native
    /// login card. Its own window keeps it out of the notch scan and fits artwork,
    /// transport, seek, volume, and brightness controls.
    static let nowPlayingPlayerWidth: CGFloat = 480
    static let nowPlayingPlayerHeight: CGFloat = 270
    /// macOS doesn't expose a stable public frame for the lock-screen account
    /// card. Keep the player in the lower half of the display with comfortable
    /// space below the native account and password controls on short screens.
    static func nowPlayingOrigin(for screen: NSScreen, size: CGSize) -> NSPoint {
        let frame = screen.frame
        // AppKit's screen origin is bottom-left. Center at 35% of the screen height
        // to move the panel a lot lower than the previous above-midpoint placement.
        let verticalCenter = frame.minY + frame.height * 0.35
        let minX = frame.minX + 16
        let maxX = max(minX, frame.maxX - size.width - 16)
        let x = min(max(frame.midX - size.width / 2, minX), maxX)
        let minY = frame.minY + 24
        let topInset = max(screen.safeAreaInsets.top, 28) + 24
        let maxY = max(minY, frame.maxY - topInset - size.height)
        let y = min(max(verticalCenter - size.height / 2, minY), maxY)
        return NSPoint(x: x, y: y)
    }

    static let nowPlayingPanelCornerRadius: CGFloat = 34

    /// Corner radii for the notch silhouette. The top radius doubles as the width
    /// of the outward flare on each side — see `FaceIDShape`.
    static let closedTopRadius: CGFloat = 8
    static let closedBottomRadius: CGFloat = 12
    static let openTopRadius: CGFloat = 16
    static let openBottomRadius: CGFloat = 60

    /// A shape drawn in a rect of width `w` has a visible body of `w - 2·topRadius`;
    /// zero in pill style, which has no flare.
    static func flareAllowance(topRadius: CGFloat, style: FaceIDPanelStyle) -> CGFloat {
        style == .notch ? topRadius * 2 : 0
    }

    // MARK: - Pill style (Macs without a notch)

    /// Deliberately narrower than every expanded footprint, so growth reads as
    /// something actually happening rather than as a size that was always there.
    static let pillClosedSize = CGSize(width: 80, height: 24)

    /// Never zero — being detached from the screen edge is the whole point of the
    /// pill.
    static let pillTopGap: CGFloat = 3

    /// Uniform on all four corners, unlike the notch, which is why it shares the
    /// open bottom radius.
    static let pillOpenCornerRadius: CGFloat = 48

    /// Blur applied to the whole panel while it is parked off-screen, resolving to
    /// zero as it slides into place — so it comes into focus rather than simply
    /// appearing.
    static let pillEnterBlur: CGFloat = 0

    /// Comfortably more than `pillEnterBlur`: a Gaussian blur spreads past its
    /// nominal radius, and without this margin the parked pill smears a faint band
    /// at the top of the screen.
    static let pillOffscreenSlack: CGFloat = 20

    /// Padding around scan content in each style, tuned independently because the
    /// notch's camera housing already occupies the top of the panel.
    static let notchContentPaddingTop: CGFloat = 26
    static let notchContentPaddingLeading: CGFloat = 40
    static let notchContentPaddingTrailing: CGFloat = 40
    static let notchContentPaddingBottom: CGFloat = 30

    static let pillContentPaddingTop: CGFloat = 32
    static let pillContentPaddingLeading: CGFloat = 32
    static let pillContentPaddingTrailing: CGFloat = 32
    static let pillContentPaddingBottom: CGFloat = 32

    // Panel opening and closing use the shared animation profile, so the
    // lock-screen overlay stays in step with the rest of the notch and respects
    // Reduce Motion.

    // MARK: - Pill enter/exit choreography
    //
    // Slide and expansion run on independent timelines: entering, the pill slides
    // first and then grows; exiting, it shrinks first and then slides away.

    static let pillSlideDuration: Double = 0.25
    static var slideAnimation: Animation {
        NotchAnimations.prefersReducedMotion
            ? NotchAnimations.reduced
            : .easeOut(duration: pillSlideDuration)
    }
    /// Expansion starts this long after the slide begins.
    static let pillEnterExpansionDelay: Double = 0.16
    /// Slide starts this long after the shrink begins.
    static let pillExitSlideDelay: Double = 0.18

    // MARK: - Minimal unlock style
    //
    // `UnlockAnimationStyle.minimal`: the silhouette widens only, revealing a lock
    // glyph on one side and the scan video on the other. See
    // `FaceIDMinimalUnlockView`.

    /// Total body width is `closedSize.width + 2 · this`.
    static let minimalNotchFlankWidth: CGFloat = 42
    static let minimalPillOpenWidth: CGFloat = 150
    /// Taller than `pillClosedSize.height` for legibility; the radius stays half
    /// the height so it remains a true capsule while stretching.
    static let minimalPillOpenHeight: CGFloat = 40
    /// Extra height added only in notch style — the physical notch's height can't
    /// change, so this appears as real black below it.
    static let minimalNotchHeightBump: CGFloat = 12
    /// More rounded than the resting silhouette's radii, in the same proportion the
    /// full-expand style uses.
    static let minimalNotchTopRadius: CGFloat = 12
    static let minimalNotchBottomRadius: CGFloat = 22
    /// The flare already occupies `topRadius` of this margin in notch style.
    static let minimalContentEdgeInset: CGFloat = 4

    static let minimalLockIconSize: CGFloat = 14
    static let minimalNotchLockIconSize: CGFloat = 16
    /// The video is square and aspect-fit, so its rendered size is really
    /// `min(this, panelHeight - 2 · mediaVerticalInset)`.
    static let minimalMediaWidth: CGFloat = 34
    static let minimalNotchMediaWidth: CGFloat = 40
    /// Without this the square aspect-fits to the full panel height and touches
    /// both edges.
    static let minimalMediaVerticalInset: CGFloat = 8
    static let minimalNotchMediaVerticalInset: CGFloat = 11

    /// So the lock glyph can be nudged to land with the video's own resolve beat.
    static let minimalLockUnlockDelay: Double = 0

    // MARK: - Scan "breathing" pulse
    //
    // While scanning, content ping-pongs between full size and this, so the panel
    // reads as actively searching rather than as a frozen frame that happens to be
    // showing a face-shaped video.

    static let scanPulseScale: CGFloat = 0.97
    static let scanPulseOpacity: Double = 0.65
    /// One half-cycle: full to dimmed, or dimmed to full.
    static let scanPulseHalfCycleDuration: Double = 0.4
    static var scanPulseAnimation: Animation {
        NotchAnimations.prefersReducedMotion
            ? NotchAnimations.reduced
            : .easeInOut(duration: scanPulseHalfCycleDuration)
    }
    static let scanPulseHoldDuration: Double = 0.05
    /// Deliberately quicker than a half-cycle, so content is back at full while the
    /// success or failure animation is still early in its playback.
    static let scanPulseSettleDuration: Double = 0.2
    static var scanPulseSettleAnimation: Animation {
        NotchAnimations.prefersReducedMotion
            ? NotchAnimations.reduced
            : .easeOut(duration: scanPulseSettleDuration)
    }
    /// Wait before the first pulse, so breathing starts only once the panel has
    /// finished expanding. Hand-tuned: springs have no hard end time.
    static let scanPulseStartDelay: Double = 0.6

    /// Cosmetic size bump on hover. Included here so the fixed window has margin
    /// for it instead of clipping the bump.
    static let hoverBump: CGFloat = 6
    static var hoverAnimation: Animation { NotchAnimations.hover }

    // MARK: - Window size, per style
    //
    // Created once and never resized afterwards — see `FaceIDOverlayWindow`. Each
    // style reserves the scan footprint and its shadow margin.

    /// Extra margin so the in-content `.shadow()` isn't clipped: the window itself
    /// has `hasShadow = false`.
    static let notchShadowPadding: CGFloat = 24
    static let pillShadowPadding: CGFloat = 24

    static func windowSize(for geometry: FaceIDGeometry) -> CGSize {
        switch geometry.style {
        case .notch:
            // The minimal style is the widest: reserve the measured notch,
            // flanking wings and their flare. The regular scan is narrower.
            let minimalWidth = geometry.closedSize.width
                + minimalNotchFlankWidth * 2
                + flareAllowance(topRadius: minimalNotchTopRadius, style: .notch)
            let regularWidth = notchOpenSize.width
                + flareAllowance(topRadius: openTopRadius, style: .notch)
            let minimumHeight = geometry.closedSize.height + minimalNotchHeightBump
            return CGSize(
                width: max(minimalWidth, regularWidth) + notchShadowPadding * 2 + hoverBump,
                height: max(notchOpenSize.height, minimumHeight)
                    + notchShadowPadding + hoverBump
            )
        case .pill:
            return CGSize(
                width: pillOpenSize.width + pillShadowPadding * 2 + hoverBump,
                height: pillOpenSize.height + pillShadowPadding + hoverBump + pillTopGap
            )
        }
    }

    // MARK: - Measurement

    /// Floor for a physical notch's measured width: the auxiliary-area arithmetic
    /// below can come up implausibly small on odd display configurations.
    private static let minimumNotchWidth: CGFloat = 200

    static func forMainScreen() -> FaceIDGeometry {
        guard let screen = NSScreen.main else {
            return FaceIDGeometry(closedSize: pillClosedSize, isPhysicalNotch: false)
        }
        return forScreen(screen)
    }

    static func forScreen(_ screen: NSScreen) -> FaceIDGeometry {
        guard screen.safeAreaInsets.top > 0 else {
            return FaceIDGeometry(closedSize: pillClosedSize, isPhysicalNotch: false)
        }

        // Width derived from the menu-bar areas flanking the notch, which is how
        // the cutout's real width is recoverable; they read nil or empty on a
        // display without one, hence the safe-area check above.
        let leftPadding = screen.auxiliaryTopLeftArea?.width ?? 0
        let rightPadding = screen.auxiliaryTopRightArea?.width ?? 0
        let width = max(screen.frame.width - leftPadding - rightPadding, minimumNotchWidth)
        let height = screen.safeAreaInsets.top

        return FaceIDGeometry(closedSize: CGSize(width: width, height: height), isPhysicalNotch: true)
    }

    /// Why no screen could be chosen, for the UI to say out loud.
    ///
    /// The only way `preferredScreen()` returns nil is a display that was pinned
    /// and is no longer attached — and that is exactly the Face ID failure with no
    /// other symptom. The camera is granted, a face is enrolled, the password is
    /// stored, the triggers are armed, and nothing at all happens at the lock
    /// screen. Without this sentence there is nothing anywhere to look at, which is
    /// how that reads as "Face ID is broken": the stored identity is a display ID,
    /// and those can be reassigned across reconnects and reboots, so this is not an
    /// exotic state — it is what an external display that moved ports looks like
    /// from in here.
    static let pinnedDisplayMissingMessage =
        "Face ID is set to use a display that isn't connected right now, so it stays "
        + "out of the way rather than appearing on one you didn't pick. Connect that "
        + "display, or choose another under Settings → Face ID → Display on."

    /// Picks the screen the panel should show on.
    ///
    /// If a display is pinned in settings it is used only while it is still
    /// connected — deliberately no fallback, because drawing a lock-screen panel
    /// on a display the user did not choose is worse than not drawing one at all.
    /// Otherwise: the notched display if any display has one, else the main one.
    static func preferredScreen() -> NSScreen? {
        if let targetID = FaceIDSettings.shared.preferredDisplayID {
            return NSScreen.screens.first { $0.faceIDDisplayID == targetID }
        }
        return NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }
}

extension NSScreen {
    /// Stable enough to persist a display choice across launches — the only
    /// per-display identity AppKit exposes.
    var faceIDDisplayID: String? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return nil
        }
        return String(number)
    }

    /// True for the Mac's own display rather than an external monitor.
    var faceIDIsBuiltIn: Bool {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return false
        }
        return CGDisplayIsBuiltin(number) != 0
    }
}
