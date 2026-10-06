/* js/dock.js — macOS-style Dock. Owned by Dev C.
   Renders into <div id="dock-root">. Dispatches 'tb:open-app' on icon clicks,
   listens for 'tb:music-state' / 'tb:window-state' to drive running dots.
   Degrades silently if the mount point or peer modules are missing. */
(function () {
    'use strict';

    var BASE = 52;        /* icon layout size (px) */
    var MAX_SCALE = 1.6;  /* peak magnification at cursor center (~84px) */
    var RANGE = 100;      /* cosine falloff radius (px) */
    var LIFT = 14;        /* max translateY lift at full scale (px) */

    /* window-state app name -> dock icon id (GitHub shares app 'safari' but
       has no dot of its own — the Safari icon carries that indicator). */
    var WINDOW_APP_TO_ICON = {
        about: 'finder',
        music: 'notch',
        safari: 'safari',
        download: 'download',
        releases: 'releases',
        messages: 'messages',
        facetime: 'facetime',
        terminal: 'terminal',
        apps: 'apps',
        settings: 'settings'
    };

    /* Icons that macOS has but this site has no PNG for: inline SVG data URIs.
       Keeps the tray self-contained (no remote image, no CSP allowance). */
    function dataIcon(svg) {
        return 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(svg);
    }

    var SVG_LAUNCHPAD =
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">' +
        '<rect x="3" y="3" width="58" height="58" rx="14" fill="#f2f2f7"/>' +
        '<g fill="#0a84ff">' +
        '<rect x="15" y="15" width="9.5" height="9.5" rx="3"/><rect x="27.3" y="15" width="9.5" height="9.5" rx="3"/><rect x="39.5" y="15" width="9.5" height="9.5" rx="3"/>' +
        '<rect x="15" y="27.3" width="9.5" height="9.5" rx="3"/><rect x="27.3" y="27.3" width="9.5" height="9.5" rx="3"/><rect x="39.5" y="27.3" width="9.5" height="9.5" rx="3"/>' +
        '<rect x="15" y="39.5" width="9.5" height="9.5" rx="3"/><rect x="27.3" y="39.5" width="9.5" height="9.5" rx="3"/><rect x="39.5" y="39.5" width="9.5" height="9.5" rx="3"/>' +
        '</g></svg>';

    var SVG_DOWNLOADS =
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">' +
        '<path d="M8 48V18a5 5 0 0 1 5-5h9.5l4.5 5H51a5 5 0 0 1 5 5v25a5 5 0 0 1-5 5H13a5 5 0 0 1-5-5z" fill="#5aa9e6"/>' +
        '<path d="M8 25.5h48V48a5 5 0 0 1-5 5H13a5 5 0 0 1-5-5z" fill="#7ec3f7"/>' +
        '<path d="M32 31v13m0 0-6.5-6.5M32 44l6.5-6.5" fill="none" stroke="#fff" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"/>' +
        '</svg>';

    var SVG_TRASH =
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">' +
        '<path d="M18 20h28l-2.4 33.6a6 6 0 0 1-6 5.6H26.4a6 6 0 0 1-6-5.6z" fill="#dcdce2" stroke="rgba(0,0,0,.18)"/>' +
        '<rect x="12.5" y="13.5" width="39" height="6.5" rx="3.2" fill="#bcbcc4" stroke="rgba(0,0,0,.16)"/>' +
        '<path d="M26 13.5V11a3 3 0 0 1 3-3h6a3 3 0 0 1 3 3v2.5" fill="none" stroke="#9a9aa2" stroke-width="2.6"/>' +
        '<g stroke="#adadb8" stroke-width="2" stroke-linecap="round"><path d="M26 28.5v21"/><path d="M32 28.5v23"/><path d="M38 28.5v21"/></g>' +
        '</svg>';

    /* null entries render as 1px vertical separators. Defs with an `icon` path
       render a PNG (or inline SVG data URI) instead of the emoji/gradient; defs
       with an `href` open a new tab instead of dispatching 'tb:open-app'. */
    var ICONS = [
        { id: 'finder', label: 'Finder', icon: 'assets/icons/finder.png', app: 'about' },
        { id: 'notch', label: 'Notch', icon: 'assets/icon.png', app: 'music' },
        { id: 'safari', label: 'Safari', icon: 'assets/icons/safari.png', app: 'safari' },
        { id: 'github', label: 'GitHub', icon: 'assets/icons/github.png', app: 'safari' },
        { id: 'messages', label: 'Messages', icon: 'assets/icons/messages.png', app: 'messages' },
        { id: 'facetime', label: 'Camera Mirror', icon: 'assets/icons/facetime.png', app: 'facetime' },
        { id: 'terminal', label: 'Terminal', icon: 'assets/icons/terminal.png', app: 'terminal' },
        { id: 'apps', label: 'Applications', icon: dataIcon(SVG_LAUNCHPAD), app: 'apps' },
        { id: 'releases', label: 'Releases & Install', icon: 'assets/icons/app-store.png', app: 'releases' },
        { id: 'settings', label: 'System Settings', icon: 'assets/icons/settings.png', app: 'settings' },
        null,
        { id: 'download', label: 'Downloads', icon: dataIcon(SVG_DOWNLOADS), app: 'download' },
        { id: 'trash', label: 'Trash', icon: dataIcon(SVG_TRASH), app: null }
    ];

    function init() {
        var mount = document.getElementById('dock-root');
        if (!mount) { return; }

        var tray = document.createElement('nav');
        tray.className = 'tb-dock';
        tray.setAttribute('aria-label', 'Dock');

        var items = []; /* { item, btn } for magnification */
        var dots = {};  /* icon id -> dot element */

        ICONS.forEach(function (def) {
            if (def === null) {
                var sep = document.createElement('div');
                sep.className = 'tb-dock-separator';
                sep.setAttribute('aria-hidden', 'true');
                tray.appendChild(sep);
                return;
            }

            var item = document.createElement('div');
            item.className = 'tb-dock-item';

            var tooltip = document.createElement('span');
            tooltip.className = 'tb-dock-tooltip';
            tooltip.setAttribute('aria-hidden', 'true');
            tooltip.textContent = def.label;

            var btn = document.createElement('button');
            btn.type = 'button';
            btn.className = 'tb-dock-icon';
            btn.setAttribute('aria-label', def.label);

            var img = document.createElement('span');
            img.className = 'tb-dock-icon-img';
            img.setAttribute('aria-hidden', 'true');
            if (def.icon) {
                /* PNG icon: full-bleed squircle, no gradient or emoji. */
                var file = document.createElement('img');
                file.className = 'tb-dock-icon-img-file';
                file.src = def.icon;
                file.alt = '';
                file.setAttribute('aria-hidden', 'true');
                file.draggable = false;
                img.appendChild(file);
            } else {
                img.style.background =
                    'linear-gradient(180deg, ' + def.colors[0] + ' 0%, ' + def.colors[1] + ' 100%)';
                img.textContent = def.emoji;
            }

            var dot = document.createElement('span');
            dot.className = 'tb-dock-dot';
            dot.setAttribute('aria-hidden', 'true');

            btn.appendChild(img);
            item.appendChild(tooltip);
            item.appendChild(btn);
            item.appendChild(dot);
            tray.appendChild(item);

            items.push({ item: item, btn: btn });
            dots[def.id] = dot;

            if (def.href) {
                /* External link: open in a new tab, no app dispatch, no dot. */
                btn.addEventListener('click', function () {
                    window.open(def.href, '_blank', 'noopener');
                });
            } else if (def.app) {
                btn.addEventListener('click', function () {
                    window.dispatchEvent(new CustomEvent('tb:open-app', { detail: { app: def.app } }));
                });
            } else {
                /* Trash: decorative — wiggle instead of dispatching. */
                btn.addEventListener('click', function () {
                    btn.classList.remove('tb-dock-icon--wiggle');
                    void btn.offsetWidth; /* restart the animation */
                    btn.classList.add('tb-dock-icon--wiggle');
                });
                btn.addEventListener('animationend', function () {
                    btn.classList.remove('tb-dock-icon--wiggle');
                });
            }
        });

        mount.appendChild(tray);

        /* ---- Magnification: scale by cursor distance AND push neighbors apart
           (each icon shifts by the accumulated extra width before it), so scaled
           icons spread with a real gap instead of stacking on each other. Rest
           centers are cached per hover session so tray padding growth and item
           shifts can't feed back into the distance math. ---- */
        var restCenters = null;

        function cacheRestCenters() {
            restCenters = items.map(function (it) {
                var r = it.item.getBoundingClientRect();
                return r.left + r.width / 2;
            });
        }

        function magnify(clientX) {
            if (!restCenters) { cacheRestCenters(); }
            var scales = [];
            var i;
            var maxScale = (window.TB_SETTINGS && typeof window.TB_SETTINGS.dockMaxScale === 'number')
                ? window.TB_SETTINGS.dockMaxScale : MAX_SCALE;
            for (i = 0; i < items.length; i++) {
                var dist = Math.abs(clientX - restCenters[i]);
                var scale = 1;
                if (dist < RANGE) {
                    /* cosine falloff: 1 at the cursor, 0 at the range edge */
                    var t = (Math.cos((dist / RANGE) * Math.PI) + 1) / 2;
                    scale = 1 + (maxScale - 1) * t;
                }
                scales.push(scale);
            }
            var baseTotal = 0;
            var scaledTotal = 0;
            for (i = 0; i < items.length; i++) {
                var w = BASE * scales[i];
                var shift = (scaledTotal + w / 2) - (baseTotal + BASE / 2);
                var lift = (scales[i] - 1) * LIFT;
                /* the wrapper shifts (tooltip + dot track the icon); the button
                   scales + lifts inside it */
                items[i].item.style.transform = 'translateX(' + shift.toFixed(2) + 'px)';
                items[i].btn.style.transform =
                    'translateY(' + (-lift).toFixed(2) + 'px) scale(' + scales[i].toFixed(3) + ')';
                baseTotal += BASE;
                scaledTotal += w;
            }
            /* the frosted tray grows with the spread (visual only — the distance
               math above uses the cached rest centers, never live rects) */
            var extra = Math.max(0, scaledTotal - baseTotal);
            tray.style.paddingLeft = (10 + extra / 2) + 'px';
            tray.style.paddingRight = (10 + extra / 2) + 'px';
        }

        function reset() {
            for (var i = 0; i < items.length; i++) {
                items[i].item.style.transform = '';
                items[i].btn.style.transform = '';
            }
            tray.style.paddingLeft = '';
            tray.style.paddingRight = '';
            restCenters = null;
        }

        /* magnification is a hover feature — off on narrow/touch layouts where
           the tray scrolls instead (scroll offsets would corrupt the math) */
        tray.addEventListener('mousemove', function (e) {
            if (window.innerWidth <= 768) { return; }
            if (window.TB_SETTINGS && window.TB_SETTINGS.dockMagnification === false) { return; }
            magnify(e.clientX);
        });
        tray.addEventListener('mouseleave', reset);
        /* System Settings toggle: snap back to rest when magnification turns off */
        window.addEventListener('tb:settings', function (e) {
            var d = e && e.detail;
            if (d && d.key === 'dockMagnification' && d.value === false) { reset(); }
        });

        /* ---- Running-indicator dots ---- */
        function setDot(iconId, on) {
            var dot = dots[iconId];
            if (dot) { dot.classList.toggle('tb-dock-dot--on', !!on); }
        }

        /* Music dot follows playback state from the notch module. */
        window.addEventListener('tb:music-state', function (e) {
            var d = e && e.detail;
            if (!d) { return; }
            setDot('notch', d.playing === true);
        });

        /* Finder/Safari/Downloads/Coffee dots follow window state. */
        window.addEventListener('tb:window-state', function (e) {
            var d = e && e.detail;
            if (!d || typeof d.app !== 'string') { return; }
            var iconId = WINDOW_APP_TO_ICON[d.app];
            if (!iconId) { return; }
            setDot(iconId, d.state !== 'closed');
        });
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }
})();
