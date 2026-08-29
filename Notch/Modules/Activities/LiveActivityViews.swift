import AppKit
import SwiftUI

/// What is left of the wing-based live activities.
///
/// Every activity that carries a reading now drops a bar beneath the notch
/// instead — see `CollapsedNotchView.dropped` — because content split across
/// the wings is cut in half by the camera housing. Only the desktop-change
/// flash, which is a glyph and nothing else, still suits a wing.









/// A Space switch.
struct DesktopChangeActivityView: View {
    let notchWidth: CGFloat

    var body: some View {
        ActivityWingLayout(
            notchWidth: notchWidth,
            leading: Image(systemName: "macwindow.on.rectangle")
                .font(.system(size: 12))
                .foregroundStyle(NotchTheme.inkSecondary),
            trailing: Text("Desktop")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(NotchTheme.inkPrimary)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Switched desktop")
    }
}


/// Shared wing layout: leading glyph, an exact reserved dead zone for the
/// hardware notch (content under the camera housing is invisible), trailing
/// readout. Both wings are equal flexible widths so the dead zone stays
/// centered whatever each side contains.
struct ActivityWingLayout<Leading: View, Trailing: View>: View {
    let notchWidth: CGFloat
    let leading: Leading
    let trailing: Trailing

    init(notchWidth: CGFloat, leading: Leading, trailing: Trailing) {
        self.notchWidth = notchWidth
        self.leading = leading
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 0) {
            leading
                .padding(.leading, 13)
                .frame(maxWidth: .infinity, alignment: .leading)
            Color.clear
                .frame(width: notchWidth)
            trailing
                .padding(.trailing, 14)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
