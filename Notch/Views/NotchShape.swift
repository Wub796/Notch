import SwiftUI

/// The notch silhouette, with independent top and bottom radii.
///
/// Geometry follows boring.notch and Atoll (both from DynamicNotchKit): the top
/// corners reach *outward* into the menu bar, and the bottom corners round
/// inward. Driving the two radii separately is what lets the closed pill sit
/// tight against the hardware notch (16/18) while the open slab reads as a soft
/// panel (26/30) — a single radius cannot express both.
///
/// The corners themselves are Apple's continuous ones rather than circular
/// arcs (see `ContinuousCorner`). That is the curve the system draws for its
/// own rounded surfaces, and it is the difference you can actually see at these
/// sizes: a quarter arc leaves a straight edge at a tangent kink, which on a
/// 32pt-tall pill reads as a dent beside the hardware notch.
struct NotchShape: Shape {
    private var topCornerRadius: CGFloat
    private var bottomCornerRadius: CGFloat

    init(topCornerRadius: CGFloat? = nil, bottomCornerRadius: CGFloat? = nil) {
        self.topCornerRadius = topCornerRadius ?? NotchSizing.cornerRadiusInsets.closed.top
        self.bottomCornerRadius = bottomCornerRadius ?? NotchSizing.cornerRadiusInsets.closed.bottom
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        guard rect.width.isFinite, rect.height.isFinite, rect.width > 0, rect.height > 0 else {
            return Path()
        }

        // Clamped so the shape stays valid at any size mid-animation; the
        // references assume the slab is always wider than the two radii, which
        // is not true while the notch is still growing out of the pill.
        let top = max(0, min(topCornerRadius, rect.width / 2))
        let bottom = max(0, min(bottomCornerRadius, rect.width / 2 - top))

        // The visible body is inset `top` from the frame, and the top corners
        // reach from the body's sides out to the frame's own corners; that
        // outward reach is the flare that welds the closed pill to the menu
        // bar the way the hardware notch is welded to it.
        let bodyLeft = rect.minX + top
        let bodyRight = rect.maxX - top

        // Room behind each corner, measured from the point where its two edges
        // meet. Across the top that room is the flare; down the sides the two
        // corners share the height, and along the bottom they share the body's
        // width — the same halves CoreGraphics hands its own corners.
        let sideRoom = rect.height / 2
        let bottomRoom = rect.width / 2 - top

        // Traversed counter-clockwise from the top-left, as this shape has
        // always been drawn: down the left side, across the bottom, up the
        // right side, back along the top. Each corner is given the edge it
        // arrives on (`v`) and the edge it leaves on (`u`), so the curve's
        // start is the point on the incoming edge and its end the point on the
        // outgoing one.
        let corners = [
            ContinuousCorner(
                at: CGPoint(x: bodyLeft, y: rect.minY),
                u: CGVector(dx: 0, dy: 1),       // away down the body's side
                v: CGVector(dx: -1, dy: 0),      // out to the frame's corner
                radius: top, roomU: sideRoom, roomV: top
            ),
            ContinuousCorner(
                at: CGPoint(x: bodyLeft, y: rect.maxY),
                u: CGVector(dx: 1, dy: 0),       // along the bottom edge
                v: CGVector(dx: 0, dy: -1),      // back up the body's side
                radius: bottom, roomU: bottomRoom, roomV: sideRoom
            ),
            ContinuousCorner(
                at: CGPoint(x: bodyRight, y: rect.maxY),
                u: CGVector(dx: 0, dy: -1),      // away up the body's side
                v: CGVector(dx: -1, dy: 0),      // back along the bottom edge
                radius: bottom, roomU: sideRoom, roomV: bottomRoom
            ),
            ContinuousCorner(
                at: CGPoint(x: bodyRight, y: rect.minY),
                u: CGVector(dx: 1, dy: 0),       // out to the frame's corner
                v: CGVector(dx: 0, dy: 1),       // back down the body's side
                radius: top, roomU: top, roomV: sideRoom
            ),
        ]

        var path = Path()
        path.move(to: corners[0].start)
        for (index, corner) in corners.enumerated() {
            if index > 0 { path.addLine(to: corner.start) }
            corner.append(to: &path)
        }
        path.closeSubpath()
        return path
    }
}

