/* js/settings-app.js — System Settings app (macOS 27 Liquid Glass style).
   TBApps.render('settings') calls TBSettingsUI(opts) -> HTMLElement.
   Supports live sidebar search filtering, opts.pane navigation, and
   in-pane shortcuts to Notch, Camera Mirror, and Wallpaper folders. */
(function () {
    'use strict';

    var STORE_KEY = 'tb-settings';

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
        } catch (e) {}
    }

    function commit(key, value) {
        store()[key] = value;
        persist();
        try {
            window.dispatchEvent(new CustomEvent('tb:settings', { detail: { key: key, value: value } }));
        } catch (e) {}
    }

    function el(tag, className, text) {
        var node = document.createElement(tag);
        if (className) node.className = className;
        if (typeof text === 'string') node.textContent = text;
        return node;
    }

    function openDetail(detail) {
        try {
            window.dispatchEvent(new CustomEvent('tb:open-app', { detail: detail }));
        } catch (e) {}
    }

    function wallpapers() {
        var c = typeof window.TB_CONFIG !== 'undefined' ? window.TB_CONFIG : null;
        return (c && c.wallpapers) || [];
    }

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

    function row(label, control) {
        var r = el('div', 'tb-set-row');
        r.appendChild(el('span', 'tb-set-label', label));
        if (control) r.appendChild(control);
        return r;
    }

    function actionRow(label, btnText, onClick) {
        var btn = el('button', 'tb-set-btn', btnText);
        btn.type = 'button';
        btn.addEventListener('click', onClick);
        return row(label, btn);
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

    function buildWifi() {
        var p = pane('Wi-Fi');
        p.appendChild(group([row('Wi-Fi', makeToggle(true))]));
        p.appendChild(el('div', 'tb-set-group-label', 'Known Network'));
        p.appendChild(group([row('Home 5G', el('span', 'tb-set-hint', 'Connected · Wi-Fi 7'))]));
        return p;
    }

    function buildBluetooth() {
        var p = pane('Bluetooth');
        p.appendChild(group([row('Bluetooth', makeToggle(true))]));
        p.appendChild(el('div', 'tb-set-group-label', 'My Devices'));
        p.appendChild(group([
            row('Magic Trackpad', el('span', 'tb-set-hint', 'Connected')),
            row('AirPods Pro', el('span', 'tb-set-hint', 'Connected'))
        ]));
        return p;
    }

    function buildBattery() {
        var p = pane('Battery');
        var pct = el('span', 'tb-set-battery-pct', '100%');
        var state = el('span', 'tb-set-hint', 'Fully Charged');
        p.appendChild(group([row('Battery Level', pct), row('Status', state)]));
        p.appendChild(group([row('Low Power Mode', makeToggle(false))]));

        function update(b) {
            var level = Math.round((b.level || 0) * 100);
            pct.textContent = level + '%';
            state.textContent = b.charging ? 'Charging' : (level >= 100 ? 'Fully Charged' : 'On Battery');
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
                }, function () {});
            } catch (e) {}
        }
        return p;
    }

    function buildGeneral() {
        var p = pane('General');
        var about = el('button', 'tb-set-subrow');
        about.type = 'button';
        about.appendChild(el('span', 'tb-set-label', 'About This Mac'));
        about.appendChild(el('span', 'tb-set-chevron', '›'));
        about.addEventListener('click', function () { openDetail({ app: 'about' }); });

        var updates = el('button', 'tb-set-subrow');
        updates.type = 'button';
        updates.appendChild(el('span', 'tb-set-label', 'Software Update & Releases'));
        updates.appendChild(el('span', 'tb-set-chevron', '›'));
        updates.addEventListener('click', function () { openDetail({ app: 'releases' }); });

        p.appendChild(group([about, updates]));
        return p;
    }

    function buildAppearance() {
        var p = pane('Appearance');
        var val = el('span', 'tb-set-slider-val', get('brightness', 100) + '%');
        var slider = makeSlider(10, 100, 1, get('brightness', 100), function (v) {
            v = Math.round(v);
            val.textContent = v + '%';
            commit('brightness', v);
        });
        p.appendChild(group([
            row('Material Style', el('span', 'tb-set-static', 'macOS 27 Liquid Glass')),
            sliderRow('Desktop Brightness', slider, val)
        ]));
        return p;
    }

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
            sliderRow('Magnification size', size, sizeVal),
            actionRow('Applications Launcher', 'Open Applications…', function () { openDetail({ app: 'apps' }); })
        ]));
        return p;
    }

    function buildNotch() {
        var p = pane('Notch');
        p.appendChild(group([
            row('Hover to peek', makeToggle(get('hoverPeek', true), function (on) { commit('hoverPeek', on); })),
            row('Pin open on click', makeToggle(get('pinOnClick', true), function (on) { commit('pinOnClick', on); })),
            row('Closed-notch meter', makeToggle(get('closedNotchMeter', true), function (on) { commit('closedNotchMeter', on); })),
            actionRow('Notch Workspace', 'Open Notch Panel', function () { openDetail({ app: 'music', view: 'home' }); })
        ]));

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
            'Simulated mode detaches the panel into a floating Liquid Glass capsule just below the menu bar, ' +
            'so notchless Macs and external monitors get the same workspace without a hardware cutout.'));
        return p;
    }

    function buildFaceId() {
        var p = pane('Face ID');
        p.appendChild(group([
            row('Unlock on wake or lock', makeToggle(get('faceIdUnlock', false), function (on) { commit('faceIdUnlock', on); })),
            row('Require Touch ID key', makeToggle(get('faceIdTouchId', true), function (on) { commit('faceIdTouchId', on); })),
            actionRow('Framing Preview', 'Open Camera Mirror…', function () { openDetail({ app: 'facetime' }); })
        ]));
        p.appendChild(el('div', 'tb-set-group-label', 'On-device model'));
        p.appendChild(group([
            row('Network', el('span', 'tb-set-static', 'ArcFace w600k_mbf')),
            row('Stored', el('span', 'tb-set-static', '512-d embedding')),
            row('Key', el('span', 'tb-set-static', 'Keychain + Touch ID'))
        ]));
        p.appendChild(el('div', 'tb-set-note',
            'Mac webcams have no depth sensor, so liveness checks reject printed photos with reasonable ' +
            'confidence — a recorded video is not reliably blocked. Treat it as convenience, not security.'));
        return p;
    }

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
                try { window.TBMusic.setVolume(frac); } catch (e) {}
            }
        });
        p.appendChild(group([
            sliderRow('Output volume', slider, val),
            actionRow('Now Playing Preview', 'Open in Notch', function () { openDetail({ app: 'music', view: 'media' }); })
        ]));

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
            'Boost above 100% saturates on a soft knee instead of clipping.'));
        return p;
    }

    function buildWallpaper() {
        var p = pane('Wallpaper');
        var list = wallpapers();

        p.appendChild(el('p', 'tb-set-wp-caption', 'Choose your desktop background. Your choice is saved in this browser.'));
        p.appendChild(group([
            actionRow('Wallpaper Files', 'Browse in Finder…', function () {
                openDetail({ app: 'folder', folder: 'wallpapers', title: 'wallpapers' });
            })
        ]));

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

    function buildAboutPane() {
        var p = pane('About');
        p.appendChild(group([
            row('Name', el('span', 'tb-set-static', 'MacBook Pro')),
            row('Chip', el('span', 'tb-set-static', 'Apple M4 Pro')),
            row('macOS', el('span', 'tb-set-static', 'macOS 27.0 (Liquid Glass)'))
        ]));
        var more = el('div', 'tb-set-moreinfo');
        var btn = el('button', 'tb-set-btn', 'System Report…');
        btn.type = 'button';
        btn.addEventListener('click', function () { openDetail({ app: 'about' }); });
        more.appendChild(btn);
        p.appendChild(more);
        return p;
    }

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

    function TBSettingsUI(opts) {
        opts = opts || {};
        var root = el('div', 'tb-set-root');

        var sidebar = el('div', 'tb-set-sidebar');
        var search = el('label', 'tb-set-search');
        search.appendChild(el('span', 'tb-set-search-glyph', '🔍'));
        var searchInput = el('input', 'tb-set-search-input');
        searchInput.type = 'search';
        searchInput.placeholder = 'Search';
        searchInput.setAttribute('aria-label', 'Search settings');
        search.appendChild(searchInput);
        sidebar.appendChild(search);

        var account = el('div', 'tb-set-account');
        account.title = 'Open About This Mac';
        account.appendChild(el('div', 'tb-set-avatar', '🧑🏻‍💻'));
        var accMeta = el('div', 'tb-set-account-meta');
        accMeta.appendChild(el('div', 'tb-set-account-name', 'This Mac'));
        accMeta.appendChild(el('div', 'tb-set-account-sub', 'macOS 27 · Notch Demo'));
        account.appendChild(accMeta);
        account.addEventListener('click', function () { openDetail({ app: 'about' }); });
        sidebar.appendChild(account);

        var nav = el('nav', 'tb-set-nav');
        sidebar.appendChild(nav);

        var content = el('div', 'tb-set-content');
        var paneHost = el('div', 'tb-set-panehost');
        content.appendChild(paneHost);

        var panes = {};
        var navBtns = {};

        function show(id) {
            if (!BUILDERS[id]) id = 'appearance';
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

        searchInput.addEventListener('input', function () {
            var q = searchInput.value.trim().toLowerCase();
            var firstMatch = null;
            SECTIONS.forEach(function (s) {
                var hit = !q || s.label.toLowerCase().indexOf(q) !== -1 || s.id.indexOf(q) !== -1;
                navBtns[s.id].hidden = !hit;
                if (hit && !firstMatch) firstMatch = s.id;
            });
            if (firstMatch) show(firstMatch);
        });

        root.addEventListener('tb:app-navigate', function (e) {
            if (e.detail && e.detail.pane && BUILDERS[e.detail.pane]) {
                show(e.detail.pane);
            }
        });

        root.appendChild(sidebar);
        root.appendChild(content);

        show(opts.pane && BUILDERS[opts.pane] ? opts.pane : 'appearance');

        return root;
    }

    window.TBSettingsUI = TBSettingsUI;
})();
