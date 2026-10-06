/* js/settings-app.js — System Settings app (macOS Sequoia style).
   TBApps.render('settings') calls TBSettingsUI(opts) -> HTMLElement.
   Settings contract — every control change performs all three steps:
   (1) mutate window.TB_SETTINGS[key], (2) persist the whole object to
   localStorage 'tb-settings' as JSON, (3) dispatch the window CustomEvent
   'tb:settings', detail { key, value }. Consumers (dock magnification,
   Control Center dim overlay, wallpaper rotator) listen for 'tb:settings';
   this module only emits. */
(function () {
    'use strict';

    var STORE_KEY = 'tb-settings';

    /* ---------- store helpers ---------- */

    function store() {
        if (typeof window.TB_SETTINGS === 'undefined' || !window.TB_SETTINGS) {
            window.TB_SETTINGS = {};
        }
        return window.TB_SETTINGS;
    }

    function get(key, fallback) {
        var v = store()[key];
        return typeof v === 'undefined' ? fallback : v;
    }

    function persist() {
        try {
            localStorage.setItem(STORE_KEY, JSON.stringify(store()));
        } catch (e) { /* storage blocked → settings live for the session */ }
    }

    /* The single mutation path: steps 1–3 of the contract, always in order. */
    function commit(key, value) {
        store()[key] = value;
        persist();
        try {
            window.dispatchEvent(new CustomEvent('tb:settings', { detail: { key: key, value: value } }));
        } catch (e) { /* no CustomEvent in odd shims → value is still saved */ }
    }

    /* ---------- tiny DOM utilities (house style, mirrors js/apps.js) ---------- */

    function el(tag, className, text) {
        var node = document.createElement(tag);
        if (className) node.className = className;
        if (typeof text === 'string') node.textContent = text;
        return node;
    }

    function openApp(app) {
        try {
            window.dispatchEvent(new CustomEvent('tb:open-app', { detail: { app: app } }));
        } catch (e) { /* fire-and-forget */ }
    }

    function wallpapers() {
        var c = typeof window.TB_CONFIG !== 'undefined' ? window.TB_CONFIG : null;
        return (c && c.wallpapers) || [];
    }

    /* ---------- reusable controls ---------- */

    /* Green iOS-style switch; purely visual when onFlip is omitted. */
    function makeToggle(on, onFlip) {
        var t = el('button', 'tb-set-toggle' + (on ? ' tb-set-on' : ''));
        t.type = 'button';
        t.setAttribute('role', 'switch');
        t.setAttribute('aria-checked', on ? 'true' : 'false');
        t.appendChild(el('span', 'tb-set-knob'));
        t.addEventListener('click', function () {
            on = !on;
            t.classList.toggle('tb-set-on', on);
            t.setAttribute('aria-checked', on ? 'true' : 'false');
            if (typeof onFlip === 'function') onFlip(on);
        });
        return t;
    }

    function makeSlider(min, max, step, value, onSlide) {
        var s = el('input', 'tb-set-slider');
        s.type = 'range';
        s.min = String(min);
        s.max = String(max);
        s.step = String(step);
        s.value = String(value);
        s.addEventListener('input', function () {
            if (typeof onSlide === 'function') onSlide(parseFloat(s.value));
        });
        return s;
    }

    /* ---------- layout pieces ---------- */

    function row(label, control) {
        var r = el('div', 'tb-set-row');
        r.appendChild(el('span', 'tb-set-label', label));
        if (control) r.appendChild(control);
        return r;
    }

    function sliderRow(label, slider, val) {
        var wrap = el('span', 'tb-set-sliderwrap');
        wrap.appendChild(slider);
        if (val) wrap.appendChild(val);
        return row(label, wrap);
    }

    function group(children) {
        var g = el('div', 'tb-set-group');
        children.forEach(function (c) { g.appendChild(c); });
        return g;
    }

    function pane(title) {
        var p = el('div', 'tb-set-pane');
        p.appendChild(el('div', 'tb-set-pane-title', title));
        return p;
    }

    /* ---------- panes: Wi-Fi / Bluetooth (decorative) ---------- */

    function buildWifi() {
        var p = pane('Wi-Fi');
        p.appendChild(group([row('Wi-Fi', makeToggle(true))]));
        p.appendChild(el('div', 'tb-set-group-label', 'Known Network'));
        p.appendChild(group([row('Home 5G', el('span', 'tb-set-hint', 'Connected'))]));
        return p;
    }

    function buildBluetooth() {
        var p = pane('Bluetooth');
        p.appendChild(group([row('Bluetooth', makeToggle(true))]));
        p.appendChild(el('div', 'tb-set-group-label', 'Devices'));
        p.appendChild(group([
            row('Magic Mouse', el('span', 'tb-set-hint', 'Not Connected')),
            row('AirPods Pro', el('span', 'tb-set-hint', 'Not Connected'))
        ]));
        return p;
    }

    /* ---------- pane: Battery (LIVE via navigator.getBattery, 100% fallback) ---------- */

    function buildBattery() {
        var p = pane('Battery');
        var pct = el('span', 'tb-set-battery-pct', '100%');
        var state = el('span', 'tb-set-hint', 'Not Charging');
        p.appendChild(group([row('Battery Level', pct), row('Status', state)]));
        p.appendChild(group([row('Low Power Mode', makeToggle(false))]));

        function update(b) {
            var level = Math.round((b.level || 0) * 100);
            pct.textContent = level + '%';
            state.textContent = b.charging ? 'Charging' : (level >= 100 ? 'Fully Charged' : 'Not Charging');
        }
        if (typeof navigator !== 'undefined' && navigator && typeof navigator.getBattery === 'function') {
            try {
                navigator.getBattery().then(function (b) {
                    if (!b) return;
                    update(b);
                    if (typeof b.addEventListener === 'function') {
                        b.addEventListener('levelchange', function () { update(b); });
                        b.addEventListener('chargingchange', function () { update(b); });
                    }
                }, function () { /* keep the 100% fallback */ });
            } catch (e) { /* keep the 100% fallback */ }
        }
        return p;
    }

    /* ---------- pane: General ---------- */

    function buildGeneral() {
        var p = pane('General');
        var about = el('button', 'tb-set-subrow');
        about.type = 'button';
        about.appendChild(el('span', 'tb-set-label', 'About'));
        about.appendChild(el('span', 'tb-set-chevron', '›'));
        about.addEventListener('click', function () { openApp('about'); });
        p.appendChild(group([about]));
        return p;
    }

    /* ---------- pane: Appearance (REAL: 'brightness' → Control Center dim overlay) ---------- */

    function buildAppearance() {
        var p = pane('Appearance');
        var val = el('span', 'tb-set-slider-val', get('brightness', 100) + '%');
        var slider = makeSlider(10, 100, 1, get('brightness', 100), function (v) {
            v = Math.round(v);
            val.textContent = v + '%';
            commit('brightness', v);
        });
        p.appendChild(group([sliderRow('Desktop dim', slider, val)]));
        return p;
    }

    /* ---------- pane: Desktop & Dock (REAL: magnification master + size) ---------- */

    function buildDock() {
        var p = pane('Desktop & Dock');
        var sizeVal = el('span', 'tb-set-slider-val', Number(get('dockMaxScale', 1.6)).toFixed(2));
        var size = makeSlider(1, 2, 0.05, Number(get('dockMaxScale', 1.6)), function (v) {
            sizeVal.textContent = v.toFixed(2);
            commit('dockMaxScale', v);
        });
        size.disabled = !get('dockMagnification', true);
        var master = makeToggle(get('dockMagnification', true), function (on) {
            size.disabled = !on;
            commit('dockMagnification', on);
        });
        p.appendChild(group([
            row('Magnification', master),
            sliderRow('Magnification size', size, sizeVal)
        ]));
        return p;
    }

    /* ---------- pane: Notch (the app's own preferences) ---------- */

    function buildNotch() {
        var p = pane('Notch');
        p.appendChild(group([
            row('Hover to peek', makeToggle(get('hoverPeek', true), function (on) { commit('hoverPeek', on); })),
            row('Pin open on click', makeToggle(get('pinOnClick', true), function (on) { commit('pinOnClick', on); })),
            row('Closed-notch meter', makeToggle(get('closedNotchMeter', true), function (on) { commit('closedNotchMeter', on); }))
        ]));

        /* notch mode: segmented (physical vs simulated) */
        var SEGS = [
            { label: 'Physical', value: 'physical' },
            { label: 'Simulated', value: 'simulated' }
        ];
        var current = get('notchMode', 'physical');
        var btns = [];
        var seg = el('div', 'tb-set-seg');
        SEGS.forEach(function (o) {
            var b = el('button', 'tb-set-seg-btn' + (o.value === current ? ' tb-set-seg-on' : ''), o.label);
            b.type = 'button';
            b.addEventListener('click', function () {
                current = o.value;
                btns.forEach(function (x) { x.classList.toggle('tb-set-seg-on', x === b); });
                commit('notchMode', o.value);
            });
            btns.push(b);
            seg.appendChild(b);
        });
        p.appendChild(el('div', 'tb-set-group-label', 'Notch placement'));
        p.appendChild(group([row('Mode', seg)]));
        p.appendChild(el('div', 'tb-set-note',
            'Simulated mode floats the panel as a status pill at the top of any display, so notchless Macs ' +
            'and external monitors get the same workspace without a hardware cutout.'));
        return p;
    }

    /* ---------- pane: Face ID (decorative; the real unlock is macOS-only) ---------- */

    function buildFaceId() {
        var p = pane('Face ID');
        p.appendChild(group([
            row('Unlock on wake or lock', makeToggle(false, function (on) { commit('faceIdUnlock', on); })),
            row('Require Touch ID key', makeToggle(true, function (on) { commit('faceIdTouchId', on); }))
        ]));
        p.appendChild(el('div', 'tb-set-group-label', 'On-device model'));
        p.appendChild(group([
            row('Network', el('span', 'tb-set-static', 'ArcFace w600k_mbf')),
            row('Stored', el('span', 'tb-set-static', '512-d embedding')),
            row('Key', el('span', 'tb-set-static', 'Keychain + Touch ID'))
        ]));
        p.appendChild(el('div', 'tb-set-note',
            'Mac webcams have no depth sensor, so liveness checks reject printed photos with reasonable ' +
            'confidence — a recorded video is not reliably blocked. Treat it as convenience, not security. ' +
            'Off by default.'));
        return p;
    }

    /* ---------- pane: Sound (REAL: 'volume' 0..1 + TBMusic.setVolume) ---------- */

    function buildSound() {
        var p = pane('Sound');
        var cur = Math.round(get('volume', 0.8) * 100);
        var val = el('span', 'tb-set-slider-val', cur + '%');
        var slider = makeSlider(0, 100, 1, cur, function (v) {
            v = Math.round(v);
            val.textContent = v + '%';
            var frac = v / 100;
            commit('volume', frac);
            if (window.TBMusic && typeof window.TBMusic.setVolume === 'function') {
                try { window.TBMusic.setVolume(frac); } catch (e) { /* player absent */ }
            }
        });
        p.appendChild(group([sliderRow('Output volume', slider, val)]));

        /* per-app mixer: the real app taps each process separately and boosts
           up to 400% (+12 dB) behind a soft-knee ceiling. Here the values just
           persist so the panel behaves like the app's. */
        p.appendChild(el('div', 'tb-set-group-label', 'Per-app mixer'));
        var MIX = [
            ['Spotify', 'mixerSpotify', 75],
            ['Safari', 'mixerSafari', 130],
            ['Display speakers', 'mixerDisplaySpeakers', 65]
        ];
        var mixRows = MIX.map(function (m) {
            var v = Number(get(m[1], m[2]));
            var out = el('span', 'tb-set-slider-val', v + '%');
            var s = makeSlider(0, 400, 1, v, function (next) {
                next = Math.round(next);
                out.textContent = next + '%';
                commit(m[1], next);
            });
            return sliderRow(m[0], s, out);
        });
        p.appendChild(group(mixRows));
        p.appendChild(el('div', 'tb-set-note',
            'An app stays untouched until you move its slider — that is when the process tap attaches. ' +
            'Boost above 100% saturates on a soft knee instead of clipping. Display speakers ride DDC/CI ' +
            'over the video cable.'));
        return p;
    }

    /* ---------- pane: Wallpaper (persistent manual picker) ---------- */

    function buildWallpaper() {
        var p = pane('Wallpaper');
        var list = wallpapers();
        /* entries are the local Unsplash photos from js/config.js */

        p.appendChild(el('p', 'tb-set-wp-caption', 'Choose your desktop background. It stays fixed until you change it, and your choice is saved in this browser.'));

        /* 4-column artwork thumbnail grid from TB_CONFIG.wallpapers */
        p.appendChild(el('div', 'tb-set-group-label', 'Wallpapers'));
        var caption = el('div', 'tb-set-wp-caption');
        var grid = el('div', 'tb-set-wp-grid');
        var fallbackSrc =
            (typeof window.TB_CONFIG !== 'undefined' && window.TB_CONFIG && window.TB_CONFIG.wallpaper) ||
            (list[0] && list[0].src) || '';
        var selSrc = get('wallpaperSrc', fallbackSrc);
        var thumbs = [];

        function credit(w) {
            return w.title + ' — ' + w.artist + (w.year ? ', ' + w.year : '');
        }

        list.forEach(function (w) {
            var t = el('button', 'tb-set-thumb' + (w.src === selSrc ? ' tb-set-thumb-on' : ''));
            t.type = 'button';
            t.title = credit(w);
            t.setAttribute('aria-label', credit(w));
            t.setAttribute('aria-pressed', String(w.src === selSrc));
            var img = el('img', 'tb-set-thumb-img');
            img.src = w.src;
            img.alt = w.title;
            t.appendChild(img);
            t.addEventListener('click', function () {
                selSrc = w.src;
                thumbs.forEach(function (x) { x.classList.toggle('tb-set-thumb-on', x === t); x.setAttribute('aria-pressed', String(x === t)); });
                caption.textContent = credit(w);
                commit('wallpaperSrc', w.src);
            });
            if (w.src === selSrc) caption.textContent = credit(w);
            thumbs.push(t);
            grid.appendChild(t);
        });
        p.appendChild(grid);
        p.appendChild(caption);
        return p;
    }

    /* ---------- pane: About ---------- */

    function buildAboutPane() {
        var p = pane('About');
        p.appendChild(group([
            row('Name', el('span', 'tb-set-static', 'MacBook Pro')),
            row('Chip', el('span', 'tb-set-static', 'Apple Silicon')),
            row('macOS', el('span', 'tb-set-static', '14.2 Sonoma'))
        ]));
        var more = el('div', 'tb-set-moreinfo');
        var btn = el('button', 'tb-set-btn', 'More Info…');
        btn.type = 'button';
        btn.addEventListener('click', function () { openApp('about'); });
        more.appendChild(btn);
        p.appendChild(more);
        return p;
    }

    /* ---------- sidebar sections ---------- */

    var SECTIONS = [
        { id: 'wifi', glyph: '🌐', label: 'Wi-Fi', color: '#0a84ff' },
        { id: 'bluetooth', glyph: '🅱️', label: 'Bluetooth', color: '#0a84ff' },
        { id: 'notch', glyph: '🎧', label: 'Notch', color: '#0a84ff' },
        { id: 'faceid', glyph: '👤', label: 'Face ID', color: '#30d158' },
        { id: 'battery', glyph: '🔋', label: 'Battery', color: '#30d158' },
        { id: 'general', glyph: '⚙️', label: 'General', color: '#8e8e93' },
        { id: 'appearance', glyph: '🎨', label: 'Appearance', color: '#5e5ce6' },
        { id: 'dock', glyph: '🖥️', label: 'Desktop & Dock', color: '#48484a' },
        { id: 'sound', glyph: '🔊', label: 'Sound', color: '#ff375f' },
        { id: 'wallpaper', glyph: '💡', label: 'Wallpaper', color: '#ffd60a' },
        { id: 'about', glyph: 'ℹ️', label: 'About', color: '#8e8e93' }
    ];

    var BUILDERS = {
        wifi: buildWifi,
        bluetooth: buildBluetooth,
        notch: buildNotch,
        faceid: buildFaceId,
        battery: buildBattery,
        general: buildGeneral,
        appearance: buildAppearance,
        dock: buildDock,
        sound: buildSound,
        wallpaper: buildWallpaper,
        about: buildAboutPane
    };

    /* ---------- the app ---------- */

    function TBSettingsUI(opts) {
        opts = opts || {};
        var root = el('div', 'tb-set-root');

        /* sidebar: search pill + account card + section rows */
        var sidebar = el('div', 'tb-set-sidebar');
        var search = el('div', 'tb-set-search');
        search.appendChild(el('span', 'tb-set-search-glyph', '🔍'));
        search.appendChild(el('span', 'tb-set-search-text', 'Search'));
        sidebar.appendChild(search);

        var account = el('div', 'tb-set-account');
        account.appendChild(el('div', 'tb-set-avatar', '🧑🏻‍💻'));
        var accMeta = el('div', 'tb-set-account-meta');
        accMeta.appendChild(el('div', 'tb-set-account-name', 'This Mac'));
        accMeta.appendChild(el('div', 'tb-set-account-sub', 'Notch desktop demo'));
        account.appendChild(accMeta);
        sidebar.appendChild(account);

        var nav = el('nav', 'tb-set-nav');
        sidebar.appendChild(nav);

        /* right pane host */
        var content = el('div', 'tb-set-content');
        var paneHost = el('div', 'tb-set-panehost');
        content.appendChild(paneHost);

        var panes = {};
        var navBtns = {};

        function show(id) {
            if (!panes[id]) {
                panes[id] = BUILDERS[id]();
                paneHost.appendChild(panes[id]);
            }
            Object.keys(panes).forEach(function (k) {
                panes[k].classList.toggle('tb-set-pane-on', k === id);
            });
            Object.keys(navBtns).forEach(function (k) {
                navBtns[k].classList.toggle('tb-set-siderow-on', k === id);
            });
        }

        SECTIONS.forEach(function (s) {
            var b = el('button', 'tb-set-siderow');
            b.type = 'button';
            var chip = el('span', 'tb-set-sideglyph', s.glyph);
            chip.style.background = s.color;
            b.appendChild(chip);
            b.appendChild(el('span', 'tb-set-sidelabel', s.label));
            b.addEventListener('click', function () { show(s.id); });
            navBtns[s.id] = b;
            nav.appendChild(b);
        });

        root.appendChild(sidebar);
        root.appendChild(content);

        /* first open shows the Appearance pane (per spec) */
        show('appearance');

        return root;
    }

    window.TBSettingsUI = TBSettingsUI;
})();
