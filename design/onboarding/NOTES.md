# Notch — first-run onboarding (design prototype)

`index.html` is a self-contained, interactive prototype of a redesigned first-run
flow for the 460 × 620 onboarding window. It is the design artifact: open it in a
browser (or the thread preview) and click through it. Nothing in the app is
changed yet.

## The flow

Eleven screens, one decision each: welcome → **nine permission asks, one per
screen** → ready.

| # | Screen | What it does |
| --- | --- | --- |
| 0 | **Meet your notch** | Says what the notch is, then asks the visitor to *touch it* — the real notch drawn in the simulated menu bar opens on hover and pins on click. The card flips to "That's it." once they do. |
| 1–9 | **One permission per screen** | A tinted tile, the permission's name, one line on what it buys, one line on what happens without it, and Grant / Not now. Grant raises the *actual* macOS consent prompt (simulated here) because that is exactly what the app does; on grant the screen confirms and then carries the flow on by itself. Refuse and nothing moves until the visitor says so — the button becomes "Next". |
| 10 | **You're all set** | Chips for what got granted, launch-at-login, a three-line recap of the gestures, and one CTA. |

**Done means done.** "Start Using Notch" closes the window — it leaves the screen
and the notch is what remains, opening with the now-playing panel (and a toast
stating the tally). Back, `Skip the rest` (top-right of every ask) and
`Not now` keep nobody trapped: asking nine questions is only acceptable if all of
them can be walked away from.

## Decisions worth keeping

- **The ask order is not the enumeration order.** `PERMS` stays in System Settings
  order — that is what Settings → Privacy matches, and where a returning visitor
  looks. The flow leads with what is instant and immediately visible (Calendar,
  Location, Music, Notifications, Camera, Bluetooth, Files) and leaves the two
  that send someone off to System Settings for the end (Screen & Audio,
  Accessibility), where the easy wins have already paid for the trip. See
  `ASK_ORDER` in the script.
- **Asking one at a time costs screens but buys honesty.** Nine explained
  permissions cannot be asked in a 620px window without hiding some below a
  scroll; a screen each means every ask is fully on screen when it is made, and
  nothing is granted by accident.
- **System prompts are simulated, not described.** Seeing the exact alert before
  it appears is worth more than a sentence about it. The two System-Settings-only
  permissions show "Open System Settings" and then sit in a
  "waiting for the switch" state — the behaviour `IntegrationPermissions`
  already implements.
- **The notch is the demo.** Step 0's payoff happens in the menu bar, not in the
  window. The silhouette is a direct port of `NotchShape.swift` (Apple's
  continuous corners, squeezed-box rule included), so the pill and the open slab
  are drawn with the app's real geometry — 16/18 closed, 26/30 open — and sprung
  between them with a critically damped spring (response 0.34s).
- **Copy is the interface.** Every ask names the feature it buys and what happens
  without it; the app's own `detail` and `fallbackNote` strings were the source
  for that tone.
- **Motion**: 300ms ease-out entrances (`cubic-bezier(.23,1,.32,1)`), 190ms exits,
  22px of travel in the direction of travel; buttons press at `scale(.975)` on
  pointer-down; the notch is a spring; the window closes upward, toward the notch.
- **Accessibility**: real focus rings, arrow-key stepping, Enter grants on an ask
  screen, a polite live region announcing every decision, and full
  `prefers-reduced-motion` / `-reduced-transparency` / `-contrast` paths.

## Review hooks

Append to the URL: `?step=0…10`, `?granted=accessibility,calendar`,
`?dialog=location`, `?done=1`. `Prototype · Replay flow` at the bottom of the
screen resets everything.

## Where this lands in the app

| Prototype piece | App counterpart |
| --- | --- |
| Window + chrome | `Notch/App/OnboardingWindowController.swift` |
| Eleven screens | `Notch/App/OnboardingView.swift` (currently one long single page) |
| Permission asks, statuses, prompts | `Notch/Core/IntegrationPermissions.swift` (`Integration`, `Status`, `request(_:)`, `openSettings(for:)`) |
| Springs, cross-fades, reduced motion | `Notch/Core/NotchAnimation.swift` |
| Notch silhouette | `Notch/Views/NotchShape.swift` |
| Launch at login | `NotchSettings.launchAtLogin` |

