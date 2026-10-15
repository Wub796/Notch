#!/bin/bash
#
# Publishes a Notch release, which is what makes "Check for Updates…" work.
#
# The app's SUFeedURL points at
# https://github.com/<owner>/<repo>/releases/latest/download/appcast.xml, and
# that address only resolves if the *latest* release carries an asset named
# exactly `appcast.xml`. Sparkle then downloads the archive that asset
# advertises, so the same release has to carry `Notch.zip` too — and both facts
# are why this script exists rather than a "just drag the app to GitHub" step:
# four released tags had no assets at all, and the button raised Sparkle's
# download-failure alert on every press.
#
# Steps: build the Release app with the tag's version stamped into it, package
# it as Notch.zip, generate and sign the appcast with Sparkle's own tool, check
# both through the same gate the app applies (tests/updates), upload them to a
# new GitHub release, and confirm the feed URL resolves to the bytes just
# published.
#
# Usage:
#   Scripts/release.sh 2.0.3 [--notes-file notes.md] [--app /path/to/Notch.app]
#                            [--skip-publish] [--dry-run]
#
#   --app           use an app already built/exported from Xcode instead of
#                   building one here (an Organizer export works: point this at
#                   the Notch.app inside the exported folder)
#   --notes-file    markdown for the release body, and for the update dialog
#   --skip-publish  stop after the artifacts pass their checks; nothing is
#                   uploaded and the working tree may be dirty
#   --dry-run       show the commands that would run, without running the
#                   publish step
#
# Publishing requires a clean tree and a commit to point the tag at, because the
# release has to correspond to something. SPARKLE_BIN overrides the directory
# holding Sparkle's generate_appcast; it is found from the resolved package when
# unset.

set -euo pipefail

fail() {
    echo "release.sh: $*" >&2
    exit 1
}

usage() {
    sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
}

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

version=""
notes_file=""
app_path=""
publish=1
dry_run=0

while [ $# -gt 0 ]; do
    case "$1" in
        --notes-file) notes_file="${2:-}"; shift 2 ;;
        --app) app_path="${2:-}"; shift 2 ;;
        --skip-publish) publish=0; shift ;;
        --dry-run) dry_run=1; shift ;;
        -h|--help) usage; exit 0 ;;
        -*) fail "unknown option $1" ;;
        *) version="$1"; shift ;;
    esac
done

version="${version#v}"
if ! printf '%s' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    fail "give a version like 2.0.3 (got \"$version\")"
fi
tag="v$version"

for tool in ditto unzip codesign curl swiftc; do
    command -v "$tool" >/dev/null || fail "$tool is not on PATH"
done

# The release tooling reads the owner, the repo and the feed URL out of the app
# itself, so a renamed feed cannot leave the assets behind at the old address.
feed_url="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' Notch/Info.plist 2>/dev/null)" \
    || fail "Notch/Info.plist has no SUFeedURL"
case "$feed_url" in
    https://github.com/*/releases/latest/download/*) ;;
    *) fail "SUFeedURL ($feed_url) is not a GitHub release asset URL; this script cannot publish a feed it cannot predict" ;;
esac
slug="${feed_url#https://github.com/}"
slug="${slug%%/releases/*}"
feed_name="${feed_url##*/}"
download_prefix="https://github.com/$slug/releases/download/$tag/"
expected_feed_url="https://github.com/$slug/releases/latest/download/$feed_name"

work="build/release/$version"
app=""

# --app is resolved before the scratch directory is recreated, because the
# point of passing one is to use an app that already exists, and the scratch
# directory is wiped on every run — an --app inside it would be gone by the
# time anything read it.
if [ -n "$app_path" ]; then
    [ -d "$app_path" ] || fail "no app bundle at $app_path"
    app_dir="$(cd "$(dirname "$app_path")" && pwd)"
    case "$app_dir/" in
        "$root/$work"*) fail "--app points inside $work, which this run recreates; copy the app somewhere else first" ;;
    esac
    app="$app_path"
fi

rm -rf "$work"
mkdir -p "$work/archives"

echo "== Release $tag of $slug"
echo "   feed: $expected_feed_url"

# MARK: - Build

if [ -n "$app" ]; then
    echo "== App: using $app (no build)"
