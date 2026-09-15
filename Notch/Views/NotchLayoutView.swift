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

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(alignment: .center, spacing: 6) {
                headerStrip

                if state.mode == .expanded {
                    sizedModule
                        .transition(NotchAnimations.panelContent)
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
                .transition(NotchAnimations.panelContent)
                .zIndex(2)
        } else {
            CollapsedNotchView(state: state, isHovering: isHovering)
                .frame(width: state.collapsedSize.width, height: state.collapsedSize.height)
                // Hovering the closed pill widens it slightly, the way both
                // references pad their wings out on hover. The amount is the
                // user's "hover grow" preference, clamped in `hoverExpansion`
                // itself — a `min(…, 5)` here used to cap it below the 6pt
                // default, so every setting above 1.083x behaved identically
                // and the slider looked broken.
                .padding(.horizontal, isHovering ? state.hoverExpansion : 0)
                .transition(NotchAnimations.closedStrip)
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
    private var sizedModule: some View {
        // One structure for both kinds of tab. This was an if/else on
        // `fitsHeight`, so a switch between a fitted and a fixed tab replaced
        // the whole module with a different view — a plain crossfade running
        // around the screen transition instead of through it.
        let fits = NotchSizing.fitsHeight(for: state.tab)
        return moduleContent
            .frame(
                width: state.moduleContentSize.width,
                height: fits ? nil : state.moduleContentSize.height,
                alignment: .center
            )
            .fixedSize(horizontal: false, vertical: fits)
            .onPreferenceChange(ModuleNaturalHeightKey.self) { heights in
                // Deferred off the layout pass: recording a height while
                // SwiftUI is mid-update can be dropped, which silently leaves
                // the slab on its full budget.
                DispatchQueue.main.async {
                    for (tab, height) in heights where NotchSizing.fitsHeight(for: tab) {
                        state.updateMeasuredModuleHeight(height, for: tab)
                    }
                }
            }
    }

    @ViewBuilder
    private var moduleContent: some View {
        // The shelf draws its own drop targets, so it stays in place while
        // something is dragged over it instead of being swapped for this one.
        if state.tab != .shelf, state.isDropTargeted || state.shelf.isResolvingDrop {
            DropZoneView(
                isResolving: state.shelf.isResolvingDrop,
                instantAirDrop: state.settings.instantAirDrop
            )
        } else {
            tabContent
        }
    }

    /// The screen itself. Keyed on the tab so switching screens is a sequenced
    /// substitution (see `NotchAnimations.screenSwap`) rather than a hard
    /// replacement, and measured under its own tab so the outgoing screen's
    /// height is never filed under the incoming one.
    private var tabContent: some View {
        MeasuredScreen(tab: state.tab) {
            tabScreen
        }
        .id(state.tab)
        .transition(NotchAnimations.screenSwap)
        .animation(NotchAnimations.content, value: state.tab)
    }

    @ViewBuilder
    private var tabScreen: some View {
        switch state.tab {
        case .home:
            HomeDashboardView(state: state, namespace: namespace)
        case .audio:
            DevicesScreenView(state: state, namespace: namespace)
        case .weather:
            WeatherDetailView(state: state)
        case .calendar:
            CalendarDetailView(state: state)
        case .shelf:
            ShelfView(state: state)
        case .tools:
            ToolsView(state: state)
        case .notes:
            NotesView(state: state)
        case .telemetry:
            TelemetryView(telemetry: state.telemetry)
        case .camera:
            CameraView(state: state)
        }
    }
}

/// Carries each screen's natural height out of the size pass, keyed by the tab
/// that measured it. Keyed, because during a switch the outgoing and incoming
/// screens are both laid out: a single number read off their container was the
/// taller of the two, filed under the new tab — so its slab opened to the
/// wrong height and then corrected itself in a second, separate animation.
private struct ModuleNaturalHeightKey: PreferenceKey {
    static let defaultValue: [NotchTab: CGFloat] = [:]

    static func reduce(value: inout [NotchTab: CGFloat], nextValue: () -> [NotchTab: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// A screen that reports its own natural height, under its own tab.
private struct MeasuredScreen<Content: View>: View {
    let tab: NotchTab
    let content: Content

    init(tab: NotchTab, @ViewBuilder content: () -> Content) {
        self.tab = tab
        self.content = content()
    }

    var body: some View {
        content.background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ModuleNaturalHeightKey.self,
                    value: [tab: proxy.size.height]
                )
            }
        }
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
            // Opaque and lifted off the black by tone alone — no outline.
            Capsule()
                .fill(Color(white: 0.16))
        }
        .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(toast.message)
    }
}
