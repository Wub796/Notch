import SwiftUI

/// What the notch body actually draws, in both states.
///
/// This is the shape of boring.notch's and Atoll's `NotchLayout()`. The point
/// of the arrangement is that **nothing sets an explicit width**: closed, the
/// layout is a strip whose intrinsic width is the hardware notch plus whatever
/// live activity is showing; open, it is a header and module pinned to the open
/// slab's width. Animating `state.mode` therefore animates a real layout change
/// from one natural size to the other, which is what makes the notch look like
/// it physically grows rather than cross-fading between two fixed pictures.
struct NotchLayoutView: View {
    let state: NotchState
    let namespace: Namespace.ID
    let isHovering: Bool

    /// The open module unfolds from the top edge.
    ///
    /// Deliberately carries no `.animation` of its own. The references pin
    /// theirs to 0.35s, which matches their 0.42s spring; against the much
    /// longer spring here it meant the content had finished arriving while the
    /// shape was still a third of the way open — the content snapping into a
    /// notch-sized window is the flash before the expansion. Without an
    /// animation the transition inherits the spring and the two move as one.
    ///
    /// The references' scale is gone with it. Over a curve this long the
    /// module growing while the panel is also growing is two motions doing the
    /// same job, and the pair reads as busier than either alone. The panel's
    /// own geometry carries the movement; the content only fades in.
    private static let moduleTransition = AnyTransition.opacity

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(alignment: .center, spacing: 6) {
                headerStrip

                if state.mode == .expanded {
                    sizedModule
                        .transition(Self.moduleTransition)
                        .allowsHitTesting(true)
                        .zIndex(1)
                }
            }

            // Action confirmations float over the open panel's bottom edge;
            // an overlay so they never participate in the fitted-height
            // measurement, and hit-testing off so they can't eat a click.
            if state.mode == .expanded, let toast = state.toast {
                NotchToastView(toast: toast)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
                    .zIndex(20)
            }
        }
    }

    // MARK: - Header / closed strip

    /// Closed, this is the live-activity strip; open, it is the module rail and
    /// status icons. Both wrap the same reserved dead zone for the camera
    /// housing, so the two states line up through the morph.
    @ViewBuilder
    private var headerStrip: some View {
        if state.mode == .expanded {
            ExpandedNotchView(state: state, namespace: namespace)
                // Both strips fill their width, so without an explicit one
                // here the VStack has nothing to size itself from and takes
                // the whole panel window — which is as wide as the display.
                .frame(width: state.moduleContentSize.width, height: state.topBarHeight)
                // Swapping the two strips with no transition is a hard cut in
                // the middle of a slow expansion, which reads as a flash.
                .transition(.opacity)
                .zIndex(2)
        } else {
            CollapsedNotchView(state: state, isHovering: isHovering)
                .frame(width: state.collapsedSize.width, height: state.collapsedSize.height)
                // Hovering the closed pill widens it slightly, the way both
                // references pad their wings out on hover. The amount is the
                // user's "hover grow" preference.
                .padding(.horizontal, isHovering ? state.hoverExpansion : 0)
                .transition(.opacity)
                .zIndex(2)
        }
    }

    // MARK: - Module

    /// The module, sized to the tab's budget — except for the tabs that opt
    /// into height fitting, where the width stays on the budget but the
    /// height is measured: `fixedSize(horizontal: false, vertical: true)`
    /// passes the width proposal through while asking the content for its
    /// natural height, and the GeometryReader in the background reports what
    /// it actually needed. That lands in `NotchState.measuredModuleHeight`,
    /// which is what `expandedSize` hugs, so the slab shrinks to the content
    /// instead of carrying a black band beneath it.
    @ViewBuilder
    private var sizedModule: some View {
        if NotchSizing.fitsHeight(for: state.tab) {
            moduleContent
                .frame(width: state.moduleContentSize.width)
                .fixedSize(horizontal: false, vertical: true)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: ModuleNaturalHeightKey.self,
                            value: proxy.size.height
                        )
                    }
                }
                .onPreferenceChange(ModuleNaturalHeightKey.self) { height in
                    // Deferred off the layout pass: recording the height while
                    // SwiftUI is mid-update can be dropped, which silently
                    // leaves the slab on its full budget — the black band
                    // under the module this mechanism exists to remove. The
                    // tab is captured so a switch before the block runs can't
                    // file the height under the wrong screen.
                    let tab = state.tab
                    DispatchQueue.main.async {
                        state.updateMeasuredModuleHeight(height, for: tab)
                    }
                }
        } else {
            moduleContent
                .frame(
                    width: state.moduleContentSize.width,
                    height: state.moduleContentSize.height,
                    alignment: .center
                )
        }
    }

    @ViewBuilder
    private var moduleContent: some View {
        if state.isDropTargeted || state.shelf.isResolvingDrop {
            DropZoneView(
                isResolving: state.shelf.isResolvingDrop,
                instantAirDrop: state.settings.instantAirDrop
            )
        } else {
            tabContent
        }
    }

    /// The screen itself. Keyed on the tab so switching screens is a
    /// substitution with a transition rather than a hard replacement — the
    /// panel is already open here, and it resizes on the same `content`
    /// animation, so the two move together instead of one cutting under the
    /// other.
    @ViewBuilder
    private var tabContent: some View {
        tabScreen
            .id(state.tab)
            .transition(
                .asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.985, anchor: .top)).combined(with: .offset(y: 4)),
                    removal: .opacity
                )
            )
            .animation(NotchAnimations.content, value: state.tab)
    }

    @ViewBuilder
    private var tabScreen: some View {
        switch state.tab {
        case .home:
            HomeDashboardView(state: state, namespace: namespace)
        case .media:
            MediaPlayerView(state: state, namespace: namespace)
        case .weather:
            WeatherDetailView(state: state)
        case .calendar:
            CalendarDetailView(state: state)
        case .shelf:
            ShelfView(state: state)
        case .clipboard:
            ClipboardView(state: state)
        case .tools:
            ToolsView(state: state)
        case .notes:
            NotesView(state: state)
        case .telemetry:
            TelemetryView(telemetry: state.telemetry)
        case .audio:
            DevicesScreenView(state: state, namespace: namespace)
        }
    }
}

/// Carries the open module's natural height out of the size pass. Defaults to
/// zero; NotchState ignores non-positive values, so the slab is unaffected
/// until a real measurement arrives.
private struct ModuleNaturalHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// The confirmation capsule for a user action: a glyph and a short label,
/// glassy on black so it reads over any module, never blocking clicks.
private struct NotchToastView: View {
    let toast: NotchState.NotchToast

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: toast.symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(NotchTheme.battery)
            Text(toast.message)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(NotchTheme.inkPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 7)
        .background {
            Capsule()
                .fill(.black.opacity(0.88))
                .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 1))
        }
        .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(toast.message)
    }
}
