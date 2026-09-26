import AppKit
import SwiftUI

/// The visible panel's current frame, relative to the fixed window's full bounds.
/// Read by `FaceIDOverlayWindowController.updateMousePassthrough()`, which uses it
/// to keep the window's click-through state matching what is actually drawn.
private struct InteractivePanelFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect?
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}

/// SwiftUI's root inside the fixed-size overlay window — only content moves and
/// resizes, never the window.
///
/// Ported from Glance (`NotchOverlay/NotchOverlayView.swift`, MIT © Jonathan
/// Zhou), minus its onboarding step machine: enrollment lives in the notch panel
/// here, so this view only ever draws a scan.
///
/// Enter and exit choreography, in pill style, staggers the slide against the
/// expansion using real `Task.sleep` delays on separate `@State` mirrors rather
/// than two `.animation(value:)` modifiers. That is not a style preference: two
/// modifiers firing in one transaction can't be split reliably, so SwiftUI picks
/// one set of properties for each and the stagger collapses.
struct FaceIDOverlayView: View {
    let controller: FaceIDOverlayController

    @State private var isHovering = false

    /// Visual mirrors of the controller's target state — see the type comment.
    @State private var visualIsExpanded = false
    @State private var visualIsPositioned = false
    @State private var choreographyTask: Task<Void, Never>?

    /// Mirrors "phase is `.success`", not the phase itself, so the flip can be
    /// delayed and can outlive the collapse.
    @State private var isMinimalLockOpen = false
    @State private var lockUnlockTask: Task<Void, Never>?

    /// Only ever mutated inside an explicit `withAnimation`, so it can never jump.
    @State private var isScanPulseDimmed = false
    @State private var scanPulseTask: Task<Void, Never>?

    private var style: FaceIDPanelStyle {
        controller.geometry.style
    }

    private var targetIsExpanded: Bool {
        switch controller.phase {
        case .closed, .collapsing: false
        case .scanning, .success, .failure: true
        }
    }

    /// Notch style is always positioned: the physical notch never travels.
    /// Expanded implies positioned regardless of the docked flag, so a mid-success
    /// `disarm()` — which undocks the pill — can't yank the panel away mid-animation.
    private var targetIsPositioned: Bool {
        if targetIsExpanded { return true }
        if style == .notch { return true }
        return controller.isPillDocked
    }

    /// `.none` keeps the full expansion too — it only drops the video — so this is
    /// specifically `.minimal` scan content.
    private var isMinimalScan: Bool {
        controller.activeUnlockStyle == .minimal
    }

    private var scanOpenSize: CGSize {
        style == .notch ? FaceIDGeometry.notchOpenSize : FaceIDGeometry.pillOpenSize
    }

    /// In notch style the width grows to add flanking black beside the cutout, and
    /// the height grows because the cutout can't — so the bump appears below it.
    private var minimalOpenBodySize: CGSize {
        switch style {
        case .notch:
            CGSize(
                width: closedBodySize.width + FaceIDGeometry.minimalNotchFlankWidth * 2,
                height: closedBodySize.height + FaceIDGeometry.minimalNotchHeightBump
            )
        case .pill:
            CGSize(
                width: FaceIDGeometry.minimalPillOpenWidth,
                height: FaceIDGeometry.minimalPillOpenHeight
            )
        }
    }

    private var openBodySize: CGSize {
        isMinimalScan ? minimalOpenBodySize : scanOpenSize
    }

    private var closedBodySize: CGSize {
        controller.geometry.closedSize
    }

    private var topRadius: CGFloat {
        if visualIsExpanded {
            if isMinimalScan {
                // The pill stays a true capsule as it stretches, so its radius
                // tracks the animating height.
                return style == .notch
                    ? FaceIDGeometry.minimalNotchTopRadius
                    : minimalOpenBodySize.height / 2
            }
            return style == .notch ? FaceIDGeometry.openTopRadius : FaceIDGeometry.pillOpenCornerRadius
        }
        // Half the height is exactly a capsule end, in pill style.
        return style == .notch ? FaceIDGeometry.closedTopRadius : closedBodySize.height / 2
    }

