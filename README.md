```text
  ███╗   ██╗ ██████╗ ████████╗ ██████╗██╗  ██╗
  ████╗  ██║██╔═══██╗╚══██╔══╝██╔════╝██║  ██║
  ██╔██╗ ██║██║   ██║   ██║   ██║     ███████║
  ██║╚██╗██║██║   ██║   ██║   ██║     ██╔══██║
  ██║ ╚████║╚██████╔╝   ██║   ╚██████╗██║  ██║
  ╚═╝  ╚═══╝ ╚═════╝    ╚═╝    ╚═════╝╚═╝  ╚═╝
```

```text
 ┌──────────────────────────────────────────────────────────────┐
 │  Finder  File  Edit  View      ╭────────────╮    Tue 9:41 AM │
 │                                │  •  ♫ ▂▃▅  │                │
 │ ───────────────────────────────┴─╮        ╭─┴─────────────── │
 │                                  │  PEEK  │                  │
 │                                  ▼   or   ▼                  │
 │                                    PIN [P]                   │
 │ ╭──────────────────────────────────────────────────────────╮ │
 │ │  Starboy - The Weeknd                   [|<]  [||]  [>|] │ │
 │ │  ------------------------o------------- 02:14 / 03:50    │ │
 │ │ ──────────────────────────────────────────────────────── │ │
 │ │  Mixer       Shelf       Calendar       Stats      Tools │ │
 │ │                                                          │ │
 │ │  Spotify     ====o==== 70%  |  Drop files here to stash  │ │
 │ │  Safari      ======o== 90%  |  or AirDrop to anyone.     │ │
 │ ╰──────────────────────────────────────────────────────────╯ │
 └──────────────────────────────────────────────────────────────┘
```

A native macOS menu bar utility that turns the area around your camera notch into an interactive workspace.

Hover to peek at media, weather, or live activities; click to pin the panel open; press Escape to put it away. When closed, it stays completely idle—no background audio polling, no periodic timers, and no Dock icon.

---

## Quick start

