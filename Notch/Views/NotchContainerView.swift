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
            // Both layers stay mounted and cross-fade in place. Insert/remove
            // transitions made the whole slab appear to fade and pop; keeping
            // the black shape and both content layers alive means only the
            // geometry moves, which is what reads as a smooth morph.
            CollapsedNotchView(state: state, namespace: notchNamespace)
                .opacity(state.mode == .expanded ? 0 : 1)
                .allowsHitTesting(state.mode != .expanded)

            ExpandedNotchView(state: state, namespace: notchNamespace)
                .opacity(state.mode == .expanded ? 1 : 0)
                .allowsHitTesting(state.mode == .expanded)
        }
        .frame(width: state.currentSize.width, height: state.currentSize.height, alignment: .top)
        // Completely black base in every state — the slab always hides the
        // menu bar behind it and merges with the hardware notch.
        .background {
            shape.fill(.black)
        }
        .clipShape(shape)
        .shadow(
            color: .black.opacity(state.mode == .expanded ? 0.5 : (state.mode == .peek ? 0.28 : 0)),
            radius: state.mode == .expanded ? 22 : 8,
            y: state.mode == .expanded ? 9 : 3
        )
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
        // One animation drives geometry and the cross-fade together.
        .animation(NotchAnimations.forMode(state.mode), value: state.mode)
        .animation(NotchAnimations.forMode(state.mode), value: state.currentSize)
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
