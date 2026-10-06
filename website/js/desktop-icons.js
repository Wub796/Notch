/* js/desktop-icons.js — macOS-style desktop icons. Owned by Dev 2 (Dev F).
   Renders into <div id="icons-root"> (full-area fixed layer from main.css,
   click-through): three blue folders + one README document. Icons are absolutely
   positioned and freely draggable with the pointer; positions persist to
   localStorage ('tb-icon-positions', {id:{x,y}}) and re-clamp into the root on
   window resize. Default layout (no saved state) is the top-right vertical
   stack. Single-click selects (one at a time, aria-pressed semantics);
   pointerdown on empty desktop space deselects. Double-click — or Enter/Space
   on a focused+selected icon — dispatches 'tb:open-app' on window,
   fire-and-forget. The click/double-click ending a drag is suppressed.
   Supports additive selection, marquee selection, keyboard context menus and
   desktop cleanup. Storage failures keep positions in memory only. */
(function () {
    'use strict';

    /* detail payloads follow the manager's event contract verbatim — each is
       dispatched as the `detail` of a window 'tb:open-app' CustomEvent. */
    var ICONS = [
        {
            id: 'folder-project', label: 'notch-website', glyph: 'folder',
            detail: { app: 'folder', folder: 'project', title: 'notch-website' }
        },
        {
            id: 'folder-wallpapers', label: 'wallpapers', glyph: 'folder',
            detail: { app: 'folder', folder: 'wallpapers', title: 'wallpapers' }
        },
        {
            id: 'downloads', label: 'Downloads', glyph: 'folder',
            detail: { app: 'download' }
        },
        {
            id: 'readme', label: 'README.md', glyph: 'doc',
            detail: { app: 'viewer', title: 'README.md', path: 'README.md' }
        }
    ];

    var STORE_KEY = 'tb-icon-positions'; /* localStorage shape: {id:{x,y}} */
    var GAP = 18;            /* px between icons in the default vertical stack */
    var FALLBACK_W = 84;     /* icon box when unmeasurable (detached / shim) */
    var FALLBACK_H = 86;
    var DRAG_THRESHOLD = 4;  /* px of movement before a press becomes a drag */
    var CLICK_GRACE = 350;   /* ms after a drag during which clicks are ignored */

    var uid = 0; /* unique gradient ids — both folders share the shape */

    /* macOS blue folder: darker back (#5aa9e6) with the tab raised top-left,
       gradient front (#7ec3f7 → #3b82d6), subtle top highlight, 1px
       rgba(0,0,0,.15) outline. 56×42 viewBox, pure inline SVG. */
    function folderSVG() {
        uid += 1;
        var g = 'tb-folder-g' + uid;
        return '<svg viewBox="0 0 56 42" width="56" height="42" aria-hidden="true" focusable="false">' +
            '<defs><linearGradient id="' + g + '" x1="0" y1="0" x2="0" y2="1">' +
            '<stop offset="0" stop-color="#7ec3f7"/><stop offset="1" stop-color="#3b82d6"/>' +
            '</linearGradient></defs>' +
            '<path d="M7 40 Q1.5 40 1.5 34 L1.5 11 Q1.5 7.5 5 7.5 L8 7.5 L8 4 Q8 2 10 2 ' +
            'L17 2 Q19 2 20.5 3.5 L24.5 7.5 L50.5 7.5 Q54.5 7.5 54.5 11.5 L54.5 34 Q54.5 40 49 40 Z" ' +
            'fill="#5aa9e6" stroke="rgba(0,0,0,.15)" stroke-width="1" stroke-linejoin="round"/>' +
            '<rect x="1.5" y="10.5" width="53" height="30" rx="6" fill="url(#' + g + ')" ' +
            'stroke="rgba(0,0,0,.15)" stroke-width="1"/>' +
            '<rect x="4" y="12.5" width="48" height="2" rx="1" fill="rgba(255,255,255,.35)"/>' +
            '</svg>';
    }

    /* README page: white sheet (4px radius), folded top-right corner (light
       gray triangle), 3 gray text lines (70% width, 4px tall, rounded), tiny
       centered 🎧 near the bottom. 42×56 viewBox, pure inline SVG. */
    function docSVG() {
        return '<svg viewBox="0 0 42 56" width="42" height="56" aria-hidden="true" focusable="false">' +
            '<path d="M5 1.5 Q1.5 1.5 1.5 5 L1.5 51 Q1.5 54.5 5 54.5 L37 54.5 Q40.5 54.5 40.5 51 ' +
            'L40.5 12 L30 1.5 Z" fill="#ffffff" stroke="rgba(0,0,0,.15)" stroke-width="1" stroke-linejoin="round"/>' +
            '<path d="M30 1.5 L40.5 12 L30 12 Z" fill="#e8e8ed" stroke="rgba(0,0,0,.12)" ' +
            'stroke-width="1" stroke-linejoin="round"/>' +
            '<rect x="6.5" y="20" width="29" height="4" rx="2" fill="#d1d1d6"/>' +
            '<rect x="6.5" y="27" width="29" height="4" rx="2" fill="#d1d1d6"/>' +
            '<rect x="6.5" y="34" width="29" height="4" rx="2" fill="#d1d1d6"/>' +
            '<text x="21" y="50" font-size="14" text-anchor="middle">🎧</text>' +
            '</svg>';
    }

    /* fresh object per dispatch so a mutating listener can't poison future events */
    function freshDetail(def) {
        var d = {};
        for (var k in def.detail) {
            if (Object.prototype.hasOwnProperty.call(def.detail, k)) { d[k] = def.detail[k]; }
        }
        return d;
    }

    function openIcon(def) {
        window.dispatchEvent(new CustomEvent('tb:open-app', { detail: freshDetail(def) }));
    }

    /* --- persistence: in-memory mirror is the truth; storage is best-effort --- */
    function loadPositions() {
        try {
            var raw = window.localStorage.getItem(STORE_KEY);
            if (!raw) { return {}; }
            var parsed = JSON.parse(raw);
            return (parsed && typeof parsed === 'object') ? parsed : {};
        } catch (e) { return {}; } /* corrupt JSON or no storage → defaults */
    }

    function savePositions(positions) {
        try { window.localStorage.setItem(STORE_KEY, JSON.stringify(positions)); }
        catch (e) { /* private mode / quota → keep in-memory only, no console noise */ }
    }

    function isSaved(p) {
        return !!p && typeof p.x === 'number' && isFinite(p.x) &&
            typeof p.y === 'number' && isFinite(p.y);
    }

    function init() {
        var mount = document.getElementById('icons-root');
        if (!mount) { return; }

        var stack = document.createElement('div');
        stack.className = 'tb-icons';

        var positions = loadPositions();
        var entries = []; /* [{def, el, x, y}] — layout source of truth */
        /* A page can boot before it has been given a real viewport (a background
           tab, a hidden webview). Geometry measured then is 0×0, so positions
           clamped against it are garbage — drop the saved state and let the
           first resize re-run the default stack instead of pinning everything
           into the top-left corner. Positions are only treated as "the user put
           them here" once a drag actually completes. */
        var userMoved = false;

        function rootSize() {
            return { w: mount.clientWidth || 0, h: mount.clientHeight || 0 };
        }

        /* keep the icon fully inside the root */
        function clampPos(x, y, el) {
            var s = rootSize();
            var maxX = Math.max(0, s.w - (el.offsetWidth || FALLBACK_W));
            var maxY = Math.max(0, s.h - (el.offsetHeight || FALLBACK_H));
            return {
                x: Math.min(Math.max(0, x), maxX),
                y: Math.min(Math.max(0, y), maxY)
            };
        }

        function applyPos(el, x, y) {
            el.style.left = x + 'px';
            el.style.top = y + 'px';
        }

        function select(iconEl, additive) {
            entries.forEach(function (entry) {
                if (!additive) entry.el.setAttribute('aria-pressed', String(entry.el === iconEl));
                else if (entry.el === iconEl) entry.el.setAttribute('aria-pressed', String(entry.el.getAttribute('aria-pressed') !== 'true'));
            });
        }

        ICONS.forEach(function (def) {
            var icon = document.createElement('div');
            icon.className = 'tb-icon tb-icon-' + def.id;
            icon.setAttribute('role', 'button');
            icon.setAttribute('tabindex', '0');
            icon.setAttribute('aria-pressed', 'false');
            icon.setAttribute('aria-label', def.label);
            icon.setAttribute('data-app', def.detail.app);

            var glyph = document.createElement('span');
            glyph.className = 'tb-icon-glyph';
            glyph.innerHTML = def.glyph === 'folder' ? folderSVG() : docSVG();

            var label = document.createElement('span');
            label.className = 'tb-icon-label';
            label.textContent = def.label;

            icon.appendChild(glyph);
            icon.appendChild(label);

            var entry = { def: def, el: icon, x: 0, y: 0 };
            entries.push(entry);

            /* --- drag gesture: press → move > 4px → captured drag → drop+persist.
                   A press that never crosses the threshold is a plain click. --- */
            var pid = null, dragging = false, lastDragAt = 0;
            var startPX = 0, startPY = 0, startX = 0, startY = 0;

            icon.addEventListener('pointerdown', function (e) {
                if (e.button && e.button !== 0) { return; } /* primary button only */
                pid = (e.pointerId === undefined) ? 1 : e.pointerId;
                startPX = e.clientX; startPY = e.clientY;
                startX = entry.x; startY = entry.y;
                dragging = false;
            });

            icon.addEventListener('pointermove', function (e) {
                if (pid === null) { return; }
                if (e.pointerId !== undefined && e.pointerId !== pid) { return; }
                var dx = e.clientX - startPX;
                var dy = e.clientY - startPY;
                if (!dragging) {
                    if (Math.abs(dx) <= DRAG_THRESHOLD && Math.abs(dy) <= DRAG_THRESHOLD) { return; }
                    dragging = true;
                    icon.classList.add('tb-dragging'); /* grab cursor, scale, z-index */
                    try { icon.setPointerCapture(pid); } catch (err) { /* non-critical */ }
                }
                var p = clampPos(startX + dx, startY + dy, icon);
                entry.x = p.x; entry.y = p.y;
                applyPos(icon, p.x, p.y);
            });

            function endDrag(e) {
                if (pid === null) { return; }
                if (e && e.pointerId !== undefined && e.pointerId !== pid) { return; }
                if (dragging) {
                    dragging = false;
                    userMoved = true;
                    icon.classList.remove('tb-dragging');
                    try { icon.releasePointerCapture(pid); } catch (err) { /* non-critical */ }
                    positions[def.id] = { x: entry.x, y: entry.y };
                    savePositions(positions);
                    lastDragAt = Date.now(); /* suppress the click that ends the drag */
                }
                pid = null;
            }
            icon.addEventListener('pointerup', endDrag);
            icon.addEventListener('pointercancel', endDrag);

            icon.addEventListener('click', function (e) {
                if (Date.now() - lastDragAt < CLICK_GRACE) { return; }
                select(icon, e.shiftKey || e.metaKey || e.ctrlKey);
            });
            icon.addEventListener('dblclick', function () {
                if (Date.now() - lastDragAt < CLICK_GRACE) { return; } /* drag tail */
                select(icon);
                openIcon(def);
            });
            icon.addEventListener('keydown', function (e) {
                if (e.key === 'Enter' || e.key === ' ' || e.key === 'Spacebar') {
                    e.preventDefault();
                    /* contract: Enter/Space opens a focused+selected icon; a first
                       press on an unselected icon just selects it (mirrors click) */
                    if (icon.getAttribute('aria-pressed') === 'true') { openIcon(def); }
                    else { select(icon); }
                }
            });

            stack.appendChild(icon);
        });

        mount.appendChild(stack);

        /* layout: saved positions (clamped) win; otherwise the default stack sits
           LEFT of the top-right widget column (macOS Sonoma behavior — icons yield
           the right edge to widgets): root width minus the 330px widget column
           minus a 24px gutter, GAP-px vertical rhythm, measured live */
        var WIDGET_ZONE = 354; /* 330px widget column + 24px gutter */
        function layout() {
            var size = rootSize();
            /* A viewport that has not been given a size yet (background tab,
               hidden webview) cannot place anything: leave the icons alone and
               let the first real resize place them. */
            if (size.w <= 0 || size.h <= 0) { return; }
            var accY = 0;
            entries.forEach(function (entry) {
                var saved = positions[entry.def.id];
                var w = entry.el.offsetWidth || FALLBACK_W;
                var h = entry.el.offsetHeight || FALLBACK_H;
                var p = isSaved(saved)
                    ? clampPos(saved.x, saved.y, entry.el)
                    : clampPos(Math.max(0, size.w - WIDGET_ZONE - w), accY, entry.el);
                accY += h + GAP;
                entry.x = p.x; entry.y = p.y;
                applyPos(entry.el, p.x, p.y);
                positions[entry.def.id] = { x: p.x, y: p.y };
            });
            savePositions(positions);
        }
        layout();

        /* window resize → the default stack re-flows; hand-placed icons re-clamp */
        window.addEventListener('resize', function () {
            if (!userMoved) {
                layout();
                return;
            }
            entries.forEach(function (entry) {
                var p = clampPos(entry.x, entry.y, entry.el);
                entry.x = p.x; entry.y = p.y;
                applyPos(entry.el, p.x, p.y);
                positions[entry.def.id] = { x: p.x, y: p.y };
            });
            savePositions(positions);
        });

        /* The mount can be laid out *after* this script runs: a page restored in
           a background tab, a webview that sizes once it is shown, a rotated
           phone. A ResizeObserver is the only signal that fires for all of them,
           so the default stack always ends up placed against a real box. */
        if (typeof ResizeObserver === 'function') {
            var lastW = -1, lastH = -1;
            try {
                new ResizeObserver(function () {
                    var size = rootSize();
                    if (size.w === lastW && size.h === lastH) { return; }
                    lastW = size.w; lastH = size.h;
                    if (!userMoved) { layout(); }
                }).observe(mount);
            } catch (e) { /* no ResizeObserver in odd shims: window resize covers it */ }
        }

        /* Finder-style menus and selection live on the existing desktop canvas. */
        var menu = document.createElement('div');
        menu.className = 'tb-desktop-menu'; menu.setAttribute('role', 'menu'); menu.hidden = true;
        document.body.appendChild(menu);
        var menuOrigin = null;
        function hideMenu(restore) {
            menu.hidden = true;
            if (restore && menuOrigin) menuOrigin.focus();
        }
        function isDesktop(target) { return target === document.body || target === document.documentElement || target.closest('#desktop'); }
        function openDetail(detail) { window.dispatchEvent(new CustomEvent('tb:open-app', { detail: detail })); }
        function showMenu(x, y, actions, origin) {
            menuOrigin = origin; menu.textContent = '';
            actions.forEach(function (action) {
                if (!action) { var rule = document.createElement('hr'); menu.appendChild(rule); return; }
                var button = document.createElement('button'); button.type = 'button'; button.setAttribute('role', 'menuitem');
                button.textContent = action[0];
                button.addEventListener('click', function () { hideMenu(false); action[1](); }); menu.appendChild(button);
            });
            menu.hidden = false;
            menu.style.left = Math.max(6, Math.min(x, window.innerWidth - menu.offsetWidth - 6)) + 'px';
            menu.style.top = Math.max(32, Math.min(y, window.innerHeight - menu.offsetHeight - 6)) + 'px';
            menu.querySelector('button').focus();
        }
        function menuActions(icon) {
            if (icon) {
                var entry = entries.filter(function (e) { return e.el === icon; })[0];
                if (icon.getAttribute('aria-pressed') !== 'true') select(icon);
                return [['Open', function () { entries.filter(function (e) { return e.el.getAttribute('aria-pressed') === 'true'; }).forEach(function (e) { openIcon(e.def); }); }], null,
                    ['About Notch', function () { openDetail({ app: 'about' }); }], ['Clean Up Desktop', cleanUp]];
            }
            return [['Open Finder', function () { openDetail({ app: 'folder', folder: 'project', title: 'notch-website' }); }],
                ['Show Desktop / Restore Windows', function () { window.dispatchEvent(new CustomEvent('tb:show-desktop')); }], null,
                ['Clean Up Desktop', cleanUp], ['Change Wallpaper…', function () { openDetail({ app: 'settings' }); }], null,
                ['Open Notch Notes', function () { window.dispatchEvent(new CustomEvent('tb:notch-view', { detail: { view: 'notes' } })); }]];
        }
        function cleanUp() {
            positions = {}; userMoved = false; layout();
        }
        document.addEventListener('contextmenu', function (e) {
            var icon = e.target.closest('.tb-icon');
            if (!icon && !isDesktop(e.target)) return;
            e.preventDefault(); showMenu(e.clientX, e.clientY, menuActions(icon), icon);
        });
        menu.addEventListener('keydown', function (e) {
            var buttons = Array.prototype.slice.call(menu.querySelectorAll('button'));
            var index = buttons.indexOf(document.activeElement);
            if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
                e.preventDefault(); buttons[(index + (e.key === 'ArrowDown' ? 1 : -1) + buttons.length) % buttons.length].focus();
            } else if (e.key === 'Escape' || e.key === 'Tab') { e.preventDefault(); e.stopPropagation(); hideMenu(true); }
        });
        var selection = document.createElement('div'); selection.className = 'tb-desktop-selection'; selection.hidden = true; document.body.appendChild(selection);
        var gesture = null;
        document.addEventListener('pointerdown', function (e) {
            if (!menu.contains(e.target)) hideMenu(false);
            if (e.button !== 0 || !isDesktop(e.target)) return;
            if (!e.shiftKey && !e.metaKey && !e.ctrlKey) select(null);
            gesture = { id: e.pointerId, x: e.clientX, y: e.clientY, selected: entries.map(function (entry) { return entry.el.getAttribute('aria-pressed') === 'true'; }) };
            e.preventDefault();
        });
        document.addEventListener('pointermove', function (e) {
            if (!gesture || gesture.id !== e.pointerId) return;
            var left = Math.min(e.clientX, gesture.x), top = Math.min(e.clientY, gesture.y);
            var right = Math.max(e.clientX, gesture.x), bottom = Math.max(e.clientY, gesture.y);
            selection.hidden = false; selection.style.left = left + 'px'; selection.style.top = top + 'px';
            selection.style.width = (right - left) + 'px'; selection.style.height = (bottom - top) + 'px';
            entries.forEach(function (entry, i) {
                var r = entry.el.getBoundingClientRect();
                entry.el.setAttribute('aria-pressed', String(gesture.selected[i] || (r.right > left && r.left < right && r.bottom > top && r.top < bottom)));
            });
        });
        function finishSelection() { gesture = null; selection.hidden = true; }
        document.addEventListener('pointerup', finishSelection); document.addEventListener('pointercancel', finishSelection);
        window.addEventListener('blur', function () { finishSelection(); hideMenu(false); });
        window.addEventListener('resize', function () { hideMenu(false); });
        document.addEventListener('keydown', function (e) {
            if (e.target.closest('input, textarea, [contenteditable="true"], .tb-window, #notch-root, .tb-spotlight')) return;
            if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'a') {
                e.preventDefault(); entries.forEach(function (entry) { entry.el.setAttribute('aria-pressed', 'true'); });
            }
            if (e.key === 'Escape' && !menu.hidden) { e.preventDefault(); e.stopImmediatePropagation(); hideMenu(true); }
            if ((e.key === 'F10' && e.shiftKey) && e.target.closest('.tb-icon')) {
                e.preventDefault(); var icon = e.target.closest('.tb-icon'), rect = icon.getBoundingClientRect();
                showMenu(rect.left, rect.bottom, menuActions(icon), icon);
            }
        });
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }
})();
