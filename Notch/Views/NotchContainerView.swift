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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Content inside the notch is always on glass over black.
        .preferredColorScheme(.dark)
    }

    private var notchBody: some View {
        ZStack(alignment: .top) {
            if state.mode == .expanded {
                ExpandedNotchView(state: state, namespace: notchNamespace)
                    .transition(.glass)
            } else {
                CollapsedNotchView(state: state, namespace: notchNamespace)
                    .transition(.opacity)
            }
        }
        .frame(width: state.currentSize.width, height: state.currentSize.height)
        .background {
            ZStack {
                if state.mode == .expanded {
                    Rectangle().fill(.ultraThinMaterial)
                }
                Rectangle().fill(.black.opacity(state.mode == .expanded ? 0.88 : 1.0))
            }
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
        .onTapGesture {
            state.handleTap()
        }
        .onDrop(
            of: ShelfController.acceptedTypes,
            delegate: NotchDropDelegate(state: state)
        )
        .animation(NotchAnimations.forMode(state.mode), value: state.mode)
        .animation(NotchAnimations.content, value: state.tab)
        .animation(NotchAnimations.activity, value: state.collapsedActivity)
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
