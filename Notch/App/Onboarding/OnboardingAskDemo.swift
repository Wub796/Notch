import SwiftUI

/// A tiny meter: sampled bands, gliding between samples.
///
/// Shared by the welcome demo and the Screen & Audio ask, because the two are
/// showing the same thing — the visualizer the permission pays for. Sampling
/// rather than animating a loop is what makes it read as audio: the bands are
/// computed from the clock, so they cannot drift out of step, and the linear run
/// between samples (`NotchAnimations.clockStep`) is what stops the motion from
/// stepping.
struct OnboardingMeter: View {
    var bars = 3
    var width: CGFloat = 1.5
    var range: ClosedRange<CGFloat> = 3 ... 8
    /// The bars' colour. The closed notch's real meter is tinted with the cover
    /// it is playing (`MusicVisualizerView`), so the welcome screen's pill — a
    /// picture of that pill — passes the cover's own colour. The ask strips keep
    /// the untinted white.
    var tint: Color = .white
    /// When false the bands hold a still frame: the demo's transport is paused,
    /// or Reduce Motion is on.
    var isActive = true

    private var moves: Bool { isActive && !OnboardingMotion.prefersReducedMotion }

    var body: some View {
        // `.animation` rather than `.periodic`: it is the schedule that can be
        // paused, and a still meter should not be sampled at all. The interval
        // is the same meterStep, so the bands land on the same beat.
        TimelineView(.animation(minimumInterval: OnboardingMotion.meterStep, paused: !moves)) { context in
            let phase = moves ? context.date.timeIntervalSinceReferenceDate : 0
            HStack(alignment: .center, spacing: 1.5) {
                ForEach(0 ..< bars, id: \.self) { index in
                    // A little frequency spread per band: identical bands read
                    // as a loading indicator, three that disagree a bit read as
                    // audio.
                    let rate = 2.1 + Double(index) * 0.45
                    let wave = 0.5 + 0.5 * sin(phase * rate + Double(index) * 1.15)
                    Capsule()
                        .fill(tint.opacity(0.75 - Double(index) * 0.08))
                        .frame(width: width, height: bandHeight(wave))
                        .animation(NotchAnimations.clockStep(OnboardingMotion.meterStep), value: wave)
                }
            }
            .frame(height: range.upperBound)
        }
        .accessibilityHidden(true)
    }

    private func bandHeight(_ wave: Double) -> CGFloat {
        let settled = moves ? wave : 0.5
        return range.lowerBound + (range.upperBound - range.lowerBound) * CGFloat(settled)
    }
}

/// What the permission pays for, shown rather than described.
///
/// Each ask says what it buys and what happens without it; this is the third
/// thing a person wants before answering a privacy question — seeing it. The
/// strips are illustrations, not live data, and they are deliberately quiet:
/// small type, no colour of their own, nothing that could be mistaken for a
/// notification or a real measurement. They are hidden from VoiceOver for the
/// same reason, since the two lines of copy above them already say everything
/// they show.
struct OnboardingAskDemo: View {
    let integration: IntegrationPermissions.Integration
    /// Granted on this screen: the strip answers, because the strip is the thing
    /// that was just switched on. A light crosses it once and its border picks
    /// up the permission's own tint — the verdict above it says what happened,
    /// and this says what it happened *to*.
    var isLive = false
    /// The ask's own arrival, so the strip's pieces can follow the strip in
    /// rather than arriving welded to it.
    var appeared = true

    /// When the strip's pieces start, in seconds after the screen arrives.
    /// The strip is the ask's fifth part (`OnboardingReveal`), so it starts
    /// around 0.23; its pieces begin just after that and are still landing as
    /// it settles, which is what makes the strip develop rather than appear.
    private static let pieceBase: Double = 0.24

