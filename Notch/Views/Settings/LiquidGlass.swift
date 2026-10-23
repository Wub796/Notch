import AppKit
import SwiftUI

/// The Settings window's liquid-glass language.
///
/// On macOS 26 the panes are the system's own Liquid Glass — `.glassEffect`
/// refracts, disperses, and lenses the desktop behind the window, which is the
/// effect this window otherwise has to fake.
///
/// Below 26 there is no such API (this app deploys to 14), so the panes are
/// built from a blurred material plus the terms of the reference renderer in
/// `ybouane/liquidglass` (MIT — see THIRD-PARTY-NOTICES.md): a bevelled edge
/// whose surface normal tilts outward, the Fresnel reflection that puts a
/// hairline of light on the last pixel of that bevel, the two specular lobes
/// above it, a chromatic fringe where the glass disperses the backdrop, and a
/// depth the user sets between clear water and smoked glass. `LiquidGlassRim`
/// is that math drawn as strokes; the pure refraction of the desktop behind the
/// window is the one term it cannot reproduce without the backdrop's pixels.
///
/// Everything reads `NotchSettings` while it renders, so moving the depth
/// slider re-tints the window and its cards in the same frame — no separate
/// refresh path to forget.
enum LiquidGlass {
    /// 0 = clear, 1 = dark.
    static var depth: Double { min(max(NotchSettings.shared.glassDepth, 0), 1) }

    /// Off gives the window back its plain material and its flat cards. The
    /// toggle is a real switch, not a style that is always on.
    static var isEnabled: Bool { NotchSettings.shared.liquidGlassEnabled }

    /// The smoke over the blurred backdrop. Black in dark mode, white in
    /// light — the same slider smokes the glass in one and frosts it in the
    /// other, which is what "Dark" means in either appearance.
    static var bodyTint: Color {
        SettingsMetrics.adaptiveColor(
            dark: NSColor(white: 0, alpha: 0.05 + depth * 0.30),
            light: NSColor(white: 1, alpha: 0.06 + depth * 0.22)
        )
    }

    /// Cards sit one step above the window's own glass, and lighter rather
    /// than darker: a card is a pane resting on the window, catching more of
    /// the room's light than the glass it sits on. Kept translucent on
    /// purpose — the tint is how much light the pane holds, not a coat of
    /// paint over its face, so the glass reads through the middle of a card
    /// and not only along its rim.
    static var cardTint: Color {
        SettingsMetrics.adaptiveColor(
            dark: NSColor(white: 1, alpha: 0.05 + depth * 0.16),
            light: NSColor(white: 1, alpha: 0.16 + depth * 0.26)
        )
    }

    /// The denser body worn under Reduce Transparency — the frosting the
    /// reference prescribes when the user asks macOS for less see-through.
    static var reduceTransparencyFill: Color {
        SettingsMetrics.adaptiveColor(
            dark: NSColor(white: 0.08, alpha: 0.72),
            light: NSColor(white: 1, alpha: 0.82)
        )
    }

    /// A gradient that is bright on the top edge and gone by a fifth of the
    /// way down — the lip of a solid, not a wash over its face.
    static var specularGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .white.opacity(0.10 + depth * 0.10), location: 0),
                .init(color: .clear, location: 0.22)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// The background of one Settings card.
struct LiquidGlassPaneBackground: View {
    /// Reduce Transparency: the reference's adaptation is "increases frosting
    /// for clarity". The native glass applies that on its own; the drawn
    /// layers need their own denser body to do the same.
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let shape = RoundedRectangle(
            cornerRadius: SettingsMetrics.rowRadius,
            style: .continuous
        )

        if LiquidGlass.isEnabled {
            ZStack {
                if #available(macOS 26.0, *) {
                    // `.regular`, not `.clear`: LiquidGlassReference scopes
                    // `.clear` to media-rich backdrops with bold content on
                    // top — requirements these cards don't meet — and puts
                    // ordinary UI on `.regular`, the variant that actually
                    // lenses and adapts to content. The tint is *not* passed
                    // here: a tint that changes while the depth slider drags
                    // re-updates the effect several times per frame (the
                    // console warning), and the drawn layers below carry the
                    // depth instead.
                    shape
                        .fill(.clear)
                        .glassEffect(.regular, in: shape)
                } else {
                    shape.fill(.ultraThinMaterial)
                }

                if reduceTransparency {
                    shape.fill(LiquidGlass.reduceTransparencyFill)
                }

                // The depth-driven layers sit on the glass in both paths, so
                // the slider moves the same rim light, face tint and edge
                // thickness however the pane is backed.
                shape.fill(LiquidGlass.cardTint)
                shape.fill(LiquidGlass.specularGradient)
                LiquidGlassRim(shape: shape)
            }
        } else {
            ZStack {
                shape.fill(SettingsMetrics.solidCardColor)
                shape.strokeBorder(
                    SettingsMetrics.rowBorder,
                    lineWidth: SettingsMetrics.rowBorderWidth
                )
            }
        }
    }
}

