import SwiftUI

/// Face ID's own accent, so the light that sweeps across the panel during
/// enrollment belongs to the feature rather than to the app's global accent.
///
/// Kept out of `NotchTheme` deliberately: every other token there is part of the
/// app's shared surface language, and this is a single effect in one screen.
enum FaceIDAccent {
    private static let base = (r: 0x34 / 255.0, g: 0x99 / 255.0, b: 0xFF / 255.0)

    static let accent = Color(red: base.r, green: base.g, blue: base.b)
    /// Accent-derived shades, shifted so the layered streaks read as one body of
    /// light rather than as several flat shapes.
    static let pale = Color(red: 0xCF / 255, green: 0xE7 / 255, blue: 0xFF / 255)
    static let bright = Color(red: 0x7F / 255, green: 0xC2 / 255, blue: 0xFF / 255)
}

/// Layered blurred ribbons that sweep toward the pose the user is being asked to
/// take.
///
/// Adapted from Glance (`Onboarding/EnrollmentDirectionSweep.swift`, MIT ©
/// Jonathan Zhou), which was written for a full-screen overlay. Here it plays
/// inside the enrollment preview, so the direction is the cue and the motion
/// itself is the instruction — no arrow, because an arrow would have to be drawn
/// twice (once per reading direction) and this doesn't.
struct FaceIDEnrollmentSweepView: View {
    /// The direction to travel, in SwiftUI's y-down screen space.
    let travel: CGVector

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(Self.streakSpecs) { spec in
                    SweepStreak(spec: spec, travel: travel, canvasSize: proxy.size)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .opacity(0.55)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Unit travel for a pose, or `nil` for the neutral pose — which has no
    /// direction to sweep in, and is the one prompt with nothing to show.
    static func travel(for pose: FaceIDPose) -> CGVector? {
        let diagonal = CGFloat(1 / sqrt(2.0))
        switch pose {
        case .center: return nil
        // Positive yaw in the pose's own convention is a turn to the user's
        // left, which is *leftward* travel across the panel as the user sees it
        // — the preview is mirrored, so the two agree. Pitch is the opposite of
        // the obvious reading, so "top" is a negative pitch and a negative dy.
        case .left: return CGVector(dx: -1, dy: 0)
        case .right: return CGVector(dx: 1, dy: 0)
        case .top: return CGVector(dx: 0, dy: -1)
        case .bottom: return CGVector(dx: 0, dy: 1)
        case .topLeft: return CGVector(dx: -diagonal, dy: -diagonal)
        case .topRight: return CGVector(dx: diagonal, dy: -diagonal)
        case .bottomLeft: return CGVector(dx: -diagonal, dy: diagonal)
        case .bottomRight: return CGVector(dx: diagonal, dy: diagonal)
        }
    }
}

// MARK: - Streak specs

private struct StreakSpec: Identifiable {
    let id: Int
    let thickness: CGFloat
    let lengthFactor: CGFloat
    let blurScale: CGFloat
    let peakOpacity: Double
    let duration: Double
    let delay: Double
    /// Perpendicular offset, as a fraction of the shorter canvas edge; signed so
    /// the streaks fan out.
    let lateral: CGFloat
    /// Bezier curvature, as a fraction of the shorter edge; opposite signs arc
    /// opposite ways.
    let bow: CGFloat
    let hasHighlight: Bool
    let isVivid: Bool
}

extension FaceIDEnrollmentSweepView {
    /// 24 ribbons across a fixed perpendicular span: dense packing rather than a
    /// wider field, because a handful of fat ribbons read as a graphic and a band
    /// of thin ones reads as light.
    fileprivate static let streakSpecs: [StreakSpec] = makeStreakSpecs()

