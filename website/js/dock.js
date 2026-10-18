/* js/dock.js — macOS 27 Liquid Glass Dock.
   Renders into <div id="dock-root">. Dispatches 'tb:open-app' on icon clicks,
   listens for 'tb:music-state' / 'tb:window-state' to drive running dots. */
(function () {
    'use strict';

    var BASE = 52;        /* icon layout size (px) */
    var MAX_SCALE = 1.6;  /* peak magnification at cursor center (~84px) */
    var RANGE = 100;      /* cosine falloff radius (px) */
    var LIFT = 14;        /* max translateY lift at full scale (px) */

    var WINDOW_APP_TO_ICON = {
        about: 'finder',
        folder: 'finder',
        viewer: 'finder',
        music: 'notch',
        safari: 'safari',
        notes: 'notes',
        download: 'download',
        releases: 'releases',
        messages: 'messages',
        facetime: 'facetime',
        terminal: 'terminal',
        apps: 'apps',
        settings: 'settings'
    };

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

    var ICONS = [
        { id: 'finder', label: 'Finder', icon: 'assets/icons/finder.png', detail: { app: 'folder', folder: 'project', title: 'notch-website' } },
        { id: 'notch', label: 'Notch', icon: 'assets/icon.png', app: 'music' },
        { id: 'safari', label: 'Safari', icon: 'assets/icons/safari.png', app: 'safari' },
        { id: 'notes', label: 'Notes', icon: 'assets/icons/notes.png', app: 'notes' },
        { id: 'github', label: 'GitHub', icon: 'assets/icons/github.png', app: 'safari' },
        { id: 'messages', label: 'Messages', icon: 'assets/icons/messages.png', app: 'messages' },
        { id: 'facetime', label: 'Camera Mirror', icon: 'assets/icons/facetime.png', app: 'facetime' },
        { id: 'terminal', label: 'Terminal', icon: 'assets/icons/terminal.png', app: 'terminal' },
        { id: 'apps', label: 'Applications', icon: dataIcon(SVG_LAUNCHPAD), app: 'apps' },
        { id: 'releases', label: 'Releases & Install', icon: 'assets/icons/app-store.png', app: 'releases' },
        { id: 'settings', label: 'System Settings', icon: 'assets/icons/settings.png', app: 'settings' },
        null,
        { id: 'download', label: 'Downloads', icon: dataIcon(SVG_DOWNLOADS), app: 'download' },
        { id: 'trash', label: 'Trash', icon: dataIcon(SVG_TRASH), wiggle: true, detail: { app: 'folder', folder: 'trash', title: 'Trash' } }
    ];

    function init() {
        var mount = document.getElementById('dock-root');
        if (!mount) return;

        var tray = document.createElement('nav');
        tray.className = 'tb-dock';
        tray.setAttribute('aria-label', 'Dock');

        var items = [];
        var dots = {};

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
                var file = document.createElement('img');
                file.className = 'tb-dock-icon-img-file';
                file.src = def.icon;
                file.alt = '';
                file.setAttribute('aria-hidden', 'true');
                file.draggable = false;
                img.appendChild(file);
            } else {
                img.style.background = 'linear-gradient(180deg, ' + def.colors[0] + ' 0%, ' + def.colors[1] + ' 100%)';
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

            btn.addEventListener('click', function () {
                if (def.wiggle) {
                    btn.classList.remove('tb-dock-icon--wiggle');
                    void btn.offsetWidth;
                    btn.classList.add('tb-dock-icon--wiggle');
                }
                if (def.href) {
                    window.open(def.href, '_blank', 'noopener');
                } else if (def.detail) {
                    window.dispatchEvent(new CustomEvent('tb:open-app', { detail: def.detail }));
                } else if (def.app) {
                    window.dispatchEvent(new CustomEvent('tb:open-app', { detail: { app: def.app } }));
                }
            });
            if (def.wiggle) {
                btn.addEventListener('animationend', function () {
                    btn.classList.remove('tb-dock-icon--wiggle');
                });
            }
        });

        mount.appendChild(tray);

        var restCenters = null;
        var restTrayWidth = 0;
        var curScales = items.map(function () { return 1; });
        var targetScales = items.map(function () { return 1; });
        var curShifts = items.map(function () { return 0; });
        var curExtra = 0;
        var rafId = 0;
        var lastTime = 0;
        var reducedMotion = typeof window.matchMedia === 'function'
            ? window.matchMedia('(prefers-reduced-motion: reduce)')
            : null;

        function cacheRestCenters() {
            restTrayWidth = tray.getBoundingClientRect().width - curExtra;
            restCenters = items.map(function (it, i) {
                var r = it.item.getBoundingClientRect();
                return r.left + r.width / 2 - curShifts[i];
            });
        }

        function applyFrame(now) {
            rafId = 0;
            var dt = lastTime ? Math.max(0.004, (now - lastTime) / 1000) : 0.016;
            lastTime = now;
            var alpha = 1 - Math.exp(-dt * 20);
            var moving = false;
            var allRest = true;
            var i;

            for (i = 0; i < items.length; i++) {
                var diff = targetScales[i] - curScales[i];
                if (Math.abs(diff) > 0.002) {
                    curScales[i] += diff * alpha;
                    if (Math.abs(targetScales[i] - curScales[i]) <= 0.002) {
                        curScales[i] = targetScales[i];
                    } else {
                        moving = true;
                    }
                } else {
                    curScales[i] = targetScales[i];
                }
                if (curScales[i] !== 1) allRest = false;
            }

            if (allRest && !moving) {
                for (i = 0; i < items.length; i++) {
                    items[i].item.style.transform = '';
                    items[i].btn.style.transform = '';
                    curShifts[i] = 0;
                }
                tray.style.paddingLeft = '';
                tray.style.paddingRight = '';
                curExtra = 0;
                lastTime = 0;
                return;
            }

            var requestedExtra = curScales.reduce(function (sum, s) { return sum + BASE * (s - 1); }, 0);
            var availableExtra = Math.max(0, window.innerWidth - 24 - restTrayWidth);
            var fit = requestedExtra ? Math.min(1, availableExtra / requestedExtra) : 1;
            var extra = requestedExtra * fit;
            var baseTotal = 0;
            var scaledTotal = 0;

            for (i = 0; i < items.length; i++) {
                var s = 1 + (curScales[i] - 1) * fit;
                var w = BASE * s;
                var shift = (scaledTotal + w / 2) - (baseTotal + BASE / 2) - extra / 2;
                var lift = (s - 1) * LIFT;
                curShifts[i] = shift;
                items[i].item.style.transform = 'translate3d(' + shift.toFixed(2) + 'px, 0, 0)';
                items[i].btn.style.transform = 'translate3d(0, ' + (-lift).toFixed(2) + 'px, 0) scale(' + s.toFixed(3) + ')';
                baseTotal += BASE;
                scaledTotal += w;
            }
            curExtra = extra;
            tray.style.paddingLeft = (11 + extra / 2).toFixed(2) + 'px';
            tray.style.paddingRight = (11 + extra / 2).toFixed(2) + 'px';

            if (moving) rafId = window.requestAnimationFrame(applyFrame);
            else lastTime = 0;
        }

        function scheduleTick() {
            if (!rafId) rafId = window.requestAnimationFrame(applyFrame);
        }

        function magnify(clientX) {
            if (!restCenters) cacheRestCenters();
            var maxScale = (window.TB_SETTINGS && typeof window.TB_SETTINGS.dockMaxScale === 'number')
                ? window.TB_SETTINGS.dockMaxScale : MAX_SCALE;
            maxScale = Number.isFinite(maxScale) ? Math.max(1, Math.min(2, maxScale)) : MAX_SCALE;
            for (var i = 0; i < items.length; i++) {
                var dist = Math.abs(clientX - restCenters[i]);
                var scale = 1;
                if (dist < RANGE) {
                    var t = (Math.cos((dist / RANGE) * Math.PI) + 1) / 2;
                    scale = 1 + (maxScale - 1) * t;
                }
                targetScales[i] = scale;
            }
            scheduleTick();
        }

        function smoothReset() {
            for (var i = 0; i < items.length; i++) targetScales[i] = 1;
            scheduleTick();
        }

        function hardReset() {
            if (rafId) { window.cancelAnimationFrame(rafId); rafId = 0; }
            lastTime = 0;
            for (var i = 0; i < items.length; i++) {
                curScales[i] = 1;
                targetScales[i] = 1;
                curShifts[i] = 0;
                items[i].item.style.transform = '';
                items[i].btn.style.transform = '';
            }
            curExtra = 0;
            tray.style.paddingLeft = '';
            tray.style.paddingRight = '';
            restCenters = null;
        }

        tray.addEventListener('mousemove', function (e) {
            if (window.innerWidth <= 768) return;
            if (reducedMotion && reducedMotion.matches) return;
            if (window.TB_SETTINGS && window.TB_SETTINGS.dockMagnification === false) return;
            magnify(e.clientX);
        });
        tray.addEventListener('mouseleave', smoothReset);
        window.addEventListener('resize', hardReset);
        window.addEventListener('tb:settings', function (e) {
            var d = e && e.detail;
            if (d && (d.key === 'dockMagnification' || d.key === 'dockMaxScale')) hardReset();
        });

        function setDot(iconId, on) {
            var dot = dots[iconId];
            if (dot) dot.classList.toggle('tb-dock-dot--on', !!on);
        }

        window.addEventListener('tb:music-state', function (e) {
            var d = e && e.detail;
            if (!d) return;
            setDot('notch', d.playing === true);
        });

        window.addEventListener('tb:window-state', function (e) {
            var d = e && e.detail;
            if (!d || typeof d.app !== 'string') return;
            var iconId = WINDOW_APP_TO_ICON[d.app];
            if (!iconId) return;
            setDot(iconId, d.state !== 'closed');
        });
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }
})();
