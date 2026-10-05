<h1 align="center">
  <br>

```text
  ███╗   ██╗ ██████╗ ████████╗ ██████╗██╗  ██╗
  ████╗  ██║██╔═══██╗╚══██╔══╝██╔════╝██║  ██║
  ██╔██╗ ██║██║   ██║   ██║   ██║     ███████║
  ██║╚██╗██║██║   ██║   ██║   ██║     ██╔══██║
  ██║ ╚████║╚██████╔╝   ██║   ╚██████╗██║  ██║
  ╚═╝  ╚═══╝ ╚═════╝    ╚═╝    ╚═════╝╚═╝  ╚═╝
```

  Notch
  <br>
</h1>

<p align="center">
  <a href="https://github.com/Wub796/Notch/releases"><img src="https://img.shields.io/badge/macOS-14.0%2B%20Sonoma%20%7C%20Sequoia-black?style=flat-square&logo=apple&logoColor=white" alt="macOS 14.0+"></a>
  <img src="https://img.shields.io/badge/Swift-6.0-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift 6">
  <img src="https://img.shields.io/badge/Xcode-16%2B-1575F9?style=flat-square&logo=xcode&logoColor=white" alt="Xcode 16">
  <a href="THIRD-PARTY-NOTICES.md"><img src="https://img.shields.io/badge/License-MIT%20%2F%20Notices-blue?style=flat-square" alt="License"></a>
  <img src="https://img.shields.io/badge/Arch-Apple%20Silicon%20%7C%20Intel-purple?style=flat-square" alt="Universal Architecture">
</p>

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

Say hello to **Notch**, a native macOS utility that turns your camera notch into an interactive workspace! Say goodbye to dead screen space: with Notch, the area around your camera transforms into a dynamic music control center, complete with a real-time three-band audio meter and full playback controls.

That's just the start: Notch also gives you a per-app audio mixer (with volume boost up to 400%), on-device Face ID unlock, a temporary file shelf with AirDrop support, calendar integration, system HUD replacements, and full multi-monitor support with simulated notch mode!

When closed, Notch stays completely idle—no background audio polling, no periodic timers, and no Dock icon.

---

## Installation

**System Requirements:**
- macOS **14.0 Sonoma** or later (macOS 14.2+ recommended for per-app audio mixer & real-time spectrum meter)
- Apple Silicon or Intel Mac
- Mac with a physical notch, or any Mac / external display using Simulated Notch Mode

---

### Option 1: Download and Install Manually

