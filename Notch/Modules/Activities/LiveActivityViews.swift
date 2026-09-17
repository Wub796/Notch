import AppKit
import SwiftUI

/// What is left of the wing-based live activities.
///
/// Every activity that carries a reading now drops a bar beneath the notch
/// instead — see `CollapsedNotchView.dropped` — because content split across
/// the wings is cut in half by the camera housing. Only the desktop-change
/// flash, which is a glyph and nothing else, still suits a wing.









/// A Space switch showing the desktop number on the right.
struct DesktopChangeActivityView: View {
    let index: Int
    let notchWidth: CGFloat

    var body: some View {
        ActivityWingLayout(
            notchWidth: notchWidth,
            leading: Image(systemName: "macwindow.on.rectangle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NotchTheme.inkSecondary),
            trailing: Text("\(index)")
                .font(.system(size: 11.5, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(NotchTheme.inkPrimary)
                .contentTransition(.numericText())
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Desktop \(index)")
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

    /// How far each wing's content sits from the frame edge. Every wing keeps
    /// the standard inset; the one exception is the closed cover, which is a
    /// filled tile nested in the notch's own corner rather than a glyph paying
    /// for clearance from it, and so sits nearer the edge (see
    /// `NotchSizing.closedArtworkInset`).
    var leadingInset: CGFloat = NotchSizing.closedWingInset
    var trailingInset: CGFloat = NotchSizing.closedWingInset

    init(
        notchWidth: CGFloat,
        leading: Leading,
        leadingInset: CGFloat = NotchSizing.closedWingInset,
        trailing: Trailing,
        trailingInset: CGFloat = NotchSizing.closedWingInset
    ) {
        self.notchWidth = notchWidth
        self.leading = leading
        self.trailing = trailing
        self.leadingInset = leadingInset
        self.trailingInset = trailingInset
    }

    var body: some View {
        HStack(spacing: 0) {
            leading
                .padding(.leading, leadingInset)
                .frame(maxWidth: .infinity, alignment: .leading)
            // The real cutout rather than the bleed-widened `notchWidth`: the
            // bleed is black drawn past the camera housing, so it belongs to
            // the visible wing and content may sit over it.
            Color.clear
                .frame(width: max(notchWidth - NotchSizing.notchCoverageBleed, 0))
            trailing
                .padding(.trailing, trailingInset)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
