# Timer regression checks

Run on macOS with the Swift command-line tools:

```bash
mkdir -p .build/timer-tests
swiftc Notch/Core/RepeatingTimer.swift \
  Notch/Modules/Activities/ClockTimerStore.swift \
  Notch/Modules/Activities/ClockTimerMonitor.swift \
  Notch/Modules/Tools/TimerManager.swift \
  tests/timers/main.swift -o .build/timer-tests/check
.build/timer-tests/check
```

The checks create and remove a disposable store in the temporary directory. They
never write to the user's Clock store or change any system timer. The installed
MobileTimer model constructs real paused/resumed timer representations, so a
schema or runtime change fails the check instead of silently guessing deadlines.
Coverage includes migrated versus legacy storage, read-only decoding, actual
paused remaining time, resume deadlines, WAL-driven cancellation, atomic plist
replacement, expiry, selection among multiple timers, stop lifecycle, privacy
denials, local pause/resume/cancel, and invalid values.

## App-level checks

Build the Debug app, then launch it through Launch Services (not by executing
its binary in Terminal, which changes macOS privacy attribution):

```bash
open -n .build/timer-refinement/Build/Products/Debug/Notch.app --args \
  --debug-clock-timer-check --prompt-log "$PWD/.build/timer-tests/app-clock-status.txt"
```

The process exits after reporting the access state, timer state, chosen activity,
and notch heights. On migrated systems without Full Disk Access it must report
`access=fullDiskAccessRequired`, not `ready` or a stale timer. After granting
access to the exact app being tested and reopening it, start a timer in Clock or
Siri, pause/resume/cancel it, and verify the notch follows each state. Also verify
that a second timer returns after the newest one expires. Full Disk Access is an
optional, broad macOS grant; neither the check nor Notch changes it automatically.

Onboarding geometry and completion checks:

```bash
open -n .build/timer-refinement/Build/Products/Debug/Notch.app --args \
  --debug-onboarding-check --prompt-log "$PWD/.build/timer-tests/onboarding-layout.txt"
open -n .build/timer-refinement/Build/Products/Debug/Notch.app --args \
  --show-onboarding --onboarding-step 10 --debug-onboarding-finish-check \
  --prompt-log "$PWD/.build/timer-tests/onboarding-finish.txt"
```

The first must report `content.fits=true`. The second activates the real default
button with Return and must report all three: `onboarding.closed=true`,
`handoff.expanded=true`, and `handoff.pinned=true`. Both restore the prior
onboarding-completion preference after the check.
