# Notch

<div align="center">

```text
  ███╗   ██╗ ██████╗ ████████╗ ██████╗██╗  ██╗
  ████╗  ██║██╔═══██╗╚══██╔══╝██╔════╝██║  ██║
  ██╔██╗ ██║██║   ██║   ██║   ██║     ███████║
  ██║╚██╗██║██║   ██║   ██║   ██║     ██╔══██║
  ██║ ╚████║╚██████╔╝   ██║   ╚██████╗██║  ██║
  ╚═╝  ╚═══╝ ╚═════╝    ╚═╝    ╚═════╝╚═╝  ╚═╝
```

### The fluid, interactive workspace for your Mac's notch.

[![macOS 14.0+](https://img.shields.io/badge/macOS-14.0%2B-black?style=flat-square&logo=apple&logoColor=white)](https://www.apple.com/macos)
[![Swift 6](https://img.shields.io/badge/Swift-6.0-F05138?style=flat-square&logo=swift&logoColor=white)](https://swift.org)
[![Xcode 16+](https://img.shields.io/badge/Xcode-16%2B-1575F9?style=flat-square&logo=xcode&logoColor=white)](https://developer.apple.com/xcode)
[![License](https://img.shields.io/badge/License-MIT%20%2F%20Notices-blue?style=flat-square)](THIRD-PARTY-NOTICES.md)
[![Architecture](https://img.shields.io/badge/Architecture-Apple%20Silicon%20%7C%20Intel-8A2BE2?style=flat-square)]()

</div>

---

```text
+-----------------------------------------------------------------------------------+
|  Finder  File  Edit  View         ╭───────────────╮        Tue 9:41 AM   (•) 94%  |
|                                   │  •  ~ :|: 94% │  <-- Hardware Notch Cutout    |
| ──────────────────────────────────┴─╮           ╭─┴────────────────────────────── |
|                                     │   HOVER   │                                 |
|                                     v  or CLICK v                                 |
|   ╭───────────────────────────────────────────────────────────────────────────╮   |
|   │ ♫ Starboy - The Weeknd                  [|<]  [ || ]  [>|]       [P]  [X] │   |
|   │ =========================o============================= 02:14 / 03:50     │   |
|   │ ───────────────────────────────────────────────────────────────────────── │   |
|   │  [Audio Mixer]    [Shelf]         [Calendar]      [Telemetry]     [Tools] │   |
|   │                                                                           │   |
|   │  Spotify      ====o===== 70%   |  Drop files here to stash, AirDrop,      │   |
|   │  Safari       ======o=== 90%   |  or share across apps seamlessly.        │   |
|   │  Podcasts     ==o======= 40%   |                                          │   |
|   ╰───────────────────────────────────────────────────────────────────────────╯   |
|                                                                                   |
+-----------------------------------------------------------------------------------+
```

**Notch** transforms the dead screen space around your MacBook's camera cutout—or creates a simulated island on any external monitor—into a fluid, spring-animated, interactive workspace.

Hover to peek at what's playing, check the weather, or monitor live activities. Click to pin the workspace open for deep control: mix volume per app up to 400%, stash files into a drag-and-drop shelf, monitor system telemetry, or unlock your Mac with your face.

Built natively in Swift and SwiftUI with custom continuous-corner geometry (`NotchShape`), Notch runs discreetly in your menu bar with **zero Dock clutter** and **zero idle CPU wakeups**.

---

## 🧭 At a Glance

| Module | What It Does |
| :--- | :--- |
| **🎛️ Per-App Audio Mixer** | Independent volume sliders (up to 400% boost with soft clipping), output routing, 10-band EQ, AutoEQ profile import, and DDC external monitor speaker control. |
| **🎵 Now Playing & Spectrum** | Apple Music & Spotify playback, live lyrics, album art, plus a real-time **3-band hardware frequency meter** on the closed notch. |
| **👤 Face ID Unlock** | Biometric face unlock on lock screen and wake using on-device ML with liveness checks, encrypted behind Touch ID in Keychain. |
| **📁 Drop Shelf** | Temporary stash for files, images, and text snippets. Drag in from anywhere; drag out, AirDrop, or Quick Look. |
| **⏱️ Live Activities & Timers** | Dynamic HUD pills for volume, brightness, battery charging, focus modes, plus native sync with macOS Clock & Siri timers. |
| **📊 Telemetry & System Gauges** | Real-time CPU usage, memory pressure, battery health, and network throughput at a glance. |
| **📅 Calendar & Weather** | Hourly and 5-day weather forecasts with automatic geolocation; week-at-a-glance agenda with one-click meeting links. |
| **🧰 Tools & Notes** | Instant scratchpad notes, clipboard history manager, timers, stopwatch, and a pre-call camera framing mirror. |
| **🖥️ Simulated Notch** | Seamlessly supports MacBooks without a physical notch, Mac mini, Mac Studio, and multi-monitor setups. |

---

## ⚡ Interaction & Gestures

```text
       Hover                    Click                      Escape
  ╭──────────────╮       ╭──────────────────╮       ╭────────────────╮
  │     PEEK     │  ──►  │    PIN OPEN      │  ──►  │    DISMISS     │
  │ Quick status │       │ Interactive work │       │ Instant close  │
  ╰──────────────╯       ╰──────────────────╯       ╰────────────────╯
```

- **Hover over the Notch** — Temporarily peeks open the workspace. Move your cursor away and it smoothly contracts back into the notch bezel.
- **Click to Pin (📌)** — Pins the workspace open so it stays in place while you tweak sliders, organize files, or inspect calendars. Click the pin icon in the rail or detail headers to return to hover mode.
- **Press `Esc`** — Instantly dismisses the open panel whenever it has keyboard focus.
- **Drag & Drop** — Drag any file, URL, or image snippet toward the top center of your display to immediately reveal the Shelf drop zone.
- **Global Hotkey** — Configure a custom keyboard shortcut in **Settings → Notch** to toggle the panel from anywhere without touching the mouse.
- **Fluid Spring Physics** — All transitions utilize critically damped springs (`response: 0.34s`) and Apple continuous corners (`NotchShape`). If system **Reduce Motion** is enabled, motion gracefully shifts to subtle opacity fades.

---

## 🎛️ Per-App Audio Mixer

The Audio Mixer rewrites sound on a per-application basis rather than altering the entire system output:

```text
 [Spotify]    ──────●──────────  80%     [EQ: Harman]   [Route: AirPods Max]
 [Safari]     ───────────●───── 125%     [Boost +2dB]   [Route: Studio Display]
 [Discord]    ────●────────────  50%     [Mute]         [Route: Built-in]
 [Display]    ───────●─────────  75%     (DDC/CI hardware control channel)
```

- **0% to 400% Volume (+12 dB Boost)**: Push quiet streams or podcasts well past macOS limits. Soft-knee clipping above unity ensures boosted tracks saturate gracefully instead of creating harsh digital distortion.
- **Per-App Routing & Mute**: Route music to external speakers while keeping Discord or Zoom pinned to your headphones.
- **10-Band Parametric EQ**: Apply fine-grained equalization per app with built-in curves (Bass Boost, Acoustic, Vocal, Flat, etc.).
- **AutoEQ Headphone Correction**: Import measured correction profiles for thousands of headphone models from [AutoEQ](https://github.com/jaakkopasanen/AutoEq). Files are stored as standard profiles in `~/Library/Application Support/Notch/AutoEQ` and can be edited or backed up anytime.
- **Dynamic Loudness Compensation**: Automatically preserves low-end bass response as you lower playback volume according to psychoacoustic curves.
- **DDC/CI External Monitor Control**: Controls speakers inside external monitors over the display's hardware DDC/CI control channel—driving hardware that macOS itself cannot adjust natively.
- **Siri & Shortcuts Integration**: Control app volume, mute, EQ profiles, and display volume directly via the macOS Shortcuts app, Siri, or keyboard macros.
- **Non-Destructive CoreAudio Tap**: Utilizes CoreAudio Process Taps (`AudioHardwareCreateProcessTap`, macOS 14.2+). An app's audio path is **only** tapped when you adjust its slider; resetting the strip instantly detaches the tap and returns native audio handling.

---

## 🎵 Now Playing & 3-Band Spectrum Meter

### Real-Time Hardware Spectrum
When music is playing, the closed notch features a hardware-style three-band visualizer right beside the camera cutout:

```text
           ╭────────────────────────────────────────╮
           │   •   ♫ Starboy    ▂ ▃ ▅    ⚡ 94%     │
           ╰────────────────────▲─▲─▲───────────────╯
                                │ │ │
                                │ │ └── High (Cymbals, Air)
                                │ └──── Mid  (Vocals, Keys)
                                └────── Low  (Kick, Bass)
```

- **True Measured Energy**: Each bar maps to real frequency bands (Low, Mid, High) calculated via in-memory FFT analysis of the live audio mix. A bass kick fills the left bar; hi-hats and cymbals light up the right.
- **Privacy Guaranteed**: Audio samples are processed strictly in volatile memory for FFT visualization and are **never recorded, cached, or written to disk**. Requires macOS 14.2+ and system Audio Capture permission. When inactive, the visualizer remains cleanly idle.

---

## 👤 Face ID Unlock for Mac

Notch brings seamless biometric face unlock to macOS lock and wake screens, ported from Jonathan Zhou's [Glance](https://github.com/jonnyoo/glance):

```text
 ┌────────────────────────────────────────────────────────┐
 │                      MAC LOCK SCREEN                   │
 │                                                        │
 │                   ╭──────────────────╮                 │
 │                   │  (•)  Scanning…  │                 │
 │                   ╰────────┬─────────╯                 │
 │                            │                           │
 │               On-Device ArcFace Embedding              │
 │                            │                           │
 │                    Liveness Verification               │
 │               (Rejects static photos/screens)          │
 │                            │                           │
 │             Touch ID Keychain Session Key (256-bit)    │
 │                            │                           │
 │           Synthesized Keystroke Authentication         │
 │                            ▼                           │
 │                      [ Mac Unlocked ]                  │
 └────────────────────────────────────────────────────────┘
```

> [!IMPORTANT]
> **Face ID is disabled by default.** Please read the security model below before turning it on in Settings.

### Security Model & Honest Disclosures
- **No TrueDepth Camera**: MacBooks lack infrared dot projectors and structured-light depth sensors. Notch uses on-device computer vision and liveness detection: printed photos and phone screen images are rejected with high confidence, but a high-resolution video of your face may not be reliably rejected. Treat this feature as an **ergonomic convenience**, not a high-assurance biometric barrier.
- **Synthesized Keystrokes**: Because macOS provides no public API for third-party apps to authorize a login session, Face ID functions by securely typing your stored password into the login window's password field. This requires the **Accessibility** permission.
- **Hardware-Backed Encryption**: Your password is encrypted with AES-256 using a key stored in the macOS Keychain behind **Touch ID**. Face identities are stored as 512-dimensional vector embeddings—never raw camera images. The session key is held in memory only while authorized, and re-locks automatically after an idle interval you define.

---

## 📁 Drop Shelf

Need to move a screenshot, PDF, or text snippet between spaces, full-screen apps, or windows?

1. **Drag** any item up to the notch.
2. The notch expands into the **Shelf** drop target.
3. **Drop** items onto the shelf to stash them.
4. **Retrieve** later: drag them out into Slack, Mail, Finder, preview them with Spacebar (Quick Look), or trigger native **AirDrop** with one click.

---

## ⏱️ Live Activities & Siri / Clock Timers

Notch hosts compact live activities that inform you without stealing focus:
- **Audio HUD & Brightness**: Sleek, modern replacements for the oversized legacy system volume and display brightness overlays.
- **Battery & Power Alerts**: Charging status, time remaining, and low-battery warnings.
- **Focus & Meeting Alerts**: Upcoming calendar notifications with one-tap Google Meet / Zoom launch buttons.
- **Siri & macOS Clock Timers**: Turn on **Settings → Activities → All Live Activities → Clock Timers** to mirror active and paused timers created in the native macOS Clock app or started hands-free with Siri.

> [!NOTE]
> On modern macOS releases that protect Clock's database, timer mirroring requires **Full Disk Access** in System Settings. Notch reads the timer store locally and never modifies, cancels, or transmits your timer data.

---

## 📊 System Telemetry, Weather & Tools

- **Hardware Telemetry**: Keep an eye on system health without opening Activity Monitor: per-core CPU usage, RAM pressure, battery cycles, and active network upload/download bandwidth.
- **Weather Station**: Real-time conditions, precipitation chances, hourly forecast curve, and 5-day outlook with automatic location lookup.
- **Calendar & Agenda**: Week-at-a-glance calendar detail view with calendar color-coding and direct video conference links.
- **Camera Mirror**: A one-click live mirror centered inside the notch to verify your lighting, framing, and hair before jumping into a meeting.
- **Notes & Clipboard**: Quick scratchpad for temporary notes and a multi-item clipboard history buffer.

---

## 💻 System Requirements & Compatibility

| Feature | macOS 14.0 – 14.1 | macOS 14.2+ (Recommended) |
| :--- | :---: | :---: |
| **Expanded Island & Workspace** | ✅ Supported | ✅ Supported |
| **Media Player & Controls** | ✅ Supported | ✅ Supported |
| **Drop Shelf & Telemetry** | ✅ Supported | ✅ Supported |
| **Calendar, Weather, Notes, Tools** | ✅ Supported | ✅ Supported |
| **Face ID Unlock** | ✅ Supported | ✅ Supported |
| **Per-App Audio Mixer** | ⚠️ Unavailable* | ✅ Supported (CoreAudio Tap) |
| **Real-Time 3-Band Spectrum** | ⚠️ Idle* | ✅ Supported (In-Memory FFT) |

*\*CoreAudio Process Taps were introduced in macOS 14.2. On macOS 14.0 and 14.1, Notch cleanly disables process-tapping features while keeping all other modules fully active.*

- **Displays**: Native support for MacBook Air and MacBook Pro physical notch displays, external monitors, and non-notch Macs via **Simulated Notch Mode**.
- **Architecture**: Universal binary (Apple Silicon M1/M2/M3/M4 & Intel x86_64).

---

## 📦 Installation

### Download DMG
1. Download the latest `Notch-<version>.dmg` from the [Releases](https://github.com/Wub796/Notch/releases) page.
2. Open the downloaded `.dmg`.
3. Drag **Notch.app** into your **Applications** folder.
4. Eject the disk image and launch Notch from Applications.
5. If macOS prompts that the app was downloaded from the Internet, click **Open**.

### First-Launch Onboarding
On your first launch, an interactive welcome window introduces you to the notch gestures and walks through optional permissions:
- Every permission is **optional**: click **Not now** or press **Skip the rest** (`⇧⌘S`) to jump straight to the summary.
- The onboarding flow respects **Reduce Motion** (replaces slide sweeps with fades) and guards against accidental double-clicks.

---

## 🛡️ Privacy & Permissions

Notch is engineered with a strict **local-first, privacy-by-design** philosophy. No telemetry, no analytics, no external trackers, and zero network calls beyond live weather queries.

Permissions are requested only when you actively enable features that depend on them:

| Permission | Why It's Needed | Privacy Guarantee |
| :--- | :--- | :--- |
| **Calendar** | Shows upcoming events and agenda. | Read locally; never transmitted. |
| **Location** | Fetches local weather conditions and hourly forecasts. | Used solely for WeatherKit / weather queries. |
| **Automation** | Reads track info and controls Apple Music and Spotify. | AppleScript events restricted to music players. |
| **Audio Capture** | Powers the Per-App Mixer tap and real-time 3-band FFT spectrum. | Measured in volatile memory; **never** recorded or saved. |
| **Accessibility** | Enables HUD replacement and lock-screen Face ID password typing. | Required to synthesize login keystrokes. |
| **Full Disk Access** | *(Optional)* Mirrors native Siri and Clock app timers. | Read-only access to local Clock database; zero data egress. |

Manage or revoke permissions anytime in **Settings → Privacy** or **System Settings → Privacy & Security**.

---

## ⚙️ Settings & Customization

Inspired by [Glance](https://github.com/jonnyoo/glance), Notch features a unified settings window with progressive header blurs, continuous corner cards, and a floating pill tab bar:

- **Notch**: Toggle physical vs. simulated notch, adjust dimensions, set hover sensitivity, and assign global hotkeys.
- **Audio & Mixer**: Manage default audio output devices, equalizer curves, AutoEQ imports, and DDC display volume.
- **Activities**: Toggle live HUD replacements, timer mirroring, and battery notifications.
- **Face ID**: Configure biometric thresholds, liveness detection strictness, idle re-lock timeouts, and enrolled identities.
- **Dashboard & Widgets**: Reorder, show, or hide tabs (Shelf, Telemetry, Weather, Calendar, Notes, Tools).

---

## 🔄 Updating Notch

Notch includes integrated update checking powered by [Sparkle](https://sparkle-project.org/):
- Notch automatically checks for signed, notarized updates in the background.
- To check manually:
  - Click the Notch menu bar item → **Check for Updates…**
  - Or open **Settings → About → Check for Updates…**

---

## 🧹 Clean Uninstallation

1. Quit Notch from the menu bar menu.
2. Drag **Notch.app** from Applications to the Trash.
3. *(Optional)* To erase all saved application preferences, run:
   ```bash
   defaults delete com.notchapp.Notch
   ```
4. *(Optional)* If you enrolled in Face ID, remove your encrypted credentials and face templates:
   ```bash
   security delete-generic-password -s com.notchapp.Notch.faceID
   rm -f "$HOME/Library/Application Support/Notch/face-identities.enc"
   ```

---

## 🛠️ Building from Source

### Prerequisites
- macOS 14.0 or later
- [Xcode 16.0+](https://developer.apple.com/xcode) or later with Swift 6 support

### Build Steps
1. Clone the repository:
   ```bash
   git clone https://github.com/Wub796/Notch.git
   cd Notch
   ```
2. Open the project in Xcode:
   ```bash
   open Notch.xcodeproj
   ```
3. In Xcode, navigate to the **Notch** target signing settings and select your Apple Developer team.
4. Select the **Notch** scheme and press **⌘B** to build or **⌘R** to run.

> [!NOTE]
> An Apple Developer ID signed and notarized build is required for login items, keychain access groups, and automated Sparkle updates to function in production.

---

## 📜 Third-Party Notices & Attribution

Notch builds upon outstanding open-source projects:

- **[Glance](https://github.com/jonnyoo/glance)** (*MIT © 2026 Jonathan Zhou*):
  Face ID detection, ArcFace embedding pipeline, liveness heuristics, lock-screen monitor, and the Settings window chrome.
- **[InsightFace](https://github.com/deepinsight/insightface)**:
  Pretrained ArcFace `w600k_mbf` weights utilized by the Face ID module (`ArcFace.mlpackage`), distributed under InsightFace's research/non-commercial license.
- **[FineTune](https://github.com/ronitsingh10/FineTune)** (*GPL-3.0 © Ronit Singh*):
  Design inspiration for the per-app audio mixer architecture. Notch contains a clean-room implementation written directly against public CoreAudio process tap interfaces, sharing no code or assets.
- **[AutoEQ](https://github.com/jaakkopasanen/AutoEq)** (*MIT © Jaakko Pasanen*):
  Headphone compensation curve format and profile dataset definitions.
- **[Lakr233/SkyLightWindow](https://github.com/Lakr233/SkyLightWindow)** (*MIT © Lakr Aream*):
  SkyLight window-server integration for displaying panels over the macOS lock screen.

Full licensing details and disclosures are documented in [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

---

<div align="center">
<sub>Crafted with precision for macOS. Enjoy your notch.</sub>
</div>
