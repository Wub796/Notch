import SwiftUI

/// Expanded state: header strip, tab bar, and the active feature module — or
/// the drop zone while a drag hovers over the notch. An ambient glow in the
/// artwork accent breathes behind the media tab.
struct ExpandedNotchView: View {
    let state: NotchState
    let namespace: Namespace.ID

    var body: some View {
        VStack(spacing: 10) {
            if state.isDropTargeted || state.shelf.isResolvingDrop {
                DropZoneView(
                    isResolving: state.shelf.isResolvingDrop,
                    instantAirDrop: state.settings.instantAirDrop
                )
            } else {
                NotchHeaderView(state: state)
                headerDivider
                tabBar
                content
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            // Ambient backdrop on the media tab: the artwork itself, blurred
            // and dimmed into a glow; accent wash as the no-artwork fallback.
            if state.tab == .media {
                Group {
                    if let artwork = state.media.artwork {
                        Image(nsImage: artwork)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 560, height: 280)
                            .blur(radius: 64)
                            .saturation(1.5)
                            .opacity(0.24)
                            .offset(y: -16)
                    } else {
                        Ellipse()
                            .fill(state.media.accent)
                            .opacity(0.1)
                            .blur(radius: 55)
                            .frame(width: 440, height: 220)
                            .offset(y: -30)
                    }
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .animation(.notchSpring, value: state.tab)
    }

    /// Full-bleed hairline separating the header strip from the content.
    private var headerDivider: some View {
        Rectangle()
            .fill(NotchTheme.hairline)
            .frame(height: 1)
            .padding(.horizontal, -24)
    }

    private var tabBar: some View {
        HStack(spacing: 3) {
            ForEach(NotchTab.allCases) { tab in
                Button {
                    state.select(tab)
                } label: {
                    Label(tab.title, systemImage: tab.systemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background {
                            if state.tab == tab {
                                Capsule()
                                    .fill(.white.opacity(0.14))
                                    .matchedGeometryEffect(id: "tabHighlight", in: namespace)
                            }
                        }
                        .foregroundStyle(state.tab == tab ? NotchTheme.inkPrimary : NotchTheme.inkSecondary)
                        .overlay(alignment: .topTrailing) {
                            if tab == .shelf, state.shelf.items.count > 0 {
                                Text("\(state.shelf.items.count)")
                                    .font(.system(size: 9, weight: .heavy).monospacedDigit())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1.5)
                                    .background(Capsule().fill(.blue))
                                    .offset(x: 6, y: -5)
                            }
                        }
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
        .padding(3)
        .background {
            Capsule().fill(.white.opacity(0.05))
        }
        .overlay {
            Capsule().stroke(NotchTheme.hairline, lineWidth: 1)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .animation(.notchSpring, value: state.tab)
    }

    /// Content enters with the frosted glass settle and exits with a plain
    /// fade, so outgoing views clear faster than incoming ones arrive.
    private static let tabTransition = AnyTransition.asymmetric(
        insertion: .glass,
        removal: .opacity
    )

    @ViewBuilder
    private var content: some View {
        switch state.tab {
        case .media:
            MediaPlayerView(media: state.media, namespace: namespace)
                .transition(Self.tabTransition)
        case .shelf:
            ShelfView(shelf: state.shelf)
                .transition(Self.tabTransition)
        case .calendar:
            CalendarView(calendar: state.calendar)
                .transition(Self.tabTransition)
        case .telemetry:
            TelemetryView(telemetry: state.telemetry)
                .transition(Self.tabTransition)
        }
    }
}

/// Full-surface drop zone shown while a drag hovers over the notch, with a
/// marching-ants border while active.
struct DropZoneView: View {
    let isResolving: Bool
    let instantAirDrop: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dashPhase: CGFloat = 0

    private var title: String {
        if isResolving {
            return instantAirDrop ? "Starting AirDrop…" : "Adding to Shelf…"
        }
        return instantAirDrop ? "Drop to AirDrop" : "Drop to add to Shelf"
    }

    private var subtitle: String {
        instantAirDrop
            ? "Files and text are sent immediately"
            : "Items stay on the shelf until you send or clear them"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: isResolving
                ? "wave.3.right.circle.fill"
                : (instantAirDrop ? "airplane.circle.fill" : "tray.and.arrow.down.fill"))
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.blue)
                .symbolEffect(.pulse, isActive: isResolving)

            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(NotchTheme.inkPrimary)

            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(NotchTheme.inkSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    .blue.opacity(0.7),
                    style: StrokeStyle(lineWidth: 1.5, dash: [7, 5], dashPhase: dashPhase)
                )
                .background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.blue.opacity(0.08))
                }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                dashPhase = -12
            }
        }
    }
}
