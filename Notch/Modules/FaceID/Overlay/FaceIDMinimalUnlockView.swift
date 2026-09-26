import SwiftUI

/// The `.minimal` unlock style: the silhouette widens rather than expanding into
/// the full square panel.
///
/// Layout is `[ lock ][ gap ][ video ]`. In notch style the gap is the physical
/// cutout, where nothing may be drawn; in pill style it is just negative space.
///
/// Ported from Glance (`NotchOverlay/MinimalUnlockView.swift`, MIT © Jonathan
/// Zhou). The breathing pulse is applied to the video alone and never to the lock
/// glyph: a pulsing padlock reads as a *failing* unlock, which is precisely the
/// wrong thing to say while the scan is still running.
struct FaceIDMinimalUnlockView: View {
    let media: FaceIDScanMedia
    /// Owned by the caller rather than derived from `media`, so the glyph and the
    /// video can be offset from each other.
    let isUnlocked: Bool
    /// Inset from the silhouette's left and right edges. The caller adds the
    /// notch's flare allowance into this where it applies.
    let edgeInset: CGFloat
    var lockIconSize: CGFloat = FaceIDGeometry.minimalLockIconSize
    var mediaWidth: CGFloat = FaceIDGeometry.minimalMediaWidth
    var mediaVerticalInset: CGFloat = FaceIDGeometry.minimalMediaVerticalInset
    /// Applied to the video only; identity by default, so most callers ignore it.
    var pulseScale: CGFloat = 1
    var pulseOpacity: Double = 1

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: isUnlocked ? "lock.open.fill" : "lock.fill")
                .font(.system(size: lockIconSize, weight: .semibold))
                .foregroundStyle(NotchTheme.inkPrimary)
                // The explicit animation is required: the phase change that flips
                // `isUnlocked` is not itself inside an animation transaction.
                // `.replace` only: the magic-move variant of the symbol transition
                // needs macOS 15, and the app targets macOS 14.
                .contentTransition(.symbolEffect(.replace))
                .animation(
                    .smooth(duration: FaceIDGeometry.minimalLockAnimationDuration),
                    value: isUnlocked
                )
                .frame(width: mediaWidth)

            Spacer(minLength: 0)

            FaceIDScanAnimationView(media: media)
                .padding(.vertical, mediaVerticalInset)
                .frame(width: mediaWidth)
                .scaleEffect(pulseScale)
                .opacity(pulseOpacity)
                .padding(.trailing, 4)
        }
        .padding(.horizontal, edgeInset)
    }
}
