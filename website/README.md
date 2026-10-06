# Notch — the website

The site is a **macOS desktop that lives in the browser**: a wallpaper, a menu
bar, the notch itself, desktop widgets and icons, a dock, and the marketing copy
living inside draggable windows. It is plain HTML, CSS and JavaScript with **no
build step, no framework, no bundler and no runtime dependency** — aside from a
handful of keyless public APIs the demo calls on purpose (see *Network calls*).

## Interactive desktop

- Hover the notch for 220 ms to open it; leaving closes after 200 ms. Pin it to
  keep it open. Keyboard focus in editors keeps them usable; Esc dismisses.
- Notes save to this browser's localStorage and export as `Notch-note.txt`.
  Storage errors are visible. Notes are limited to 20,000 characters.
- File Shelf accepts a picker or file drops, including drops on the closed notch.
  It holds at most 20 files / 50 MiB in memory for this page session. Save downloads
  the original file; remove/clear releases it. Nothing is uploaded; no native AirDrop.
- Timer offers 5/15/25-minute presets and a 1–180-minute custom duration, pause,
  reset, and a completion banner. It uses wall-clock deadlines to survive tab
  throttling, but it does not survive reloads or work after the page is closed.
- Right-click the desktop or an icon for a keyboard-navigable context menu.
  Shift/Cmd/Ctrl-click adds to icon selection; drag empty space for marquee selection.
- F11 or Cmd/Ctrl+Shift+D shows/restores the desktop. Cmd/Ctrl+Space opens Spotlight
  when the OS/browser does not intercept it. Cmd/Ctrl+W closes the front window and
  Cmd/Ctrl+M minimizes it when not editing; browser/OS shortcuts may take precedence.
- Inactive windows have muted traffic lights and reduced shadows. Finder's
  wallpaper folder opens directly to the supplied images.

## Files

```
index.html          the whole page: <head> metadata + eight empty mount points
css/main.css        THE SHELL — tokens, wallpaper layers, mount geometry,
                    stacking order, menu bar, menubar popups, Spotlight, media queries
css/notch.css       native-shaped hover notch, dashboard, media and local tools
css/windows.css     window chrome: titlebar, traffic lights, Safari address bar,
                    resize handles, fallback card
css/dock.css        the Dock tray, magnification boxes, tooltips, running dots
css/widgets.css     right-hand widget column (calendar, weather, clocks, markets, CTA)
css/promo.css       left-hand promo column (download card, banners, sticky note)
css/desktop-icons.css  draggable desktop icons
css/apps.css        in-window content: GitHub replica, cards, Finder, Preview,
                    Messages, Terminal, Camera Mirror, Launchpad
css/settings-app.css   the System Settings window (sidebar + white panes)
js/config.js        single source of truth: name, links, wallpapers, music, version
js/menubar.js       menu bar + its popups + the wallpaper rotator
js/notch.js         hover/pin state, preview transport, Notes, Timer and File Shelf
js/windows.js       window manager: open/focus/minimize/zoom/drag/resize
js/apps.js          renderers for everything that lives inside a window + the VFS
js/dock.js          dock tray, magnification, running indicators
js/widgets.js       desktop widget column
js/promo.js         promo column
js/desktop-icons.js draggable desktop icons
js/settings-app.js  System Settings panes + the settings contract
assets/icon.png     app icon (favicon, dock, cards, manifest)
assets/icons/       macOS app icons used by the Dock and Launchpad
assets/wallpapers/  the rotating wallpapers (Unsplash, credited in js/config.js)
```

## The shell (css/main.css)

`main.css` is the only stylesheet that lays out the page. Every other file styles
*inside* a mount point. Stacking order is documented at the top of the file and
matters when you add a layer:

```
  0  #desktop (wallpaper layers)      40  #dock-root
  2  #icons-root                      44  .tb-dim (brightness)
  3  #widgets-root / #promo-root      50  #menubar-root
 10  #windows-root                    55  #notch-root (owns the bar's middle strip)
 30  (free)                           60  .tb-spotlight
```

Two rules that are easy to break:

- A mount that is `pointer-events: none` needs its **inner container** to re-enable
  events (`.tb-promo`, `.tb-widgets`, `.tb-icon`, `.tb-window` all do). `#dock-root`
  deliberately does *not* set `none`: the tray shrink-wraps its root, and
  `dock.css` never re-enables pointer events for it.
- The notch sits **above** the menu bar (z-index 55) because the bar's middle is
  empty. Lower it and the notch becomes unclickable behind the bar's full-width
  background.

Every popup (`#menubar-root`'s dropdowns, Power, Control Center, and the
body-level Spotlight overlay) is toggled with the `hidden` attribute, so those
classes restate `display: none` for `[hidden]` — a `display: flex` rule would
otherwise beat the attribute.

## Configuration is one file

`js/config.js` is loaded first and is the only place that defines
`window.TB_CONFIG` and `window.TB_SETTINGS`:

