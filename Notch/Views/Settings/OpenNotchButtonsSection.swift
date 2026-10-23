import SwiftUI

/// The open notch's rail, arranged by dragging.
///
/// A `List` with `.onMove` was the alternative and is the wrong shape here: it
/// needs an edit mode and its own row chrome, on a page made of plain rows.
/// Two rows that accept a drop are the same gesture with none of that — the
/// dragged button is picked up by its own row, and dropped where it belongs.
///
/// Additions go underneath, out of the rail's own list, so the list reads as
/// exactly what is on the notch and nothing else.
struct OpenNotchButtonsSection: View {
    @Bindable var settings = NotchSettings.shared

    /// The buttons not on the rail, in their shipped order.
    private var available: [NotchRailItem] {
        NotchRailItem.allCases.filter { !settings.topBarModules.contains($0) }
    }

    var body: some View {
        SettingsCard(title: "Open Notch Buttons") {
            ForEach(settings.topBarModules) { item in
                SettingsRow(
                    systemImage: item.symbol,
                    title: item.title
                ) {
                    HStack(spacing: 8) {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(SettingsMetrics.textTertiary)
                            .accessibilityHidden(true)

                        Button {
                            remove(item)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(SettingsMetrics.textTertiary)
                        }
                        .buttonStyle(.borderless)
                        .disabled(settings.topBarModules.count <= 1)
                        .help("Remove \(item.title)")
                        .accessibilityLabel("Remove \(item.title) from the notch")
                    }
                }
                .draggable(item.rawValue)
                .dropDestination(for: String.self) { values, _ in
                    guard let raw = values.first,
                          let dragged = NotchRailItem(rawValue: raw)
                    else { return false }
                    move(dragged, before: item)
                    return true
                }
                .accessibilityLabel("\(item.title), draggable")
                .accessibilityHint("Drag to change its place on the notch")
            }

            if !available.isEmpty {
                SettingsRow(
                    systemImage: "plus.circle",
                    title: "Add",
                    showsDivider: false
                ) {
                    HStack(spacing: 6) {
                        ForEach(available) { item in
                            Button {
                                add(item)
                            } label: {
                                Image(systemName: item.symbol)
                                    .font(.system(size: 12, weight: .medium))
                                    .frame(width: 24, height: 18)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                            .help("Add \(item.title)")
                            .accessibilityLabel("Add \(item.title) to the notch")
                        }
                    }
                }
            }
        }

        SettingsCaption(
            text: "Drag a button to change its place on the rail. Home always comes first, "
                + "and at least one module stays on it."
        )
    }

    /// Puts `item` directly before `target`, which is what dropping onto a row
    /// means. The index is taken after the removal, so a button dragged to the
    /// right of where it started does not land one row short.
    private func move(_ item: NotchRailItem, before target: NotchRailItem) {
        guard item != target else { return }
        var items = settings.topBarModules
        guard let from = items.firstIndex(of: item) else { return }
        items.remove(at: from)
        guard let to = items.firstIndex(of: target) else { return }
        items.insert(item, at: to)
        withAnimation(NotchAnimations.content) { settings.topBarModules = items }
    }

    private func add(_ item: NotchRailItem) {
        withAnimation(NotchAnimations.content) {
            settings.topBarModules.append(item)
        }
    }

    /// Never the last one: a rail with nothing on it would put every screen but
    /// Home out of reach from the panel.
    private func remove(_ item: NotchRailItem) {
        guard settings.topBarModules.count > 1 else { return }
        withAnimation(NotchAnimations.content) {
            settings.topBarModules.removeAll { $0 == item }
        }
    }
}
