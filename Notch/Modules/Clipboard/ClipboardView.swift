import SwiftUI

/// Clipboard history: a horizontal tray of recent copies. Click to copy back,
/// pin to keep across relaunches.
struct ClipboardView: View {
    let clipboard: ClipboardManager

    var body: some View {
        VStack(alignment: .leading, spacing: NotchTheme.Space.m) {
            ScreenHeader("Clipboard", subtitle: subtitle) {
                if !clipboard.entries.isEmpty {
                    ScreenTextButton(title: "Clear Unpinned", systemImage: "trash") {
                        withAnimation(NotchAnimations.content) {
                            clipboard.clearUnpinned()
                        }
                    }
                }
            }

            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(NotchAnimations.content, value: clipboard.entries)
    }

    private var subtitle: String {
        guard NotchSettings.shared.clipboardHistoryEnabled else { return "History is off" }
        let count = clipboard.entries.count
        guard count > 0 else { return "Nothing copied yet" }
        let pinned = clipboard.entries.filter(\.isPinned).count
        let items = "\(count) item\(count == 1 ? "" : "s")"
        return pinned > 0 ? items + " · \(pinned) pinned" : items
    }

    @ViewBuilder
    private var content: some View {
        if !NotchSettings.shared.clipboardHistoryEnabled {
            ScreenEmptyState(
                symbol: "clipboard",
                title: "Clipboard history is off",
                caption: "Turn it on in Settings → Activities"
            )
        } else if clipboard.entries.isEmpty {
            ScreenEmptyState(
                symbol: "doc.on.clipboard",
                title: "Nothing copied yet",
                caption: "Copies you make will collect here"
            )
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: NotchTheme.Space.m) {
                    ForEach(clipboard.entries) { entry in
                        ClipboardCard(entry: entry, clipboard: clipboard)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 3)
            }
        }
    }
}

private struct ClipboardCard: View {
    let entry: ClipboardManager.Entry
    let clipboard: ClipboardManager

    @State private var hovering = false
    @State private var justCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: NotchTheme.Space.xs) {
            HStack(spacing: 5) {
                if entry.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.orange)
                }

                Text(entry.copiedAt, style: .relative)
                    .font(.notchFootnote)
                    .foregroundStyle(NotchTheme.inkMuted)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Image(systemName: justCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(justCopied ? NotchTheme.battery : NotchTheme.inkMuted)
                    .opacity(justCopied || hovering ? 1 : 0)
            }

            Text(entry.text.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.notchCaption)
                .foregroundStyle(NotchTheme.inkPrimary)
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(11)
        .frame(width: 152, height: 96, alignment: .topLeading)
        .notchCard(radius: NotchTheme.Radius.tile, isHighlighted: entry.isPinned, tint: .orange)
        .overlay {
            if hovering, !entry.isPinned {
                RoundedRectangle(cornerRadius: NotchTheme.Radius.tile, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1)
            }
        }
        .onHover { isHovering in
            withAnimation(NotchAnimations.content) { hovering = isHovering }
        }
        .onTapGesture {
            clipboard.copyBack(entry)
            withAnimation(NotchAnimations.content) { justCopied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(NotchAnimations.content) { justCopied = false }
            }
        }
        .contextMenu {
            Button("Copy") { clipboard.copyBack(entry) }
            Button(entry.isPinned ? "Unpin" : "Pin") { clipboard.togglePin(entry) }
            Divider()
            Button("Remove") {
                withAnimation(NotchAnimations.content) { clipboard.remove(entry) }
            }
        }
        .help(entry.text)
        .accessibilityLabel("Clipboard item")
        .accessibilityValue(entry.text)
        .accessibilityHint("Click to copy back")
    }
}
