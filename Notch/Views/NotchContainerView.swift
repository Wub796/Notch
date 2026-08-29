import SwiftUI

/// Root SwiftUI view hosted in the panel. Renders the morphing notch body,
/// top-anchored so it grows downward out of the hardware notch. Three visual
/// states: closed pill, hover peek, and the full glass slab.
struct NotchContainerView: View {
    let state: NotchState

    @Namespace private var notchNamespace

    private var shape: NotchShape {
        NotchShape(cornerRadius: state.cornerRadius)
    }

    var body: some View {
        VStack(spacing: 0) {
            notchBody
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        // Every label in the notch inherits the rounded face; individual
        // views only choose size and weight.
        .fontDesign(.rounded)
        .preferredColorScheme(.dark)
    }

    private var notchBody: some View {
        ZStack(alignment: .top) {
            // Each layer is laid out ONCE, at the size it will have when it is
            // the active layer, and never re-laid-out during the morph. The
            // outer frame below is smaller than the layer for most of an
            // expansion, so the clip reveals the content as the shape grows
            // instead of squeezing the content into an intermediate width.
            // That reflow — text rewrapping and columns collapsing frame by
            // frame — is what read as the notch fading out and coming back.
            CollapsedNotchView(state: state)
                .frame(
                    width: state.collapsedSize.width,
                    height: state.collapsedSize.height,
                    alignment: .top
                )
                // Peek is a real scale of the resting layout, so the wings
                // grow with the shape rather than reflowing inside it.
                .scaleEffect(state.collapsedContentScale, anchor: .top)
                .opacity(state.mode == .expanded ? 0 : 1)
                .allowsHitTesting(state.mode != .expanded)

            ExpandedNotchView(state: state, namespace: notchNamespace)
                // Laid out at the unscaled size and then scaled, so the panel-
                // size preference magnifies the slab instead of squeezing each
                // module's content into a shorter box.
                .frame(
                    width: state.expandedLayoutSize.width,
                    height: state.expandedLayoutSize.height,
                    alignment: .top
                )
                .scaleEffect(state.expandedScale, anchor: .top)
                .opacity(state.mode == .expanded ? 1 : 0)
                .allowsHitTesting(state.mode == .expanded)
        }
        // The one animated dimension. Everything above is already at its final
        // size, so this frame plus the clip below is the entire morph.
        .frame(width: state.currentSize.width, height: state.currentSize.height, alignment: .top)
        // Completely black base in every state — the slab always hides the
        // menu bar behind it and merges with the hardware notch.
        .background {
            shape.fill(.black)
        }
        .clipShape(shape)
        // A single fixed shadow: animating radius and opacity alongside the
        // geometry made the edge look like it was dissolving.
        .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
        // Hit testing — and therefore hover — is limited to the physical
        // notch while closed, so the pointer must actually be on the notch
        // rather than merely near it. Expanded, the whole slab stays live so
        // hovering anywhere in it keeps it open.
        .contentShape(
            HoverRegionShape(
                probe: state.mode == .expanded ? nil : state.hoverProbeSize
            )
        )
        .onHover { hovering in
            state.hoverChanged(hovering)
        }
        // Click-to-expand only matters while closed. macOS gives a parent
        // `.onTapGesture` priority over child `Button`s, so leaving it live in
        // expanded mode swallows the top bar's clicks.
        .modifier(
            ConditionalTapModifier(active: state.mode != .expanded) {
                state.handleTap()
            }
        )
        .onDrop(
            of: ShelfController.acceptedTypes,
            delegate: NotchDropDelegate(state: state)
        )
        // Geometry only. The layers' opacity is deliberately left out of every
        // animation below so the swap is a hard cut hidden under the opaque
        // shape — a cross-fade between two half-visible layers is the one
        // thing that makes a morph look like a dissolve.
        .animation(NotchAnimations.forMode(state.mode), value: state.currentSize)
        .animation(NotchAnimations.forMode(state.mode), value: state.cornerRadius)
        .animation(NotchAnimations.content, value: state.tab)
        .animation(NotchAnimations.activity, value: state.collapsedActivity)
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
