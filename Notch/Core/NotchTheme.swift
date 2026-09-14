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

    static let surfaceHover = Color.white.opacity(0.08)

    /// Whether the user has asked macOS to reduce on-screen transparency
    /// (Accessibility → Display → Reduce Transparency). The notch's own
    /// surface is solid black, but transient materials — the charging popup's
    /// `.ultraThinMaterial`, any future frosted sheet — must frost over or go
    /// solid under this preference rather than stay blurry.
    static var prefersReducedTransparency: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }

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
    /// Shared rendering context. Building a `CIContext` allocates GPU-backed
    /// resources and costs milliseconds — doing it per artwork made every
    /// track change pay for one.
    private static let averageColorContext = CIContext(
        options: [.workingColorSpace: NSNull()]
    )

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
        Self.averageColorContext.render(
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

/// Compresses subtly while pressed with instant tactile feedback for every
/// tappable control.
///
/// Asymmetric on purpose: the press is the user's own action and should land
/// immediately, while the release is the control recovering and can settle.
/// Symmetric timing made both halves feel equally deliberate, which reads as
/// lag on the half the user is actually watching.
struct PressableButtonStyle: ButtonStyle {
    private static let press = Animation.spring(response: 0.12, dampingFraction: 0.9)
    private static let release = Animation.spring(response: 0.26, dampingFraction: 0.7)

    func makeBody(configuration: Configuration) -> some View {
        // Reduce Motion keeps the feedback but drops the movement: the opacity
        // dip still confirms the press.
        let reduced = NotchAnimations.prefersReducedMotion
        return configuration.label
            .scaleEffect(configuration.isPressed && !reduced ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(
                reduced
                    ? NotchAnimations.reduced
                    : (configuration.isPressed ? Self.press : Self.release),
                value: configuration.isPressed
            )
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
            // Reduce Motion drops the scale, not the interaction: the hover
            // still registers, it just stops moving things around.
            .scaleEffect(hovering && !NotchAnimations.prefersReducedMotion ? scale : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.78), value: hovering)
            .onHover { hovering = $0 }
    }
}

extension View {
    func hoverLift(_ scale: CGFloat = 1.05) -> some View {
        modifier(HoverLiftModifier(scale: scale))
    }
}

/// Hover + cursor affordance for tap-through tiles — the dashboard's weather
/// and calendar blocks select via a tap gesture, so unlike Buttons they got
/// neither the pointing-hand cursor nor any hover response. This restores
/// both: the system pointing hand while the pointer is over the tile, and a
/// faint brightening so the tile reads as live under the cursor.
///
/// The press is tracked with a zero-distance drag, which claims the click on
/// mouse-down. Any tap that should act on the tile must be attached outside
/// this modifier as a `.simultaneousGesture`; a plain `.onTapGesture` there
/// never fires.
struct TileHoverModifier: ViewModifier {
    @State private var hovering = false
    @State private var pressed = false

    func body(content: Content) -> some View {
        content
            .brightness(hovering ? 0.07 : 0)
            // A tap-through tile is a control, so it should answer a press the
            // way every Button here does. Reduce Motion keeps the brightening
            // and drops the movement.
            .scaleEffect(scale)
            .animation(NotchAnimations.content, value: hovering)
            .animation(.spring(response: 0.16, dampingFraction: 0.85), value: pressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !pressed { pressed = true } }
                    .onEnded { _ in pressed = false }
            )
            .onHover { entering in
                // Balanced push/pop: SwiftUI can deliver `false` without a
                // preceding `true` (on a view update, or when the window stops
                // taking the mouse), and popping for a push this modifier never
                // made corrupts the process-wide cursor stack. Transition on
                // the stored state, never on the raw event.
                guard entering != hovering else { return }
                hovering = entering
                if entering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .onDisappear {
                if hovering {
                    NSCursor.pop()
                    hovering = false
                }
                // A tile removed mid-press must not come back pressed.
                pressed = false
            }
    }

    private var scale: CGFloat {
        guard !NotchAnimations.prefersReducedMotion else { return 1 }
        if pressed { return 0.985 }
        return hovering ? 1.012 : 1
    }
}

extension View {
    func tileHover() -> some View { modifier(TileHoverModifier()) }
}


