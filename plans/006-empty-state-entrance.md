# 006 — Animate empty states on entry

- **Status**: DONE (executed; feel-check pending a live run)
- **Commit**: 0045fcb
- **Severity**: MEDIUM
- **Category**: Missed opportunity (state indication / preventing a jarring change)
- **Estimated scope**: 1 file, ~8 lines

## Problem

`ScreenEmptyState` — used by Clipboard, Shelf, Notes, Calendar, and Weather
whenever a module has nothing to show — appears instantly when a list is
cleared or a module is first opened:

```swift
// Notch/Views/NotchScreenComponents.swift:181-201 — current
struct ScreenEmptyState: View {
    let symbol: String
    let title: String
    var caption: String?
    var tint: Color = NotchTheme.inkMuted

    var body: some View {
        VStack(spacing: NotchTheme.Space.s) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(tint)

            Text(title)
                .font(.notchBody)
                .foregroundStyle(NotchTheme.inkSecondary)

            if let caption {
                Text(caption)
                    .font(.notchCaption)
                    .foregroundStyle(NotchTheme.inkMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}
```

Empty states are occasional-to-rare (clearing the shelf, an empty clipboard) —
the exact frequency tier where a gentle entrance belongs. Right now they
teleport in. The fix is a subtle fade + settle, not a bounce: this is a quiet
status, not a celebration.

## Target

Wrap the existing content in a short opacity + scale entrance, using the house
curve. The scale starts at 0.97 (never `scale(0)`) and the whole thing fades
and settles on appear:

```swift
// target — Notch/Views/NotchScreenComponents.swift
    var body: some View {
        VStack(spacing: NotchTheme.Space.s) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(tint)

            Text(title)
                .font(.notchBody)
                .foregroundStyle(NotchTheme.inkSecondary)

            if let caption {
                Text(caption)
                    .font(.notchCaption)
                    .foregroundStyle(NotchTheme.inkMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .scaleEffect(isPresented ? 1 : 0.97)
        .opacity(isPresented ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .onAppear {
            withAnimation(NotchAnimations.content) {
                isPresented = true
            }
        }
    }

    @State private var isPresented = false
```

## Repo conventions to follow

- House curve: `NotchAnimations.content` (`Notch/Core/NotchAnimation.swift`) —
  the standard micro-interaction spring, profile-aware, collapses to a 150ms
  fade under Reduce Motion. This is the same curve the notch uses for content
  substitution (e.g. `Notch/Views/NotchLayoutView.swift:152-160`).
- Entrance scale: 0.97 (the house `activitySwap` insertion uses 0.97 —
  `NotchAnimation.swift:131`). Never `scale(0)`.
- `onAppear` + `withAnimation` is the established pattern in this codebase
  (`Notch/Views/CalendarDetailView.swift:318`, `ChargingPopupView.swift:60`).

## Steps

1. Open `Notch/Views/NotchScreenComponents.swift`.
2. Add `@State private var isPresented = false` inside `ScreenEmptyState`
   (immediately after the `var tint` property).
3. In `body`, after the `VStack` closing brace and before `.frame(...)`, insert:
   - `.scaleEffect(isPresented ? 1 : 0.97)`
   - `.opacity(isPresented ? 1 : 0)`
4. Append `.onAppear { withAnimation(NotchAnimations.content) { isPresented = true } }`
   after `.accessibilityElement(...)`.
5. Verify the component is re-created on each list-clear (it is — the callers
   conditionally render it, so `onAppear` fires per appearance). If any caller
   keeps the view alive across state changes (it should not), report it.

## Boundaries

- Do NOT animate anything inside individual empty states (no per-item stagger —
  this is a single surface).
- Do NOT use a bounce or `scale(0)`.
- Do NOT touch the callers (`ClipboardView`, `ShelfView`, `NotesView`,
  `CalendarDetailView`, `WeatherDetailView`) — the change is entirely inside
  `ScreenEmptyState`.
- Do NOT add dependencies.

## Verification

- **Mechanical**: `xcrun swiftc -frontend -parse Notch/Views/NotchScreenComponents.swift`
  passes; `git diff --check` clean.
- **Feel check**: build and run; open the Shelf and clear it (or open a fresh
  Clipboard):
  - The empty state fades in and settles from 0.97 → 1 over ~250-300ms —
    visible but quiet, never a pop.
  - Clearing a list and seeing the empty state twice in a row feels identical
    (no drift, no accumulated scale).
  - Under Reduce Motion the entrance becomes a short fade only — no movement.
- **Done when**: empty states enter with a brief, gentle fade-settle and never
  teleport or bounce.

## Feel-check note

The opacity/scale balance is the feel-dependent part. If 0.97 reads as too
subtle (invisible), nudge to 0.95; if the settle feels busy, drop the scale
entirely and keep the fade — the quiet fade is the floor. Confirm against the
default first.
