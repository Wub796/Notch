import SwiftUI

/// The notch silhouette, with independent top and bottom radii.
///
/// Geometry follows boring.notch and Atoll (both from DynamicNotchKit): the
/// top corners flare *outward* into the menu bar with a quad curve, and the
/// bottom corners round inward with another. Driving the two radii separately
/// is what lets the closed pill sit tight against the hardware notch (6/14)
/// while the open slab reads as a soft panel (19/24) — a single radius cannot
/// express both.
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
        let top = max(0, min(topCornerRadius, rect.width / 2, rect.height))
        let bottom = max(0, min(
            bottomCornerRadius,
            max(0, rect.width / 2 - top),
            max(0, rect.height - top)
        ))

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top, y: rect.minY + top),
            control: CGPoint(x: rect.minX + top, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY),
            control: CGPoint(x: rect.minX + top, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom),
            control: CGPoint(x: rect.maxX - top, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - top, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))

        return path
    }
}
