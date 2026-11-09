import SwiftUI

/// Animated checkmark shape that draws itself using a stroke trim animation.
/// Ported from Glance (`AnimatedCheckmark.swift`, MIT © Jonathan Zhou).
private struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: w * 0.16, y: h * 0.52))
        path.addLine(to: CGPoint(x: w * 0.40, y: h * 0.78))
        path.addLine(to: CGPoint(x: w * 0.86, y: h * 0.22))
        return path
    }
}

struct FaceIDAnimatedCheckmark: View {
    var color: Color = FaceIDAccent.accent
    var lineWidth: CGFloat = 8

    @State private var progress: CGFloat = 0

    var body: some View {
        CheckmarkShape()
            .trim(from: 0, to: progress)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            .onAppear {
                withAnimation(
                    .timingCurve(0.65, 0.0, 0.35, 1.0, duration: FaceIDMetrics.checkmarkDrawDuration)
                ) {
                    progress = 1
                }
            }
    }
}
