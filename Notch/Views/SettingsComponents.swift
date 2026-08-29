import AppKit
import SwiftUI

/// The building blocks of the Settings panes, styled after the Sapphire
/// reference: grouped cards with a small-caps title, rows separated by
/// hairlines, a coloured rounded-square icon tile leading each row, and the
/// control trailing.
///
/// These replace `Form`/`Section`, which renders as a stock macOS inspector —
/// correct, but nothing like the reference's cards.

/// A titled card. Rows inside are separated automatically.
struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content()
            }
            .padding(.vertical, 4)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.quaternary.opacity(0.45))
            }
        }
    }
}

/// A row: optional icon tile, a title with optional subtitle, and a trailing
/// control. `divider` draws the hairline beneath, which the last row omits.
struct SettingsRow<Trailing: View>: View {
    var systemImage: String?
    var tint: Color = .gray
    let title: String
    var subtitle: String?
    var showsDivider: Bool = true
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 28, height: 28)
                        .background {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(tint.opacity(0.18))
                        }
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 12)

                trailing()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if showsDivider {
                Divider()
                    .padding(.leading, systemImage == nil ? 14 : 54)
            }
        }
    }
}

/// A slider row with the value shown at the trailing edge, as in the
/// reference's Hover Delay control.
struct SettingsSliderRow: View {
    var systemImage: String?
    var tint: Color = .gray
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String
    var showsDivider: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(tint)
                            .frame(width: 28, height: 28)
                            .background {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(tint.opacity(0.18))
                            }
                    }
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                    Spacer(minLength: 12)
                    Text(format(value))
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Slider(value: $value, in: range, step: step)
                    .padding(.leading, systemImage == nil ? 0 : 40)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if showsDivider {
                Divider().padding(.leading, systemImage == nil ? 14 : 54)
            }
        }
    }
}

/// The reference's tinted explanatory box.
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
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.14))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(tint.opacity(0.3), lineWidth: 1)
        }
    }
}

/// Scrolling container that gives every pane the same margins.
struct SettingsPane<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 20) {
                content()
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
