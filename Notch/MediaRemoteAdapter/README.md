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

1. **The framework is kept out of the link — it ships in `Resources/`.** The
   app never calls the framework; the Perl script `dlopen`s it. Xcode's
   synchronized group would otherwise auto-link it into the app (embedding a
   dead `@rpath` reference that crashes launch with a "Library not loaded"
   dyld error), so it is excluded from target membership via
   `membershipExceptions` in the pbxproj, and a `PBXShellScriptBuildPhase`
   (`ditto`) copies it into `$(UNLOCALIZED_RESOURCES_FOLDER_PATH)` on every
   build. If you move or rename the framework, update both the exception path
   (`MediaRemoteAdapter/MediaRemoteAdapter.framework`) and the `ditto` source
   path.

2. **The framework binary has its minos patched to 14.0.** The original build
   declares `LC_BUILD_VERSION` minos 26.0. The patch was originally needed to
   link against this app's macOS 14.0 deployment target; now that the
   framework is not linked it is only relevant if you ever re-add it to the
   link. It was applied with:
   ```
   vtool -set-build-version macos 14.0 26.4 -replace -output <binary> <binary>
   codesign --force -s - MediaRemoteAdapter.framework
   ```
   The minos change does not affect dlopen.
