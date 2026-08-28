# Notch

A native macOS notch-extending utility in the spirit of **Sapphire** and **boringNotch**.
Hover (or click) the notch and it springs open into a liquid-glass hub with media +
live lyrics, a file shelf, your next 24 hours of events, and hardware telemetry.

- **Target:** macOS 14.0+ (Apple Silicon optimized)
- **Stack:** SwiftUI + AppKit, `@Observable` (Observation framework), EventKit, IOKit, Mach host statistics, ServiceManagement
- **Xcode:** 16.0 or newer (project uses file-system-synchronized groups)

## Features

- **Home dashboard** (default tab, modeled on the reference demo) — now
  playing with inline transport and a badge showing which app the audio comes
  from, weather (icon, temperature, city, condition), and today's date + next
  event. One clean slab: no dividers, no boxes, no centered controls.
- **Flanking icon strip** — tabs and settings sit to the left of the hardware
  notch, battery / keep-awake / pin to the right, borderless. They appear as
  the slab opens and collapse away with it.
- **Tight hover target** — hit testing while closed is limited to the notch
  itself, so the panel only reacts when the pointer is actually on it, and a
  dwell requirement means sweeping past never opens it.
- **Lyric live activity** — while music plays, the *closed* notch grows a slim
  bar showing the current synced lyric line in the artwork accent.
- **Pin** — a header pin holds the panel open, ignoring hover-out and outside
  clicks until unpinned or closed.
- **Media hub** — system-wide now-playing (any player) with artwork, a seekable
  scrubber, transport controls, and LRCLIB-synchronized lyrics that auto-scroll;
  tap a lyric line to jump there. The whole tab is tinted by an accent color
  extracted from the album artwork, with an ambient glow behind the player.
- **Shelf** — drop files (or text) onto the notch and they land on a Dropover-style
  shelf: drag them back out, AirDrop one or all, copy, reveal in Finder, or clear.
  An optional instant mode AirDrops drops immediately instead.
- **Schedule** — EventKit timeline of the next 24 h with "Now" and live-countdown
  chips and one-click Join buttons for Zoom / Teams / Meet / Webex links.
- **System** — CPU gauge with rolling sparkline, memory pressure, battery
  wattage + health, and live network up/down throughput.
- **Header** — clock + date, battery pill, a caffeine-style **keep-awake** toggle
  (IOKit power assertion), and a gear that opens Settings.
- **Settings** — a native tabbed preferences window (General / Notch / Media /
  Activities / System / About): launch at login (SMAppService), animation style,
  hover and scroll expansion with tunable delays, haptics, sneak peek, idle
  face, live-activity toggles, instant AirDrop, telemetry refresh rate.
- **Live Activities** (Sapphire-inspired) — the collapsed notch grows wings for
  whatever matters right now, by priority: a **volume HUD** (CoreAudio listener)
  when you change the system volume, a **battery event** when you plug/unplug or
  cross 10%, a **lock/unlock moment** ("Welcome back"), a **track sneak peek**
  (boring.notch-style: new tracks marquee their title through the closed notch),
  a **meeting-soon countdown** starting 15 minutes before your next event, and
  otherwise the now-playing artwork + equalizer. Every source is push-based — no
  polling while collapsed.
- **Idle face** — an homage to boring.notch's animated face: a tiny blinking
  companion in the wing when nothing else is happening (PhaseAnimator, no
  timers; still under Reduce Motion; toggleable).
- **Scroll gesture** (DynamicNotch-style) — a two-finger scroll over the closed
  notch springs it open.
- **Hover peek** — hovering scales the closed pill 1.10× (Sapphire's signature
  affordance) before a click or hover-linger springs it fully open; corner radii
  step 10 → 18 → 32 with the state.
- **Weather** — current conditions chip in the header via keyless Open-Meteo with
  reduced-accuracy location, cached 30 minutes, fetched only on expand.
- **Animation profiles** — Snappy / Bouncy / Calm personalities with distinct
  springs per gesture (overshooting expand, hard-settling collapse, quick hover,
  fully damped content), adapted from Sapphire's animation tables.
- Haptic feedback (trackpads) on expand/collapse, drops, and the keep-awake toggle.

## First launch

A one-time welcome window introduces the features and gestures and offers the
two optional permission grants (Calendar, Location for weather). Hover the
notch to peek, click or scroll to open, drop files to shelve them, click
anywhere outside to close.

## Building

1. Open `Notch.xcodeproj` in Xcode 16+.
2. Select your signing team (Signing & Capabilities → Team). The app is not sandboxed
   and enables Hardened Runtime with the Apple Events entitlement.
3. Build & run. The app is an agent (`LSUIElement`) — it appears only as the notch
   overlay and a menu bar item (settings / quit).

