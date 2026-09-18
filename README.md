# Notch

Notch is a native macOS utility that turns the area around your Mac's notch into a small, interactive workspace. Hover over or click the notch to open the panel, then move the pointer away or click elsewhere to close it.

Notch runs as a menu bar application. It does not add an icon to the Dock, and it keeps the rest of the screen available for normal use.

## What Notch does

- Shows currently playing music, artwork, playback controls, progress, and lyrics.
- Displays weather, the current date, and upcoming calendar events.
- Provides a temporary file shelf for dropped files and text, with AirDrop and Finder actions.
- Shows system information such as CPU, memory, battery, and network activity.
- Offers quick access to audio devices, timers, notes, clipboard history, and other utilities.
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
- **Screen Recording** — the optional real-time audio visualizer.
- **Accessibility** — optional replacement of the system volume and brightness HUDs.

You can grant or manage these permissions later from **Settings → Privacy** or from **System Settings → Privacy & Security**.

To start using Notch, hover over or click the notch. You can also use the keyboard shortcut configured in **Settings → Notch**.

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

## Building from source

1. Open `Notch.xcodeproj` in Xcode 16 or later.
2. Select your Apple Developer team under the target's signing settings.
3. Select the `Notch` scheme and build or run.

A Developer ID signed and notarized build is required for normal distribution, login-at-launch registration, and Sparkle updates.
