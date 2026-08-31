# 001 — Make the HUD bar drag track 1:1 and settle with a spring

- **Status**: DONE (executed; feel-check pending a live run)
- **Commit**: 0045fcb
- **Severity**: HIGH
- **Category**: Interruptibility
- **Estimated scope**: 1 file, ~15 lines

## Problem

`DraggableProgressBar` in `Notch/Modules/Activities/InlineHUD.swift` animates the
value with a fixed 0.3s timing curve on **every drag frame**:

```swift
// Notch/Modules/Activities/InlineHUD.swift:50-62 — current
.gesture(
    DragGesture(minimumDistance: 0)
        .onChanged { gesture in
            withAnimation(NotchAnimations.hudBar) {
                isDragging = true
                update(to: gesture.location.x, in: geometry)
            }
        }
        .onEnded { _ in
            withAnimation(NotchAnimations.hudBar) {
                isDragging = false
            }
        }
)
```

`NotchAnimations.hudBar` is `.smooth(duration: 0.3)` (a fixed-duration timing
curve, defined in `Notch/Core/NotchAnimation.swift:98`). Two problems:

1. **The bar lags the pointer.** Every `onChanged` retargets a 300ms ease toward
   the new finger position, so the fill chases the cursor instead of sticking to
   it. A drag must track 1:1.
2. **Fixed-duration tween can't be grabbed mid-flight.** A timing curve restarts
   from zero on each retarget; a spring re-targets from the current value and
   carries velocity, which is what an interruptible drag needs.

`isDragging` (the bar's thickness 5→8) is a legitimate animated state change;
the **value** itself must not be.

## Target

The value updates with no animation during the drag (1:1 tracking). The
`isDragging` thickness change still animates. On release, the bar settles with
the house content spring (`NotchAnimations.content`), which is already
profile-aware and collapses to a short fade under Reduce Motion:

```swift
// target — Notch/Modules/Activities/InlineHUD.swift
.gesture(
    DragGesture(minimumDistance: 0)
        .onChanged { gesture in
            // 1:1: the fill follows the pointer instantly; no animation on the
            // value while the finger is down.
            isDragging = true
            update(to: gesture.location.x, in: geometry)
        }
        .onEnded { _ in
            // Settle with the house spring (already reduced-motion aware).
            withAnimation(NotchAnimations.content) {
                isDragging = false
            }
        }
)
```

## Repo conventions to follow

- The house motion vocabulary is `NotchAnimations` in `Notch/Core/NotchAnimation.swift`.
  `NotchAnimations.content` is the standard micro-interaction curve (spring,
  damping ~0.9, response 0.24-0.34 depending on profile), used everywhere in
  module views (e.g. `Notch/Views/NotchTopBarView.swift:129`). It returns
  `NotchAnimations.reduced` (150ms ease-out) under Reduce Motion by contract.
- `update(to:in:)` already clamps `value` to 0...1 (`InlineHUD.swift:78-81`).
  Leave it unchanged.
- This is the only `DraggableProgressBar` in the app; the collapsed HUD and the
  dropped HUD bar both use this same struct, so one change covers both.

## Steps

1. Open `Notch/Modules/Activities/InlineHUD.swift`. In `DraggableProgressBar.body`,
   replace the `.gesture(...)` block (lines ~50-62) with the target code above:
   - `onChanged`: set `isDragging = true` and call `update(...)` directly, no
     `withAnimation` around the value change.
   - `onEnded`: wrap **only** `isDragging = false` in
     `withAnimation(NotchAnimations.content)`.
2. Do not touch `height` (the `isDragging ? 8 : 5` / `9 : 6` computed property) —
   it will now animate only on press/release, which is the intent.
3. Verify no other caller of `NotchAnimations.hudBar` exists that should also
   change (grep `hudBar` — it is only used by this gesture; if a stray use
   remains elsewhere, leave it and report).

## Boundaries

- Do NOT change `NotchAnimations.hudBar` itself or remove the token.
- Do NOT change the drag math in `update(to:in:)`.
- Do NOT touch `DroppedHUDBar` / `InlineHUD` layout, only the gesture on
  `DraggableProgressBar`.
- Do NOT add dependencies.

## Verification

- **Mechanical**: `xcrun swiftc -frontend -parse Notch/Modules/Activities/InlineHUD.swift`
  must pass; `git diff --check` must be clean.
- **Feel check**: build and run; expand the notch, press a volume/brightness key
  to raise the HUD, then drag the bar:
  - The fill must sit **exactly under the cursor** at all times — no chase, no
    lag, no easing toward the finger while dragging.
  - Mid-drag reversal (drag right then left quickly) must be continuous, never
    restarting from the old value.
  - On release the bar may settle gently; it must not overshoot or wobble.
  - Enable Reduce Motion (System Settings → Accessibility → Display) and confirm
    the press/release still works — the thickness change may snap or fade
    briefly, but the drag itself stays 1:1.
- **Done when**: dragging tracks the cursor 1:1 with zero perceived lag, and
  rapid reversals never jump.

## Feel-check note

The 1:1 tracking is mechanical and verifiable; the only feel-dependent part is
the settle curve on release. If the settle feels dead, try `NotchAnimations.activity`
(a slightly bouncier spring) instead of `content` — but only after confirming
the drag itself is correct.