else
    command -v xcodebuild >/dev/null || fail "xcodebuild is not on PATH; build in Xcode and pass --app"
    # MARKETING_VERSION and CURRENT_PROJECT_VERSION are stamped from the tag, so
    # the archive's sparkle:version is the tag and every release outranks the
    # one before it. The project's own values are placeholders for local builds.
    echo "== Build: Release, MARKETING_VERSION=$version CURRENT_PROJECT_VERSION=$version"
    xcodebuild \
        -project Notch.xcodeproj \
        -scheme Notch \
        -configuration Release \
        -derivedDataPath "$work/DerivedData" \
        -clonedSourcePackagesDirPath "$work/SourcePackages" \
        -allowProvisioningUpdates \
        MARKETING_VERSION="$version" \
        CURRENT_PROJECT_VERSION="$version" \
        build
    app="$work/DerivedData/Build/Products/Release/Notch.app"
fi

[ -d "$app" ] || fail "no app bundle at $app"
app_plist="$app/Contents/Info.plist"
[ -f "$app_plist" ] || fail "$app is not an app bundle (no Contents/Info.plist)"

# MARK: - The app the archive will contain

built_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app_plist")"
built_short="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_plist")"
built_key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$app_plist" 2>/dev/null || true)"
repo_key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' Notch/Info.plist)"

[ "$built_version" = "$version" ] \
    || fail "the app reports CFBundleVersion $built_version, not $version — Sparkle compares that number, and a repeat of the previous one is an update nobody is offered"
[ "$built_short" = "$version" ] \
    || fail "the app reports CFBundleShortVersionString $built_short, not $version"
[ "$built_key" = "$repo_key" ] && [ -n "$built_key" ] \
    || fail "the app ships SUPublicEDKey \"$built_key\" while Notch/Info.plist ships \"$repo_key\" — Sparkle would reject every update signed for the app"

echo "== Signing"
codesign --verify --deep --strict "$app" \
    || fail "the app is not validly code signed; Sparkle refuses an unsigned update over a signed app"
authority="$(codesign -dv --verbose=2 "$app" 2>&1 | sed -n 's/^Authority=//p' | head -1 || true)"
echo "   ${authority:-ad-hoc identity}"
case "$authority" in
    "Developer ID Application"*) ;;
    *) echo "   ! not a Developer ID signature: the update installs from a locally built app, but an app distributed to others must be signed with the same identity as the copy it replaces" ;;
esac

# MARK: - Package

zip_path="$work/archives/Notch.zip"
echo "== Package: $zip_path"
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip_path"

# What is inside the archive is what will be installed, and it is read back out
# rather than assumed, because `ditto` on the wrong directory produces a zip
# that unzips to something else entirely.
unzip -p "$zip_path" "Notch.app/Contents/Info.plist" > "$work/archive-Info.plist" 2>/dev/null \
    || fail "$zip_path does not contain Notch.app/Contents/Info.plist"
archived_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$work/archive-Info.plist" 2>/dev/null || echo "")"
archived_key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$work/archive-Info.plist" 2>/dev/null || echo "")"
[ "$archived_version" = "$version" ] \
    || fail "the archive holds an app reporting CFBundleVersion \"$archived_version\", not $version"
[ "$archived_key" = "$repo_key" ] \
    || fail "the archive holds an app with a different SUPublicEDKey"

# MARK: - Appcast

sparkle_bin="${SPARKLE_BIN:-}"
if [ -z "$sparkle_bin" ]; then
    echo "== Sparkle: resolving package tools"
    xcodebuild \
        -project Notch.xcodeproj \
        -resolvePackageDependencies \
        -clonedSourcePackagesDirPath "$work/SourcePackages" \
        > "$work/resolve.log" 2>&1 \
        || { cat "$work/resolve.log" >&2; fail "could not resolve the Sparkle package"; }
    # The tools ship in Sparkle's artifact bundle, which SPM unpacks beside the
    # checkouts — artifacts/sparkle/Sparkle/bin — while a checkout Xcode made
    # earlier keeps a copy in checkouts/Sparkle/bin. Search for whichever one
    # this resolve produced instead of assuming a layout that is not documented
    # and has already changed once.
    found_tool="$(find "$work/SourcePackages" -type f -name generate_appcast \
        -path '*/bin/*' -print -quit 2>/dev/null || true)"
    if [ -n "$found_tool" ]; then
        sparkle_bin="$(dirname "$found_tool")"
    fi
