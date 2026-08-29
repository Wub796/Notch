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

    private var notchBody: some View {
        ZStack(alignment: .top) {
            slab

            // Closed, hovering and clicking are detected by this and nothing
            // else: a rectangle of exactly the hardware notch's size, pinned to
            // the top centre. The previous approach derived the region from a
            // custom Shape laid inside the slab's own bounds — bounds that
            // animate, and that the live-activity wings make far wider than the
            // notch — so the region moved with them. A real view with a real
            // frame cannot drift.
            if state.mode != .expanded {
                Color.clear
                    .frame(
                        width: state.adjustedNotchSize.width,
                        height: state.adjustedNotchSize.height
                    )
                    .contentShape(Rectangle())
                    .onHover { state.hoverChanged($0) }
                    .onTapGesture { state.handleTap() }
            }
        }
    }

    private var slab: some View {
        NotchLayoutView(state: state, namespace: notchNamespace, isHovering: state.isHovering)
            // Open, the horizontal inset clears the top flare and the extra 12
            // is the references' slab padding. Closed it is zero, which is the
            // one place this diverges from them: they pad the closed pill too
            // and compensate by narrowing the camera dead zone by 20, which
            // draws content under the housing. Keeping the pill exactly as
            // wide as the notch plus its wings costs nothing and means the
            // idle pill never overhangs the hardware notch.
            .padding(.horizontal, state.mode == .expanded
                ? NotchSizing.cornerRadiusInsets.opened.top + NotchSizing.openContentInset
                : 0)
            .padding(.bottom, state.mode == .expanded ? NotchSizing.openContentInset : 0)
            // The height goes on before the background, and top-aligned: a
            // .frame(height:) applied after clipShape centres the already-drawn
            // shape inside it, so the slab's top edge drifts down the screen as
            // the height animates instead of staying welded to the notch.
            .frame(
                height: state.mode == .expanded ? state.expandedSize.height : nil,
                alignment: .top
            )
            .background(.black)
            .clipShape(shape)
            // A hairline of black across the top, inside the flare, so no
            // sliver of desktop shows between the slab and the screen edge.
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(.black)
                    .frame(height: 1)
                    .padding(.horizontal, state.cornerRadii.top)
            }
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
            // Closed, the slab is purely visual — the probe above owns hover
            // and clicks, so the wings beside the notch are not a target.
            .allowsHitTesting(state.mode == .expanded)
            .onHover { state.hoverChanged($0) }
            .onDrop(
                of: ShelfController.acceptedTypes,
                delegate: NotchDropDelegate(state: state)
            )
    }
}
