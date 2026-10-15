# Appcast checks

Run from the workspace root on macOS:

```bash
mkdir -p .build/updates
swiftc tests/updates/main.swift -o .build/updates/check
.build/updates/check build/release/2.0.3/appcast.xml \
  build/release/2.0.3/archives/Notch.zip \
  Notch/Info.plist 2.0.3
```

That is what [Scripts/release.sh](../../Scripts/release.sh) runs before it
publishes, so the same check is what stands between a release and every Mac
pressing **Check for Updates…**.

A fifth argument names the release tag the assets live on, for the tags already
on GitHub that the script did not make: `.build/updates/check appcast.xml
Notch.zip Notch/Info.plist 1 v.2.0.3`. Without it the tag is taken to be
`v<version>`, which is what the script publishes.

## What it proves

Sparkle's gate on an update archive is the EdDSA signature carried in the
item's `sparkle:edSignature`, verified against the `SUPublicEDKey` compiled into
the running app, plus the `length` it compares against the bytes it downloaded.
Both are checked here against the real archive — the signature over the file's
own bytes, with the public key read out of the app's Info.plist.

The enclosure URL is measured against the feed URL from the same Info.plist
rather than against a second copy of that address kept in the release tooling:
the checks derive `https://github.com/<owner>/<repo>/releases/download/v<version>`
from `SUFeedURL` and require the appcast to point there, so a renamed feed
cannot leave the assets behind at the old address. A `SUFeedURL` of another
shape fails the check that says so, because then this file cannot speak for the
release either.

Also covered: the appcast parses and carries at least one item; every item is
signed, so no unsigned entry can sit in the feed; exactly one item advertises
the archive being published; `sparkle:version` and
`sparkle:shortVersionString` are the version being released — the number
Sparkle compares, and the one whose repetition is an update nobody is offered;
`sparkle:minimumSystemVersion` is declared; and the declared `length` is the
archive's own length.

`checks: passed/total` and a nonzero exit on any failure; a failing check is a
failing check whether the output is piped or not.

## What this cannot check

Anything about the running app: Sparkle's own download, the install, and the
relaunch need the built app and a Mac, and nothing here builds one. The step
after the appcast exists — that `releases/latest/download/appcast.xml` answers
with these bytes — is checked by `release.sh` itself with `curl` and `cmp`
against the published release.

## Releasing

```bash
Scripts/release.sh 2.0.3 --notes-file notes.md
```

It builds the Release app with `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`
stamped from the tag, refuses a build whose `CFBundleVersion` is not that
version, refuses an app whose `SUPublicEDKey` differs from
`Notch/Info.plist`'s, refuses a build that is not code signed (Sparkle will not
install an unsigned update over a signed app), packages `Notch.zip`, generates
and signs the appcast through Sparkle's own `generate_appcast`, runs the checks
above, then creates the GitHub release and confirms the feed URL returns exactly
those bytes. Publishing needs a clean tree, because the tag is pinned to the
commit that was built.

The appcast carries one item — the release being published — because it is
generated from that release's archive alone. Sparkle offers the newest item the
running app can install, so one item is a complete feed while every release
requires the same macOS version; `sparkle:minimumSystemVersion` is what keeps
that true, which is why its absence fails a check.

`--skip-publish` stops after the checks, for a build with no release behind it;
`--app /path/to/Notch.app` uses an app exported from Xcode's Organizer instead
of building one (copy it out of `build/release/<version>` first — that directory
is recreated empty on every run, and the script refuses an app inside it).
`generate_appcast` is found by searching the resolved packages, because the
tools ship in the package's artifact bundle rather than a path worth
hard-coding; `SPARKLE_BIN` overrides that search. The EdDSA private key has to be in the
login keychain under `https://sparkle-project.org` — `generate_keys` creates it,
and `Notch/Info.plist` already ships the matching public key.

Two things to keep in mind when publishing: the release must not be a draft or a
pre-release, because `releases/latest` does not move for those and the feed URL
would keep answering with the previous release; and the assets must be named
`Notch.zip` and `appcast.xml`, which is what makes both the feed URL and the
README's download step work.