A SwiftUI port is a rewrite of `OnboardingView` into a stepped container with the
same copy and the same sequencing; the permission screens can be driven by the
existing `IntegrationPermissions` observable rather than any new state, and
`OnboardingWindowController.finish()` already closes the window — the prototype
just makes that close visible.

## Ported into the app

The flow is no longer a prototype: it is the app's first-run flow.

| Piece | File |
| --- | --- |
| Step model, ask order, per-permission copy and tints, motion tokens | `Notch/App/Onboarding/OnboardingStep.swift` |
| Tile, verdict line, summary chip, persistent footer | `Notch/App/Onboarding/OnboardingComponents.swift` |
| Welcome, in-window notch demo, gesture rows | `Notch/App/Onboarding/OnboardingWelcomeView.swift` |
| One ask per screen | `Notch/App/Onboarding/OnboardingAskView.swift` |
| Ready: chips, launch at login, recap | `Notch/App/Onboarding/OnboardingReadyView.swift` |
| Sequencing, grant/pending/auto-advance, arrow keys | `Notch/App/OnboardingView.swift` |
| Fixed-size window, review hook | `Notch/App/OnboardingWindowController.swift` |

**What the port settled** (the items this document had left open):

- **The notch demo lives in the window.** The real notch is a few centimetres
  above the window, and a first-run screen that says "look up there" loses
  everyone who does not. It is drawn with the same `NotchShape` and the same
  0.34s critically damped response, scaled to a miniature top-of-screen.
- **A grant still auto-advances** — after 850ms, or 250ms under Reduce Motion.
  A refusal never moves anything: the button becomes `Next`.
- **The system prompts are not simulated** because they are real: the ask calls
  `IntegrationPermissions.request`, which is what raises the actual macOS alert.
  Accessibility and Screen & Audio wait for the System Settings switch instead,
  with the engine's own "nothing moved" note under the verdict.
- **The hotkey copy stays generic** ("Set a shortcut in Settings → Notch").

**Deviations from this prototype, deliberately:**

- A real 460 × 620 window with the real traffic lights, not a drawn title bar.
- Chips carry the app's full permission names.
- No replay control: onboarding is once per user. The routes back in are the
  menu bar's **Show Welcome Again** and `--show-onboarding`.
- Review hooks are command-line: `--onboarding-step N` (0 = welcome, 10 = ready);
  `--debug-onboarding-check`, which presents the flow, prints whether the window
  is on screen, how much each screen wants to be tall, the real notch and panel
  geometry and the welcome demo's own drawn sizes, then restores the seen-it flag
  so a check run cannot use up a first run; and `--debug-render-onboarding <path>`,
  which renders the welcome screen offscreen — panel open — to a PNG, printing
  the geometry it drew at.

## Workflow, refined in the port

- **It ends on the product, not on a closed window.** Reaching the last button
  closes the welcome *and opens the notch* — held for about seven seconds, then
  released back to the panel's normal rules (hover to peek, click to pin). Closing
  the window on any other screen is a valid ending too, and deliberately does not
  trigger it: someone who dismissed the flow is not asking to be shown the app.
- **Waiting is never a dead end.** While a System-Settings permission is being
  waited on, and after a refusal, the screen carries a button that reopens that
  exact Privacy pane. The pane can be closed by accident; the flow used to have
  nothing to say about it.
- **The buttons tell the truth about what they are.** `Granted` only appears when
  *this* run raised the prompt and it was granted, so the press is an
  acknowledgement. A permission that was already on before the flow reached it
  says `Continue`, because there is nothing to acknowledge and one thing to do.
- **The tally gains a countdown.** For the last three asks the footer reads
  "n of 9 granted · 3 left", because past a certain point how much is left is the
  more interesting number than how much has been done.
- **The last screen can act on what is left.** Anything not granted is listed as
  a chip that opens its own Privacy pane — rather than a sentence asking someone
  to remember a path at the moment they are trying to leave.

