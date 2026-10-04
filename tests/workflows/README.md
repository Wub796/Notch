# Workflow regression checks

Run from the workspace root on macOS:

```bash
mkdir -p .build/workflow-tests
swiftc Notch/Core/RepeatingTimer.swift \
  Notch/Modules/Notes/NotesManager.swift \
  Notch/Modules/Clipboard/ClipboardManager.swift \
  Notch/Modules/Shelf/ShelfController.swift \
  Notch/Modules/Activities/VolumeMonitor.swift \
  Notch/Modules/Activities/PowerMonitor.swift \
  Notch/Modules/Activities/LiveActivityManager.swift \
  tests/workflows/main.swift -o .build/workflow-tests/check
.build/workflow-tests/check
```

Checks use a unique pasteboard, an isolated defaults suite, and temporary files;
they never change the user's clipboard, notes, or source files. The isolated
settings stand-in lets the production model implementations be tested without
starting unrelated audio, camera, weather, or Face ID integrations. Volume
listener checks attach real CoreAudio listeners but never change system volume.

Covered behavior: pending versus saved notes, immediate lifecycle flush,
debounced save, Clear and Undo Clear, protection against overwriting newer edits,
clipboard opt-out boundaries, concealed content, stable row identities, updated
pin timestamps, pin ordering, independent recent-history capacity, immediate
trimming, self-copy handling, shelf batch deduplication, source-file preservation,
and volume listener enable/disable after launch.

## Native app check

Build the Debug app and launch it via Launch Services:

```bash
open -n .build/timer-refinement/Build/Products/Debug/Notch.app --args \
  --debug-workflow-check --prompt-log "$PWD/.build/workflow-tests/native-results.txt"
```

This types into the real Notes `TextEditor`, delivers mouse events to the real
Clear and Undo Clear buttons, checks persisted text, and leaves the editor to
exercise the actual lifecycle flush. It also verifies the production settings
callbacks for volume HUD and clipboard capacity. The notes use an isolated suite;
the prior settings values are restored. The app exits after writing its report.
All entries and `checks.passed` must be `true`; a report file existing alone is
not a passing check.