### 1. Download and install
1. Download the latest `Notch.zip` (or `Notch-<version>.zip`) from the [Releases](https://github.com/Wub796/Notch/releases) page.
2. Unzip the downloaded file to extract **Notch.app**.
3. Move **Notch.app** into your `/Applications` folder.
4. Open **Notch** from Applications.
5. If macOS asks to confirm opening an app downloaded from the Internet, click **Open**.

### 2. First launch
On first launch, a welcome guide introduces the gestures and walks through optional permissions.
- Every permission is optional: click **Not now** or press **Skip the rest** (`⇧⌘S`) to jump straight to the app.
- Notch sits in your menu bar and attaches to your display. It works on both MacBooks with a physical notch and non-notch Macs using its simulated notch mode.

### 3. Gestures & shortcuts

```text
       Hover                    Click                      Escape
  ╭──────────────╮       ╭──────────────────╮       ╭────────────────╮
  │     PEEK     │  ──►  │    PIN OPEN      │  ──►  │    DISMISS     │
  │ Quick status │       │ Sliders & shelf  │       │ Instant close  │
  ╰──────────────╯       ╰──────────────────╯       ╰────────────────╯
```

| Action | How to trigger |
| :--- | :--- |
| **Peek** | Hover over the notch. Moving the pointer away collapses it. |
| **Pin Open** | Click the notch (or click the pin icon `[P]` in the header) to keep it open while dragging files or tweaking sliders. |
| **Dismiss** | Press `Esc` while the panel is focused. |
| **Drop Shelf** | Drag any file, snippet, or link toward the top-center of your screen to reveal the shelf drop target. |
| **Quick Look** | Select any item on the shelf and press `Space` to preview it. |
| **Global Toggle** | Set a custom keyboard shortcut in **Settings → Notch** to toggle the panel from anywhere. |

---

## What's inside

- **Now Playing & Lyrics** — Album artwork, playback controls, progress scrubbers, and live lyrics for Apple Music and Spotify.
- **Real-time three-band meter** — Measured spectral energy across low, mid, and high frequencies drawn beside the camera cutout on the closed notch.
- **Per-app audio mixer** — Independent volume levels (up to 400% with soft-knee clipping), output device routing, 10-band EQ, AutoEQ headphone correction, loudness compensation, and DDC/CI external display volume.
- **Face ID unlock** — Enrolls your face on-device and types your password at the lock screen via Accessibility. Encrypted in Keychain behind Touch ID.
- **Drop shelf** — A temporary surface for files and text. Drag anything up to the notch; drag out to any app, trigger AirDrop, or inspect with Quick Look.
- **System telemetry** — Real-time CPU usage, memory pressure, battery health, and network bandwidth.
- **Calendar & Weather** — Hourly and 5-day weather forecasts; week-at-a-glance agenda with one-click meeting links.
- **Live activities** — Compact dynamic indicators for volume, brightness, battery, focus states, and macOS Clock/Siri timers.
- **Camera mirror** — A quick mirror inside the notch to verify your lighting and framing before joining a call.
- **Simulated notch** — Runs on any display, including notchless MacBooks, Mac mini, Mac Studio, and external monitors.

---

## Per-app audio mixer

The mixer uses CoreAudio's process tap API (`AudioHardwareCreateProcessTap`, macOS 14.2+) to intercept audio from individual apps rather than altering system-wide output:

```text
 [Spotify]    -------o----------  75%    [EQ: Harman Target]  [Route: AirPods Max]
 [Safari]     -------------o---- 130%    [Boost +2.5 dB]      [Route: Built-in]
 [Display]    ---------o--------  65%    (DDC/CI hardware control channel)
```

```text
     Output Level
          ▲
     400% │ . . . . . . . . . . . . ╭─────── Soft-knee ceiling (+12 dB)
          │                       ╭─╯
     100% │                 ╭─────╯ (Unity)
          │           ╭─────╯
        0 └───────────┴──────────────────► Input Level
```

- **Zero footprint until adjusted**: An app's audio stream is never tapped or touched until you move its slider. Resetting a strip detaches the tap and returns the app directly to native CoreAudio handling.
- **Boost up to 400% (+12 dB)**: Push quiet streams or podcasts well past macOS limits. Soft-knee clipping above unity ensures boosted tracks saturate gracefully instead of creating harsh digital clipping.
- **Equalizer & AutoEQ**: A 10-band parametric EQ with standard presets, plus support for importing headphone correction curves from [AutoEQ](https://github.com/jaakkopasanen/AutoEq). Imported curves live as plain text files in `~/Library/Application Support/Notch/AutoEQ` so they can be edited or backed up by hand.
- **Loudness compensation**: Automatically boosts low frequencies at lower playback volumes following psychoacoustic curves, keeping audio from sounding thin when quiet.
- **External display speakers**: Adjusts volume on external monitors over DDC/CI (VCP codes `0x62` and `0x8D`) via `IOAVService`, controlling speakers that macOS normally marks as unadjustable.
- **Shortcuts & Siri**: All mixer operations (volume, mute, EQ, display volume) are exposed as native App Intents for the Shortcuts app, Siri, or keyboard macros.

---

## The closed-notch frequency meter

Beside the camera cutout on the closed notch, a real-time three-band meter visualizes output audio:

```text
               ╭──────────────────────╮
               │  •  ♫   ▂ ▃ ▅    94% │
               ╰─────────▲─▲─▲────────╯
                         │ │ │
  20 Hz – 250 Hz ────────┘ │ └──────── 4 kHz – 20 kHz
  (Kick, Sub, Bass)        │           (Cymbals, Air)
                    250 Hz – 4 kHz
                    (Vocals, Snare, Keys)
```

Each of the three bars represents measured spectral energy from an in-memory FFT of the output mix: low (bass), mid (speech/instruments), and high (cymbals/air).
- It reflects real frequency content, not a volume level masquerading as an equalizer.
- Audio samples are inspected strictly in volatile RAM and are **never recorded, cached, or written to disk**.
- Requires macOS 14.2+ and audio capture permission. If either is missing, the meter stays quietly idle.

---

## Face ID unlock

Ported from Jonathan Zhou's [Glance](https://github.com/jonnyoo/glance) (MIT), Face ID lets you unlock your Mac from the notch on wake and lock screens. It is **off by default**.

```text
  Lock / Wake  ──►  InsightFace ArcFace  ──►  Liveness Check  ──►  Synthesized Keystroke
                      (512-d vector)         (Photo rejected)        (via Accessibility)
                                                    │
                                      Keychain (AES-256 + Touch ID)
```

What you should know before enabling it:
- **Not hardware TrueDepth**: MacBooks have standard RGB webcams without dot projectors or infrared depth sensors. Notch runs liveness heuristics that reject printed photos and phone screens with reasonable confidence, but a recorded video of your face will not be reliably blocked. Treat it as an ergonomic convenience, not biometric security.
- **Password entry**: macOS has no public API for third-party apps to authenticate a user session. Notch unlocks the machine by synthesizing password keystrokes into the login window, which is why it requires the **Accessibility** permission.
- **Key storage**: Your login password is encrypted with AES-256. The decryption key is sealed in Keychain behind **Touch ID**, alongside your face embeddings (512 numbers per face; no photos are saved). The key is kept in memory only during an active Touch ID session and purges after your configured idle interval.

---

## Display modes

Notch adapts seamlessly depending on the display:

```text
  Physical Display (MacBook)           External Monitor / Notchless Mac
  ──────────────────╮       ╭───────   ────────────────────────────────────────
                    │   •   │                         ╭───────────────╮
                    ╰───────╯                         │    •   ♫ 84%  │
             (Hardware bezel cutout)                  ╰───────────────╯
                                                    (Floating simulated pill)
```

- **Physical notch**: Snaps flush to the top bezel, matching Apple's continuous-corner curvature (`NotchShape`).
- **Simulated notch**: Floats as an unobtrusive status pill at the top of any external monitor or older Mac screen.

---

## Siri and Clock timers

Enable **Settings → Activities → All Live Activities → Clock Timers** to mirror active and paused timers from the macOS Clock app or timers started hands-free with Siri.
- Notch reads timers locally from the system store and never modifies, cancels, or dismisses them.
- On macOS releases that store Clock timers in a protected SQLite database, Notch requires **Full Disk Access** in **System Settings → Privacy & Security**. Full Disk Access is used solely to read this local file; no data leaves your Mac.
- Notch's built-in timers (in Tools) do not require Full Disk Access.

---

## Drop shelf

The Shelf is a scratchpad for files, images, and text snippets:
- Drag any file, URL, or image to the notch to drop it onto the shelf.
- Tap Spacebar to preview any stashed item with Quick Look.
- Drag items back out to Mail, Slack, Finder, or hit the AirDrop action.

---

## Requirements

| Feature | macOS 14.0 – 14.1 | macOS 14.2+ |
| :--- | :---: | :---: |
| **Workspace & Shelf** | Supported | Supported |
| **Media & Lyrics** | Supported | Supported |
| **Calendar, Weather, Telemetry** | Supported | Supported |
| **Face ID Unlock** | Supported | Supported |
| **Per-App Audio Mixer** | Unavailable* | Supported (CoreAudio Tap) |
| **Real-Time 3-Band Meter** | Idle* | Supported (In-Memory FFT) |

*\*CoreAudio Process Taps were introduced in macOS 14.2. On macOS 14.0 and 14.1, process-tapping features are disabled while all other modules remain fully active.*

- **Displays**: MacBook Air and MacBook Pro physical notch displays, external monitors, and non-notch Macs via Simulated Notch Mode.
- **Architecture**: Universal binary (Apple Silicon & Intel).

---

## Permissions & privacy

Notch makes zero network requests (except for WeatherKit queries) and collects zero telemetry or analytics. All processing happens on-device.

| Permission | Needed For | Detail |
| :--- | :--- | :--- |
| **Calendar** | Upcoming events & meeting links | Read-only; kept in memory. |
| **Location** | Weather forecast | Used solely for WeatherKit queries. |
| **Automation** | Apple Music & Spotify | Read-only playback status and transport controls. |
| **Audio Capture** | Per-app mixer & real-time frequency meter | FFT analyzed in memory; never saved to disk. |
| **Accessibility** | Face ID password typing & volume/brightness HUD | Types keystrokes into lock screen password field. |
| **Full Disk Access** | Siri & macOS Clock timer sync | *(Optional)* Only needed to read Clock's protected timer database. |

Manage permissions anytime in **Settings → Privacy** or **System Settings → Privacy & Security**.

---

## Uninstalling

1. Quit Notch from the menu bar menu.
2. Move **Notch.app** from Applications to the Trash.
3. To delete saved preferences:
   ```bash
   defaults delete com.notchapp.Notch
   ```
4. If you used Face ID, remove your stored Keychain credentials and face templates:
   ```bash
   security delete-generic-password -s com.notchapp.Notch.faceID
   rm -f "$HOME/Library/Application Support/Notch/face-identities.enc"
   ```

---

## Building from source

1. Requires macOS 14.0+ and **Xcode 16.0+**.
2. Clone the repository:
   ```bash
   git clone https://github.com/Wub796/Notch.git
   cd Notch
   ```
3. Open `Notch.xcodeproj`.
4. Set your Apple Developer Team in target signing settings.
5. Select the `Notch` scheme and press `⌘B` (Build) or `⌘R` (Run).

A Developer ID signed and notarized build is required for login items, keychain access groups, and automated Sparkle updates.

---

## Third-party credits

- **[Glance](https://github.com/jonnyoo/glance)** (MIT © Jonathan Zhou) — Face ID pipeline, ArcFace alignment, liveness heuristics, lock-screen monitor, and the Settings window chrome.
- **[InsightFace](https://github.com/deepinsight/insightface)** — Pretrained ArcFace `w600k_mbf` model weights bundled in `ArcFace.mlpackage` (research/non-commercial license).
- **[FineTune](https://github.com/ronitsingh10/FineTune)** (GPL-3.0 © Ronit Singh) — Design reference for the per-app audio mixer. Notch's mixer is a clean-room implementation written directly against public CoreAudio process tap interfaces, sharing no code or assets with FineTune.
- **[AutoEQ](https://github.com/jaakkopasanen/AutoEq)** (MIT © Jaakko Pasanen) — Headphone correction curve parser and profile formats.
- **[Lakr233/SkyLightWindow](https://github.com/Lakr233/SkyLightWindow)** (MIT © Lakr Aream) — Window-server integration for raising panels above the macOS login screen.

See [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) for full licensing details.