## Motion, refined in the port

The app's flow is more animated than this prototype is, and deliberately so —
the prototype could only animate whole screens, where SwiftUI can animate the
parts inside them.

- **The screen is the frame, the parts are the picture.** A step swap is a
  14pt slide with a whisper of scale and blur (260ms in, 160ms out, direction
  aware). The parts of the arriving screen — mark, name, why, what happens
  without it, the demo — then come in on their own quint-out curve, 45ms apart.
- **Nothing scales up from nothing.** Every entrance moves a few points and
  fades. Scale-from-zero is the vocabulary of a popup, not of a welcome.
- **One invitation, not two.** The ring around the demo notch breathes until it
  has been touched; the try-card arrow deliberately does not pulse as well.
- **Confirmation is an event.** A grant settles the tile a touch larger, rings
  it green, bounces the check, and springs the primary button from white to
  green. Nothing loops.
- **Ambient motion is sampled, not frame-rate.** The breathing ring and the
  bands are computed from the clock at 4–8Hz and glided between samples
  (`NotchAnimations.clockStep`), rather than held open as repeating animations.
- **Every screen demos itself.** Each ask carries a quiet strip showing what the
  permission buys — a live three-band meter for Screen & Audio, a sweeping
  viewfinder for Camera, and so on. They are illustrations, hidden from
  VoiceOver, and they hold still under Reduce Motion.
- **A strip develops; it does not appear.** The pieces inside each demo — its
  glyph, its subject, its trailing note — arrive in their own turn just after
  the strip itself lands, so a strip is made of the flow's vocabulary rather
  than an appearance of its own.
- **A granted strip answers the switch.** The strip *is* the thing the
  permission turns on, so a grant sends a light across it once and its border
  picks up the permission's own tint: the verdict says what happened, and the
  strip says what it happened to.
- **The panel closes in the order it opened, reversed.** Its contents leave
  first and quickly — transport, then the title, then the artwork — because the
  pill is already contracting around them, and contents that linger on a closing
  shape read as a rendering fault rather than as a transition. The pill's own
  contents shrink *into* the pill and come back only once the panel has cleared,
  which is the handoff `NotchAnimations.closedStrip` makes in the real app.
- **The invitation withdraws.** The ring around the demo notch leaves over
  300ms after an accepted touch instead of vanishing mid-breath, and its
  timeline is stopped 60ms later — an answered invitation costs nothing to keep
  on screen.
- **The welcome screen opens like all the others.** It was the last screen still
  arriving as one block; it now stages hero → demo → try-card → rows → note on
  the same curve and stagger as the asks and the ready screen.
- **Counts roll.** The footer tally and the ready screen's "n of 9 on" use
  `.contentTransition(.numericText())`: a grant changes a digit instead of
  reflowing a sentence.

What is *not* animated, on purpose: the layout shift when a verdict appears. The
ask screens are vertically centred, so an answer moves the content up by half its
height. That shift reads as the screen making room — which is what it is — and
padding the screens against a shift nobody minds would cost height the flow does
not have.

**Reduce Motion** removes delays, travel, scale and all ambient motion; what is
left is the fade, the copy, and the state.

## Consent: what a Grant button actually needs

Whether a button prompts is not decided by the button. Four separate gates
stand behind it, and a missing one produces the same symptom — no dialog, no
record, nothing to answer — which is why it reads as a broken button rather
than as a blocked one.

1. **The usage description in `Info.plist`.** Camera, calendar, location,
   Bluetooth, Apple Events and audio capture all had theirs. The two protected
   folders the file catcher watches did **not**: macOS cannot raise its
   "access files in your Downloads folder" prompt without
   `NSDownloadsFolderUsageDescription` / `NSDesktopFolderUsageDescription`, so a
   read of those folders was simply refused. The Files & Folders Grant button
   had nothing to show by construction. Both keys are now in, plus Documents,
   because the screenshot folder is a user preference and can point there.
