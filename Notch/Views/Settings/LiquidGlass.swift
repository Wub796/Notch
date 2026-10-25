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

    /// The smoke over the blurred backdrop. Spans from pure crystal-clear
    /// glass at 0% to a balanced, elegant smoked obsidian at 100%.
    static var bodyTint: Color {
        SettingsMetrics.adaptiveColor(
            dark: NSColor(white: 0, alpha: pow(depth, 1.25) * 0.45),
            light: NSColor(white: 1, alpha: pow(depth, 1.25) * 0.40)
        )
    }

    /// Cards sit one step above the window's own glass, and lighter rather
    /// than darker. Spans from a featherlight transparent plane to a distinct,
    /// refined smoked glass slab.
    static var cardTint: Color {
        SettingsMetrics.adaptiveColor(
            dark: NSColor(white: 1, alpha: pow(depth, 1.25) * 0.22),
            light: NSColor(white: 1, alpha: pow(depth, 1.25) * 0.26)
        )
    }

    /// The denser body worn under Reduce Transparency — the frosting the
    /// reference prescribes when the user asks macOS for less see-through.
    static var reduceTransparencyFill: Color {
        SettingsMetrics.adaptiveColor(
            dark: NSColor(white: 0.08, alpha: 0.78),
            light: NSColor(white: 1, alpha: 0.86)
        )
    }

    /// A gradient that is bright on the top edge and gone by a fifth of the
    /// way down — the lip of a solid, not a wash over its face.
    static var specularGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .white.opacity(0.10 + depth * 0.14), location: 0),
                .init(color: .white.opacity(0.02 + depth * 0.04), location: 0.06),
                .init(color: .clear, location: 0.18)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Full-surface chromatic dispersion across the window backdrop.
    /// Spans from delicate crystal separation to balanced prismatic dispersion.
    static var backdropChromaticGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.40, green: 0.75, blue: 1).opacity(0.03 + depth * 0.06),
                .clear,
                Color(red: 1, green: 0.55, blue: 0.85).opacity(0.02 + depth * 0.05)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Full-surface specular wash across the window backdrop.
    /// At 0% it is clear and unshadowed; at 100% it has subtle top reflections
    /// and gentle bottom ambient depth.
    static var backdropSpecularGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.03 + depth * 0.12),
                Color.clear,
                Color.black.opacity(pow(depth, 1.3) * 0.20)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Caustic pooling along the top edge of the backdrop.
    static var backdropCausticGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.03 + depth * 0.14),
                Color.white.opacity(depth * 0.03),
                .clear
            ],
            startPoint: .top,
            endPoint: UnitPoint(x: 0.5, y: 0.25)
        )
    }

    /// Ambient chromatic dispersion over the entire card surface.
    static var elementChromaticGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.40, green: 0.75, blue: 1).opacity(0.02 + depth * 0.05),
                .clear,
                Color(red: 1, green: 0.55, blue: 0.85).opacity(0.015 + depth * 0.04)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Ambient specular sheen over the face of the element.
    static var elementSpecularGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color.white.opacity(0.05 + depth * 0.10), location: 0),
                .init(color: Color.white.opacity(0.01 + depth * 0.03), location: 0.08),
                .init(color: .clear, location: 0.20)
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
                    shape.fill(.ultraThinMaterial.opacity(pow(LiquidGlass.depth, 1.4)))
                }

                if reduceTransparency {
                    shape.fill(LiquidGlass.reduceTransparencyFill)
                }

                // The depth-driven layers sit on the glass in both paths, so
                // the slider moves the same rim light, face tint and edge
                // thickness however the pane is backed.
                shape.fill(LiquidGlass.cardTint)
                shape.fill(LiquidGlass.elementChromaticGradient)
                shape.fill(LiquidGlass.elementSpecularGradient)
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
            shape.strokeBorder(.white.opacity(0.20 + depth * 0.16), lineWidth: 1)

            // The bevel's inner glow: a few pixels wide, and only on the side
            // the light reaches.
            shape
                .inset(by: 1)
                .strokeBorder(.white.opacity(0.05 + depth * 0.10), lineWidth: 2)
                .blur(radius: 1)
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
                    Color(red: 0.40, green: 0.75, blue: 1).opacity(0.12 + depth * 0.14),
                    lineWidth: 1.5
                )
            shape
                .inset(by: 1.5)
                .strokeBorder(
                    Color(red: 1, green: 0.55, blue: 0.85).opacity(0.08 + depth * 0.12),
                    lineWidth: 1.5
                )

            // The pane's thickness. Light that enters the top face leaves at
            // the bottom edge, so the far lip carries a dim caustic line — and
            // just above it, the shadow the glass's depth casts on itself.
            shape
                .inset(by: 1)
                .strokeBorder(.white.opacity(0.06 + depth * 0.12), lineWidth: 1)
                .mask {
                    LinearGradient(
                        colors: [.clear, .white],
                        startPoint: UnitPoint(x: 0.5, y: 0.55),
                        endPoint: .bottom
                    )
                }
            shape
                .inset(by: 2)
                .strokeBorder(.black.opacity(pow(depth, 1.25) * 0.20), lineWidth: 2)
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
                .strokeBorder(.white.opacity(0.18 + depth * 0.18), lineWidth: 1.5)
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
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        ZStack {
            if LiquidGlass.isEnabled {
                if #available(macOS 26.0, *) {
                    // The whole window is the system's glass, not just the
                    // cards' faces: `.regular` lenses the desktop behind the
                    // window here the way the panes' glass lenses the window.
                    shape
                        .fill(.clear)
                        .glassEffect(.regular, in: shape)
                } else {
                    // No glass API below 26 — the blurred material is the
                    // closest stand-in for sampling the desktop.
                    VisualEffectView(material: .sidebar)
                        .opacity(0.50 + pow(LiquidGlass.depth, 1.2) * 0.35)
                }

                if reduceTransparency {
                    shape.fill(LiquidGlass.reduceTransparencyFill)
                }

                LiquidGlass.bodyTint
                shape.fill(LiquidGlass.backdropChromaticGradient)
                shape.fill(LiquidGlass.backdropSpecularGradient)
                shape.fill(LiquidGlass.backdropCausticGradient)
            } else {
                // Off is a plain, opaque window: no blur of the desktop at all,
                // so turning the glass off is visible on any wallpaper.
                shape.fill(SettingsMetrics.solidWindowColor)
            }
        }
        .clipShape(shape)
        .contentShape(shape)
        .overlay {
            if LiquidGlass.isEnabled {
                shape
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.20 + LiquidGlass.depth * 0.16),
                                Color.white.opacity(0.05 + LiquidGlass.depth * 0.05),
                                Color.clear,
                                Color.black.opacity(pow(LiquidGlass.depth, 1.3) * 0.18)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                    .allowsHitTesting(false)
            }
        }
    }
}