/// One of Apple's continuous corners, resolved into a shape's own coordinates.
///
/// `RoundedRectangle(style: .continuous)` is not a circular arc. It leaves a
/// straight edge gradually — through three cubic segments, reaching about one
/// and a half radii along each edge — and that long, kink-free transition is
/// the whole difference between the system's rounded shapes and a corner drawn
/// with `addQuadCurve`.
///
/// The constants below were read back out of CoreGraphics's own paths
/// (`RoundedRectangle(...).path(in:)`, at several radii and box proportions),
/// including the squeezed cases, where the rule turns out to be:
///
/// 1. the radius is first clamped to the tightest room its two edges offer, so
///    a corner in a short box behaves as a smaller corner rather than changing
///    character;
/// 2. the reach along each edge is then capped by that edge's own room;
/// 3. the two outer control distances follow that reach along two straight
///    lines, while the interior points keep their canonical proportions.
///
/// Step 1 is why this type rather than a radius: the closed notch is exactly
/// such a squeezed box — a 32pt-tall pill asking for a 16pt corner — and so is
/// the cover art drawn inside it.
struct ContinuousCorner {
    /// How far a continuous corner reaches along an edge, in radii. A circular
    /// corner reaches one radius.
    static let reach: CGFloat = 1.5286649466

    /// The two interior points where the corner's three arcs meet, in radii
    /// from the point the edges would have met at.
    private static let first = CGPoint(x: 0.0749114, y: 0.6314939)
    private static let innerFirst = CGPoint(x: 0.1690600, y: 0.3728240)
    private static let innerSecond = CGPoint(x: 0.3728240, y: 0.1690600)
    private static let second = CGPoint(x: 0.6314939, y: 0.0749114)

    /// The outer control distances, as `flat + slope × reach` above one radius'
    /// reach: the two straight lines CoreGraphics walks as a corner is given
    /// more room than a radius but less than its full reach.
    private static let outer: (flat: CGFloat, slope: CGFloat) = (0.96, 0.2430462)
    private static let inner: (flat: CGFloat, slope: CGFloat) = (0.82, 0.0915639)

    /// The point the corner's curve begins at: on the incoming edge, `v` away
    /// from the corner point.
    let start: CGPoint
    private let arcs: [(control1: CGPoint, control2: CGPoint, end: CGPoint)]

    /// - Parameters:
    ///   - corner: where the two edges would meet if they were not rounded.
    ///   - u: unit vector along the edge the corner leaves on, from `corner`.
    ///   - v: unit vector along the edge the corner arrives on, from `corner`.
    ///   - radius: the corner's nominal radius.
    ///   - roomU: straight edge available along `u`, measured from `corner`.
    ///   - roomV: straight edge available along `v`, measured from `corner`.
    init(
        at corner: CGPoint,
        u uAxis: CGVector,
        v vAxis: CGVector,
        radius: CGFloat,
        roomU: CGFloat,
        roomV: CGFloat
    ) {
        let roomU = max(roomU, 0)
        let roomV = max(roomV, 0)

        // Step 1: the radius the edges can actually hold, then step 2: how far
        // the curve reaches along each of them.
        let effectiveRadius = min(max(radius, 0), roomU, roomV)
        let reachU = min(Self.reach * effectiveRadius, roomU)
        let reachV = min(Self.reach * effectiveRadius, roomV)

        // Step 3: each edge's own reach, in effective radii.
        let limitU = effectiveRadius > 0 ? reachU / effectiveRadius : 0
        let limitV = effectiveRadius > 0 ? reachV / effectiveRadius : 0

        func control(_ line: (flat: CGFloat, slope: CGFloat), _ limit: CGFloat) -> CGFloat {
            (limit <= 1 ? line.flat * limit : line.flat + line.slope * (limit - 1)) * effectiveRadius
        }

        func point(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
            CGPoint(
                x: corner.x + uAxis.dx * u + vAxis.dx * v,
                y: corner.y + uAxis.dy * u + vAxis.dy * v
            )
        }

        func interior(_ offset: CGPoint) -> CGPoint {
            point(offset.x * effectiveRadius, offset.y * effectiveRadius)
        }

        start = point(0, reachV)
        arcs = [
            (
                point(0, control(Self.outer, limitV)),
                point(0, control(Self.inner, limitV)),
                interior(Self.first)
            ),
            (interior(Self.innerFirst), interior(Self.innerSecond), interior(Self.second)),
            (
                point(control(Self.inner, limitU), 0),
                point(control(Self.outer, limitU), 0),
                point(reachU, 0)
            ),
        ]
    }

    /// Appends the corner's three arcs. The path must already be at `start`.
    func append(to path: inout Path) {
        for arc in arcs {
            path.addCurve(to: arc.end, control1: arc.control1, control2: arc.control2)
        }
    }
}
