# MediaRemoteAdapter

The bundled [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter)
(© 2025 Jonas van den Berg), redistributed unmodified under the BSD 3-Clause
License — see `LICENSE`.

## Why it exists

macOS 15.4+ gates MediaRemote's now-playing entry points for third-party apps:
calls resolve and return, but answer with silence ("Operation not permitted"),
and the only way around it is an entitlement Apple no longer issues. `/usr/bin/perl`
is a system binary that already carries that entitlement, so running the
adapter's Perl script under it is the only way to read and control now-playing
from a regular app without TCC prompts. Sapphire uses the same mechanism.

## How it is launched

`MediaRemoteAdapter.swift` (in `../Modules/Media/`) spawns

```
/usr/bin/perl mediaremote-adapter.pl MediaRemoteAdapter.framework stream
```

parses the JSON lines on stdout, merges diff updates, and feeds the merged
state into `MediaController` — which treats it as the primary now-playing
source, falling back to the Apple Events path only if the adapter fails its
`test` command (exit code 0 = functional).

## Maintenance steps (non-obvious)

1. **The framework binary has its minos patched to 14.0.** The original build
   declares `LC_BUILD_VERSION` minos 26.0, which fails to link against this
   app's macOS 14.0 deployment target. It was patched with:
   ```
   vtool -set-build-version macos 14.0 26.4 -replace -output <binary> <binary>
   codesign --force -s - MediaRemoteAdapter.framework
   ```
   If you re-copy the framework from Sapphire (or rebuild it), re-apply both
   steps or the build breaks. The minos change does not affect dlopen.

2. **The framework is looked up in both `Resources/` and `Frameworks/`.**
   Xcode's synchronized group links the `.framework` into the app (embedding
   it under `Contents/Frameworks/`) rather than copying it as a plain
   resource. `MediaRemoteAdapter.frameworkURL()` checks `Resources/` first and
   falls back to `Frameworks/`, so it works either way.
