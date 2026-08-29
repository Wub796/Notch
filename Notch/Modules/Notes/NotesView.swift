import SwiftUI

/// Scratchpad: a plain text field that autosaves.
struct NotesView: View {
    @Bindable var notes: NotesManager

    var body: some View {
        VStack(alignment: .leading, spacing: NotchTheme.Space.m) {
            ScreenHeader("Notes", subtitle: subtitle) {
                ScreenTextButton(title: "Clear", systemImage: "trash") {
                    withAnimation(NotchAnimations.content) { notes.clear() }
                }
                .opacity(notes.text.isEmpty ? 0.4 : 1)
                .disabled(notes.text.isEmpty)
            }

            TextEditor(text: $notes.text)
                .font(.notchBody.weight(.regular))
                .foregroundStyle(NotchTheme.inkPrimary)
                .scrollContentBackground(.hidden)
                .padding(10)
                .notchCard()
                .overlay(alignment: .topLeading) {
                    if notes.text.isEmpty {
                        Text("Jot something down…")
                            .font(.notchBody.weight(.regular))
                            .foregroundStyle(NotchTheme.inkMuted)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Scratchpad")
    }

    /// Word count and save state on one line, where every other screen puts
    /// its status — rather than a footer row of its own.
    private var subtitle: String {
        let words = "\(notes.wordCount) word\(notes.wordCount == 1 ? "" : "s")"
        return notes.lastSavedAt == nil ? words : words + " · Saved"
    }
}
