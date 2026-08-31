# 003 — Shorten the charging popup fill animation

- **Status**: DONE (executed; feel-check pending a live run)
- **Commit**: 0045fcb
- **Severity**: MEDIUM
- **Category**: Easing & duration
- **Estimated scope**: 1 file, ~3 lines

## Problem

The charging popup's level bar fills over 900ms with a bare `easeOut`:

```swift
// Notch/Modules/Activities/ChargingPopupView.swift:60-63 — current
.onAppear {
    withAnimation(.easeOut(duration: 0.9)) {
        isFilled = true
    }
}
```

`isFilled` drives the fill bar's height/width from 0 to the battery level.
900ms is triple the 300ms UI budget for a transient status popup that itself
holds for only ~1.6-4 seconds, and it reads as sluggish against the springy
pop-in (`NotchAnimations.chargePop`). It also uses a hand-rolled `.easeOut(0.9)`
instead of the house vocabulary.

## Target

Drive the fill with the house content animation, which is fast, profile-aware,
and collapses to a 150ms fade under Reduce Motion:

```swift
// target — Notch/Modules/Activities/ChargingPopupView.swift
.onAppear {
    withAnimation(NotchAnimations.content) {
        isFilled = true
    }
}
```

`NotchAnimations.content` resolves to a spring (response 0.24-0.34, damping
~0.78-0.98 depending on profile) — roughly 240-340ms, inside the budget, and
still reads as a deliberate fill rather than a snap.

## Repo conventions to follow

- The house animation vocabulary is `NotchAnimations` in
  `Notch/Core/NotchAnimation.swift`; `NotchAnimations.content` is the standard
  micro-interaction curve used throughout module views.
- The popup's own entry/exit already uses `NotchAnimations.chargePop`
  (`ChargingPopupView.swift` background transitions), so the fill following the
  same family keeps the popup cohesive.
- If a fixed timing curve is ever preferred over a spring, the repo precedent is
  `NotchAnimations.reduced` (`.easeOut(duration: 0.15)`), not a 0.9s ease.

## Steps

1. Open `Notch/Modules/Activities/ChargingPopupView.swift`.
2. Replace the `.onAppear` block at lines 60-63: swap `.easeOut(duration: 0.9)`
   for `NotchAnimations.content`.
3. Confirm `isFilled` is not animated anywhere else (it is only set in
   `.onAppear`).

## Boundaries

- Do NOT change the popup's entry/exit transitions (`chargePop`).
- Do NOT change the `isFilled` semantics or the fill bar layout.
- Do NOT touch `NotchAnimations.content`'s definition.

## Verification

- **Mechanical**: `xcrun swiftc -frontend -parse Notch/Modules/Activities/ChargingPopupView.swift`
  passes; `git diff --check` clean.
- **Feel check**: plug in a charger (or trigger the popup) and watch the fill:
  - The fill reaches the battery level in under ~350ms — a quick, confident
    sweep, not a drawn-out crawl.
  - The fill and the pop-in feel like the same motion family (both springy).
  - Under Reduce Motion the fill completes almost instantly with a short fade —
    still legible, never removed.
- **Done when**: the fill reads as immediate and confident, roughly a third of
  the current duration.

## Feel-check note

The one feel-dependent choice is spring vs. fixed ease. `NotchAnimations.content`
is the safe default. If the fill's springy end overshoots visibly above the
level (unlikely at these dampings), switch to
`withAnimation(NotchAnimations.activity)` or `NotchAnimations.reduced` and
re-check — but confirm against the default first.
