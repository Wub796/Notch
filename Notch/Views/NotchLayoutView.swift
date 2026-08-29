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

    /// The open module swaps in with a slight scale from the top, so it reads
    /// as unfolding out of the notch. Verbatim from the references.
    private static let moduleTransition = AnyTransition
        .scale(scale: 0.8, anchor: .top)
        .combined(with: .opacity)
        .animation(.smooth(duration: 0.35))

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            headerStrip

            if state.mode == .expanded {
                moduleContent
                    .frame(
                        width: state.moduleContentSize.width,
                        height: state.moduleContentSize.height,
                        alignment: .center
                    )
                    .transition(Self.moduleTransition)
                    .allowsHitTesting(true)
                    .zIndex(1)
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
                .zIndex(2)
        } else {
            CollapsedNotchView(state: state, isHovering: isHovering)
                .frame(width: state.collapsedSize.width, height: state.collapsedSize.height)
                // Hovering the closed pill widens it slightly, the way both
                // references pad their wings out on hover. The amount is the
                // user's "hover grow" preference.
                .padding(.horizontal, isHovering ? state.hoverExpansion : 0)
                .zIndex(2)
        }
    }

    // MARK: - Module

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

    @ViewBuilder
    private var tabContent: some View {
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
            ShelfView(shelf: state.shelf)
        case .clipboard:
            ClipboardView(clipboard: state.clipboard)
        case .tools:
            ToolsView(state: state)
        case .notes:
            NotesView(notes: state.notes)
        case .telemetry:
            TelemetryView(telemetry: state.telemetry)
        }
    }
}
