# Notch

A native macOS notch-extending utility in the spirit of **Sapphire** and **boringNotch**.
Hover the notch and it springs open into a liquid-glass hub with media + live lyrics,
your next 24 hours of events, hardware telemetry, and drag-anything-to-AirDrop.

- **Target:** macOS 14.0+ (Apple Silicon optimized)
- **Stack:** SwiftUI + AppKit, `@Observable` (Observation framework), EventKit, IOKit, Mach host statistics
- **Xcode:** 16.0 or newer (project uses file-system-synchronized groups)

## Building

1. Open `Notch.xcodeproj` in Xcode 16+.
2. Select your signing team (Signing & Capabilities → Team). The app is not sandboxed
   and enables Hardened Runtime with the Apple Events entitlement.
3. Build & run. The app is an agent (`LSUIElement`) — it appears only as the notch
   overlay and a menu bar item (used to quit).

On first expansion macOS will prompt for **Calendars** access; the first Apple Events
use (media fallback) prompts for **Automation** consent.

## Architecture

```
Notch/
├── App/
│   ├── NotchApp.swift            @main entry + menu bar extra (quit)
│   ├── AppDelegate.swift         Screen selection, panel lifecycle, display changes
│   ├── NotchPanel.swift          Borderless non-activating NSPanel @ .statusBar level
│   └── NotchWindowController.swift  Sizes/anchors the panel top-center on the notch screen
├── Core/
│   ├── NotchGeometry.swift       Exact notch size from safeAreaInsets + auxiliary areas
│   ├── NotchState.swift          Root @Observable state; wakes/sleeps modules on expand
│   └── NotchAnimation.swift      The shared spring: response 0.35, damping 0.65, blend 0.1
├── Views/
│   ├── NotchShape.swift          Animatable notch silhouette (flared top, curved bottom)
│   ├── NotchContainerView.swift  Morphing body: black ↔ ultraThinMaterial glass
│   ├── CollapsedNotchView.swift  Media wings: mini artwork + equalizer bars
│   └── ExpandedNotchView.swift   Tab bar, module content, AirDrop drop zone
└── Modules/
    ├── Media/                    MediaRemote bridge, controller, LRCLIB lyrics engine + views
    ├── Calendar/                 EventKit next-24h timeline + meeting-link detection
    ├── Drop/                     DropDelegate + AirDrop sharing service
    └── Telemetry/                host_statistics/host_statistics64 + IOKit battery, gauges
```

### Window architecture

`NotchPanel` is a borderless, transparent, non-activating `NSPanel` at
`NSWindow.Level.statusBar` with `.canJoinAllSpaces` / `.fullScreenAuxiliary`
collection behavior, so the notch UI floats above everything on every Space
without ever stealing focus. The panel is sized for the fully expanded UI and the
SwiftUI content morphs inside it, so expansion never resizes the window (which
keeps the spring animation fully GPU-side).

`NotchGeometry` reads `NSScreen.safeAreaInsets.top` for the exact notch height and
derives the width from the gap between `auxiliaryTopLeftArea` and
`auxiliaryTopRightArea`. Displays without a notch get a simulated 196×32 notch.

### Animation

Every expansion, contraction, tab change, gauge fill, and lyric transition uses the
single shared spring `Animation.notchSpring` —
`.spring(response: 0.35, dampingFraction: 0.65, blendDuration: 0.1)`.
The album art travels between the collapsed wing and the expanded player via
`matchedGeometryEffect`, as does the tab highlight capsule.

### Media & lyrics

System-wide now-playing metadata (any player) comes from the private
**MediaRemote** framework, loaded via `dlopen`/`dlsym` so missing symbols degrade
gracefully instead of crashing. Updates are push-based notifications — zero polling
while collapsed. Where MediaRemote is unavailable (macOS 15.4+ restricted it), the
controller falls back to querying **Music.app over Apple Events**, and only while
the notch is expanded, never in the background.

Synchronized lyrics are fetched from the free [LRCLIB](https://lrclib.net) catalog,
parsed from LRC timestamps, and auto-scrolled with the live line centered and
highlighted. Playback position is extrapolated from the last
elapsed-time/timestamp anchor, so no timer is needed to keep it accurate.

### Zero-impact collapsed state

All periodic work is gated on expansion:

| Module    | Collapsed                    | Expanded                    |
|-----------|------------------------------|-----------------------------|
| Media     | push notifications only      | 0.5 s progress/lyrics tick  |
| Lyrics    | idle                         | driven by media tick        |
| Calendar  | idle                         | one EventKit query on open  |
| Telemetry | idle                         | 2 s sampling timer          |

`NotchState.wakeModules()` / `sleepModules()` are the single choke point.

## Permissions (Info.plist)

| Key | Why |
|-----|-----|
| `NSCalendarsUsageDescription` | Legacy calendar prompt text |
| `NSCalendarsFullAccessUsageDescription` | macOS 14 full-access prompt for the 24 h timeline |
| `NSAppleEventsUsageDescription` | Music.app fallback when MediaRemote is unavailable |
| `NSAppleMusicUsageDescription` | Media metadata / artwork display |
| `LSUIElement` | Agent app — no Dock icon |

Entitlements: `com.apple.security.app-sandbox = NO`,
`com.apple.security.automation.apple-events = YES`,
`com.apple.security.personal-information.calendars = YES`.

## Notes & caveats

- **MediaRemote is a private framework.** This is the same approach used by
  boringNotch and friends; it is fine for personal/side-loaded builds but not
  App Store eligible. MusicKit was not used because it only reports Apple
  Music content and requires a developer token, and `MPNowPlayingInfoCenter`
  on macOS is publisher-side (it cannot read other apps' sessions).
- On **macOS 15.4+** Apple gated the MediaRemote entry points; the app then uses
  the Apple Events fallback (Music.app only) automatically.
- Battery gauges hide themselves on desktop Macs with no `AppleSmartBattery`
  service.
