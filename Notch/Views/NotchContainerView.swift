import SwiftUI

/// Root SwiftUI view hosted in the panel: the morphing notch body, top-anchored
/// so it grows downward out of the hardware notch.
///
/// The structure is boring.notch's and Atoll's `ContentView`. Nothing here sets
/// an explicit width — the body takes its size from whatever the layout is
/// currently drawing, and the animation is on `state.mode`, so SwiftUI
/// interpolates from the closed pill's natural size to the open slab's. Height
/// is the one exception, pinned while open so every tab opens to the same
/// panel.
struct NotchContainerView: View {
    let state: NotchState

    @Namespace private var notchNamespace

    /// The open/close springs, which follow the user's Animation Style.
    private var notchAnimation: Animation {
        NotchAnimations.forMode(state.mode)
    }

    private var shape: NotchShape {
        let radii = state.cornerRadii
        return NotchShape(topCornerRadius: radii.top, bottomCornerRadius: radii.bottom)
    }

    var body: some View {
        VStack(spacing: 0) {
            notchBody
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .fontDesign(.rounded)
        .preferredColorScheme(.dark)
    }

    /// The volume/brightness bar rendered while the notch is expanded. It drops
    /// in the band the slab grows by — *below* the module, never over it — and
    /// the panel pokes down to make room, so it reads like the system's own
    /// level overlay. Dragging the bar raises the matching activity again so it
    /// tracks the finger, exactly like the closed HUD.
    @ViewBuilder
    private var expandedHUD: some View {
        Group {
            switch state.activities.transient {
            case let .volume(level, muted):
                DroppedHUDBar(
                    kind: .volume(muted: muted),
                    value: Binding(
                        get: { CGFloat(muted ? 0 : level) },
                        set: { newValue in
                            let level = Float(newValue)
                            state.audio.setVolume(level)
                            state.activities.showVolume(level: level, muted: level == 0)
                        }
                    ),
                    showsPercentage: state.settings.showHUDPercentage
                )
            case let .brightness(level):
                DroppedHUDBar(
                    kind: .brightness,
                    value: Binding(
                        get: { CGFloat(level) },
                        set: { newValue in
                            let level = Float(newValue)
                            state.brightness.setBrightness(level)
                            state.activities.showBrightness(level: level)
                        }
                    ),
                    showsPercentage: state.settings.showHUDPercentage
                )
            default:
                EmptyView()
            }
        }
        .frame(width: NotchSizing.expandedHUDWidth)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.black.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                )
        }
        // The capsule is vertically centered in the drop band the slab grew by
        // (and horizontally, by the VStack), so it floats in the panel rather
        // than hugging the content above it.
        .frame(height: NotchSizing.expandedHUDDropHeight)
    }

    private var notchBody: some View {
        ZStack(alignment: .top) {
            slab

            // Closed, hovering and clicking are detected by this and nothing
            // else: a rectangle of exactly the hardware notch's size, pinned to
            // the top centre.
            if state.mode != .expanded {
                Color.black.opacity(0.001)
                    .frame(
                        width: state.hoverProbeSize.width,
                        height: state.hoverProbeSize.height
                    )
                    .contentShape(Rectangle())
                    .onHover { state.hoverChanged($0) }
                    .onTapGesture { state.handleTap() }
            }
        }
    }

    private var slab: some View {
        VStack(spacing: 0) {
            NotchLayoutView(state: state, namespace: notchNamespace, isHovering: state.isHovering)
                .padding(.horizontal, state.mode == .expanded
                    ? NotchSizing.cornerRadiusInsets.opened.top + NotchSizing.openContentInset
                    : 0)
                .padding(.bottom, state.mode == .expanded ? NotchSizing.openContentInset : 0)

            // When the notch is open, the volume/brightness HUD drops below the
            // module in the band the slab grows by (see `expandedHUD`), rather
            // than floating over the content. It lives here — not in
            // `collapsedActivity`, which only drives the closed/peek slab — so
            // a media-key tap still shows its level while the panel is
            // expanded. Appearing here rather than as an overlay lets the slab
            // extend down to hold it instead of covering the screen beneath.
            if state.mode == .expanded, state.isShowingExpandedHUD {
                expandedHUD
                    .transition(NotchAnimations.activitySwap)
            }
        }
        .frame(
            height: state.mode == .expanded ? state.expandedTotalHeight : state.collapsedSize.height,
            alignment: .top
        )
        .background(.black)
            // Keep the top edge bonded to the screen while the shape still
            // rounds into it. The clip is applied after the background, so
            // the rounded intersections remain visible instead of becoming
            // square corner steps.
            .clipShape(shape)
            // Only the open slab and the hovered pill cast a shadow; a closed
            // pill sitting on the black notch does not need one.
            .shadow(
                color: (state.mode == .expanded || state.isHovering)
                    ? .black.opacity(0.7)
                    : .clear,
                radius: state.settings.cornerRadiusScaling ? 6 : 4
            )
            .animation(notchAnimation, value: state.mode)
            // Hover motion is fast and the expansion is slow; leaving the fast
            // one live across the transition let it grab the same geometry
            // change for a frame, which is the jolt at the start of an
            // expansion. Hover only animates while the notch is closed.
            .animation(
                state.mode == .expanded ? nil : NotchAnimations.hover,
                value: state.isHovering
            )
            .animation(notchAnimation, value: state.collapsedActivity)
            // The HUD's drop band appears and disappears at a media-key's
            // transient pace, which is faster than the open/close spring — so
            // the slab's grow-and-shrink (and the bar popping in) settle with
            // the content spring. Innermost, so it wins for this transaction.
            .animation(NotchAnimations.content, value: state.isShowingExpandedHUD)
            // Closed, the slab is otherwise inert: the probe above owns hover
            // and clicks, so the wings beside the notch are not a target. The
            // exception is a draggable HUD, which needs its bar to receive the
            // drag — it hangs below the notch, clear of the probe.
            .allowsHitTesting(state.mode == .expanded || state.collapsedActivityIsInteractive)
            // Hover is the probe's job whenever the notch is closed; letting
            // the slab report it too is what made the region grow.
            .onHover { hovering in
                guard state.mode == .expanded else { return }
                state.hoverChanged(hovering)
            }
            .onDrop(
                of: ShelfController.acceptedTypes,
                delegate: NotchDropDelegate(state: state)
            )
    }
}