/// The lit edge of a pane, drawn from the reference renderer's terms.
///
/// The shader walks a bevel height field, takes its gradient as the surface
/// normal, and lights that normal: Fresnel against the eye, two Blinn-Phong
/// lobes from above, a top-biased inner stroke, and a chromatic fringe wherever
/// the normal is steep. On a static shape all of that is a function of distance
/// from the edge and direction from the light, so it is drawn here as a handful
/// of strokes rather than per pixel — the same light, at the cost of a few
/// gradients.
struct LiquidGlassRim<S: InsettableShape>: View {
    let shape: S

    /// The key light, as a point inside the pane. Above, and slightly toward
    /// the trailing edge — the direction the reference lights a biconvex pill
    /// from (`vec3(0.4, 0.7, 1.0)`), mapped to a unit point.
    var light = UnitPoint(x: 0.62, y: 0)

    var body: some View {
        let depth = LiquidGlass.depth

        ZStack {
            // Fresnel. `pow(1 - N·V, 4)` leaves nothing but the last pixel or
            // two of a bevel, so this is a hairline rather than a border.
            shape.strokeBorder(.white.opacity(0.22 + depth * 0.14), lineWidth: 1)

            // The bevel's inner glow: a few pixels wide, and only on the side
            // the light reaches.
            shape
                .inset(by: 1)
                .strokeBorder(.white.opacity(0.08 + depth * 0.07), lineWidth: 3)
                .blur(radius: 1.5)
                .mask {
                    LinearGradient(
                        colors: [.white, .white.opacity(0.12)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }

            // Chromatic aberration. Split along the edge normal — a cool
            // fringe just inside the rim, warm just past it — at the strength
            // `liquid-glass-react` tunes in (aberration intensity 2), which is
            // where the dispersion reads without smearing the edge.
            shape
                .inset(by: 0.5)
                .strokeBorder(
                    Color(red: 0.42, green: 0.78, blue: 1).opacity(0.18 + depth * 0.10),
                    lineWidth: 1.5
                )
            shape
                .inset(by: 1.5)
                .strokeBorder(
                    Color(red: 1, green: 0.62, blue: 0.86).opacity(0.13 + depth * 0.08),
                    lineWidth: 1.5
                )

            // The pane's thickness. Light that enters the top face leaves at
            // the bottom edge, so the far lip carries a dim caustic line — and
            // just above it, the shadow the glass's depth casts on itself.
            shape
                .inset(by: 1)
                .strokeBorder(.white.opacity(0.10 + depth * 0.08), lineWidth: 1)
                .mask {
                    LinearGradient(
                        colors: [.clear, .white],
                        startPoint: UnitPoint(x: 0.5, y: 0.55),
                        endPoint: .bottom
                    )
                }
            shape
                .inset(by: 2)
                .strokeBorder(.black.opacity(0.10 + depth * 0.12), lineWidth: 3)
                .blur(radius: 2)
                .mask {
                    LinearGradient(
                        colors: [.clear, .white],
                        startPoint: UnitPoint(x: 0.5, y: 0.5),
                        endPoint: .bottom
                    )
                }

            // The two specular lobes: a tight one over the top edge, and the
            // broad wash beneath it that `specularGradient` already lays down.
            shape
                .strokeBorder(.white.opacity(0.28 + depth * 0.14), lineWidth: 2)
                .blur(radius: 1.5)
                .mask {
                    RadialGradient(
                        colors: [.white, .white.opacity(0)],
                        center: light,
                        startRadius: 0,
                        endRadius: 130
                    )
                }
        }
        .allowsHitTesting(false)
    }
}

/// The window's own layer: the glass of the desktop, the smoke over it, and
/// the light pooling along its top edge.
struct LiquidGlassBackdrop: View {
    var body: some View {
        ZStack {
            if LiquidGlass.isEnabled {
                if #available(macOS 26.0, *) {
                    // The whole window is the system's glass, not just the
                    // cards' faces: `.regular` lenses the desktop behind the
                    // window here the way the panes' glass lenses the window.
                    Rectangle()
                        .fill(.clear)
                        .glassEffect(.regular, in: Rectangle())
                } else {
                    // No glass API below 26 — the blurred material is the
                    // closest stand-in for sampling the desktop.
                    VisualEffectView(material: .sidebar)
                }
                LiquidGlass.bodyTint

                // Cool at the top-leading corner, warm shadow at the
                // bottom-trailing one — what stops a big glass panel from
                // reading as a flat slab of grey.
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.07),
                        .clear,
                        Color.black.opacity(0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // The window's own lip. Its corner is AppKit's native mask, so
                // it cannot take a stroke the way a card can; the light pooling
                // at the top edge is where a full-window pane shows its bevel.
                LinearGradient(
                    colors: [
                        .white.opacity(0.09 + LiquidGlass.depth * 0.06),
                        .clear
                    ],
                    startPoint: .top,
                    endPoint: UnitPoint(x: 0.5, y: 0.16)
                )
            } else {
                // Off is a plain, opaque window: no blur of the desktop at all,
                // so turning the glass off is visible on any wallpaper.
                SettingsMetrics.solidWindowColor
            }
        }
        .allowsHitTesting(false)
    }
}
