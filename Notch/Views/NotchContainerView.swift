import SwiftUI

/// Root SwiftUI view hosted in the panel. Renders the morphing notch body,
/// top-anchored so it grows downward out of the hardware notch.
struct NotchContainerView: View {
    let state: NotchState

    @Namespace private var notchNamespace

    private var shape: NotchShape {
        state.mode == .expanded
            ? NotchShape(topRadius: 14, bottomRadius: 24)
            : NotchShape()
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
                // Liquid-glass base: system blur under a deep black tint that
                // lightens as the notch expands.
                if state.mode == .expanded {
                    Rectangle().fill(.ultraThinMaterial)
                }
                Rectangle().fill(.black.opacity(state.mode == .expanded ? 0.82 : 1.0))
            }
        }
        .clipShape(shape)
        .overlay {
            // Rim light: invisible where the shape meets the bezel, catching
            // the lower curve like an edge highlight.
            if state.mode == .expanded {
                shape.stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.02), .white.opacity(0.22)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            }
        }
        .shadow(color: .black.opacity(state.mode == .expanded ? 0.55 : 0), radius: 20, y: 8)
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
        .animation(.notchSpring, value: state.mode)
        .animation(.notchSpring, value: state.showsMediaWings)
    }
}
