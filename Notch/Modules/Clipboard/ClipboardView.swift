import SwiftUI

/// Clipboard history: a horizontal tray of recent copies. Click to copy back,
/// pin to keep across relaunches.
struct ClipboardView: View {
    let clipboard: ClipboardManager

    var body: some View {
        if !NotchSettings.shared.clipboardHistoryEnabled {
            emptyState(
                icon: "clipboard",
                title: "Clipboard history is off",
                caption: "Turn it on in Settings → Activities"
            )
        } else if clipboard.entries.isEmpty {
            emptyState(
                icon: "doc.on.clipboard",
                title: "Nothing copied yet",
                caption: "Copies you make will collect here"
            )
        } else {
            VStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 9) {
                        ForEach(clipboard.entries) { entry in
                            ClipboardCard(entry: entry, clipboard: clipboard)
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 3)
                }

                HStack {
                    Text("\(clipboard.entries.count) item\(clipboard.entries.count == 1 ? "" : "s")")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(NotchTheme.inkMuted)
                    Spacer()
                    Button("Clear unpinned") {
                        withAnimation(NotchAnimations.content) {
                            clipboard.clearUnpinned()
                        }
                    }
                    .buttonStyle(PressableButtonStyle())
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(NotchTheme.inkSecondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(NotchAnimations.content, value: clipboard.entries)
        }
    }

    private func emptyState(icon: String, title: String, caption: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(NotchTheme.inkMuted)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NotchTheme.inkSecondary)
            Text(caption)
                .font(.system(size: 10.5))
                .foregroundStyle(NotchTheme.inkMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ClipboardCard: View {
    let entry: ClipboardManager.Entry
    let clipboard: ClipboardManager

    @State private var hovering = false
    @State private var justCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                if entry.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.orange)
                }
                Text(entry.copiedAt, style: .relative)
                    .font(.system(size: 8.5))
                    .foregroundStyle(NotchTheme.inkMuted)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if justCopied {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(NotchTheme.battery)
                }
            }

            Text(entry.text.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(size: 10.5))
                .foregroundStyle(NotchTheme.inkPrimary)
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(9)
        .frame(width: 132, height: 84, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(hovering ? NotchTheme.surfaceHover : NotchTheme.surface)
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
