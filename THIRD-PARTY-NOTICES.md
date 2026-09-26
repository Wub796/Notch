# Third-party notices

## Glance — face unlock for Mac

The Face ID feature (`Notch/Modules/FaceID/`) is a port of **Glance** by
Jonathan Zhou — <https://github.com/jonnyoo/glance> — which is MIT licensed:

```
MIT License

Copyright (c) 2026 Jonathan Zhou

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

What was ported, and what was written for this app, is noted in the header of
each file in `Notch/Modules/FaceID/`. In short: the recognition pipeline
(detection, ArcFace alignment and embedding), the liveness cues, the credential
and keychain layers, the lock/wake monitor, the space-key monitor, the
per-display camera catalog, and the notch overlay's geometry, shape, and scan
animation are Glance's, renamed and adapted to this app's conventions; the guided
enrollment session, the panel screen, the settings pane, and the SkyLight
lock-screen delegation are the same design rebuilt against this app's panel,
tokens, and settings store.

## Glance — the settings window

The Settings window (`Notch/Views/Settings/`) is Glance's as well: the design
tokens in `SettingsMetrics.swift`, the row/option/button vocabulary in
`SettingsControls.swift`, the graded overlay in `ProgressiveHeaderBlur.swift`,
the floating pill tab bar in `SettingsTabBar.swift`, the session lock control in
`SessionLockButton.swift`, and the window chrome in `WindowConfiguringView` are
ported from Glance's `Settings/` directory, as is the Face ID page's structure
(`Notch/Modules/FaceID/Views/FaceIDSettingsPane.swift`, built from Glance's six
settings pages). The app's own panes are reskinned onto those same tokens by
`Notch/Views/SettingsComponents.swift`, whose row types stand in for Glance's
`SettingsRow`/`SettingsActionRow`.

Deviations from Glance in that layer, all noted in the files themselves:
`GlanceTheme.accent` is `SettingsMetrics.accent`, `GlanceToggle` is
`SettingsToggle`, the unlock-animation and liveness pickers call this app's
`FaceIDOverlayController`, and the header's refresh glyph is `arrow.clockwise`
because Glance's `arrow.trianglehead.clockwise.rotate.90` needs macOS 15 while
this app targets 14.0.

### The bundled recognition model

`Notch/Modules/FaceID/Resources/ArcFace.mlpackage` is the model file shipped in
the Glance repository. Its weights originate from **InsightFace**'s
`w600k_mbf` ArcFace checkpoint (<https://github.com/deepinsight/insightface>).

Glance's *code* is MIT; InsightFace's *pretrained models* are published for
non-commercial research purposes. The two licences are separate, and this one
governs the model file rather than the code around it. If you intend to ship
this build commercially, treat the model as the thing to check — swapping it for
one you have clear rights to means retraining or re-sourcing an ArcFace-family
model with the same 112x112 input and 512-dimensional output, then re-enrolling
every face (the embedder's `modelIdentifier` deliberately invalidates templates
from a different model).

## FineTune — per-app audio (design reference only)

The per-app mixer (`Notch/Modules/Audio/Mixer/`) follows the **design** of
**FineTune** by Ronit Singh — <https://github.com/ronitsingh10/FineTune> — which
is GPL-3.0 licensed.

**No FineTune code, text, or asset is used in this repository.** The mixer is an
independent implementation written against Apple's public CoreAudio interfaces:
the process tap API (`AudioHardwareCreateProcessTap`, macOS 14.2 and later), a
private aggregate device built over the tap, an IOProc that scales and filters
that app's samples, and Apple's own HID symbols for display volume. Nothing was
translated from FineTune's sources, so FineTune's copyleft does not reach this
project and this project's licence is unchanged by it.

That boundary is deliberate and worth keeping. GPL-3.0 is a strong copyleft:
copying any part of FineTune's implementation into this repository would put the
whole app under GPL-3.0 and require this file, the app's licence, and every
distributed binary to say so. What is credited here is the design — that a Mac's
audio can be given a per-app mixer on modern macOS at all, the shape of that
mixer (per-app level with boost past unity, mute, output routing, equalizer and
loudness in one place), the idea of reading measured headphone corrections from
published profiles, and the use of the display's own control channel for the
speakers macOS never lists. Where this app's behaviour is deliberately the same,
the file headers say so.

The corresponding areas of FineTune's tree, for anyone reading both: its
`Audio/Engine` (tap and aggregate-device lifecycle), `Audio/EQ` and
`Audio/AutoEQ` (curves and imported corrections), `Audio/Loudness` (level-linked
compensation), `Audio/DDC` (display volume), and its `AppIntents` (Shortcuts
actions). This app's versions of those live in `MixerStrip.swift`,
`Equalizer.swift`, `AutoEQProfile.swift`, `LoudnessCurve.swift`,
`DisplayVolume.swift` and `MixerIntents.swift` respectively.

## AutoEQ — the correction profile format

The headphone corrections this app imports describe curves measured and
published by the **AutoEQ** project
(<https://github.com/jaakkopasanen/AutoEq>, MIT) and by the people who publish
measurements through it. `AutoEQProfile.swift` reads the two text formats AutoEQ
defines — parametric filter blocks and `GraphicEQ` gain lists — and applies them
as filters; no AutoEQ code is included, and the measurements themselves belong
to whoever published the profile, which is why each imported profile keeps its
source string.

## DDC/CI display volume

Display volume (`DisplayVolume.swift`) drives VCP codes 0x62 (volume) and 0x8D
(mute) over DDC/CI, using Apple's private `IOAVService*` symbols, resolved at
runtime with `dlsym` so a macOS that moves them degrades to "this display cannot
be controlled" instead of failing to launch. This is the same approach FineTune
credits above uses; Apple exposes no public path to a display's speakers.

## SkyLight window-server API

The `FaceIDSkyLight` implementation adapts **Lakr233/SkyLightWindow**
(<https://github.com/Lakr233/SkyLightWindow>, MIT) to raise the panel above the
login window. It calls private, undocumented Apple symbols; see the file's own
header for the risk this carries.
