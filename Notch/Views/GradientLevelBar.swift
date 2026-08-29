import SwiftUI

/// A thick, rounded, gradient-filled level bar that can be dragged.
/// Used for volume and brightness in the notch.
struct GradientLevelBar: View {
    let value: Float
    let systemImage: String
    let gradient: [Color]
    let accessibilityLabel: String
    /// Nil makes the bar read-only.
    var onChange: ((Float) -> Void)?

    @State private var isDragging = false
    @State private var dragValue: Float?

    private var displayed: Float {
        min(max(dragValue ?? value, 0), 1)
    }

    private var height: CGFloat {
        isDragging ? 26 : 22
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.12))

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: gradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    // Never collapse to nothing — a sliver keeps the control
                    // legible and grabbable at zero.
                    .frame(width: max(width * CGFloat(displayed), height))

                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.black.opacity(0.75))
                    .padding(.leading, (height - 14) / 2 + 2)
            }
            .frame(height: height)
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard onChange != nil, width > 0 else { return }
                        isDragging = true
                        let fraction = Float(min(max(drag.location.x / width, 0), 1))
                        dragValue = fraction
                        onChange?(fraction)
                    }
                    .onEnded { _ in
                        isDragging = false
                        dragValue = nil
                    }
            )
            .animation(NotchAnimations.content, value: isDragging)
            .animation(NotchAnimations.content, value: value)
        }
        .frame(height: 30)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue("\(Int(displayed * 100)) percent")
        .accessibilityAdjustableAction { direction in
            guard let onChange else { return }
            let step: Float = 0.05
            switch direction {
            case .increment: onChange(min(displayed + step, 1))
            case .decrement: onChange(max(displayed - step, 0))
            @unknown default: break
            }
        }
    }
}
