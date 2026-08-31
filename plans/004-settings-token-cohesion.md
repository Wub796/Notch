# 004 — Use the house animation token in the settings sidebar

- **Status**: DONE (executed; feel-check pending a live run)
- **Commit**: 0045fcb
- **Severity**: LOW
- **Category**: Cohesion & tokens
- **Estimated scope**: 1 file, ~3 lines

## Problem

The settings sidebar pane selection animates with a hand-rolled timing curve
instead of the house token:

```swift
// Notch/Views/SettingsView.swift:126-129 — current
Button {
    withAnimation(.easeInOut(duration: 0.12)) {
        selection = pane
    }
} label: { ... }
```

`0.12s easeInOut` is fast enough to be near-imperceptible (which is fine for a
tens-of-times/day pane switcher), but it forks the curve vocabulary: the rest of
the app animates state changes through `NotchAnimations.content`. The sidebar
currently animates nothing visible anyway (the detail pane swap has no
transition — see plan 005), so this wrapper is close to dead weight and the one
curve it could animate is out-of-family.

## Target

Use the house token for consistency:

```swift
// target — Notch/Views/SettingsView.swift
Button {
    withAnimation(NotchAnimations.content) {
        selection = pane
    }
} label: { ... }
```

If the executor prefers the fastest possible response here (a pane switcher is
high-frequency), `NotchAnimations.reduced` (`.easeOut(duration: 0.15)`) is the
repo's sanctioned fast curve — pick one, don't invent a third value.

## Repo conventions to follow

- All state-change animation goes through `NotchAnimations` in
  `Notch/Core/NotchAnimation.swift`. `NotchAnimations.content` is the default
  micro-interaction curve; `NotchAnimations.reduced` is the fast/reduced-motion
  curve.
- Exemplar: `Notch/Views/NotchTopBarView.swift:129` uses
  `withAnimation(NotchAnimations.content)` for a selection change — imitate it.

## Steps

1. Open `Notch/Views/SettingsView.swift`, line ~127.
2. Replace `.easeInOut(duration: 0.12)` with `NotchAnimations.content`.
3. Grep `SettingsView.swift` for any other `.easeInOut` / hand-rolled curves and
   leave them untouched (this plan covers the sidebar selection only) — report
   if you find others.

## Boundaries

- Do NOT touch the pane detail transition (that's plan 005).
- Do NOT change `NotchAnimations` definitions.
- Do NOT touch any other file.

## Verification

- **Mechanical**: `xcrun swiftc -frontend -parse Notch/Views/SettingsView.swift`
  passes; `git diff --check` clean.
- **Feel check**: open Settings and click through panes:
  - The sidebar selection highlight responds immediately; no perceptible
    slowdown vs. before (the token resolves to a fast spring).
  - Under Reduce Motion the selection still highlights (fade-style), never
    disappears.
- **Done when**: pane selection uses the house curve and feels at least as
  responsive as before.

## Feel-check note

This is a token swap on a near-invisible animation; the main risk is a barely
perceptible response change. If the spring's settle feels slower than the old
120ms ease (it shouldn't), use `NotchAnimations.reduced` instead and re-check.
