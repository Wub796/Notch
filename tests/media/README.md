# Media push checks

Run from the workspace root on macOS:

```bash
mkdir -p .build/media-tests
swiftc Notch/Modules/Media/PlaybackPush.swift \
  Notch/Modules/Media/SourceArbitration.swift \
  Notch/Core/MediaKeyTapPolicy.swift \
  tests/media/main.swift -o .build/media-tests/check
.build/media-tests/check
```

These exercise `PlaybackPush`, the parser behind the closed notch's real-time
updates, and `SourceArbitration`, the rules that decide which report owns the
screen. `PlaybackPush` reads the two distributed playback reports — Music's
`com.apple.iTunes.playerInfo` and Spotify's
`com.spotify.client.PlaybackStateChanged` — which are the only metadata source
that is both push-based and permission-free, so the closed pill follows a skip,
a pause and a seek without the gated MediaRemote entry points and without
Automation consent.

Neither type has an AppKit or `MediaController` dependency for exactly this
reason: both payload shapes, and the arbitration between them, can be checked
on a machine where neither player is installed, let alone running.

Covered behavior: Music's `Total Time` in seconds against Spotify's `Duration`
in milliseconds; `Player State` against `PlaybackState`; keys matched without
case, spaces or underscores, so a respelled field is still read; a report with
no track name yields no metadata (a state-only push must not blank the notch);
a zero duration stays zero; and `Artwork Count` is not mistaken for the
`Artwork` image.

From `SourceArbitration`: the priority ladder every media surface follows — a
*playing* player, then a browser item (the whole of "if music isn't playing,
show the YouTube item"), then the track a paused player still holds, then
nothing; and that only the app owning the item on screen may move its play
state, while a push saying it is *playing* is let through from any player,
because that one is a source change in progress.

The last group covers `MediaKeyTapPolicy`, the recovery rules for the event tap
that replaces the system volume and brightness HUD. A real tap cannot be built,
disabled or invalidated on demand from a test, so what is checked is the
decision about a tap in each of those states: left alone while the system still
has it enabled; given a moment when it has only just been armed, because the run
loop serving it has not started; re-armed once the system disables it mid-session
(the case that used to leave the system's own HUD back on screen for good);
rebuilt when a re-arm did not take, because `tapEnable` on an invalidated port
reports success and changes nothing; taken down when HUD replacement is off or
Accessibility is revoked; and installed when a tap is missing, which is also how
a permission granted after launch is picked up without a relaunch.

`checks.passed` must equal `checks` — a nonzero exit is a failing check.

## What this cannot check

The adoption of a push *inside* the app — the provider filter, the browser-item
and preferred-player guards, and the artwork fetch — needs the running app,
which needs Xcode. It is type-checked by
`sh .freebuff/typecheck/shadow-check.sh` and wants a live feel-check on a
closed notch: skip a track in the player and the pill's cover should change
with it.

So does the wiring the arbitration rules feed: that pausing the player while a
YouTube video plays really switches the closed pill and the open panel over.
What is checked here is only the decision — which reading wins — not that the
AppleScript reading produces it. The live test to run on the Mac: play a video
in a browser, pause the player, and both the pill's cover and the open panel's
cover should become the video's thumbnail with the channel beneath it. Note
that the browser reading is consent-gated: with Automation for the browser not
yet granted, opening the notch once is what raises the prompt, and the closed
pill cannot read the tab until it has been answered.
