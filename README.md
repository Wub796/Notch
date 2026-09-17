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
  hover and scroll expansion with tunable delays and hover tolerance, sneak
  peek, live-activity toggles, instant AirDrop, telemetry refresh rate, and
  the real-time audio meter.
- **Live Activities** (Sapphire-inspired) — the collapsed notch grows wings for
  whatever matters right now, by priority: a **volume HUD** (CoreAudio listener)
  when you change the system volume, a **battery event** when you plug/unplug or
  cross 10%, a **lock/unlock moment** ("Welcome back"), a **track sneak peek**
  (boring.notch-style: new tracks marquee their title through the closed notch),
  a **meeting-soon countdown** starting 15 minutes before your next event, and
  otherwise the now-playing artwork + equalizer. Every source is push-based — no
  polling while collapsed.
- **Devices** — two sections behind one nav. *Now* is the player; *Audio*
  holds three output tabs — the apps making sound and their individual levels,
  every CoreAudio output, and the local AirPlay ones. No accounts and no web
  APIs anywhere: everything here is this Mac, read from CoreAudio and driven
  over Apple Events and the hardware media keys.
- **Instant audio detection** — CoreAudio property listeners (`'prs#'`,
  `'piro'`, and `deviceIsRunningSomewhere`) report the moment any process
  starts or stops output, so the Audio screen is current before it is opened
  and the closed notch can wear the cover-and-visualiser wings for a browser
  video or a game. Nothing polls.
- **Real-time visualiser** (opt-in) — with Screen Recording permission the bars
  follow the actual output mix through ScreenCaptureKit, split into three
  bands. Without it they follow the output volume, which is real but static.
- **Click-through** — the panel hands the mouse back to the rest of the system
  everywhere except the notch itself, so the top of the screen stays usable
  while Notch is running.
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
use (media fallback) prompts for **Automation** consent. **Screen Recording** is
optional and only asked for by the real-time audio meter, and **Accessibility**
only if you let the notch replace the system volume and brightness HUDs. Launch-at-login registration
requires a signed build.

## Architecture