- `siteName` / `appName` — the menu bar's bold name, window titles, cards.
- `links` — GitHub, releases, issues, README, third-party notices, and the tags API.
- `wallpapers` — the rotating list plus its credit chip metadata.
- `music` — the demo track; an empty `audioUrl` makes the notch look up a 30-second
  iTunes preview at runtime.
- `getLatestTag()` — cached (1 h) GitHub tag lookup for every version label, with a
  hard-coded fallback so the page never shows an empty version.

Rename the product or repoint the repository **here**, not in the modules.

## Apps: adding one means five edits

There is no registry object; an app is wired in the places that can reach it:

1. `js/windows.js` — `APP_SPECS` (title, chrome, emoji, default size/position).
2. `js/apps.js` — a `render…()` and a `case` in the `TBApps.render` switch.
3. `js/dock.js` — an `ICONS` entry (and `WINDOW_APP_TO_ICON` if it should light a dot).
4. `js/menubar.js` — a `SPOTLIGHT_APPS` row so Spotlight can find it.
5. Whatever links to it (a widget, a promo card, the Window menu).

An id that exists in `APP_SPECS` but has no renderer still opens a window: the
manager falls back to a card with an "open in new tab" link, which is how you can
tell a missing renderer from a broken one.

App ids used here: `releases`, `safari`, `download`, `about`, `folder`, `viewer`,
`messages`, `facetime` (Camera Mirror), `terminal`, `apps` (Launchpad), `settings`.
`music` is *not* a window — the notch owns it (`js/notch.js` listens for
`tb:open-app` with `app: 'music'` and expands).

## Content honesty

The demos are labelled as demos and do not invent third-party facts:

- **Messages** is a scripted feature tour sent by Notch's own subsystems, not
  testimonials. Do not put quotes attributed to real people in without a source.
- **Safari** renders a GitHub-style replica of `Wub796/Notch` with no invented star,
  watch or fork counters.
- **Finder / Preview** browse a virtual filesystem whose text entries are the real
  files on the origin, so opening `index.html` shows the actual current source.
- **Camera Mirror** states that the page never opens the visitor's camera.
- **Releases & install** carries the real requirements and the real
  `xattr -dr com.apple.quarantine` step from the project README.

## Network calls (and the CSP)

The page is static, but the demo is live in four places, which is why `_headers`
ships a CSP with explicit origins instead of a bare `script-src 'self'`:

| Call | Used by |
| :--- | :--- |
| `api.github.com/…/tags` | version labels (`getLatestTag`) |
| `api.open-meteo.com` | weather widget (falls back to static content + an "offline" badge) |
| `api.coingecko.com` | markets widget (same graceful fallback) |
| `itunes.apple.com` + `*.mzstatic.com` | artwork and the 30-second preview in the notch |
| `googletagmanager.com`, `cloudflareinsights.com` | analytics, see below |

`Permissions-Policy` allows `geolocation=(self)` so the weather widget can use the
visitor's position; it silently falls back to a fixed city if the prompt is
declined or the API is unavailable.

**Analytics.** `index.html` carries a GA4 snippet with a placeholder measurement id
(`G-XXXXXXXXXX`) and a commented-out Cloudflare beacon. Both are wired into the
CSP, so enabling them is: paste your own id/token, uncomment if needed. They are
deliberately *not* pointed at another project's property or beacon token.

## The repository-root mirror

The repository root holds a byte-identical copy of this directory so the site can
also be served from `/` (`wrangler.jsonc` points at `./website`; GitHub Pages can
serve the root). **Any change made here must be copied there**, or the two
deployments drift.

Copy the site's own paths only — never `rsync --delete` a site directory into the
repository root, which would take the Xcode project, README, tests and plans with
it:

```bash
rm -rf css js assets
cp -R website/css website/js website/assets .
cp website/index.html website/404.html website/_headers \
   website/robots.txt website/sitemap.xml .
```

Check `git status` afterwards: the copy removes root files the new site no longer
ships (`css/styles.css`, `js/main.js`, `js/vendor/`); stage those deliberately. To
confirm the mirror is exact:

```bash
for f in index.html 404.html _headers robots.txt sitemap.xml; do
  diff -q "$f" "website/$f" || echo "DRIFT: $f"
done
diff -r css website/css && diff -r js website/js && diff -r assets website/assets
echo "mirror verified"
```

## Previewing locally

```bash
python3 -m http.server 8817 --directory website   # then open http://127.0.0.1:8817/
```

Worth re-checking after a change:

- The eight mount points in `index.html` all have content (no bare page).
- The dock opens a window; the notch expands on click; `Esc` dismisses windows.
- Console is clean apart from the widgets' one-time "offline" warnings when a
  public API is rate-limited.
- Desktop icons sit **left of the widget column** and **below the menu bar**; a
  page that boots without a viewport (background tab, hidden webview) must
  re-place them on the first real resize rather than pinning them into the corner.

## Deployment

Zero build step: publish this directory as-is (`website/` with `wrangler.jsonc`,
or the repository root). `_headers` is applied by Cloudflare Pages / Netlify;
`robots.txt` and `sitemap.xml` point at `https://notch.app/`.
