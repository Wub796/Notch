import AppKit
import CoreImage
import SwiftUI

/// Design tokens for the notch UI.
///
/// The telemetry palette is validated for the dark glass surface (#0A0A0A):
/// lightness band, chroma floor, CVD separation, normal-vision separation, and
/// 3:1 contrast all pass. Identity is additionally carried by an icon and a
/// direct text label on every metric — never color alone.
enum NotchTheme {
    // MARK: Metric palette (validated, dark surface)

    static let cpu = Color(red: 234 / 255, green: 88 / 255, blue: 12 / 255) // #EA580C
    static let memory = Color(red: 139 / 255, green: 92 / 255, blue: 246 / 255) // #8B5CF6
    static let battery = Color(red: 5 / 255, green: 150 / 255, blue: 105 / 255) // #059669
    static let network = Color(red: 2 / 255, green: 132 / 255, blue: 199 / 255) // #0284C7

    // MARK: Ink — text always wears these, never a series color
    // Opacities are chosen so normal text stays ≥ 4.5:1 against the black
    // glass (0.47 white on black ≈ 4.8:1).

    static let inkPrimary = Color.white
    static let inkSecondary = Color.white.opacity(0.62)
    static let inkMuted = Color.white.opacity(0.47)

    // MARK: Surfaces

    static let surface = Color.clear
    static let surfaceHover = Color.white.opacity(0.08)
    static let hairline = Color.clear

    /// Accent derived from album artwork: the average color pushed into a
    /// saturation/brightness band that stays legible on black glass.
    /// Near-grayscale artwork falls back to a neutral white accent.
    static func accent(from image: NSImage) -> Color {
        guard let average = image.averageColor()?.usingColorSpace(.deviceRGB) else {
            return .white
        }
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        average.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        guard saturation >= 0.08 else { return .white }
        return Color(nsColor: NSColor(
            hue: hue,
            saturation: min(max(saturation, 0.5), 0.8),
            brightness: max(brightness, 0.82),
            alpha: 1
        ))
    }
}

extension NSImage {
    /// Single-pass average color via CIAreaAverage.
    func averageColor() -> NSColor? {
        guard let tiff = tiffRepresentation,
              let inputImage = CIImage(data: tiff),
              let filter = CIFilter(name: "CIAreaAverage", parameters: [
                  kCIInputImageKey: inputImage,
                  kCIInputExtentKey: CIVector(cgRect: inputImage.extent),
              ]),
              let output = filter.outputImage
        else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        context.render(
            output,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )
        return NSColor(
            red: CGFloat(bitmap[0]) / 255,
            green: CGFloat(bitmap[1]) / 255,
            blue: CGFloat(bitmap[2]) / 255,
            alpha: 1
        )
    }
}

// MARK: - Micro-interactions

/// Compresses subtly while pressed with instant tactile feedback for every tappable control.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.16, dampingFraction: 0.85), value: configuration.isPressed)
    }
}

/// Standard feedback for bare icon buttons: dimmed at rest, full brightness
/// on hover, half-faded when disabled (picked up from the environment).
struct HoverIconModifier: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .opacity(isEnabled ? (hovering ? 1 : 0.72) : 0.35)
            .animation(NotchAnimations.content, value: hovering)
            .onHover { hovering = $0 }
    }
}

/// Lifts an element on pointer hover with smooth physical spring.
struct HoverLiftModifier: ViewModifier {
    var scale: CGFloat
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering ? scale : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.78), value: hovering)
            .onHover { hovering = $0 }
    }
}

extension View {
    func hoverLift(_ scale: CGFloat = 1.05) -> some View {
        modifier(HoverLiftModifier(scale: scale))
    }
}

// MARK: - Transitions

/// Frosted content transition: blur + fade + a short downward settle.
struct GlassTransitionModifier: ViewModifier {
    let blur: CGFloat
    let opacity: Double
    let offsetY: CGFloat

    func body(content: Content) -> some View {
        content
            .blur(radius: blur)
            .opacity(opacity)
            .offset(y: offsetY)
    }
}

extension AnyTransition {
    static let glass = AnyTransition.modifier(
        active: GlassTransitionModifier(blur: 3, opacity: 0, offsetY: 6),
        identity: GlassTransitionModifier(blur: 0, opacity: 1, offsetY: 0)
    )
}
