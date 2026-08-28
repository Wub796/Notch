import SwiftUI

/// Scratchpad: a plain text field that autosaves.
struct NotesView: View {
    @Bindable var notes: NotesManager

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextEditor(text: $notes.text)
                .font(.system(size: 12))
                .foregroundStyle(NotchTheme.inkPrimary)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(NotchTheme.surface)
                }
                .overlay(alignment: .topLeading) {
                    if notes.text.isEmpty {
                        Text("Jot something down…")
                            .font(.system(size: 12))
                            .foregroundStyle(NotchTheme.inkMuted)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }

            HStack(spacing: 10) {
                Text("\(notes.wordCount) word\(notes.wordCount == 1 ? "" : "s")")
                    .font(.system(size: 9.5).monospacedDigit())
                    .foregroundStyle(NotchTheme.inkMuted)

                if notes.lastSavedAt != nil {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 9.5))
                        .foregroundStyle(NotchTheme.inkMuted)
                }

                Spacer()

                Button("Clear") {
                    withAnimation(NotchAnimations.content) { notes.clear() }
                }
                .buttonStyle(PressableButtonStyle())
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(NotchTheme.inkSecondary)
                .disabled(notes.text.isEmpty)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Scratchpad")
    }
}
