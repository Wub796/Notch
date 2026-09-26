import SwiftUI

/// Scratchpad: a plain text field that autosaves.
struct NotesView: View {
    @Bindable var notes: NotesManager
    let state: NotchState

    /// Where the editor lays out its first character, measured from the text
    /// view rather than guessed from the card's padding.
    ///
    /// The placeholder used to sit at a hardcoded 15 across and 18 down from the
    /// card's edge, and `TextEditor` has no way to ask where its text really
    /// starts — it starts at the text system's own insets. Those two origins are
    /// unrelated numbers, so the phrase and the caret blinking beside it ended up
    /// at different heights. The starting value here is the old guess, so a
    /// failed measurement is no worse than before rather than a jump to a corner.
    @State private var textOrigin = CGPoint(x: 15, y: 18)

    init(state: NotchState) {
        self.state = state
        _notes = Bindable(wrappedValue: state.notes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NotchTheme.Space.m) {
            ScreenHeader("Notes", subtitle: subtitle) {
                ScreenTextButton(title: "Clear", systemImage: "trash") {
                    withAnimation(NotchAnimations.content) { notes.clear() }
                    state.showToast("All notes cleared", symbol: "trash")
                }
                .opacity(notes.text.isEmpty ? 0.4 : 1)
                .disabled(notes.text.isEmpty)
            }

            TextEditor(text: $notes.text)
                .font(.notchBody.weight(.regular))
                .foregroundStyle(NotchTheme.inkPrimary)
                .scrollContentBackground(.hidden)
                .background {
                    // Sits behind the editor only to report its metrics.
                    TextEditorOriginReader { origin in
                        // Only when it actually moves: publishing from every
                        // layout pass would re-render the screen in a loop.
                        guard abs(origin.x - textOrigin.x) > 0.5
                            || abs(origin.y - textOrigin.y) > 0.5 else { return }
                        textOrigin = origin
                    }
                }
                .overlay(alignment: .topLeading) {
                    if notes.text.isEmpty {
                        Text("Jot something down…")
                            .font(.notchBody.weight(.regular))
                            .foregroundStyle(NotchTheme.inkMuted)
                            .padding(.leading, textOrigin.x)
                            .padding(.top, textOrigin.y)
                            .allowsHitTesting(false)
                    }
                }
                .padding(10)
                .notchCard()
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

/// Reports the point `TextEditor` draws its first character at.
///
/// SwiftUI publishes nothing about the editor's internal insets, so the answer
/// comes from the `NSTextView` it builds: `textContainerOrigin` is precisely
/// where the first glyph is laid out — insets and line-fragment padding
/// included — and one coordinate conversion puts that point in this view's
/// space, which is the editor's own frame with y measured from the top, exactly
/// the space the placeholder's `padding` uses.
///
/// Every number therefore comes from the text system. The placeholder cannot
/// drift from the caret, because there are no longer two opinions about where
/// the text begins.
private struct TextEditorOriginReader: NSViewRepresentable {
    let onOrigin: (CGPoint) -> Void

    func makeNSView(context: Context) -> NSView {
        let probe = MetricsProbe()
        probe.onOrigin = onOrigin
        return probe
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let probe = view as? MetricsProbe else { return }
        probe.onOrigin = onOrigin
        probe.measureSoon()
    }

    final class MetricsProbe: NSView {
        var onOrigin: ((CGPoint) -> Void)?

        /// Flipped, so a measured y is already a top-down inset — the direction
        /// SwiftUI's `padding` counts in.
        override var isFlipped: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            measureSoon()
        }

        // Deliberately no `layout()` override. Measuring from a layout pass and
        // mutating anything as a result is how a window ends up demanding
        // another layout pass for every pass it has already had — AppKit caps
        // that and then raises, which kills the app. The text origin does not
        // move when the view is merely resized (it is an inset from the top-left
        // corner), so `viewDidMoveToWindow` and `updateNSView` are the only
        // moments this needs to look.

        /// Deferred, because `updateNSView` can run inside a SwiftUI update and
        /// mutating view state there warns. It also gives the editor's views a
        /// turn to exist: on the first pass they may not.
        func measureSoon() {
            DispatchQueue.main.async { [weak self] in self?.measure() }
        }

        private func measure() {
            guard let onOrigin, let editor = Self.editor(near: self) else { return }

            // A deliberate 8pt of air above the first line: with the editor's
            // own inset at zero, text sits flush against the card's edge. Set
            // here rather than assumed, so the measurement that follows reports
            // what is true instead of what was expected.
            //
            // Only when it differs, and never during a layout pass: writing this
            // marks the text view — and therefore its scroll view — as needing
            // layout, so writing it on every measure would be a layout change
            // caused by measuring, which is the shape of a layout loop.
            if editor.textContainerInset.height != 8 {
                editor.textContainerInset = NSSize(
                    width: editor.textContainerInset.width,
                    height: 8
                )
            }

            onOrigin(convert(editor.textContainerOrigin, from: editor))
        }

        /// Outward from this probe, nearest ancestor first: a `background` view
        /// is a sibling of the content it sits behind, not a descendant of it,
        /// so the editor's text view is a neighbour rather than a child.
        private static func editor(near view: NSView) -> NSTextView? {
            var ancestor: NSView? = view.superview
            var depth = 0
            while let current = ancestor, depth < 6 {
                if let found = firstEditor(in: current) { return found }
                ancestor = current.superview
                depth += 1
            }
            return nil
        }

        /// The window's shared field editor is an `NSTextView` too, and it
        /// belongs to whichever `NSTextField` is being typed into — never to
        /// this editor — so it is skipped wherever it appears.
        private static func firstEditor(in view: NSView) -> NSTextView? {
            if let textView = view as? NSTextView, !textView.isFieldEditor {
                return textView
            }
            if let scrollView = view as? NSScrollView,
               let document = scrollView.documentView as? NSTextView,
               !document.isFieldEditor {
                return document
            }
            for subview in view.subviews {
                if let found = firstEditor(in: subview) { return found }
            }
            return nil
        }
    }
}
