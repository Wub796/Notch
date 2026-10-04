# Onboarding and notch refinement — October 4, 2026

## Delivered

### Onboarding

- Per-step accent lighting that moves across the surface on normal motion and
  stays centered under Reduce Motion; no ambient repeating animation.
- Eleven animated progress markers with current-step emphasis and accessible
  step counts. Permission progress is distinct from the number granted.
- One-shot permission-tile confirmation ripple, button checkmark and light
  sweep, waiting spinner, ready checkmark reveal, and animated login-row changes.
- Directional page entrances; fades instead of travel under Reduce Motion.
- A 280ms navigation gate (150ms reduced) prevents duplicate Continue events
  from skipping questions or requesting the next permission unintentionally.
- Pending requests always retain Not now; Skip the rest also has ⇧⌘S.
- Cancelled invitation withdrawal, panel-arrival, navigation, and dismissal
  tasks cannot update an obsolete screen.
- Reduced/paused demo meters and scan timelines stop sampling; reduced mode
  omits sheen, decorative bounce/ripple/scale, and traveling accent light.

### Notch workflow

- Explicit click pins the notch and is no longer rejected during a fast hover.
- Visible animated pin controls in both the main rail and detail headers.
- Escape through the native panel closes and clears the pin.
- Onboarding lands on Home, gives a brief welcome hint, and releases its
  temporary pin only if the user has not changed pin intent since handoff.
- Feedback replacements transition by unique identity; closing removes stale
  feedback. Drop-zone arrival, resolving state, and dismissal animate.
- Collapsed shape animation follows actual size changes, not every timer tick
  or volume payload. The existing Animation Style still drives notch springs.

## Verified

- Final Debug app build passed without new warnings in its build log.
- 12 native-event experience checks passed in normal mode, and the same 12
  passed with the Debug Reduce Motion override.
- Nine existing native Notes/settings workflow checks passed after final edits.
- Onboarding geometry checks covered all steps, every ask's granted/denied/
  pending state, and ready-screen all/none-granted extremes: tallest 596pt
  within the unchanged 460×620pt window.
- Real final-button handoff check passed: window closed, notch expanded/pinned.
- Native 920×1240 PNG captures for Welcome, permission, and Ready were saved
  alongside the experience report under `.build/` and exposed in a local review
  sheet in Preview. Images were confirmed loaded; the preview screenshot tool
  could not composite the browser, so no screenshot-based visual-quality pass
  is claimed.
- `git diff --check` passed.

Commands and manual-review cases are in
[onboarding checks](../tests/workflows/onboarding.md).

## Limits

No real permission was requested/granted by the native interaction checks.
Permission-confirmation motion and perceived animation smoothness remain manual
review items. No timing benchmark or CPU speedup is claimed. Existing running
Notch was not replaced or terminated. No commit, distribution signing, release
packaging, or deployment was performed.