    private static func makeStreakSpecs() -> [StreakSpec] {
        let count = 24
        let laterals = (0..<count).map { index -> CGFloat in
            let t = CGFloat(index) / CGFloat(count - 1)
            return -0.86 + t * 1.72
        }
        return laterals.enumerated().map { index, lateral in
            let lane = index % 7
            let edgeFade = 1 - abs(Double(lateral)) * 0.22
            let isVivid = index % 6 == 1 || index % 6 == 4
            let heavyBlur = index % 4 != 0
            let blurScale: CGFloat = [1.35, 1.16, 0.96, 1.22, 0.82, 1.32, 1.02][lane]
                * (heavyBlur ? 2.6 : 1.1)
            let peakBase: Double = [0.58, 0.72, 0.80, 0.52, 0.66, 0.42, 0.48][lane]
            return StreakSpec(
                id: index,
                thickness: [310, 190, 105, 155, 72, 230, 88][lane],
                lengthFactor: [1.16, 0.94, 0.72, 0.86, 0.54, 1.04, 0.62][lane],
                blurScale: blurScale,
                peakOpacity: peakBase * edgeFade * (isVivid ? 1.4 : 1),
                duration: [1.22, 1.08, 0.98, 1.16, 0.94, 1.28, 1.04][lane],
                delay: [0.00, 0.03, 0.06, 0.015, 0.08, 0.04, 0.065][lane]
                    + Double(index % 4) * 0.008,
                lateral: lateral,
                bow: [0.18, -0.14, 0.10, -0.22, 0.26, 0.08, -0.12][lane],
                hasHighlight: isVivid || lane == 2 || lane == 4,
                isVivid: isVivid
            )
        }
    }
}

// MARK: - Geometry

private struct SweepGeometry {
    let start: CGPoint
    let end: CGPoint
    let control: CGPoint
    let canvasSize: CGSize
    let length: CGFloat
    let rotationDrift: Double

    init(spec: StreakSpec, travel: CGVector, canvasSize: CGSize) {
        self.canvasSize = canvasSize
        let perpendicular = CGVector(dx: -travel.dy, dy: travel.dx)
        let shortEdge = min(canvasSize.width, canvasSize.height)
        // The far end stops short of a full off-screen exit, so the ease-out is
        // still on camera when it finishes.
        let diagonal = hypot(canvasSize.width, canvasSize.height)
        let startSpan = diagonal * 0.58
        let endSpan = diagonal * 0.50
        length = max(shortEdge * spec.lengthFactor * 0.55, 180)
        let centerX = canvasSize.width / 2
        let centerY = canvasSize.height / 2
        // Spread along the true perpendicular screen axis, so the ribbons fan
        // across the whole panel rather than only across one dimension of it.
        let perpendicularExtent = abs(perpendicular.dx) * canvasSize.width
            + abs(perpendicular.dy) * canvasSize.height
        let lateral = spec.lateral * perpendicularExtent * 0.46
        start = CGPoint(
            x: centerX - travel.dx * startSpan + perpendicular.dx * lateral,
            y: centerY - travel.dy * startSpan + perpendicular.dy * lateral
        )
        end = CGPoint(
            x: centerX + travel.dx * endSpan + perpendicular.dx * lateral,
            y: centerY + travel.dy * endSpan + perpendicular.dy * lateral
        )
        let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let bow = spec.bow * shortEdge * 0.20
        control = CGPoint(x: mid.x + perpendicular.dx * bow, y: mid.y + perpendicular.dy * bow)
        rotationDrift = Double(spec.bow.sign == .minus ? -0.05 : 0.05)
    }

    func point(at t: Double) -> CGPoint {
        let u = 1 - t
        return CGPoint(
            x: u * u * start.x + 2 * u * t * control.x + t * t * end.x,
            y: u * u * start.y + 2 * u * t * control.y + t * t * end.y
        )
    }

    /// The Bezier's heading at `t`, in radians.
    func heading(at t: Double) -> Double {
        let dx = 2 * (1 - t) * (control.x - start.x) + 2 * t * (end.x - control.x)
        let dy = 2 * (1 - t) * (control.y - start.y) + 2 * t * (end.y - control.y)
        return atan2(dy, dx)
    }

