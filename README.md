# Notch

Notch is a native macOS utility that turns the area around your Mac's notch into a small, interactive workspace. Hover over or click the notch to open the panel, then move the pointer away or click elsewhere to close it.

Notch runs as a menu bar application. It does not add an icon to the Dock, and it keeps the rest of the screen available for normal use.

## What Notch does

- Shows currently playing music, artwork, playback controls, progress, and lyrics.
- Displays weather, the current date, and upcoming calendar events.
- Provides a temporary file shelf for dropped files and text, with AirDrop and Finder actions.
- Shows system information such as CPU, memory, battery, and network activity.
- Offers quick access to audio devices, timers, notes, clipboard history, and other utilities.
- **Per-app audio mixer** — gives any app its own level (including a boost past 100%), mute, output
  device, equalizer and headphone correction. See [Per-app audio](#per-app-audio) below.
- **A three-band meter** beside the artwork on the closed notch: each of the three bars is the measured
  energy of its own range of frequencies — low, mid and high — taken from the output mix, so a kick fills
  the first and cymbals the third. It needs macOS 14.2 and audio access; without either the bars fall
  back to moving with the output volume.
- **Face ID** — recognizes your face from the notch on lock and wake, and can unlock the Mac by typing
your password for you. Off by default; see [Face ID](#face-id) below before turning it on.
- Displays compact live activities for music, volume, battery, meetings, focus changes, and other events.
- Supports hover, click, scroll, keyboard shortcut, pinning, and configurable animation behavior.
- Includes a settings window for appearance, behavior, permissions, dashboard widgets, and integrations.

## Requirements

- macOS 14.0 or later
- A Mac with a physical notch, or any Mac running Notch in its simulated notch mode
- A signed build for login items, notarization, and Sparkle updates to work correctly

## Installation

### Install from a DMG

1. Download the latest `Notch-<version>.dmg` from the [Releases](https://github.com/Wub796/Notch/releases) page.
2. Open the downloaded DMG.
3. Drag **Notch** into the **Applications** folder shown in the DMG window.
4. Eject the DMG.
5. Open **Notch** from Applications.

If macOS asks whether you want to open an app downloaded from the Internet, choose **Open**. Only install DMGs downloaded from a release source you trust.

### First launch

Notch appears in the menu bar and attaches itself to the display selected in Settings. On the first launch, a welcome window explains the basic gestures and optional permissions.

Notch asks only for permissions needed by the features you use:

- **Calendar** — upcoming events and meeting links.
- **Location** — accurate weather for your area.
- **Automation** — reading and controlling Apple Music or Spotify.
- **Audio capture** — only if your macOS asks for it when the mixer takes over an app's audio, or when
  the real-time meter reads the output mix to draw its three bars. Samples are measured in memory and
  never recorded or written anywhere; see [Per-app audio](#per-app-audio).
- **Accessibility** — optional replacement of the system volume and brightness HUDs, and required by
  Face ID to type your password at the lock screen.
- **Input Monitoring** — only if you use the Face ID "on space" trigger. Usually already satisfied by
  the Accessibility grant, so Notch normally never appears under it.

You can grant or manage these permissions later from **Settings → Privacy** or from **System Settings → Privacy & Security**.

To start using Notch, hover over or click the notch. You can also use the keyboard shortcut configured in **Settings → Notch**.

## Face ID

Face ID comes from [Glance](https://github.com/jonnyoo/glance) (MIT) and is **off by default**. When it
is on, the notch appears by itself at the lock screen, looks for an enrolled face, and — if it finds one
and the liveness checks agree it is a real person — types your stored password into the login window.

Read this before enabling it:

- **This is not Face ID as an iPhone does it.** MacBook cameras have no depth sensor, so a reflection
  cannot be measured and a flat image cannot be ruled out by geometry alone. With liveness checking on,
  a printed photo and a photo on a phone screen are rejected with reasonable confidence; a *video* of
  you is not reliably rejected.
- **macOS offers no way for an app to authorize a login.** Face ID logs in the only way a third-party
  app can: by synthesizing the keystrokes for your password into the lock screen's own field. That is
  why the feature needs Accessibility.
- **The password is stored encrypted, not in plaintext.** It is sealed with a 256-bit key that lives in
  the keychain behind Touch ID, alongside the face templates — which are 512-number embeddings, never
  images. The key is held in memory only while a Touch ID-authorized session is live, and re-locks
  after the idle interval you choose.

Treat it as a convenience, not a security upgrade: anyone who has your unlocked Mac and a recording of
your face is not stopped by it.

## Updating Notch

Notch checks for updates automatically when a signed release is available. To check immediately, use:

- The menu bar item → **Check for Updates…**
- **Settings → About → Check for Updates…**

When an update is available, Sparkle downloads and verifies the signed release before installing it. Notch then relaunches with the new version. You can continue to use the current version if you postpone the update.

## Uninstalling

1. Quit Notch from the menu bar menu.
2. Open Applications in Finder.
3. Move **Notch.app** to the Trash.
4. Empty the Trash if you want to remove the application immediately.

Notch stores preferences in your user account. To remove those preferences as well, open Terminal and run:

```bash
defaults delete com.notchapp.Notch
```

This does not revoke permissions previously granted in System Settings. Remove those separately from **System Settings → Privacy & Security** if desired.

Face ID's stored password and face templates stay in your keychain and Application Support until you
remove them with **Settings → Face ID → Password → Remove** (hold the button down to confirm), or run:

```bash
security delete-generic-password -s com.notchapp.Notch.faceID
rm -f "$HOME/Library/Application Support/Notch/face-identities.enc"
```

## Per-app audio

The **Mixer** surface on the Audio screen rewrites a single app's audio instead of the whole system's.
Each app gets its own level from silence to 400% (a +12 dB boost, with soft clipping above unity so a
boosted track clips gracefully rather than digitally), a mute, an output device, a ten-band equalizer
with built-in curves, an imported headphone correction, and loudness compensation that keeps the low end
as you listen more quietly. The speakers inside an external display appear alongside the apps, set over
the display's own control channel — they are not an audio device macOS lists, so nothing else can reach
them.

How it works, and what that means for you:

- **An app is only taken over when you change it.** Nothing runs in the background: the app's own audio
  path is untouched until you move its slider, and resetting it hands the app straight back. This is
  also why the mixer can be switched off entirely without breaking anything.
- **It needs macOS 14.2 or later.** The mechanism is CoreAudio's process tap API, which does not exist
  before 14.2. On 14.0 and 14.1 the feature reports itself as unavailable rather than offering controls
  that do nothing — those releases also removed CoreAudio's older per-process level property, which is
  why per-app volume needs a tap at all.
- **It replaces the app's output rather than adding to it.** The tap takes the app's audio and the mixer
  plays it back through the chosen device, so what you hear is the mixed signal and never a doubled one.
- **A newer macOS may ask for audio-capture permission** the first time an app is taken over. If taking
  an app over fails with a CoreAudio error on a release that asks, allow Notch under
  **System Settings → Privacy & Security**, then switch the mixer off and on.
- **Your settings are per app, not per process.** They are keyed by bundle identifier and kept in your
  preferences, so they survive relaunches, updates and reboots.

### Headphone corrections

AutoEQ publishes measured corrections for thousands of headphones as plain text — how a given pair
deviates from a target curve. Import one under **Settings → System → Headphone Corrections**, then
choose it for an app in the mixer. Imported profiles are kept as files in
`~/Library/Application Support/Notch/AutoEQ`, so they can be backed up, edited, or added by hand.

### Shortcuts

Every one of the mixer's operations is available to Shortcuts (and to Siri, and the Action button): set
an app's volume, mute it, apply an equalizer curve, switch loudness compensation, reset an app, switch
the mixer off, and set an external display's volume. They act on the running app's mixer, so they are
visible in the Shortcuts editor without any setup here.

## The settings window

The Settings window is [Glance](https://github.com/jonnyoo/glance)'s as well: one translucent panel with
the selected page scrolling under a blurred header and a floating pill tab bar along the bottom, and the
same row cards, option tiles, and sliders throughout. Face ID's page is Glance's six settings pages
(General, Face, Password, Camera, Recognition, About) folded into one tab, since Notch has a tab per
feature where Glance has one per Face ID page.

## Building from source

1. Open `Notch.xcodeproj` in Xcode 16 or later.
2. Select your Apple Developer team under the target's signing settings.
3. Select the `Notch` scheme and build or run.

A Developer ID signed and notarized build is required for normal distribution, login-at-launch registration, and Sparkle updates.

## Third-party notices

Face ID is a port of [Glance](https://github.com/jonnyoo/glance) (MIT © Jonathan Zhou). The recognition
model bundled with it originates from InsightFace and carries its own terms, which are not the same as
the code's. The per-app audio mixer follows the design of
[FineTune](https://github.com/ronitsingh10/FineTune) (GPL-3.0 © Ronit Singh) but shares no code with it,
and the headphone-correction format it reads is [AutoEQ](https://github.com/jaakkopasanen/AutoEq)'s
(MIT). All of this is set out in [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
