# Animation Improvement Plans

Plans produced by the `improve-animations` audit (commit `0045fcb`). Each plan
is self-contained — an executor needs no context beyond the plan file and the
repo.

| # | Title | Severity | Status |
| --- | --- | --- | --- |
| 001 | HUD bar drag tracks 1:1 and settles with a spring | HIGH | DONE |
| 002 | Remove the bouncy spring from play/pause transport | HIGH | DONE |
| 003 | Shorten the charging popup fill animation | MEDIUM | DONE |
| 004 | Use the house animation token in the settings sidebar | LOW | DONE |
| 005 | Crossfade the settings pane on selection | MEDIUM | DONE |
| 006 | Animate empty states on entry | MEDIUM | DONE |

All six executed and parse-verified; the diff was reviewed against the
`review-animations` bar (no `scale(0)`, no hand-rolled curves left in the
changed sites, reduced-motion handled through `NotchAnimations.content`).
Feel-checks (drag tracking, transport crispness, fill speed, pane crossfade,
empty-state entrance) still need a live run.

## Recommended execution order

1. **002** (remove transport bounce) — trivial, removes the worst feel offense
   (bounce on a frequent control), zero risk.
2. **001** (HUD drag 1:1) — the other HIGH; mechanical change to one file.
3. **003** (charging fill duration) — small, independent.
4. **005** (settings pane crossfade) — the highest-value additive change.
5. **004** (settings token cohesion) — apply together with 005, or after it.
6. **006** (empty-state entrance) — independent, lowest risk of the additive
   group.

## Dependencies

- **004 and 005 touch the same file** (`Notch/Views/SettingsView.swift`), and
  005's transition is driven by 004's `withAnimation(NotchAnimations.content)`.
  Apply 004 first, or apply 005 against the existing
  `withAnimation(.easeInOut(duration: 0.12))` and flag the follow-up. Do not
  run both concurrently in separate worktrees.
- 001, 002, 003, 006 are fully independent of each other and of 004/005.
- All plans use only the existing `NotchAnimations` vocabulary — no new tokens,
  no new dependencies.

## Second pass (after 006)

Two more smoothing changes, made after the audit above. Neither invents a curve:
everything new reuses the existing vocabulary, and neither touches a state the
user can reverse mid-flight without keeping it interruptible.

| # | Change | Where |
| --- | --- | --- |
| 007 | The playback fill glides between timeline samples | `Notch/Modules/Media/ScrubberBar.swift` |
| 008 | The lock-screen player fades in and out instead of popping | `Notch/Modules/FaceID/Overlay/FaceIDNowPlayingView.swift` |

**007** — `sampleInterval` matches the caller's own cadence (10Hz in the panel
and on the Devices screen) and interpolates with `NotchAnimations.clockStep`, one
linear segment per interval. Never while dragging: the fill under the thumb is
the user's gesture and has to track the pointer 1:1. Verified offscreen — a
quarter track fills a quarter of the bar with and without the parameter, so no
static geometry moved.

**008** — the pane is ordered in at zero alpha and faded up, and fades out before
it is ordered out. The fade runs on the window's own alpha rather than a SwiftUI
opacity, so the Liquid Glass surface is not re-driven on every frame of the fade;
the generation guard stops a slow fade-out from ordering out a pane that has been
asked back. Still needs a live feel-check on a real lock screen.

## How to execute

Run any plan with a capable agent, e.g.:
`improve-animations execute <plan-file>` or hand the file to any coding agent.
Each plan ends with a mechanical verification (parse + `git diff --check`) and
a feel-check that requires running the app.