fi
if [ -z "$sparkle_bin" ] || [ ! -x "$sparkle_bin/generate_appcast" ]; then
    fail "no generate_appcast found (looked under ${sparkle_bin:-the resolved packages}; set SPARKLE_BIN to Sparkle's bin directory)"
fi

# A notes file beside the archive is what generate_appcast embeds in the item,
# so the update dialog and the release body say the same thing.
notes_flag=""
if [ -n "$notes_file" ]; then
    [ -f "$notes_file" ] || fail "no notes file at $notes_file"
    cp "$notes_file" "$work/archives/Notch.md"
    notes_flag="--embed-release-notes"
fi

appcast="$work/appcast.xml"
echo "== Appcast: $appcast"
generate_appcast() {
    if [ -n "$notes_flag" ]; then
        "$sparkle_bin/generate_appcast" "$notes_flag" "$@"
    else
        "$sparkle_bin/generate_appcast" "$@"
    fi
}
generate_appcast \
    --download-url-prefix "$download_prefix" \
    -o "$appcast" \
    "$work/archives"

# MARK: - Verify, through the app's own gate

echo "== Verify"
mkdir -p .build/updates
swiftc tests/updates/main.swift -o .build/updates/check
.build/updates/check "$appcast" "$zip_path" Notch/Info.plist "$version" \
    || fail "the appcast would be rejected by the app — nothing was published"

# MARK: - Publish

if [ "$publish" -eq 0 ]; then
    echo "== Skipping publish (--skip-publish)"
    echo "   $zip_path"
    echo "   $appcast"
    exit 0
fi

[ -z "$(git status --porcelain)" ] \
    || fail "the working tree has uncommitted changes; a release has to correspond to a commit, so commit or stash them first (or pass --skip-publish to build without publishing)"
if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
    fail "tag $tag already exists — releases are append-only; bump the version instead"
fi
command -v gh >/dev/null || fail "gh is not on PATH"
gh auth status >/dev/null 2>&1 || fail "gh is not authenticated; run gh auth login"

if [ "$dry_run" -eq 1 ]; then
    echo "== Dry run: would publish tag $tag at $(git rev-parse --short HEAD)"
    echo "   gh release create $tag --title \"Notch App - $tag\" --latest ... $zip_path $appcast"
    exit 0
fi

release_notes="Notch $version"
if [ -n "$notes_file" ]; then
    release_notes="$(cat "$notes_file")"
fi

echo "== Publish: $tag"
# `--target` pins the tag to the commit that was built. Without it gh tags the
# default branch's tip, which is not necessarily what is in this archive.
gh release create "$tag" \
    --title "Notch App - $tag" \
    --latest \
    --target "$(git rev-parse HEAD)" \
    --notes "$release_notes" \
    "$zip_path" "$appcast"

# The whole point of the release: the address the app asks for now answers with
# the appcast that was just built, byte for byte. `releases/latest` only moves
# for a published release, so a draft or a pre-release would fail here.
#
# It is retried, because `releases/latest` is answered by a CDN edge that does
# not turn over the instant the release is created: the first fetch after a
# publish that has already succeeded can still return the *previous* release's
# appcast, and calling that a failed release is worse than not checking. Only
# the last attempt decides, so a feed that never serves these exact bytes still
# fails the run.
echo "== Feed: $expected_feed_url"
published="$work/published-appcast.xml"
attempts=6
attempt=1
while : ; do
    if curl -fsSL "$expected_feed_url" -o "$published" && cmp -s "$appcast" "$published"; then
        break
    fi
    if [ "$attempt" -ge "$attempts" ]; then
        fail "$expected_feed_url still does not answer with the appcast that was built, after $attempts attempts ($tag itself is published — check that it is the latest release, is not a draft or a pre-release, and carries $feed_name)"
    fi
    echo "   attempt $attempt of $attempts did not return these bytes (edge catching up)"
    attempt=$((attempt + 1))
    sleep 5
done

echo "== Done: $tag is live at $expected_feed_url"