    private var bottomRadius: CGFloat {
        if visualIsExpanded {
            if isMinimalScan {
                return style == .notch
                    ? FaceIDGeometry.minimalNotchBottomRadius
                    : minimalOpenBodySize.height / 2
            }
            guard style == .notch else {
                // Uniform corners in pill style: there is no flare to balance.
                return FaceIDGeometry.pillOpenCornerRadius
            }
            return FaceIDGeometry.openBottomRadius
        }
        return style == .notch ? FaceIDGeometry.closedBottomRadius : closedBodySize.height / 2
    }

    /// Widened by `flareAllowance` in notch style, so the closed state lands
    /// exactly on the physical notch's width instead of coming up short by the
    /// flare.
    private var currentSize: CGSize {
        let body = visualIsExpanded ? openBodySize : closedBodySize
        let bump: CGFloat = isHovering ? FaceIDGeometry.hoverBump : 0
        return CGSize(
            width: body.width + FaceIDGeometry.flareAllowance(topRadius: topRadius, style: style) + bump,
            height: body.height + bump
        )
    }

    /// Top-aligned inside the fixed window, so sliding is purely a question of
    /// where the top edge sits.
    private var verticalOffset: CGFloat {
        guard style == .pill else { return 0 }
        guard visualIsPositioned else {
            return -(closedBodySize.height + FaceIDGeometry.pillOffscreenSlack)
        }
        return FaceIDGeometry.pillTopGap
    }

    private var panelBlur: CGFloat {
        style == .pill && !visualIsPositioned ? FaceIDGeometry.pillEnterBlur : 0
    }

    private var contentPaddingTop: CGFloat {
        style == .pill ? FaceIDGeometry.pillContentPaddingTop : FaceIDGeometry.notchContentPaddingTop
    }

    private var contentPaddingLeading: CGFloat {
        style == .pill ? FaceIDGeometry.pillContentPaddingLeading : FaceIDGeometry.notchContentPaddingLeading
    }

    private var contentPaddingTrailing: CGFloat {
        style == .pill ? FaceIDGeometry.pillContentPaddingTrailing : FaceIDGeometry.notchContentPaddingTrailing
    }

    private var contentPaddingBottom: CGFloat {
        style == .pill ? FaceIDGeometry.pillContentPaddingBottom : FaceIDGeometry.notchContentPaddingBottom
    }

    /// Direction only — an enter-side delay is a real `Task.sleep` applied before
    /// this, never baked into the curve.
    private func expansionAnimation(entering: Bool) -> Animation {
        entering
            ? .spring(
                response: FaceIDGeometry.openSpringResponse,
                dampingFraction: FaceIDGeometry.openSpringDamping
            )
            : .spring(
                response: FaceIDGeometry.closeSpringResponse,
                dampingFraction: FaceIDGeometry.closeSpringDamping
            )
    }

    /// A straight-line move, not a bouncy resize.
    private var slideAnimation: Animation {
        .easeOut(duration: FaceIDGeometry.pillSlideDuration)
    }

    // MARK: - Scan pulse

    /// Success and failure both leave `.scanning`, which ends the pulse so the
    /// resolve animation plays against steady content.
    private var isScanning: Bool {
        controller.phase == .scanning
    }

    private var scanPulseScale: CGFloat {
        isScanPulseDimmed ? FaceIDGeometry.scanPulseScale : 1
    }

    private var scanPulseOpacity: Double {
        isScanPulseDimmed ? FaceIDGeometry.scanPulseOpacity : 1
    }

    @ViewBuilder
    private var scanContent: some View {
        if isMinimalScan {
            FaceIDMinimalUnlockView(
                media: controller.media,
                isUnlocked: isMinimalLockOpen,
                // The notch's flare eats `topRadius` before any real black begins.
                edgeInset: FaceIDGeometry.minimalContentEdgeInset + (style == .notch ? topRadius : 0),
                lockIconSize: style == .notch
                    ? FaceIDGeometry.minimalNotchLockIconSize
                    : FaceIDGeometry.minimalLockIconSize,
                mediaWidth: style == .notch
                    ? FaceIDGeometry.minimalNotchMediaWidth
                    : FaceIDGeometry.minimalMediaWidth,
                mediaVerticalInset: style == .notch
                    ? FaceIDGeometry.minimalNotchMediaVerticalInset
                    : FaceIDGeometry.minimalMediaVerticalInset,
                pulseScale: scanPulseScale,
                pulseOpacity: scanPulseOpacity
            )
        } else {
            FaceIDScanAnimationView(media: controller.media)
                .padding(.leading, contentPaddingLeading)
                .padding(.trailing, contentPaddingTrailing)
                .padding(.top, contentPaddingTop)
                .padding(.bottom, contentPaddingBottom)
                .scaleEffect(scanPulseScale)
                .opacity(scanPulseOpacity)
        }
    }

