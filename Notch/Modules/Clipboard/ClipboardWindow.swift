import AppKit
import SwiftUI

/// Clipboard history in a window of its own.
///
/// It used to be a strip of cards under the notch: four lines of text a copy,
/// in a panel that closed the moment the pointer left it. History is something
/// you read, search and pick from, which wants a real window that stays put.
final class ClipboardWindowController: NSWindowController, NSWindowDelegate {
    static let shared = ClipboardWindowController()

    private weak var hostedClipboard: ClipboardManager?

    private init() {
        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)

        window.title = "Clipboard"
        window.isReleasedWhenClosed = false
        window.identifier = NSUserInterfaceItemIdentifier("NotchClipboardWindow")
        window.collectionBehavior = [.managed, .participatesInCycle, .fullScreenAuxiliary]
        window.minSize = NSSize(width: 380, height: 360)
        window.hidesOnDeactivate = false
        window.center()
        window.setFrameAutosaveName("NotchClipboardWindow")
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ClipboardWindowController does not support NSCoding")
    }

    func show(clipboard: ClipboardManager) {
        if hostedClipboard !== clipboard {
            window?.contentView = SettingsHostingView(
                rootView: ClipboardWindowView(clipboard: clipboard)
            )
            hostedClipboard = clipboard
        }
        AppWindows.present(window)
    }

    func windowWillClose(_ notification: Notification) {
        AppWindows.didClose(window)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }
}

/// The clipboard window's content: a grouped list, the way System Settings
/// lays out a pane — search, then pinned items, then recent ones.
struct ClipboardWindowView: View {
    let clipboard: ClipboardManager

    @State private var query = ""
    @State private var justCopied: UUID?

    private var settings: NotchSettings { .shared }

    private func matches(_ entry: ClipboardManager.Entry) -> Bool {
        query.isEmpty || entry.text.localizedCaseInsensitiveContains(query)
    }

    private var pinned: [ClipboardManager.Entry] {
        clipboard.entries.filter { $0.isPinned && matches($0) }
    }

    private var recent: [ClipboardManager.Entry] {
        clipboard.entries.filter { !$0.isPinned && matches($0) }
    }

    private var hasUnpinned: Bool {
        clipboard.entries.contains { !$0.isPinned }
    }

    var body: some View {
        Form {
            if !settings.clipboardHistoryEnabled {
                Section {
                    HStack {
                        Label("Clipboard history is off", systemImage: "clipboard")
                        Spacer()
                        Button("Turn On") {
                            settings.clipboardHistoryEnabled = true
                        }
                    }
                } footer: {
                    Text("Notch only reads the clipboard while history is on.")
                }
            }

            Section {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search", text: $query, prompt: Text("Search copied text"))
                        .textFieldStyle(.plain)
                        // A grouped form draws a field's label beside it;
                        // the prompt already says what this is.
                        .labelsHidden()
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Clear search")
                    }
                }
            }

            if !pinned.isEmpty {
                Section("Pinned") {
                    ForEach(pinned) { entry in
                        ClipboardHistoryRow(entry: entry, clipboard: clipboard, justCopied: $justCopied)
                    }
                }
            }

            Section {
                if recent.isEmpty {
                    Text(emptyMessage)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(recent) { entry in
                        ClipboardHistoryRow(entry: entry, clipboard: clipboard, justCopied: $justCopied)
                    }
                }
            } header: {
                HStack {
                    Text("Recent")
                    Spacer()
                    if hasUnpinned {
                        Button("Clear Unpinned") {
                            withAnimation { clipboard.clearUnpinned() }
                        }
                        .buttonStyle(.borderless)
                    }
                }
            } footer: {
                Text("Recent copies are kept in memory only and are gone when Notch quits — pin one to keep it. Anything another app marks as a password is never recorded.")
            }
        }
        .formStyle(.grouped)
        .animation(.default, value: clipboard.entries)
        .frame(minWidth: 380, minHeight: 360)
    }

    private var emptyMessage: String {
        if !query.isEmpty { return "Nothing matches “\(query)”." }
        return pinned.isEmpty ? "Copies you make will collect here." : "No other recent copies."
    }
}

/// One copied item: its text, when it was copied, and its actions. Clicking
/// anywhere on the row copies it back.
private struct ClipboardHistoryRow: View {
    let entry: ClipboardManager.Entry
    let clipboard: ClipboardManager
    @Binding var justCopied: UUID?

    @State private var isHovering = false

    private var preview: String {
        entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var kindSymbol: String {
        if let url = URL(string: preview), url.scheme?.hasPrefix("http") == true {
            return "link"
        }
        return preview.contains("\n") ? "text.alignleft" : "text.quote"
    }

    private var wasJustCopied: Bool {
        justCopied == entry.id
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: kindSymbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(preview)
                    .lineLimit(3)
                Text(entry.copiedAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            HStack(spacing: 2) {
                actionButton(
                    wasJustCopied ? "checkmark" : "doc.on.doc",
                    tint: wasJustCopied ? .green : nil,
                    help: "Copy"
                ) {
                    copy()
                }
                actionButton(
                    entry.isPinned ? "pin.fill" : "pin",
                    tint: entry.isPinned ? .orange : nil,
                    help: entry.isPinned ? "Unpin" : "Pin"
                ) {
                    withAnimation { clipboard.togglePin(entry) }
                }
                actionButton("trash", help: "Remove") {
                    withAnimation { clipboard.remove(entry) }
                }
            }
            // Quiet until the row is pointed at, so a long list reads as text
            // rather than as a column of buttons.
            .opacity(isHovering || entry.isPinned || wasJustCopied ? 1 : 0.35)
        }
        .contentShape(Rectangle())
        .onTapGesture { copy() }
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Copy") { copy() }
            Button(entry.isPinned ? "Unpin" : "Pin") {
                withAnimation { clipboard.togglePin(entry) }
            }
            Divider()
            Button("Remove", role: .destructive) {
                withAnimation { clipboard.remove(entry) }
            }
        }
        .help("Click to copy")
        .accessibilityElement(children: .combine)
        .accessibilityHint("Click to copy back to the clipboard")
    }

    private func actionButton(
        _ symbol: String,
        tint: Color? = nil,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .foregroundStyle(tint ?? .secondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(help)
    }

    private func copy() {
        clipboard.copyBack(entry)
        let id = entry.id
        justCopied = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if justCopied == id { justCopied = nil }
        }
    }
}
