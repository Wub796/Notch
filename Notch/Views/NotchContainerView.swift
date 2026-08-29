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
    @State private var isHovering = false

    // Animation constants taken from the references. Open is slightly quicker
    // than close and both are critically damped, so the slab settles without
    // the wobble a lighter spring gives a shape this large.
    private static let openAnimation = Animation.spring(
        response: 0.42, dampingFraction: 1.0, blendDuration: 0
    )
    private static let closeAnimation = Animation.spring(
        response: 0.45, dampingFraction: 1.0, blendDuration: 0
    )
    private static let hoverAnimation = Animation.bouncy.speed(1.2)

    private var notchAnimation: Animation {
        guard !NotchAnimations.prefersReducedMotion else { return NotchAnimations.reduced }
        return state.mode == .expanded ? Self.openAnimation : Self.closeAnimation
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
        NotchLayoutView(state: state, namespace: notchNamespace, isHovering: isHovering)
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
                color: (state.mode == .expanded || isHovering) ? .black.opacity(0.7) : .clear,
                radius: state.settings.cornerRadiusScaling ? 6 : 4
            )
            .frame(height: state.mode == .expanded ? state.expandedSize.height : nil)
            .animation(notchAnimation, value: state.mode)
            .animation(Self.hoverAnimation, value: isHovering)
            .animation(notchAnimation, value: state.collapsedActivity)
            .contentShape(
                HoverRegionShape(
                    probe: state.mode == .expanded ? nil : state.hoverProbeSize
                )
            )
            .onHover { hovering in
                isHovering = hovering
                state.hoverChanged(hovering)
            }
            .modifier(
                ConditionalTapModifier(active: state.mode != .expanded) {
                    state.handleTap()
                }
            )
            .onDrop(
                of: ShelfController.acceptedTypes,
                delegate: NotchDropDelegate(state: state)
            )
            .onChange(of: state.mode) { _, newMode in
                if newMode != .expanded, isHovering {
                    isHovering = false
                }
            }
    }
}

/// Applies the tap gesture only while `active`, so the container never
/// competes with its child buttons.
private struct ConditionalTapModifier: ViewModifier {
    let active: Bool
    let action: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if active {
            content.onTapGesture(perform: action)
        } else {
            content
        }
    }
}

/// Hit-test region: the full bounds when `probe` is nil, otherwise a
/// top-centered rectangle of exactly that size.
private struct HoverRegionShape: Shape {
    let probe: CGSize?

    func path(in rect: CGRect) -> Path {
        guard let probe else { return Path(rect) }
        return Path(CGRect(
            x: rect.midX - probe.width / 2,
            y: rect.minY,
            width: probe.width,
            height: min(probe.height, rect.height)
        ))
    }
}