```
Notch/
├── App/
│   ├── NotchApp.swift            @main entry and the menu bar item's commands
│   ├── AppDelegate.swift         Screen selection, panel lifecycle, display changes
│   ├── NotchPanel.swift          Borderless non-activating NSPanel @ .statusBar level
│   ├── NotchWindowController.swift  Sizes/anchors the panel top-center on the notch screen
│   ├── OnboardingView.swift      First-launch welcome and permission prompts
│   └── OnboardingWindowController.swift
├── Core/
│   ├── NotchGeometry.swift       Exact notch size from safeAreaInsets + auxiliary areas
│   ├── NotchState.swift          Root @Observable state; per-tab size budgets;
│   │                             wakes/sleeps modules on expand
│   ├── NotchSettings.swift       Preferences (UserDefaults) + SMAppService login item
│   ├── NotchAnimation.swift      Per-gesture timing curves, three selectable profiles
│   ├── NotchTheme.swift          Design tokens and artwork accent extraction
│   ├── IntegrationPermissions.swift  Cached, live authorization status per integration
│   ├── HotKeyManager.swift       Carbon RegisterEventHotKey (no Accessibility needed)
│   └── KeepAwakeController.swift IOKit power assertion toggle
├── Views/
│   ├── NotchShape.swift          Animatable notch silhouette (flared top, curved bottom)
│   ├── NotchContainerView.swift  The morph: fixed-size layers under a growing clip
│   ├── CollapsedNotchView.swift  Live-activity wings around the hardware notch
│   ├── ExpandedNotchView.swift   Top bar / detail headers, module content, drop zone
│   ├── NotchTopBarView.swift     Module rail, battery pill, focus, keep-awake
│   ├── WeatherDetailView.swift   Hero band, hourly and five-day strips
│   ├── CalendarDetailView.swift  Week strip, month grid, day agenda
│   ├── MarqueeText.swift         Scrolling label for overlong titles
│   ├── SettingsWindowController.swift  A real NSWindow — SwiftUI's Settings
│   │                             scene never focuses in an LSUIElement app
│   ├── NotchScreenComponents.swift  The type, radius and spacing scales, the
│   │                             shared card, screen headers and empty states
│   ├── NotchLayoutView.swift     Header strip and module as animating siblings
│   └── SettingsView.swift        Sidebar Settings window
└── Modules/
    ├── Home/                     The dashboard: music, weather, calendar
    ├── Media/                    MediaRemote bridge (info + seek), controller, accent,
    │                             LRCLIB lyrics engine, lyrics + scrubber views
    ├── Weather/                  Open-Meteo current, hourly and daily; optional IP fallback
    ├── Calendar/                 EventKit next-24h timeline + meeting-link detection
    ├── Shelf/                    Drop delegate, shelf controller (AirDrop/copy/reveal), tray UI
    ├── Clipboard/                Opt-in history with pinning
    ├── Notes/                    Autosaving scratchpad
    ├── Tools/                    Audio routing, timer, eye breaks, Shortcuts, quick actions
    ├── Activities/              Volume, power, desktop and focus live activities
    ├── Audio/ Bluetooth/ Display/ Focus/
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

The expansion is boring.notch's and Atoll's, structurally. `NotchLayoutView`
holds the header strip and the module as siblings in one `VStack` and **nothing
sets an explicit width**: closed, the layout's intrinsic width is the hardware
notch plus whatever live activity is showing; open, it is the header and module
pinned to the open panel. Animating `mode` therefore animates a real layout
change between two natural sizes, which is what makes the notch look like it
grows. Animating a fixed frame instead — with both content layers filling it —
re-flows the module on every frame and reads as a dissolve.

Springs are the references' values: `.spring(response: 0.42, dampingFraction: 1)`
opening, `0.45` closing, both critically damped, and `.bouncy.speed(1.2)` on
hover. The module arrives with their `.scale(0.8, anchor: .top)` + opacity
transition. Hovering the closed pill pads its wings outward rather than scaling
a fixed layer.

`NotchShape` carries independent top and bottom radii as an `AnimatablePair` —
closed `(6, 14)`, open `(19, 24)`. A single radius cannot express both a pill
welded to the hardware notch and a soft open panel. The open header's centre is
a black rectangle masked by the notch shape itself, so the hardware notch reads
as continuing through the slab.

### Sizing

Following `sizing/matters.swift` in both references, and the one idea worth
copying above all: **every tab opens to the same panel**. Sizing each screen to
its own content resized the slab on every tab switch, which neither app does.
`NotchSizing.openNotchSize` is user-set, clamped to the display the way Atoll
clamps it, and `NotchState.moduleContentSize` is what is left for a module once
the header and slab insets are taken out. Module views are written to that
budget and say so in their headers.

The one deliberate divergence: the references pad the closed pill horizontally
and compensate by narrowing the camera dead zone by 20pt, which draws content
under the housing. Notch pads only the open slab, so the idle pill is exactly
the notch plus its wings and never overhangs the hardware.

### System HUD

The volume and brightness bar is their `DraggableProgressBar`: a `.tertiary`
track under a gradient capsule oriented trailing-to-leading, thickening from 5
to 8pt while dragged, hidden at zero so muted does not look broken — and
draggable, writing the system value as it moves. `InlineHUD` places it in their
fixed 100pt wings (less 12 when not hovered) either side of the notch dead
zone, so changing digits never shift the glyph.

Driving it is `MediaKeyInterceptor`, ported from theirs: a `CGEvent` tap on
`systemDefined` events (type 14, subtype 8) reads the key from `data1`, acts on
key-down only, applies macOS's own 1/16 step (quartered with Option-Shift), and
returns nil so the system overlay never appears. An event tap needs
Accessibility access, so this is opt-in; with it off the notch falls back to
sampling brightness and macOS keeps drawing its own overlay. With the tap
running, nothing polls — the key press is the event.

### Media & lyrics

System-wide now-playing metadata (any player) comes from the private
**MediaRemote** framework, loaded via `dlopen`/`dlsym` so missing symbols degrade
gracefully instead of crashing — including seeking through
`MRMediaRemoteSetElapsedTime`. Updates are push-based notifications — zero polling
while collapsed.

macOS 15.4 gated those entry points for apps without an entitlement Apple no
longer issues. The failure is quiet: the symbols still resolve and the calls
still succeed, they just return nothing while the console logs
`kMRMediaRemoteFrameworkErrorDomain Code=3 "Operation not permitted"`. So the
controller detects it empirically — three consecutive empty replies received
while Music or Spotify is actually running — and demotes itself to querying that
player over **Apple Events** for the rest of the session, polling only while the
notch is expanded. Players Apple Events cannot reach, browsers included, cannot
be shown at all on those systems; the player says so instead of claiming nothing
is playing.

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

### Collapsed-state cost

Most periodic work is gated on expansion, but not all of it — the closed notch
still shows live activities, and some of those have to be asked for rather than
pushed. What actually runs:

| Module    | Collapsed                                   | Expanded                            |
|-----------|---------------------------------------------|-------------------------------------|
| Media     | MediaRemote push; a 4 s poll only on the Apple Events fallback | 0.1 s progress tick, 1 s browser probe |
| Lyrics    | 0.1 s tick, only while the lyric activity is on and something is playing | driven by the media tick |
| Playback reconcile | 15 s (catches a pause the notch was not told about) | 2 s |
| Calendar  | idle                                        | one EventKit query on open          |
| Telemetry | idle                                        | 1–5 s sampling timer (configurable) |
| Shelf     | idle                                        | resolves drops on demand            |
| Clipboard | 1 s pasteboard poll while history is on (macOS has no change notification) | same |
| Hover probe | 60 Hz cursor sample                       | stopped — SwiftUI owns hover        |
| Audio meter | 20 Hz, only while the real-time visualiser is on and audio is playing | same |

`NotchState.wakeModules()` / `sleepModules()` are the choke point for the
expansion-gated half; `MediaController.setActive(_:)` is the choke point for
the media timers.

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
- On **macOS 15.4+** Apple gated the MediaRemote entry points. The app detects
  this at runtime and falls back to Apple Events, which reaches the selected
  player (Music or Spotify) and nothing else — a browser playing audio cannot
  be read on those systems by any available API.
- **Spotify Canvas was retired.** It played the looping video Spotify shows
  behind a track. Canvas has no public API, so the app did what every
  third-party client did: sign in through Spotify's own web login, keep the
  `sp_dc` session cookie, and exchange it for a web-player token. Spotify has
  since closed that door — `open.spotify.com/get_access_token` now answers
  **403 "URL Blocked"** to every request shape, cookie or not, and the web
  player's replacement (`/api/token`, which needs a TOTP generated from a
  secret embedded in their own bundle) states outright that third-party use is
  not permitted. The feature, its sign-in window and the stored cookie are
  gone rather than left looking half-working; the implementation is in this
  file's history under `Notch/Modules/SpotifyCanvas/`. The notch still shows
  the album art it always had.
- Battery gauges hide themselves on desktop Macs with no `AppleSmartBattery`
  service; network throughput sums the `en*` interfaces.
- Telemetry refresh-rate changes apply the next time the notch opens.