2. **The entitlement.** The app is signed with the hardened runtime
   (`flags=0x10000(runtime)`), and under it the system gates several services
   behind entitlements *before* consent is even considered. Camera, calendars
   and Apple Events were listed; **location and Bluetooth were not**, and for
   location that is not a subtlety — locationd says so in as many words:
   `Client has supported the hardened runtime but doesn't have the entitlement,
   not sending #AuthPrompt message to #CoreLocationAgent`. After adding
   `com.apple.security.personal-information.location` and
   `com.apple.security.device.bluetooth`, the same call logs
   `#AuthPrompt posted` and the dialog appears. Bluetooth gates identically for
   a fresh install; it could not be observed here because that Mac has already
   granted it.
3. **Consent is asked once.** A decided permission cannot be re-prompted by
   anyone — that is macOS, not a bug in the button. When the answer is already
   on record the flow says so and offers the System Settings pane instead of
   firing a request that cannot happen (`canPrompt(for:)`).
4. **Which process is responsible.** A build launched from a terminal is
   attributed to that terminal for consent purposes: the same binary read the
   same folders happily from a shell and reported a different calendar status
   than when opened the way a person opens it. Any verification of prompts has
   to use `open -n Notch.app --args …`, not `./Notch`.

One repair came with this. The folder probe is the only integration whose
prompt is raised by the read itself, so pre-fix builds recorded
`requested.filesAndFolders` on a read that could never have prompted — leaving
the record claiming a firm "Denied", and a denied row is never asked again.
`repairFolderRecord()` clears that flag once, so the next press gets a real
chance to prompt.

**Deliberate, and worth not "fixing" later:** modules raise these prompts on
their own when a feature is first used (weather asks for location when the
panel needs a forecast, the calendar asks when its timeline is shown, a timer
asks for notifications when it starts). That is the ready screen's promise —
"Notch asks again the first time a feature actually needs it, and never
before" — and it is why a permission can be decided before the flow reaches
its screen. The flow handles that as a fact, not an error: the screen is shown
anyway, and the button is what reports the answer — **Continue** for one that
was already granted, **Next** for one already refused. See the section below.

## Every screen is walked

An answer macOS already holds changes the verb on the ask, not whether the ask
is shown. A permission granted before the window opened has nothing to
acknowledge, so its button reads **Continue**; one granted *during* this run
reads **Granted**, because the press is the acknowledgement; a refusal reads
**Next**; anything still undecided reads **Grant Access**. Eleven screens,
eleven stops.

Three things follow, and they are why the extra screens are worth it:

- **The flow cannot disagree with itself.** Walking past a granted permission
  needed a snapshot of every answer taken *after* the asynchronous ones had
  landed — folders only exist once they have been listed, notification consent
  arrives from a read, Apple Events consent needs the player to answer.
  Snapshotted in `init`, which is where this went wrong first, a granted
  permission read as "not on": the flow skipped a screen it should have stopped
  at *and* asked about a permission already granted. With nothing skipped there
  is nothing to settle and no snapshot to get wrong.
- **The track measures the flow it is in.** `progress = index / lastIndex`, and
  the footer's "n of 9 granted · n left" counts every ask still ahead. A track
  sized to a stopped-at subset was a second definition of the flow's length, and
  the two could disagree in front of the user.
- **What is left is still honest.** `Not now` appears only where something can
  actually be put off — an ask with no answer yet, or one being waited on. A
  permission macOS will no longer ask about keeps its screen, its explanation
  and its place in the order; the ready screen lists it with the pane that can
  change it.

Measured here, where seven of the nine are granted and one can no longer be
asked:

```
flow.granted=[accessibility, screenCapture, filesAndFolders, music, location,
              camera, bluetooth]
flow.unaskable=[notifications]   # denied: macOS will not ask again
flow.screens=11
```

## The welcome's notch is the app's own geometry

The demo on the welcome screen is a picture of the top of the screen, and it is
built out of the product's numbers rather than drawn beside them. It used to
carry its own: a 246 × 100 panel, 30pt artwork, invented radii and a rail of
invented controls. The real Now panel is 880 × 287 — three times as wide as it is
tall, not two and a half — and none of the old picture's proportions survived
that comparison, which is exactly what it looked like on screen.