    var body: some View {
        ZStack {
            scanContent
                // The content dissolves as the panel shrinks rather than being
                // abruptly clipped by the collapsing shape. It rides the animation
                // already active on `visualIsExpanded`.
                .blur(radius: visualIsExpanded ? 0 : 40)
                .opacity(visualIsExpanded ? 1 : 0)
                .scaleEffect(visualIsExpanded ? 1 : 0.3)
        }
        .frame(width: currentSize.width, height: currentSize.height)
        .background(Color.black)
        .clipShape(FaceIDShape(topRadius: topRadius, bottomRadius: bottomRadius, style: style))
        // Reports this panel's own frame relative to the fixed window's bounds, so
        // the window's click capture can be restricted to the shape on screen
        // rather than to its whole maximum envelope.
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: InteractivePanelFramePreferenceKey.self,
                    value: proxy.frame(in: .named(Self.interactiveCoordinateSpace))
                )
            }
        )
        // Shadow only while expanded: otherwise it left a faint halo around the
        // real notch even while sitting closed in armed mode. The radius is fixed
        // rather than growing on hover, because a larger radius needs more window
        // margin than the window reserves.
        .shadow(color: .black.opacity(visualIsExpanded ? (isHovering ? 0.55 : 0.3) : 0), radius: 9)
        .blur(radius: panelBlur)
        // Applied after the shadow so both travel together, and before `.onHover`.
        .offset(y: verticalOffset)
        .animation(.easeOut(duration: 0.18), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                performHapticFeedback(.generic)
                controller.activate()
            }
        }
        .onAppear {
            // Synced without animating: on first appearance there is nothing to
            // animate from.
            visualIsExpanded = targetIsExpanded
            visualIsPositioned = targetIsPositioned
            updateScanPulse()
            updateMinimalLock()
        }
        .onDisappear {
            scanPulseTask?.cancel()
            scanPulseTask = nil
            lockUnlockTask?.cancel()
            lockUnlockTask = nil
        }
        .onChange(of: controller.phase) { _, newPhase in
            scheduleChoreography()
            updateScanPulse()
            updateMinimalLock()
            if newPhase == .success {
                performHapticFeedback(.levelChange)
            }
        }
        .onChange(of: controller.isPillDocked) { _, _ in
            scheduleChoreography()
        }
        .frame(
            width: FaceIDGeometry.windowSize(for: style).width,
            height: FaceIDGeometry.windowSize(for: style).height,
            alignment: .top
        )
        // Anchored on this outermost, full-window-sized frame so the panel's
        // reported frame is directly comparable to the hosting view's own bounds.
        .coordinateSpace(name: Self.interactiveCoordinateSpace)
        .onPreferenceChange(InteractivePanelFramePreferenceKey.self) { rect in
            controller.updateInteractiveContentRect(rect)
        }
    }

    private static let interactiveCoordinateSpace = "FaceIDOverlayRoot"

    /// Staggers the slide against the expansion when both need to change — see the
    /// type comment for why this uses real `Task.sleep` delays rather than
    /// `Animation.delay()`.
    private func scheduleChoreography() {
        let wantExpanded = targetIsExpanded
        let wantPositioned = targetIsPositioned
        choreographyTask?.cancel()
        choreographyTask = nil

        let expandedChanging = wantExpanded != visualIsExpanded
        let positionedChanging = wantPositioned != visualIsPositioned
        guard expandedChanging || positionedChanging else { return }

        guard expandedChanging && positionedChanging else {
            // Only one property is moving, so there is nothing to stagger against.
            if expandedChanging {
                withAnimation(expansionAnimation(entering: wantExpanded)) { visualIsExpanded = wantExpanded }
            } else {
                withAnimation(slideAnimation) { visualIsPositioned = wantPositioned }
            }
            return
        }

        if wantExpanded {
            // Entering: the slide leads, the expansion trails behind a real delay.
            withAnimation(slideAnimation) { visualIsPositioned = wantPositioned }
            let delay = FaceIDGeometry.pillEnterExpansionDelay
            let animation = expansionAnimation(entering: true)
            choreographyTask = Task {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                withAnimation(animation) { visualIsExpanded = wantExpanded }
            }
        } else {
            // Exiting: the shrink leads, the slide trails.
            withAnimation(expansionAnimation(entering: false)) { visualIsExpanded = wantExpanded }
            let delay = FaceIDGeometry.pillExitSlideDelay
            let animation = slideAnimation
            choreographyTask = Task {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                withAnimation(animation) { visualIsPositioned = wantPositioned }
            }
        }
    }

    // MARK: - Haptics

    /// `defaultPerformer` isn't tied to this view or window, so this is safe even
    /// while the panel isn't key — and at the lock screen it never is.
    private func performHapticFeedback(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        guard FaceIDSettings.shared.hapticFeedbackEnabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .default)
    }

    // MARK: - Scan pulse

    private func updateScanPulse() {
        if isScanning {
            startScanPulse()
        } else {
            stopScanPulse()
        }
    }

    /// Each half-cycle is its own finite `withAnimation` rather than one
    /// `.repeatForever(autoreverses:)`. A `repeatForever` owns the property for
    /// its whole lifetime and snaps when it is removed, whereas discrete
    /// half-cycles let `stopScanPulse()` retarget mid-flight and interpolate from
    /// whatever is currently rendered.
    private func startScanPulse() {
        // Already breathing or waiting to start — don't stack a second loop.
        guard scanPulseTask == nil else { return }

        // The pill doesn't start expanding until `pillEnterExpansionDelay` has
        // elapsed, so that is added on top here too.
        let entryDelay = (style == .pill ? FaceIDGeometry.pillEnterExpansionDelay : 0)
            + FaceIDGeometry.scanPulseStartDelay
        let half = FaceIDGeometry.scanPulseHalfCycleDuration
        let hold = FaceIDGeometry.scanPulseHoldDuration
        scanPulseTask = Task {
            try? await Task.sleep(for: .seconds(entryDelay))
            while !Task.isCancelled {
                withAnimation(.easeInOut(duration: half)) { isScanPulseDimmed = true }
                try? await Task.sleep(for: .seconds(half + hold))
                guard !Task.isCancelled else { break }

                withAnimation(.easeInOut(duration: half)) { isScanPulseDimmed = false }
                try? await Task.sleep(for: .seconds(half + hold))
            }
        }
    }

    /// Retargets to full so SwiftUI animates back from the rendered value rather
    /// than jumping; the guard leaves an already-settled panel alone.
    private func stopScanPulse() {
        scanPulseTask?.cancel()
        scanPulseTask = nil
        guard isScanPulseDimmed else { return }
        withAnimation(.easeOut(duration: FaceIDGeometry.scanPulseSettleDuration)) {
            isScanPulseDimmed = false
        }
    }

    // MARK: - Minimal lock glyph

    /// The animation lives on the glyph itself, so setting this plainly is already
    /// animated.
    private func updateMinimalLock() {
        let shouldOpen: Bool
        switch controller.phase {
        case .success:
            shouldOpen = true
        case .collapsing:
            // Hold whatever it currently is: re-locking now would read as undoing
            // the unlock the user just watched happen.
            return
        case .closed, .scanning, .failure:
            shouldOpen = false
        }

        lockUnlockTask?.cancel()
        lockUnlockTask = nil
        guard shouldOpen != isMinimalLockOpen else { return }

        let delay = FaceIDGeometry.minimalLockUnlockDelay
        guard shouldOpen, delay > 0 else {
            isMinimalLockOpen = shouldOpen
            return
        }
        lockUnlockTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            isMinimalLockOpen = true
        }
    }
}
