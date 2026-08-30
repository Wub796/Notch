import SwiftUI

/// Clipboard history: a horizontal tray of recent copies. Click to copy back,
/// pin to keep across relaunches.
struct ClipboardView: View {
    let clipboard: ClipboardManager
    let state: NotchState

    init(state: NotchState) {
        self.state = state
        clipboard = state.clipboard
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NotchTheme.Space.m) {
            ScreenHeader("Clipboard", subtitle: subtitle) {
                if !clipboard.entries.isEmpty {
                    ScreenTextButton(title: "Clear Unpinned", systemImage: "trash") {
                        withAnimation(NotchAnimations.content) {
                            clipboard.clearUnpinned()
                        }
                        state.showToast("Cleared unpinned items", symbol: "trash")
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
                        ClipboardCard(entry: entry, clipboard: clipboard, state: state)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 3)
            }
                .notchScrollFadeHorizontal(10)
        }
    }
}

private struct ClipboardCard: View {
    let entry: ClipboardManager.Entry
    let clipboard: ClipboardManager
    let state: NotchState

    @State private var hovering = false

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

                Image(systemName: "doc.on.doc")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(NotchTheme.inkMuted)
                    .opacity(hovering ? 1 : 0)
            }

            Text(entry.text.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.notchCaption)
                .foregroundStyle(NotchTheme.inkPrimary)
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(12)
        .frame(width: 168, height: 104, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: NotchTheme.Radius.tile, style: .continuous)
                .fill(entry.isPinned ? Color.orange.opacity(0.14) : (hovering ? Color.white.opacity(0.08) : Color.white.opacity(0.04)))
        }
        .onHover { isHovering in
            withAnimation(NotchAnimations.content) { hovering = isHovering }
        }
        .onTapGesture {
            clipboard.copyBack(entry)
            state.showToast("Copied", symbol: "doc.on.doc")
        }
        .contextMenu {
            Button("Copy") {
                clipboard.copyBack(entry)
                state.showToast("Copied", symbol: "doc.on.doc")
            }
            Button(entry.isPinned ? "Unpin" : "Pin") {
                clipboard.togglePin(entry)
                state.showToast(entry.isPinned ? "Unpinned" : "Pinned", symbol: "pin")
            }
            Divider()
            Button("Remove") {
                withAnimation(NotchAnimations.content) { clipboard.remove(entry) }
                state.showToast("Removed from clipboard", symbol: "trash")
            }
        }
        .help(entry.text)
        .accessibilityLabel("Clipboard item")
        .accessibilityValue(entry.text)
        .accessibilityHint("Click to copy back")
    }
}
