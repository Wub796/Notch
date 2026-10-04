# Onboarding and notch experience checks

Build the Debug app and launch it through Launch Services:

```bash
open -n .build/timer-refinement/Build/Products/Debug/Notch.app --args \
  --debug-experience-check --prompt-log "$PWD/.build/experience-normal.txt"
open -n .build/timer-refinement/Build/Products/Debug/Notch.app --args \
  --debug-experience-check --debug-reduce-motion \
  --prompt-log "$PWD/.build/experience-reduced.txt"
```

Wait for each run to finish before starting the next. Both reports must contain
`checks.passed=true` and no failed assertions. The Reduce Motion flag is Debug
only; it exercises the app's fade-only branches without changing macOS settings.

The check sends actual mouse events to the hosted onboarding controls, including
two Continue clicks in one turn and Back. It invokes the real Skip the rest
keyboard shortcut (Shift-Command-S), finishes with the actual primary button,
then tests a fast notch click, pin retention on pointer exit, replacing feedback,
and a real Escape key event delivered to the native panel. The debug observer
only reports which onboarding step is on screen; it cannot navigate the flow.
No real permission is requested or granted. The previous tab preference is
restored; the check process exits and leaves any existing Notch instance alone.

Add `--debug-experience-capture` to save native welcome, permission, and ready
renders beside the report in `<report-basename>.images/`. Captures are actual
AppKit hosting-view images, not browser reimplementations. They show settled
screens, not a frame-by-frame proof of animation timing.

Layout coverage includes every step, both ready-screen extremes, and granted,
denied, and pending variants of every permission:

```bash
open -n .build/timer-refinement/Build/Products/Debug/Notch.app --args \
  --debug-onboarding-check --prompt-log "$PWD/.build/experience-layout.txt"
```

Require `content.fits=true`. The window remains 460×620 points. Onboarding
completion/handoff is checked separately with the existing
`--show-onboarding --onboarding-step 10 --debug-onboarding-finish-check` hook.

## Manual review

- Navigate forward/back repeatedly; only the current page accepts input.
- Grant an optional permission and watch its one-shot tile ripple and button
  confirmation. Revisit an already-granted permission: it must not auto-skip.
- On a pending permission, Not now and Skip must remain available.
- Hover/open, click/pin, switch main and detail tabs, toggle the pin, and press
  Escape while the panel has keyboard focus.
- Trigger volume/brightness and a countdown: payload changes should not restart
  the slab's geometry spring. Replacing action feedback should transition once.
- Drag over the notch: the drop well should arrive and leave without a hard cut.
- Enable macOS Reduce Motion: no traveling glow, scan line, breathing halo,
  confirmation ripple, sheen, or decorative scale should remain.

The automated checks verify behavior and layout. Real permission-confirmation
motion and perceived smoothness still need visual review on the user's display.