1. Download the latest **`Notch.zip`** from the [Releases](https://github.com/Wub796/Notch/releases) page.
2. Unzip the archive to extract **Notch.app**.
3. Move **Notch.app** into your `/Applications` folder.
4. Launch **Notch** from Applications.

> [!IMPORTANT]
> If macOS warns that Notch is from an unidentified developer on first launch, you will need to approve it once before the app will open. Use one of the methods below.

#### Recommended: Terminal (Always Works)

After moving Notch to your Applications folder, run:

```bash
xattr -dr com.apple.quarantine "/Applications/Notch.app"
```

Then open the app normally.

#### Alternative: System Settings

1. Try to open the app — you will see a security warning.
2. Click **OK** to dismiss it.
3. Open **System Settings** > **Privacy & Security**.
4. Scroll to the bottom and click **Open Anyway** next to the Notch prompt.
5. Confirm when prompted.

---

### Option 2: Building from Source

See [Building from Source](#building-from-source) below.

---

## Usage

```text
       Hover                    Click                      Escape
  ╭──────────────╮       ╭──────────────────╮       ╭────────────────╮
  │     PEEK     │  ──►  │    PIN OPEN      │  ──►  │    DISMISS     │
  │ Quick status │       │ Sliders & shelf  │       │ Instant close  │
  ╰──────────────╯       ╰──────────────────╯       ╰────────────────╯
```

- **Hover** over your notch to peek at your music, weather, and timers. Move your cursor away to dismiss it.
- **Click** the notch to pin the panel open so you can adjust volume sliders, drop files, or inspect calendars. Click the pin icon (`[P]`) in the header to return to hover behavior.
- **Press `Esc`** while the panel is focused to put it away immediately.
- **Drag & drop** any file, image, or link to the top-center of your screen to stash it on the shelf.
- **Press `Space`** on any stashed shelf item to preview it with Quick Look.
- **Set a global hotkey** in **Settings → Notch** to toggle the workspace from anywhere on your keyboard.

---

## 📋 Features

- [x] Now Playing playback controls, scrubbers, and live lyrics (Apple Music & Spotify) 🎧
- [x] Real-time three-band hardware frequency meter (FFT) on the closed notch 📊
- [x] Per-app audio mixer with volume levels up to 400% (+12 dB boost) 🎛️
- [x] Soft-knee analog-style clipping above unity to prevent digital distortion 🎚️
- [x] 10-band parametric equalizer with acoustic presets 🎵
- [x] AutoEQ headphone correction profile import 🎧
- [x] Loudness compensation for low-volume listening 🔈
- [x] DDC/CI external monitor speaker volume control 🖥️
- [x] Face ID biometric unlock for lock and wake screens (on-device ArcFace ML) 👤
- [x] Temporary file shelf with AirDrop and Finder integration 📚
- [x] Quick Look preview on shelf items 🔍
- [x] System HUD replacements (volume, brightness) 🎚️💡
- [x] Live hardware telemetry (CPU, RAM, battery health, network bandwidth) 📈
- [x] Calendar agenda with one-click video conference links 📆
- [x] Weather station with hourly and 5-day forecasts ⛅️
- [x] Siri and macOS Clock timer mirroring ⏱️
- [x] Pre-call camera framing mirror 📷
- [x] Physical notch & simulated notch mode for external displays 🖥️
- [x] macOS Shortcuts app & Siri automation actions ⚡
- [x] Full Reduce Motion compliance and zero idle CPU wakeups 🍃

---

## Deep-Dive Features

### Per-App Audio Mixer

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

### The Closed-Notch Frequency Meter

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

### Face ID Unlock

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

### Display Modes

Notch adapts seamlessly depending on your display:

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

### Siri and Clock Timers

Enable **Settings → Activities → All Live Activities → Clock Timers** to mirror active and paused timers from the macOS Clock app or timers started hands-free with Siri.
- Notch reads timers locally from the system store and never modifies, cancels, or dismisses them.
- On macOS releases that store Clock timers in a protected SQLite database, Notch requires **Full Disk Access** in **System Settings → Privacy & Security**. Full Disk Access is used solely to read this local file; no data leaves your Mac.
- Notch's built-in timers (in Tools) do not require Full Disk Access.

---

## Building from Source

### Prerequisites

- **macOS 14.0 or later**
- **Xcode 16.0 or later** with Swift 6 support

### Build Steps

1. **Clone the Repository**:
   ```bash
   git clone https://github.com/Wub796/Notch.git
   cd Notch
   ```

2. **Open the Project in Xcode**:
   ```bash
   open Notch.xcodeproj
   ```

3. **Build and Run**:
   - Set your Apple Developer Team under target signing settings.
   - Select the `Notch` scheme and press `Cmd + R` (Run) or `Cmd + B` (Build).

> [!NOTE]
> An Apple Developer ID signed and notarized build is required for login-at-launch registration and automated Sparkle updates to function in production.

---

## Permissions & Privacy

Notch makes zero network requests (except for WeatherKit weather queries) and collects zero telemetry or analytics. All processing happens on-device.

| Permission | Needed For | Privacy Guarantee |
| :--- | :--- | :--- |
| **Calendar** | Upcoming events & meeting links | Read-only; kept in memory. |
| **Location** | Weather forecast | Used solely for WeatherKit queries. |
| **Automation** | Apple Music & Spotify | Read-only playback status and transport controls. |
| **Audio Capture** | Per-app mixer & real-time frequency meter | FFT analyzed in memory; never saved to disk. |
| **Accessibility** | Face ID password typing & volume/brightness HUD | Types keystrokes into lock screen password field. |
| **Full Disk Access** | Siri & macOS Clock timer sync | *(Optional)* Only needed to read Clock's protected timer database. |

Manage permissions anytime in **Settings → Privacy** or **System Settings → Privacy & Security**.

---

## Clean Uninstallation

1. Quit Notch from the menu bar menu.
2. Move **Notch.app** from Applications to the Trash.
3. *(Optional)* To erase all saved application preferences:
   ```bash
   defaults delete com.notchapp.Notch
   ```
4. *(Optional)* If you used Face ID, remove your stored Keychain credentials and face templates:
   ```bash
   security delete-generic-password -s com.notchapp.Notch.faceID
   rm -f "$HOME/Library/Application Support/Notch/face-identities.enc"
   ```

---

## 🤝 Contributing

Contributions, bug reports, and pull requests are welcome! Feel free to open an issue or submit a PR on GitHub.

---

## 🎉 Acknowledgments

We would like to express our gratitude to the authors and maintainers of the open-source projects that made this possible:

- **[Glance](https://github.com/jonnyoo/glance)** (*MIT © 2026 Jonathan Zhou*) — Face ID detection, ArcFace embedding pipeline, liveness heuristics, lock-screen monitor, and the Settings window chrome.
- **[InsightFace](https://github.com/deepinsight/insightface)** — Pretrained ArcFace `w600k_mbf` model weights bundled in `ArcFace.mlpackage` (research/non-commercial license).
- **[FineTune](https://github.com/ronitsingh10/FineTune)** (*GPL-3.0 © Ronit Singh*) — Design reference for the per-app audio mixer architecture. Notch's mixer is a clean-room implementation written directly against public CoreAudio process tap interfaces, sharing no code or assets with FineTune.
- **[AutoEQ](https://github.com/jaakkopasanen/AutoEq)** (*MIT © Jaakko Pasanen*) — Headphone correction curve parser and profile formats.
- **[Lakr233/SkyLightWindow](https://github.com/Lakr233/SkyLightWindow)** (*MIT © Lakr Aream*) — Window-server integration for raising panels above the macOS login screen.
- **[Sparkle](https://sparkle-project.org/)** — Secure, automated software updates for macOS.

For a full list of licenses and attributions, please see [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
