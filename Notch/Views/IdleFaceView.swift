import SwiftUI

/// The idle companion (an homage to boring.notch's animated face): a tiny
/// blinking face that lives in the notch wing when nothing else is going on.
/// The blink loop is a PhaseAnimator — no timers — and holds still under
/// Reduce Motion.
struct IdleFaceView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 3.5) {
            if reduceMotion {
                eyes.scaleEffect(y: 1)
            } else {
                eyes.phaseAnimator([false, true]) { content, blinking in
                    content.scaleEffect(y: blinking ? 0.15 : 1, anchor: .center)
                } animation: { blinking in
                    blinking
                        ? .easeIn(duration: 0.09).delay(3.4)
                        : .easeOut(duration: 0.14)
                }
            }

            smile
        }
        .frame(width: 30, height: 22)
        .accessibilityHidden(true)
    }

    private var eyes: some View {
        HStack(spacing: 7) {
            Capsule().fill(.white).frame(width: 3.5, height: 8)
            Capsule().fill(.white).frame(width: 3.5, height: 8)
        }
    }

    private var smile: some View {
        SmilePath()
            .stroke(.white, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            .frame(width: 13, height: 5)
    }
}

private struct SmilePath: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.midX, y: rect.maxY + rect.height)
        )
        return path
    }
}
