import AppKit
import SwiftUI

/// The building blocks the app's own settings panes are written against.
///
/// These are the same shapes Glance's pages use — `SettingsCard` is its
/// "section title + `SettingsGroup`" pair, `SettingsRow` is its
/// `SettingsRowContent`, `SettingsSliderRow` is its `SettingsSlider` — but
/// spelled with the parameter names this app's panes already pass, so all
/// eight of them picked up the new window's look without being rewritten.
/// Home of the tokens is `SettingsMetrics`.
///
/// One deliberate difference from Glance's rows: this app's rows carry a
/// leading icon and a tint, and those are kept (minus the coloured tile the
/// old design drew behind them) because they are content — which row is which
/// — rather than chrome.

/// A titled section: Glance's `SettingsSectionTitle` above a `SettingsGroup`.
/// Rows inside are separated by the hairlines each row draws itself.
struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionTitle(text: title)
            SettingsGroup {
                content()
            }
        }
    }
}

/// A row: optional icon, a title with optional subtitle, and a trailing
/// control. `divider` draws the hairline beneath, which the last row omits.
struct SettingsRow<Trailing: View>: View {
    var systemImage: String?
    var tint: Color = .secondary
    let title: String
    var subtitle: String?
    var showsDivider: Bool = true
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(tint)
                        // Fixed box so rows with and without an icon line up.
                        .frame(width: 18)
                }

                SettingsRowContent(title: title, subtitle: subtitle, trailing: trailing)
            }

            if showsDivider {
                SettingsGroupDivider()
                    .padding(.leading, systemImage == nil ? 0 : 28)
            }
        }
    }
}

/// A slider row with the value shown at the trailing edge, as in Glance's
/// `SettingsSlider`.
struct SettingsSliderRow: View {
    var systemImage: String?
    var tint: Color = .secondary
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String
    var showsDivider: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(tint)
                            .frame(width: 18)
                    }
                    Text(title)
                        .font(SettingsMetrics.rowFont)
                        .foregroundStyle(SettingsMetrics.textPrimary)
                    Spacer(minLength: 8)
                    Text(format(value))
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(SettingsMetrics.textSecondary)
                }

                Slider(value: $value, in: range, step: step)
                    .tint(SettingsMetrics.accent)
                    .padding(.leading, systemImage == nil ? 0 : 28)
            }
            .padding(.horizontal, SettingsMetrics.rowHorizontalInset)
            .padding(.vertical, 10)

            if showsDivider {
                SettingsGroupDivider()
                    .padding(.leading, systemImage == nil ? 0 : 28)
            }
        }
    }
}

/// A settings row whose control is a row of small selectable chips, laid out
/// beneath the title instead of in the trailing column.
///
/// `SettingsRow` puts its control on the title's line, which only works for
/// something that fits there. A set of options — the calendar reminders, where
/// each lead time is a yes/no of its own — needs the row's full width.
struct SettingsChipRow<Chip: View>: View {
    var systemImage: String?
    var tint: Color = .secondary
    let title: String
    var subtitle: String?
    var showsDivider: Bool = true
    @ViewBuilder var chips: () -> Chip

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(tint)
                            .frame(width: 18)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(SettingsMetrics.rowFont)
                            .foregroundStyle(SettingsMetrics.textPrimary)
                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: 11))
                                .foregroundStyle(SettingsMetrics.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Spacer(minLength: 8)
                }

                chips()
                    .padding(.leading, systemImage == nil ? 0 : 28)
            }
            .padding(.horizontal, SettingsMetrics.rowHorizontalInset)
            .padding(.vertical, 10)

            if showsDivider {
                SettingsGroupDivider()
                    .padding(.leading, systemImage == nil ? 0 : 28)
            }
        }
    }
}

/// A tinted explanatory box. Glance has no equivalent component — its pages
/// put explanation in row subtitles and captions — so this keeps its shape but
/// takes the ported window's radii and text ramp.
struct SettingsCallout: View {
    let text: String
    var systemImage: String = "questionmark.circle.fill"
    var tint: Color = .blue

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 14))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(SettingsMetrics.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: SettingsMetrics.rowRadius - 4, style: .continuous)
                .fill(tint.opacity(0.14))
        }
    }
}

/// A pane's content, in the new window's vocabulary.
///
/// The window owns the scrolling and the insets now — its page sits in one
/// `ScrollView` beneath a floating header and above the tab bar, exactly as in
/// Glance — so a pane is just its rows, spaced like the rows of a Glance page.
struct SettingsPane<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.rowSpacing) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