On first expansion macOS will prompt for **Calendars** access; the first Apple Events
use (media fallback) prompts for **Automation** consent. Launch-at-login registration
requires a signed build.

## Architecture

```
Notch/
├── App/
│   ├── NotchApp.swift            @main entry, menu bar extra, Settings scene
│   ├── AppDelegate.swift         Screen selection, panel lifecycle, display changes
│   ├── NotchPanel.swift          Borderless non-activating NSPanel @ .statusBar level
│   └── NotchWindowController.swift  Sizes/anchors the panel top-center on the notch screen
├── Core/
│   ├── NotchGeometry.swift       Exact notch size from safeAreaInsets + auxiliary areas
│   ├── NotchState.swift          Root @Observable state; wakes/sleeps modules on expand
│   ├── NotchSettings.swift       Preferences (UserDefaults) + SMAppService login item
│   ├── NotchAnimation.swift      The shared spring: response 0.35, damping 0.65, blend 0.1
│   ├── NotchTheme.swift          Design tokens, artwork accent extraction, haptics,
│   │                             micro-interactions, glass transition
│   └── KeepAwakeController.swift IOKit power assertion toggle
├── Views/
│   ├── NotchShape.swift          Animatable notch silhouette (flared top, curved bottom)
│   ├── NotchContainerView.swift  Morphing body: black ↔ ultraThinMaterial glass + rim light
│   ├── CollapsedNotchView.swift  Media wings: mini artwork + accent equalizer
│   ├── ExpandedNotchView.swift   Header, badged tab bar, module content, drop zone, glow
│   ├── NotchHeaderView.swift     Clock/date, battery pill, keep-awake, settings gear
│   └── SettingsView.swift        Grouped-form Settings window
└── Modules/
    ├── Media/                    MediaRemote bridge (info + seek), controller, accent,
    │                             LRCLIB lyrics engine, player + lyrics views
    ├── Calendar/                 EventKit next-24h timeline + meeting-link detection
    ├── Shelf/                    Drop delegate, shelf controller (AirDrop/copy/reveal), tray UI
    └── Telemetry/                host_statistics/host_statistics64, getifaddrs network
                                  throughput, IOKit battery; gauges + sparkline + stat tiles
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

### Animation & feel

Every expansion, contraction, tab change, gauge fill, and lyric transition uses the
single shared spring `Animation.notchSpring` —
`.spring(response: 0.35, dampingFraction: 0.65, blendDuration: 0.1)`.
The album art travels between the collapsed wing and the expanded player via
`matchedGeometryEffect`; tab content swaps through a custom blur+fade "glass"
transition; buttons compress on press and lift on hover; numeric readouts roll
with `.numericText()` content transitions; NSHapticFeedback punctuates expansion,
drops, and toggles.

### Media & lyrics

System-wide now-playing metadata (any player) comes from the private
**MediaRemote** framework, loaded via `dlopen`/`dlsym` so missing symbols degrade
gracefully instead of crashing — including seeking through
`MRMediaRemoteSetElapsedTime`. Updates are push-based notifications — zero polling
while collapsed. Where MediaRemote is unavailable (macOS 15.4+ restricted it), the
controller falls back to querying **Music.app over Apple Events**, and only while
the notch is expanded, never in the background.

The artwork accent is a `CIAreaAverage` of the album art pushed into a
saturation/brightness band that stays legible on black glass, computed off the
main thread once per unique image.

### Telemetry palette

The four metric colors (CPU `#EA580C`, memory `#8B5CF6`, battery `#059669`,
network `#0284C7`) are validated against the dark glass surface for lightness
band, chroma, color-vision-deficiency separation, and 3:1 contrast. Every metric
is identified by icon + direct label — never color alone — and values wear
white/secondary ink, not series colors.

### Accessibility & HIG conformance

The UI was audited against the Apple Human Interface Guidelines (macOS) and the
ui-ux-pro-max design ruleset:

- **Reduce Motion** collapses every spring to a short ease and freezes the
  equalizer; auto-animating content never pulses under the setting.
- **Contrast**: ink tokens keep normal text ≥ 4.5:1 on the black glass
  (muted ink is 47% white ≈ 4.8:1); no text below 9pt.
- **VoiceOver**: every icon-only control has an accessibility label; gauges,
  stat tiles, the scrubber, and the battery pill announce label + value as
  single elements; decorative artwork/equalizer/sparkline are hidden.
- **Menu bar commands** (HIG): open/close notch (⌥⌘N), play/pause (⌥⌘P),
  next/previous track, keep-awake toggle, AirDrop shelf — all functional
  without touching the notch, with disabled states when inapplicable.
