# 005 — Crossfade the settings pane on selection

- **Status**: DONE (executed with 004; feel-check pending a live run)
- **Commit**: 0045fcb
- **Severity**: MEDIUM
- **Category**: Missed opportunity (preventing a jarring change)
- **Estimated scope**: 1 file, ~6 lines

## Problem

Switching settings panes is an occasional action (opening Settings, tabbing
through), and the content swap is a hard teleport:

```swift
// Notch/Views/SettingsView.swift:163-175 — current
@ViewBuilder
private var detail: some View {
    switch selection {
    case .general: GeneralSettingsPane()
    case .notch: NotchSettingsPane()
    case .media: MediaSettingsPane()
    case .weather: WeatherSettingsPane()
    case .activities: ActivitiesSettingsPane()
    case .system: SystemSettingsPane()
    case .privacy: PrivacySettingsPane()
    case .about: AboutSettingsPane()
    }
}
```

Each pane replaces the previous one with no transition — the content
teleports. Per the audit rule catalog, a brief transition that prevents a
jarring change is the textbook fix, and the frequency tier (occasional) is
exactly where standard animation belongs.

## Target

An opacity crossfade, fast enough for an occasional switcher and aligned with
the house vocabulary:

```swift
// target — Notch/Views/SettingsView.swift
@ViewBuilder
private var detail: some View {
    Group {
        switch selection {
        case .general: GeneralSettingsPane()
        case .notch: NotchSettingsPane()
        case .media: MediaSettingsPane()
        case .weather: WeatherSettingsPane()
        case .activities: ActivitiesSettingsPane()
        case .system: SystemSettingsPane()
        case .privacy: PrivacySettingsPane()
        case .about: AboutSettingsPane()
        }
    }
    .id(selection)
    .transition(.opacity)
}
```

The `selection` state change already happens inside
`withAnimation(NotchAnimations.content)` (see plan 004), so the `.id` + `.transition`
will animate through that spring — the header's `.animation` in plan 004 is the
driver. Do NOT add a separate `withAnimation` here.

## Repo conventions to follow

- The house transition style for content substitution is an opacity crossfade
  driven by `NotchAnimations.content`, used in the notch's own tab switching
  (`Notch/Views/NotchLayoutView.swift:152-160`) and detail headers
  (`Notch/Views/ExpandedNotchView.swift:19-20`). Imitate those.
- SwiftUI crossfade idiom: `.id(<equatable selection>)` + `.transition(.opacity)`,
  with the state change inside a `withAnimation`.

## Steps

1. Open `Notch/Views/SettingsView.swift`.
2. Wrap the `switch selection` in a `Group { ... }`.
3. Append `.id(selection)` and `.transition(.opacity)` to the `Group` (after the
   closing brace of the switch, before the closing brace of `detail`).
4. Confirm the sidebar button still wraps `selection = pane` in
   `withAnimation(...)` (plan 004 ensures it uses `NotchAnimations.content`);
   if plan 004 is not yet applied, apply this plan with the existing
   `withAnimation(.easeInOut(duration: 0.12))` first — it will still drive the
   crossfade, just with the weaker curve. Flag the ordering dependency in your
   report.

## Boundaries

- Do NOT animate the sidebar itself, the header title, or the search field.
- Do NOT add a new animation token or dependency.
- Do NOT change any pane's contents.
- Do NOT change the crossfade to a slide/scale — panes swap in place; a
  translate or scale would imply spatial movement that doesn't exist.

## Verification

- **Mechanical**: `xcrun swiftc -frontend -parse Notch/Views/SettingsView.swift`
  passes; `git diff --check` clean.
- **Feel check**: build and run; open Settings and click between General and
  Notch (the two structurally different panes):
  - The old pane fades out while the new fades in — no hard cut, no flash of
    background between them.
  - Spamming clicks across panes never shows a half-drawn state; each click
    simply retargets the crossfade (transitions retarget; no keyframes).
  - Under Reduce Motion the crossfade becomes a short, gentle fade — panes
    still swap legibly, never blinking.
- **Done when**: pane switches crossfade smoothly and spamming the sidebar never
  stutters or shows a blank gap.

## Feel-check note

Opacity-only crossfades can briefly double-expose dense content (two panes at
50% overlapping). If that reads as a ghost flash on the denser panes
(Telemetry), prefer a slightly faster curve — `NotchAnimations.reduced`
(150ms ease-out) — or apply `.transition(.opacity)` only on the insertion side.
Confirm against the default first.
