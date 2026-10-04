# Workflow audit — October 4, 2026

## Scope

Reviewed source for Notes, Clipboard, Shelf/drop intake, Tools/Shortcuts, live
activities, settings callbacks, and app shutdown. This is a focused workflow
pass, not a claim that every camera, Face ID, media, and network integration has
been tested interactively.

## Implemented

- Notes: explicit pending-save state; flush on leaving, deactivation, and quit;
  truthful Saving/Saved subtitle; one-step Undo Clear, invalidated by new typing.
- Clipboard: no capture of content copied while history was disabled; stable
  row IDs on re-copy; pins ordered ahead of recents; updated pin copy timestamps
  persisted; concealed/transient content still excluded; recent capacity applies
  immediately and pins do not consume it; unpinning also trims; no timed window
  that can swallow an external copy after Copy Back.
- Shelf: normalize local file URLs and deduplicate within a single batch as
  well as against existing items. Clearing still never deletes source files.
- Volume HUD: enable/disable updates CoreAudio listeners immediately, including
  when launching with the feature off. Disabling removes an existing volume
  activity; repeated activity startup does not duplicate observers.
- Settings: label the clipboard limit as Recent History Size and explain pins.

## Verification

- Full Debug app build passed after the final source changes.
- 26 isolated workflow assertions and 27 existing timer assertions passed.
- Nine production/native interface checks passed, including Notes mouse input,
  Clear/Undo, leaving the editor, and immediate settings callbacks.
- `git diff --check` passed.
- The standalone command-line compile reports the existing macOS 27 deprecation
  of the shelf's `NSItemProvider.loadItem` API; it is a warning, not a failed check.
- Native regression commands and fixture boundaries are in
  [workflow checks](../tests/workflows/README.md).
- Full Debug app build typechecks the real production settings and views.
- `--debug-workflow-check` uses the real Notes editor and mouse-delivered button
  actions, without cross-app Accessibility automation or changing user notes.
- Existing timer regression coverage remains documented in
  [timer checks](../tests/timers/README.md).

## Remaining candidates

- **Shortcuts errors/concurrency:** command execution ignores termination status,
  loses stderr, and does not guard concurrent runs. A failing `shortcuts list`
  appears as an empty list. A large unread stderr pipe can also block execution.
  Follow up with structured result/error UI and serial/cancellable runs.
- **Shelf intake errors:** provider load errors and unsupported AirDrop failures
  are silent; asynchronous completion counts resolved URLs rather than newly
  shelved items. Add honest success/error feedback and batch ordering.
- **Timer persistence:** Notch's local timer is cancelled on app shutdown;
  restarting the app does not restore a running or paused local countdown.
- **Settings accessibility:** several blank-label native toggles lack explicit
  accessibility labels. Audit VoiceOver names and keyboard focus throughout.

## Limits

Siri/Clock's migrated timer store remains protected until the user grants Full
Disk Access to the exact app being used. No permission was granted automatically.
The original running app was not replaced or terminated. No distribution signing,
release packaging, deployment, or commit was performed.