- **Motion**: tab content exits with a plain fade and enters with the glass
  settle (exit faster than enter); transport controls dim and disable when
  no track is loaded.
- **Personalization** (HIG): the notch reopens on the last-used tab; hover
  delays, modules, and behaviors are configurable in Settings.
- Actionable empty states: calendar-denied links straight to
  Privacy & Security → Calendars.

### Zero-impact collapsed state

All periodic work is gated on expansion:

| Module    | Collapsed               | Expanded                          |
|-----------|-------------------------|-----------------------------------|
| Media     | push notifications only | 0.5 s progress/lyrics tick        |
| Lyrics    | idle                    | driven by media tick              |
| Calendar  | idle                    | one EventKit query on open        |
| Telemetry | idle                    | 1–5 s sampling timer (configurable) |
| Shelf     | idle                    | resolves drops on demand          |

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

## Sapphire feature parity

Modules ported from [Sapphire](https://github.com/cshariq/Sapphire), rebuilt on
public APIs:

| Sapphire module | Status here |
|---|---|
| Notch shape, states, animation profiles | ✅ |
| Music + synced lyrics + lyric live activity | ✅ |
| Weather | ✅ Open-Meteo, reduced-accuracy location |
| Calendar + meeting links | ✅ |
| Battery / stats / energy | ✅ CPU, memory, battery, network |
| File shelf + AirDrop | ✅ with Quick Look thumbnails |
| Caffeinate (keep awake) | ✅ IOKit power assertion |
| Clipboard manager | ✅ history, pinning, paste-back |
| Notes | ✅ autosaving scratchpad |
| Timer | ✅ with countdown live activity |
| Eye break (20-20-20) | ✅ |
| Focus mode detection | ✅ reads the DND database |
| Bluetooth accessory battery | ✅ AirPods / mouse / keyboard via IORegistry |
| Audio device switching | ✅ CoreAudio output picker |
| Shortcuts runner | ✅ via the `shortcuts` CLI |
| Desktop (Space) change | ✅ |
| Volume / lock / sneak-peek HUDs | ✅ |
| Nearby Share (NearDrop) | ❌ requires reimplementing Google's Quick Share protobuf protocol |
| Launchpad replacement | ❌ separate full-screen app surface |
| Lock screen replacement | ❌ private window levels + login-session hooks |
| Menu bar management (spacing/hiding) | ❌ needs Accessibility control of the system menu bar |
| Snap zones / window tiling | ❌ needs Accessibility API window control |
| Multi-audio / per-app EQ | ❌ needs an audio HAL plugin |
| DDC display / brightness control | ❌ needs I²C display access |
| Face ID unlock | ❌ camera + biometric surface |
| Gemini AI / Circle to Search | ❌ third-party AI service and API keys |
| Sports / Finance widgets | ❌ (stubs in Sapphire too) |

The unported items all need a privileged helper, a private framework, or a
third-party service — deliberate omissions, not oversights.

## Monetization scaffold

Settings → Pro contains a pricing pane (Free vs. Pro cards with a gradient
CTA, styled after the reference) backed by `LicenseManager`: license keys in
the `NOTCH-XXXX-XXXX-XXXX` format are validated **locally only** and persist
in defaults. Before selling, point `LicenseManager.purchaseURL` at your store
and replace `validate(_:)` with a real backend check (Paddle, Lemon Squeezy,
or your own). No current features are gated — `isPro` is the hook for future
pro-only modules.

## Shipping checklist

To distribute outside the App Store (the MediaRemote dependency rules the App
Store out):

1. Archive in Xcode with your Developer ID Application certificate
   (Hardened Runtime is already enabled; the Apple Events entitlement is set).
2. Notarize: `xcrun notarytool submit Notch.zip --keychain-profile <profile> --wait`
   then `xcrun stapler staple Notch.app`.
3. Launch-at-login (SMAppService) and Apple Events consent only behave
   correctly in signed builds.
4. The app icon lives in `Notch/Assets.xcassets/AppIcon.appiconset`
   (generated artwork — replace with final brand art at the same sizes if
   desired).

## Notes & caveats

- **MediaRemote is a private framework.** This is the same approach used by
  boringNotch and friends; it is fine for personal/side-loaded builds but not
  App Store eligible. MusicKit was not used because it only reports Apple
  Music content and requires a developer token, and `MPNowPlayingInfoCenter`
  on macOS is publisher-side (it cannot read other apps' sessions).
- On **macOS 15.4+** Apple gated the MediaRemote entry points; the app then uses
  the Apple Events fallback (Music.app only) automatically.
- Battery gauges hide themselves on desktop Macs with no `AppleSmartBattery`
  service; network throughput sums the `en*` interfaces.
- Telemetry refresh-rate changes apply the next time the notch opens.
