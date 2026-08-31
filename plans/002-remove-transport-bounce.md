# 002 — Remove the bouncy spring from play/pause transport

- **Status**: DONE (executed; feel-check pending a live run)
- **Commit**: 0045fcb
- **Severity**: HIGH
- **Category**: Purpose & frequency
- **Estimated scope**: 4 files, ~8 lines

## Problem

The play/pause button is a tens-of-times-per-day control, and in four places it
is wrapped in an under-damped, bouncy spring:

```swift
// Notch/Modules/Media/MediaPlayerView.swift:365-367 — current
Button {
    withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
        media.togglePlayPause()
    }
} label: { ... }
```

The same pattern appears at:

- `Notch/Modules/Home/HomeDashboardView.swift:145`
- `Notch/Modules/Audio/AudioDevicesView.swift:210`
- `Notch/Modules/Audio/DevicesScreenView.swift:359`

`dampingFraction: 0.7` produces visible overshoot/bounce. Per the audit rule
catalog: bounce belongs on rare, playful moments (drag-to-dismiss, delight);
a frequent transport control wrapped in a bouncing spring feels jittery and
un-damped. The icon already crossfades via `.contentTransition(.symbolEffect(.replace))`
on the label — that IS the state-change animation the button needs. The extra
spring wrapper animates nothing visible except a bounce that wasn't asked for.

## Target

Remove the `withAnimation` wrapper entirely from all four call sites. The
`contentTransition(.symbolEffect(.replace))` on the button label already animates
the icon swap; `PressableButtonStyle` already gives press feedback (instant
scale 0.96 on press, spring response 0.16 / damping 0.85). Nothing else is
needed:

```swift
// target — Notch/Modules/Media/MediaPlayerView.swift
Button {
    media.togglePlayPause()
} label: { ... }
```

## Repo conventions to follow

- `NotchAnimations.content` is the house default for state-change animation
  (`Notch/Core/NotchAnimation.swift`), but here no implicit animation is wanted
  at all — the icon crossfade handles the transition. If a future change needs
  an animation, use `NotchAnimations.content`, never a hand-rolled
  `dampingFraction: 0.7` spring.
- Transport buttons elsewhere in the codebase call the media action with no
  `withAnimation` wrapper (e.g. previous/next track at `MediaPlayerView.swift:361-364`),
  which is the pattern to match.

## Steps

1. `Notch/Modules/Media/MediaPlayerView.swift:365-367` — remove the
   `withAnimation(...)` wrapper around `media.togglePlayPause()`, leaving the
   plain call.
2. `Notch/Modules/Home/HomeDashboardView.swift:144-147` — same removal.
3. `Notch/Modules/Audio/AudioDevicesView.swift:209-212` — same removal.
4. `Notch/Modules/Audio/DevicesScreenView.swift:358-361` — same removal.
5. Grep for `dampingFraction: 0.7` across `Notch/` to confirm no other transport
   call site remains. (If a non-transport site legitimately uses it — e.g. a
   rare celebration — leave it and report.)

## Boundaries

- Do NOT touch `PressableButtonStyle` (the press feedback stays).
- Do NOT touch the `contentTransition(.symbolEffect(.replace))` on the button
  label.
- Do NOT change `media.togglePlayPause()` or any MediaController logic.
- Do NOT remove the spring from any genuinely rare/delight animation.

## Verification

- **Mechanical**: parse all four files with
  `xcrun swiftc -frontend -parse <file>`; `git diff --check` clean.
- **Feel check**: build and run; in the Media panel, Home dashboard, Audio tab,
  and Devices screen, click play/pause rapidly (spam it):
  - The icon swaps instantly with its own crossfade.
  - No bounce, no overshoot, no wobble — just the icon change and the press
    scale.
  - Under Reduce Motion the icon still swaps (opacity-style), because
    `contentTransition` is reduced-motion aware.
- **Done when**: rapid play/pause feels crisp and flat — the icon is the only
  thing that changes.

## Feel-check note

This is a removal, so there is little feel to tune: if the icon swap alone ever
feels abrupt on a non-reduced-motion machine, add
`withAnimation(NotchAnimations.content)` around the call — but that is not
expected and should only be done after testing the plain version.
