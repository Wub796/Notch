# Notch — agent instructions

A native macOS app ([Notch/](Notch)), a static site ([index.html](index.html), `css/`, `js/`, [website/](website)), and plain-Swift regression harnesses ([tests/](tests)).

## Quality gates — on every change, and again before any push to main

Three skills are installed here and are not optional. `.agents/skills/` holds the copies that run; [skills-lock.json](skills-lock.json) holds their source and pinned commit.

| Gate | Skill | Fires |
|---|---|---|
| Smallest complete change | `ponytail` | The whole session. Read it before writing code. |
| Rigor | `poteto-mode` | Any task that needs proof: repro-then-fix, perf against a baseline, refactors, multi-file features. It routes to the rest of pstack when a step needs them. |
| Review of the pending change | `ponytail-review` | On the diff, before committing or pushing. |
| Maintainability | `thermo-nuclear-code-quality-review` | On the diff, before committing or pushing. |

Order, every time a change is ready: review the diff with `ponytail-review`, then `thermo-nuclear-code-quality-review`. If either returns a structural blocker, fix it before committing — or state plainly in the reply that it is unfixed and why. Do not commit past a blocker silently.

Reach for these directly when the work calls for them: `ponytail-audit` (whole repo, ranked), `ponytail-debt` (the `shortcut:` ledger), `tdd`, `no-comments`, `unslop`, `technical-writing`, `blast-radius`, and the `principle-*` set.

## Verification on this machine

There is no Xcode here, so nothing can be built or launched — every behavioural claim has to come from a check that actually ran, or be reported as unverified.

```bash
sh .freebuff/typecheck/shadow-check.sh   # whole app; type-check plus SILGen, exits non-zero on any error
swiftc Notch/Modules/Media/PlaybackPush.swift Notch/Modules/Media/SourceArbitration.swift \
  Notch/Core/MediaKeyTapPolicy.swift tests/media/main.swift -o .build/media-tests/check \
  && .build/media-tests/check
```

`tests/timers` and `tests/workflows` build the same way; each README beside them has the exact command. Filtering output through a pipe does not count as a pass — check the exit status of the check itself.

## Reinstalling (a fresh clone)

`.agents/` and `skills-lock.json` are gitignored local tooling, so a new checkout needs:

```bash
npx skills add DietrichGebert/ponytail -y
npx skills add "https://github.com/cursor/plugins/tree/1e5c90a4b6f249917bd21fe361b3a2a7deb741b8/pstack" -y
npx skills add "https://github.com/cursor/plugins/tree/1e5c90a4b6f249917bd21fe361b3a2a7deb741b8/cursor-team-kit/skills/thermo-nuclear-code-quality-review" -y
```
