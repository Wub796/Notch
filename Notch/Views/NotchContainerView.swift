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

    /// The volume/brightness bar rendered while the notch is expanded, or nil
    /// when no HUD activity is current. It floats just below the header strip
    /// (which is `topBarHeight` tall) so it never covers the rail or a detail
    /// screen's controls. Dragging the bar raises the matching activity again
    /// so it tracks the finger, exactly like the closed HUD.
    @ViewBuilder
    private var expandedHUD: some View {
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
            .frame(height: 34)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.black.opacity(0.55))
            }
            .padding(.top, state.topBarHeight + 6)
            .padding(.horizontal, 16)
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
            .frame(height: 34)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.black.opacity(0.55))
            }
            .padding(.top, state.topBarHeight + 6)
            .padding(.horizontal, 16)
        default:
            EmptyView()
        }
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
        NotchLayoutView(state: state, namespace: notchNamespace, isHovering: state.isHovering)
            .padding(.horizontal, state.mode == .expanded
                ? NotchSizing.cornerRadiusInsets.opened.top + NotchSizing.openContentInset
                : 0)
            .padding(.bottom, state.mode == .expanded ? NotchSizing.openContentInset : 0)
            .overlay(alignment: .top) {
                // When the notch is open, the volume/brightness HUD would
                // otherwise be invisible — `collapsedActivity` only drives the
                // closed/peek slab. Reuse the same dropped bar so a media-key
                // tap shows its level while the panel is expanded too.
                if state.mode == .expanded,
                   let hud = expandedHUD {
                    hud
                        .transition(NotchAnimations.activitySwap)
                }
            }
            .frame(
                height: state.mode == .expanded ? state.expandedSize.height : state.collapsedSize.height,
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