    var body: some View {
        HStack(spacing: 10) {
            content
        }
        .padding(.horizontal, 12)
        .frame(height: 54)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(isLive ? integration.tint.opacity(0.055) : Color.white.opacity(0.04))
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(
                            isLive ? integration.tint.opacity(0.22) : Color.white.opacity(0.06),
                            lineWidth: 1
                        )
                }
        }
        .overlay { OnboardingSheen(isActive: isLive, cornerRadius: 11) }
        .animation(OnboardingMotion.confirmation, value: isLive)
        .accessibilityHidden(true)
    }

    /// One piece of the strip, arriving in its turn: a few points of travel and
    /// the same fade the rest of the screen uses, so the strip is made of the
    /// flow's vocabulary rather than its own.
    private func staged<V: View>(_ index: Int, @ViewBuilder _ piece: () -> V) -> some View {
        piece()
            .onboardingReveal(
                index,
                appeared: appeared,
                travel: 5,
                extraDelay: Self.pieceBase + Double(index) * 0.06
            )
    }

    @ViewBuilder
    private var content: some View {
        switch integration {
        case .accessibility:
            staged(0) { glyph("speaker.wave.2.fill") }
            staged(1) { volumeHUD }
            staged(2) { caption("Hardware keys, straight to the notch") }

        case .screenCapture:
            staged(0) { glyph("waveform") }
            staged(1) { OnboardingMeter(bars: 3, width: 4, range: 7 ... 24) }
            staged(2) { caption("Audio only, read in memory") }

        case .filesAndFolders:
            staged(0) { glyph("doc.fill") }
            staged(1) {
                Text("Screenshot 19.33.12.png")
                    .font(.system(size: 11))
                    .foregroundStyle(NotchTheme.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            staged(2) { badge("Just landed", tint: integration.tint) }

        case .music:
            staged(0) { artwork }
            staged(1) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Sunset Drive")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(NotchTheme.inkSecondary)
                    playhead
                }
            }
            Spacer(minLength: 0)
            staged(2) { caption("3:47") }

        case .location:
            staged(0) { glyph("sun.max.fill") }
            staged(1) {
                Text("18° · Partly cloudy")
                    .font(.system(size: 11))
                    .foregroundStyle(NotchTheme.inkSecondary)
            }
            Spacer(minLength: 0)
            staged(2) { caption("Today, at the notch") }

        case .calendar:
            staged(0) { glyph("calendar") }
            staged(1) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Design review")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(NotchTheme.inkSecondary)
                    Text("14:30 · 30 min")
                        .font(.system(size: 9.5))
                        .foregroundStyle(NotchTheme.inkMuted)
                }
            }
            Spacer(minLength: 0)
            staged(2) { badge("Join", tint: integration.tint) }

        case .camera:
            staged(0) { viewfinder }
            staged(1) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Camera screen")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(NotchTheme.inkSecondary)
                    Text("Opens only while you look at it")
                        .font(.system(size: 9.5))
                        .foregroundStyle(NotchTheme.inkMuted)
                }
            }
            Spacer(minLength: 0)

        case .bluetooth:
            staged(0) { glyph("airpods") }
            staged(1) {
                Text("AirPods Pro")
                    .font(.system(size: 11))
                    .foregroundStyle(NotchTheme.inkSecondary)
            }
            Spacer(minLength: 0)
            staged(2) { battery("82%") }

        case .notifications:
            staged(0) { glyph("timer") }
            staged(1) {
                Text("Timer finished")
                    .font(.system(size: 11))
                    .foregroundStyle(NotchTheme.inkSecondary)
            }
            Spacer(minLength: 0)
            staged(2) { badge("5:00", tint: integration.tint) }
        }
    }

    // MARK: - Pieces

    private func glyph(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 12))
            .foregroundStyle(NotchTheme.inkMuted)
            .frame(width: 18)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9.5))
            .foregroundStyle(NotchTheme.inkMuted)
            .lineLimit(1)
    }

    private func badge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.15)))
    }

    private func battery(_ percent: String) -> some View {
        HStack(spacing: 5) {
            Text(percent)
                .font(.system(size: 9.5))
                .monospacedDigit()
                .foregroundStyle(NotchTheme.inkMuted)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                    .frame(width: 22, height: 10)
                RoundedRectangle(cornerRadius: 1.4, style: .continuous)
                    .fill(integration.tint.opacity(0.75))
                    .frame(width: 16, height: 5)
                    .padding(.leading, 3)
            }
        }
    }

    /// The volume HUD the media keys raise, at HUD size: a speaker, and a bar of
    /// segments rather than a continuous fill, because that is what macOS draws.
    private var volumeHUD: some View {
        HStack(spacing: 2) {
            ForEach(0 ..< 16, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(index < 11 ? Color.white.opacity(0.7) : Color.white.opacity(0.14))
                    .frame(width: 2.5, height: index < 11 ? 11 : 7)
            }
        }
        .frame(height: 12)
        .animation(NotchAnimations.content, value: integration)
    }

    private var artwork: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 244 / 255, green: 114 / 255, blue: 88 / 255),
                        Color(red: 126 / 255, green: 74 / 255, blue: 200 / 255),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 32, height: 32)
    }

    /// A playhead that keeps moving, so the strip is alive without pretending to
    /// know what is playing: it is driven by the clock, not by a track.
    private var playhead: some View {
        TimelineView(.animation(minimumInterval: 0.5, paused: OnboardingMotion.prefersReducedMotion)) { context in
            let phase = OnboardingMotion.prefersReducedMotion
                ? 0.42
                : (context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 6)) / 6
            Capsule()
                .fill(Color.white.opacity(0.12))
                .frame(width: 84, height: 2.5)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.7))
                        .frame(width: max(2, 84 * (0.18 + 0.72 * phase)))
                        .animation(NotchAnimations.clockStep(0.5), value: phase)
                }
        }
        .accessibilityHidden(true)
    }

    /// A viewfinder whose scan line passes over it: the Face ID sweep, at the
    /// size of a sentence.
    ///
    /// Sampled at 4Hz and glided between samples rather than holding one long
    /// animation open: the line is two points tall, so nobody can see the
    /// difference, and the difference is a continuous redraw.
    private var viewfinder: some View {
        TimelineView(.animation(minimumInterval: 0.25, paused: OnboardingMotion.prefersReducedMotion)) { context in
            let sweep = OnboardingMotion.prefersReducedMotion
                ? 0.5
                : (context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.4)) / 2.4
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.black.opacity(0.45))
                .frame(width: 44, height: 30)
                .overlay {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.clear, integration.tint.opacity(0.75), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 44, height: 2)
                        .offset(y: -12 + 24 * sweep)
                        .animation(NotchAnimations.clockStep(0.25), value: sweep)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .accessibilityHidden(true)
    }
}