    func opacity(at t: Double, peak: Double) -> Double {
        let fadeInEnd = 0.07
        // Dissolves during the ease-out, so the slowdown is still visible.
        let fadeOutStart = 0.7
        if t <= 0 || t >= 1 { return 0 }
        if t < fadeInEnd {
            let u = t / fadeInEnd
            return peak * (u * u * (3 - 2 * u))
        }
        if t > fadeOutStart {
            let u = (t - fadeOutStart) / (1 - fadeOutStart)
            let smooth = u * u * (3 - 2 * u)
            return peak * (1 - smooth)
        }
        return peak
    }
}

// MARK: - Motion

/// A `View` rather than a `ViewModifier`, so SwiftUI interpolates
/// `animatableData` on the view itself. That is the reliable path for evaluating
/// a Bezier every frame instead of sliding a shape between two endpoints.
private struct SweepMovingContainer<Content: View>: View, Animatable {
    var progress: Double
    let geometry: SweepGeometry
    let peakOpacity: Double
    let content: Content

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let t = min(max(progress, 0), 1)
        let point = geometry.point(at: t)
        let centerX = geometry.canvasSize.width / 2
        let centerY = geometry.canvasSize.height / 2
        // Rotate first, then offset: rotating after the offset would spin the
        // translation around the canvas center and send most directions the wrong
        // way.
        content
            .rotationEffect(.radians(geometry.heading(at: t) + geometry.rotationDrift * t))
            .offset(x: point.x - centerX, y: point.y - centerY)
            .opacity(geometry.opacity(at: t, peak: peakOpacity))
    }
}

// MARK: - Streak view

private struct SweepStreak: View {
    let spec: StreakSpec
    let travel: CGVector
    let canvasSize: CGSize

    @State private var progress: Double = 0

    var body: some View {
        let geometry = SweepGeometry(spec: spec, travel: travel, canvasSize: canvasSize)
        SweepMovingContainer(
            progress: progress,
            geometry: geometry,
            peakOpacity: spec.peakOpacity,
            content: layers(length: geometry.length)
        )
        .onAppear { runSweep() }
    }

    private func layers(length: CGFloat) -> some View {
        ZStack {
            streakLayer(
                length: length,
                thickness: spec.thickness * 2.35,
                blur: 78 * spec.blurScale,
                opacity: spec.isVivid ? 0.28 : 0.16,
                colors: [FaceIDAccent.accent, FaceIDAccent.bright]
            )
            streakLayer(
                length: length,
                thickness: spec.thickness,
                blur: 34 * spec.blurScale,
                opacity: spec.isVivid ? 0.48 : 0.30,
                colors: spec.isVivid
                    ? [FaceIDAccent.bright, FaceIDAccent.pale]
                    : [FaceIDAccent.accent, FaceIDAccent.bright]
            )
            streakLayer(
                length: length,
                thickness: spec.thickness * 0.42,
                blur: 14 * spec.blurScale,
                opacity: spec.isVivid ? 0.62 : 0.38,
                colors: [FaceIDAccent.bright, FaceIDAccent.pale]
            )
            if spec.hasHighlight {
                streakLayer(
                    length: length * 0.72,
                    thickness: spec.thickness * 0.12,
                    blur: 6,
                    opacity: spec.isVivid ? 0.36 : 0.20,
                    colors: [FaceIDAccent.pale, .white]
                )
            }
        }
        .compositingGroup()
    }

    private func streakLayer(
        length: CGFloat,
        thickness: CGFloat,
        blur: CGFloat,
        opacity: Double,
        colors: [Color]
    ) -> some View {
        Capsule()
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: colors[0].opacity(0), location: 0),
                        .init(color: colors[0].opacity(0.6), location: 0.18),
                        .init(color: colors[1], location: 0.55),
                        .init(color: colors[1].opacity(0.85), location: 0.82),
                        .init(color: colors[1].opacity(0), location: 1),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: length, height: thickness)
            .blur(radius: blur)
            .opacity(opacity)
    }

    private func runSweep() {
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) { progress = 0 }
        // A turn of the runloop, so the reset isn't coalesced into the forward
        // animation.
        DispatchQueue.main.async {
            withAnimation(
                .timingCurve(0.68, 0.0, 0.32, 1.0, duration: spec.duration)
                .delay(spec.delay)
            ) {
                progress = 1
            }
        }
    }
}
