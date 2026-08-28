import SwiftUI

/// The notch silhouette, drawn Sapphire-style: quad-curve flares at the top
/// (radius derived from the corner radius) and true circular arcs at the
/// bottom, all clamped so the shape stays valid at any size mid-animation.
struct NotchShape: Shape {
    /// Single driving radius; the top flare derives from it.
    var cornerRadius: CGFloat

    init(cornerRadius: CGFloat = 10) {
        self.cornerRadius = cornerRadius
    }

    var animatableData: CGFloat {
        get { cornerRadius }
        set { cornerRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        guard rect.width.isFinite, rect.height.isFinite,
              rect.width > 0, rect.height > 0
        else { return Path() }

        let topRadiusBase: CGFloat = cornerRadius > 15 ? cornerRadius - 5 : 8
        let topRadius = max(0, min(topRadiusBase, rect.height / 2, rect.width / 2))

        let bottomRadius = max(0, min(
            cornerRadius,
            (rect.width - 2 * topRadius) / 2,
            rect.height - topRadius
        ))

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topRadius, y: rect.minY + topRadius),
            control: CGPoint(x: rect.minX + topRadius, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + topRadius, y: rect.maxY - bottomRadius))
        if bottomRadius > 0 {
            path.addArc(
                center: CGPoint(
                    x: rect.minX + topRadius + bottomRadius,
                    y: rect.maxY - bottomRadius
                ),
                radius: bottomRadius,
                startAngle: Angle(degrees: 180),
                endAngle: Angle(degrees: 90),
                clockwise: true
            )
        }
        path.addLine(to: CGPoint(x: rect.maxX - topRadius - bottomRadius, y: rect.maxY))
        if bottomRadius > 0 {
            path.addArc(
                center: CGPoint(
                    x: rect.maxX - topRadius - bottomRadius,
                    y: rect.maxY - bottomRadius
                ),
                radius: bottomRadius,
                startAngle: Angle(degrees: 90),
                endAngle: Angle(degrees: 0),
                clockwise: true
            )
        }
        path.addLine(to: CGPoint(x: rect.maxX - topRadius, y: rect.minY + topRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - topRadius, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}