`OnboardingDemoGeometry` derives every part of it:

| Part | Comes from |
| --- | --- |
| Panel width | `NotchState.expandedSize(for: .audio)` — the user's own width preference, clamped by the display |
| Panel height | `DevicesScreenMetrics.naturalNowHeight` + the safe band + the header, the same sum `NotchState` makes for the Now page |
| Closed pill | `NotchState.collapsedSize(for: .music)` — the measured cutout plus the playing pill's wings, because the pill the demo draws is the playing one |
| Radii, insets | `NotchSizing` — 26/30 open, 16/18 closed, 31/5 audio gutters |
| Header strip | `NotchState.topBarHeight` (44), `NotchLayoutView`'s 6pt gap |
| Module | `DevicesScreenMetrics`: hero 98 + gap 8 + playback 120 + 6 safe = 232 |
| Cover (open) | 76pt at radius 20 — what `DevicesScreenView` draws, not the reference `ArtworkSizes.opened` (90) nothing uses any more |
| Cover (closed) | 22pt at radius 8, at `CollapsedNotchView`'s own `closedArtworkInset` |

The panel's contents are the Now page's, too: the audio tab's own header (a back
button — `ExpandedNotchView` gives `.audio` a `DetailHeaderView` with an empty
trailing flank, not the module rail), the hero card with the cover, the artist
row, the album line and the Now/Audio switch, and the playback card with
`ScrubberBar`'s elapsed / accent / remaining row, the 38pt transport circle and
the shuffle-heart-lyrics row. The pill's wings are arranged by the app's own
`ActivityWingLayout`, and its meter carries the cover's accent the way
`MusicVisualizerView` does.

Framing is the only thing the demo decides for itself: `sideMargin` (150pt of
menu bar shown either side) and `belowMargin` (12pt of screen under the panel).
Everything is drawn at real size inside that crop and scaled once — 0.3458 at the
460pt window, on this machine — so a size preference moves the picture with the
product:

```
demo.crop=1180x343 scale=0.3458
demo.slab=880x287 drawn=304.3x99.2
demo.notch=215x32 drawn=74.3x11.1
demo.closedPill=303x32 drawn=104.8x11.1
demo.module=232 hero=98 playback=120
demo.heroArtwork=76 corner=20 drawn=26.3
demo.closedArtwork=22 corner=8 drawn=7.6
demo.topBar=44 drawn=15.2
```

The drawing and the report read the same struct, so the printed numbers cannot
describe a different picture from the one on screen. `--debug-onboarding-check`
reports them beside the real geometry (`geometry.audio=880x287`,
`geometry.notch=215x32`), and `--debug-render-onboarding <path>` writes the whole
welcome screen to a PNG offscreen with the panel open — the way to look at the
picture on a machine with no screen-recording permission.

One trap if the picture is ever checked by pixels rather than by numbers: the
silhouette's *body* is the frame narrowed by the top radius on each side, so
below the corners 880 points of frame is 828 of visible black. A dark-region
measurement at mid-height reports 828, not 880; only the topmost rows reach the
full frame, and only through the flared corners.

## What the asks cost

**What was measured:** with the app's own audio path idle, a static ask screen
cost 0.4% of a core and the screens with live demos cost 7–9% (Debug build).
The samplers were then slowed (6.7Hz → 4Hz) and the camera sweep's glide
shortened from a held 800ms animation to the sample interval. Re-measuring the
improvement was not possible afterwards: every configuration — including static
screens — reported ~35%, because the app's own audio visualizer runs whenever
there is audio on the machine. The reduction is reasoned, not confirmed, and the
Release figure is unmeasured.

**One trap worth remembering:** a SwiftUI root that fills its container reports
an ideal size AppKit will grow the window to on assignment — this window came up
4038pt tall before the hosting view was told not to size it
(`sizingOptions = []`).

## Not decided

- Whether the notch demo should live in the window (a mini screen at the top of
  it) instead of in the simulated menu bar, for people who dismiss the window and
  never look up.
- The real hotkey default to quote in the recap card — the prototype says
  "Set a shortcut in Settings → Notch" instead of naming a key.
