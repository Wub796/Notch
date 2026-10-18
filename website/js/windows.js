/* js/windows.js — Dev D: in-page macOS window manager.
   Owns .tb-window lifecycle (open/focus/minimize/restore/close/zoom/drag/resize),
   renders content via window.TBApps (with fallback), reports to the dock via
   'tb:window-state', consumes 'tb:open-app' and 'tb:window-cmd'. */
(function () {
    "use strict";

    var zCounter = 100,
        root = null;
    var windowsByApp = {}; /* key -> { el, app, state, zoomed, preZoom, token } */

    var APP_SPECS = {
        releases: { title: "Releases & Install", chrome: "plain", emoji: "🧩", width: 780, height: 660, top: 38 },
        safari: { title: "Safari", chrome: "safari", emoji: "🧭", width: 740, height: 520 },
        download: { title: "Downloads", chrome: "plain", emoji: "⬇️" },
        about: { title: "About This Mac", chrome: "plain", emoji: "🖥️", width: 420, height: 420 },
        folder: { title: "Finder", chrome: "plain", emoji: "📁", width: 660, height: 440 },
        viewer: { title: "Preview", chrome: "plain", emoji: "👁️", width: 640, height: 460 },
        messages: { title: "Messages", chrome: "plain", emoji: "💬", width: 680, height: 520 },
        terminal: { title: "Terminal — zsh", chrome: "plain", emoji: "⬛", width: 620, height: 440 },
        facetime: { title: "Camera Mirror", chrome: "plain", emoji: "📹", width: 640, height: 480 },
        apps: { title: "Applications", chrome: "plain", emoji: "🧩", width: 760, height: 560 },
        settings: { title: "System Settings", chrome: "plain", emoji: "⚙️", width: 720, height: 520 },
        notes: { title: "Notes", chrome: "plain", emoji: "📝", width: 640, height: 460 },
    };

    var FALLBACK_LINKS = {
        releases: function (c) { return c && c.links && c.links.githubReleases; },
        safari: function (c) { return c && c.links && c.links.github; },
        download: function (c) { return c && c.links && c.links.githubReleases; },
        about: function (c) { return c && c.links && c.links.github; },
    };

    function el(tag, cls, text) {
        var n = document.createElement(tag);
        if (cls) n.className = cls;
        if (text != null) n.textContent = text;
        return n;
    }

    function dispatchState(app, state) {
        window.dispatchEvent(new CustomEvent("tb:window-state", { detail: { app: app, state: state } }));
    }

    function safariUrlLabel() {
        var cfg = window.TB_CONFIG;
        var url = cfg && cfg.links && cfg.links.github;
        if (!url) return "";
        try {
            var u = new URL(url);
            return u.host + u.pathname.replace(/\/$/, "");
        } catch (err) {
            return String(url).replace(/^https?:\/\//, "").replace(/\/$/, "");
        }
    }

    /* ---- focus / topmost ---- */
    function focusWindow(rec) {
        rec.el.style.zIndex = String(++zCounter);
        if (root) {
            root.querySelectorAll(".tb-window").forEach(function (windowEl) {
                windowEl.classList.toggle("tb-window-active", windowEl === rec.el);
            });
        }
    }

    function topmostRecord() {
        var best = null;
        Object.keys(windowsByApp).forEach(function (key) {
            var rec = windowsByApp[key];
            if (rec.state !== "open") return;
            if (!best || Number(rec.el.style.zIndex || 0) > Number(best.el.style.zIndex || 0)) {
                best = rec;
            }
        });
        return best;
    }

    /* ---- state transitions ---- */
    function closeWindow(rec) {
        Object.keys(windowsByApp).forEach(function (key) {
            if (windowsByApp[key] === rec) delete windowsByApp[key];
        });
        if (rec.el.parentNode) rec.el.parentNode.removeChild(rec.el);
        dispatchState(rec.app, "closed");
    }

    function minimizeWindow(rec) {
        if (rec.state !== "open") return;
        rec.state = "minimized";
        rec.token += 1;
        var token = rec.token,
            winEl = rec.el,
            r = winEl.getBoundingClientRect();
        var dx = window.innerWidth / 2 - (r.left + r.width / 2);
        var dy = window.innerHeight - r.top - 24;
        winEl.style.transform = "translate(" + Math.round(dx) + "px," + Math.round(dy) + "px) scale(0.1)";
        winEl.style.opacity = "0";
        winEl.style.pointerEvents = "none";
        var finish = function () {
            if (token !== rec.token) return;
            winEl.style.display = "none";
            dispatchState(rec.app, "minimized");
        };
        winEl.addEventListener("transitionend", function onEnd(ev) {
            if (ev.propertyName !== "transform") return;
            winEl.removeEventListener("transitionend", onEnd);
            finish();
        });
        setTimeout(finish, 450);
    }

    function restoreWindow(rec) {
        if (rec.state !== "minimized") return;
        rec.state = "open";
        rec.token += 1;
        var winEl = rec.el;
        winEl.style.display = "flex";
        void winEl.offsetHeight;
        winEl.style.transform = "";
        winEl.style.opacity = "";
        winEl.style.pointerEvents = "";
        if (rec.app === "releases" && window.innerWidth > 768) fitStore(rec);
        focusWindow(rec);
        dispatchState(rec.app, "restored");
    }

    function toggleZoom(rec) {
        if (rec.state !== "open") return;
        var winEl = rec.el,
            rootRect = root.getBoundingClientRect();
        winEl.classList.add("tb-animating");
        if (rec.zoomed && rec.preZoom) {
            winEl.style.left = rec.preZoom.left + "px";
            winEl.style.top = rec.preZoom.top + "px";
            winEl.style.width = rec.preZoom.width + "px";
            winEl.style.height = rec.preZoom.height + "px";
            rec.zoomed = false;
        } else {
            rec.preZoom = {
                left: winEl.offsetLeft,
                top: winEl.offsetTop,
                width: winEl.offsetWidth,
                height: winEl.offsetHeight,
            };
            winEl.style.left = window.innerWidth * 0.05 - rootRect.left + "px";
            winEl.style.top = window.innerHeight * 0.04 - rootRect.top + "px";
            winEl.style.width = window.innerWidth * 0.9 + "px";
            winEl.style.height = window.innerHeight * 0.82 + "px";
            rec.zoomed = true;
        }
        if (rec.app === "releases" && window.innerWidth > 768) fitStore(rec);
        setTimeout(function () { winEl.classList.remove("tb-animating"); }, 420);
    }

    function tileWindow(rec, side) {
        if (!rec || rec.state !== "open" || !root) return;
        var winEl = rec.el;
        winEl.classList.add("tb-animating");
        rec.preZoom = {
            left: winEl.offsetLeft,
            top: winEl.offsetTop,
            width: winEl.offsetWidth,
            height: winEl.offsetHeight,
        };
        rec.zoomed = true;
        var pad = 10;
        var halfW = Math.floor((root.clientWidth - pad * 3) / 2);
        var fullH = Math.max(320, root.clientHeight - 86);
        winEl.style.top = pad + "px";
        winEl.style.left = (side === "right" ? pad * 2 + halfW : pad) + "px";
        winEl.style.width = halfW + "px";
        winEl.style.height = fullH + "px";
        focusWindow(rec);
        setTimeout(function () { winEl.classList.remove("tb-animating"); }, 420);
    }

    /* ---- dragging (titlebar only, clamped: >=60px stays in viewport) ---- */
    function attachDrag(rec, titlebar) {
        titlebar.addEventListener("dblclick", function (e) {
            if (e.target.closest(".tb-window-traffic")) return;
            toggleZoom(rec);
        });
        titlebar.addEventListener("pointerdown", function (e) {
            if (e.button !== 0 || e.target.closest(".tb-window-traffic")) return;
            var winEl = rec.el,
                startX = e.clientX,
                startY = e.clientY;
            var origLeft = winEl.offsetLeft,
                origTop = winEl.offsetTop;
            try { titlebar.setPointerCapture(e.pointerId); } catch (err) { /* noop */ }
            var move = function (ev) {
                var nl = Math.max(60 - winEl.offsetWidth, Math.min(root.clientWidth - 60, origLeft + ev.clientX - startX));
                var nt = Math.max(0, Math.min(root.clientHeight - 60, origTop + ev.clientY - startY));
                winEl.style.left = nl + "px";
                winEl.style.top = nt + "px";
            };
            var up = function () {
                titlebar.removeEventListener("pointermove", move);
                titlebar.removeEventListener("pointerup", up);
                titlebar.removeEventListener("pointercancel", up);
            };
            titlebar.addEventListener("pointermove", move);
            titlebar.addEventListener("pointerup", up);
            titlebar.addEventListener("pointercancel", up);
        });
    }

    function attachTouchDragFallback(rec, titlebar) {
        if (window.PointerEvent) return;
        titlebar.addEventListener("touchstart", function (e) {
            if (e.target.closest(".tb-window-traffic")) return;
            focusWindow(rec);
            var t = e.touches[0];
            var winEl = rec.el,
                startX = t.clientX,
                startY = t.clientY;
            var origLeft = winEl.offsetLeft,
                origTop = winEl.offsetTop;
            var move = function (ev) {
                var m = ev.touches[0];
                var nl = Math.max(60 - winEl.offsetWidth, Math.min(root.clientWidth - 60, origLeft + m.clientX - startX));
                var nt = Math.max(0, Math.min(root.clientHeight - 60, origTop + m.clientY - startY));
                winEl.style.left = nl + "px";
                winEl.style.top = nt + "px";
                ev.preventDefault();
            };
            var up = function () {
                titlebar.removeEventListener("touchmove", move);
                titlebar.removeEventListener("touchend", up);
                titlebar.removeEventListener("touchcancel", up);
            };
            titlebar.addEventListener("touchmove", move, { passive: false });
            titlebar.addEventListener("touchend", up);
            titlebar.addEventListener("touchcancel", up);
        });
    }

    /* ---- resizable-window geometry ---- */
    function storeViewport() { return { width: root.clientWidth, height: root.clientHeight }; }
    function storeRect(rec) {
        return { left: rec.el.offsetLeft, top: rec.el.offsetTop, width: rec.el.offsetWidth, height: rec.el.offsetHeight };
    }
    function applyStoreRect(rec, rect) {
        ["left", "top", "width", "height"].forEach(function (key) { rec.el.style[key] = rect[key] + "px"; });
    }
    function fitStore(rec) {
        if (window.TBWindowGeometry) applyStoreRect(rec, window.TBWindowGeometry.fit(storeRect(rec), storeViewport()));
    }
    function attachResize(rec) {
        if (!window.TBWindowGeometry) return;
        ["n", "s", "e", "w", "ne", "nw", "se", "sw"].forEach(function (direction) {
            var handle = el(direction === "se" ? "button" : "div", "tb-resize-handle tb-resize-" + direction);
            if (direction === "se") {
                handle.type = "button";
                handle.setAttribute("aria-label", "Resize window. Use arrow keys; hold Shift for larger steps.");
                handle.addEventListener("keydown", function (event) {
                    var step = event.shiftKey ? 50 : 10;
                    var delta = { ArrowLeft: [-step, 0], ArrowRight: [step, 0], ArrowUp: [0, -step], ArrowDown: [0, step] }[event.key];
                    if (!delta) return;
                    event.preventDefault(); event.stopPropagation();
                    rec.zoomed = false; rec.preZoom = null;
                    applyStoreRect(rec, window.TBWindowGeometry.resize(storeRect(rec), "se", delta[0], delta[1], storeViewport()));
                });
            } else handle.setAttribute("aria-hidden", "true");
            handle.addEventListener("pointerdown", function (event) {
                if (event.button !== 0 || rec.state !== "open" || window.innerWidth <= 768) return;
                event.preventDefault(); event.stopPropagation(); focusWindow(rec);
                if (direction === "se") handle.focus({ preventScroll: true });
                fitStore(rec);
                var start = storeRect(rec), x = event.clientX, y = event.clientY, pointer = event.pointerId;
                rec.zoomed = false; rec.preZoom = null; rec.el.classList.remove("tb-animating");
                root.classList.add("tb-resizing");
                try { handle.setPointerCapture(pointer); } catch (_) { /* noop */ }
                function move(next) {
                    if (next.pointerId !== pointer) return;
                    applyStoreRect(rec, window.TBWindowGeometry.resize(start, direction, next.clientX - x, next.clientY - y, storeViewport()));
                }
                function finish(next) {
                    if (next.pointerId !== undefined && next.pointerId !== pointer) return;
                    root.classList.remove("tb-resizing");
                    document.removeEventListener("pointermove", move);
                    document.removeEventListener("pointerup", finish);
                    document.removeEventListener("pointercancel", finish);
                    handle.removeEventListener("lostpointercapture", finish);
                    window.removeEventListener("blur", finish);
                }
                document.addEventListener("pointermove", move);
                document.addEventListener("pointerup", finish);
                document.addEventListener("pointercancel", finish);
                handle.addEventListener("lostpointercapture", finish);
                window.addEventListener("blur", finish);
            });
            rec.el.appendChild(handle);
        });
    }

    /* ---- content ---- */
    function buildFallback(app, spec) {
        var card = el("div", "tb-fallback");
        card.appendChild(el("div", "tb-fallback-emoji", spec.emoji || "🪟"));
        card.appendChild(el("div", "tb-fallback-title", spec.title));
        var href = FALLBACK_LINKS[app] ? FALLBACK_LINKS[app](window.TB_CONFIG) : null;
        if (href) {
            var a = el("a", "tb-fallback-link", "Open in new tab ↗");
            a.href = href;
            a.target = "_blank";
            a.rel = "noopener";
            card.appendChild(a);
        } else {
            card.appendChild(el("span", "tb-fallback-link tb-fallback-plain", "Open in new tab ↗"));
        }
        return card;
    }

    function fillContent(app, spec, contentEl) {
        var node = null,
            apps = window.TBApps;
        if (apps && typeof apps.render === "function") {
            var ropts = {
                name: spec.name || spec.folder || undefined,
                folder: spec.folder || undefined,
                path: spec.path || undefined,
                pane: spec.pane || undefined,
                tab: spec.tab || undefined,
            };
            try {
                node = apps.render(app, ropts);
            } catch (err) {
                node = null;
            }
        }
        var mounted = node && node.nodeType === 1 ? node : buildFallback(app, spec);
        contentEl.appendChild(mounted);
        return mounted;
    }

    /* ---- construction ---- */
    function buildWindow(app, spec) {
        var w = el("section", "tb-window");
        var contentNode = null;
        w.setAttribute("data-app", app);
        w.setAttribute("role", "dialog");
        w.setAttribute("aria-label", spec.title);
        var titlebar = el("header", "tb-window-titlebar");
        var traffic = el("div", "tb-window-traffic");
        [
            ["tb-tl-close", "Close"],
            ["tb-tl-min", "Minimize"],
            ["tb-tl-zoom", "Zoom"],
        ].forEach(function (p) {
            var b = el("button", "tb-tl " + p[0]);
            b.type = "button";
            b.tabIndex = 0;
            b.setAttribute("aria-label", p[1]);
            traffic.appendChild(b);
        });
        titlebar.appendChild(traffic);
        titlebar.appendChild(el("span", "tb-window-title", spec.title));
        w.appendChild(titlebar);

        if (spec.chrome === "safari") {
            var bar = el("div", "tb-window-addressbar");
            var backBtn = el("button", "tb-ab-nav tb-ab-back", "‹");
            backBtn.type = "button";
            backBtn.setAttribute("aria-label", "Back");
            var fwdBtn = el("button", "tb-ab-nav tb-ab-fwd", "›");
            fwdBtn.type = "button";
            fwdBtn.setAttribute("aria-label", "Forward");
            var field = el("button", "tb-ab-field");
            field.type = "button";
            field.title = "Click to copy repository URL";
            field.appendChild(el("span", "tb-ab-lock", "🔒"));
            var urlSpan = el("span", "tb-ab-url", spec.urlLabel || "");
            field.appendChild(urlSpan);
            var reloadBtn = el("button", "tb-ab-reload", "↻");
            reloadBtn.type = "button";
            reloadBtn.setAttribute("aria-label", "Reload page");

            backBtn.addEventListener("click", function () {
                (contentNode || w).dispatchEvent(new CustomEvent("tb:safari-nav", { detail: { action: "back" } }));
            });
            fwdBtn.addEventListener("click", function () {
                (contentNode || w).dispatchEvent(new CustomEvent("tb:safari-nav", { detail: { action: "forward" } }));
            });
            reloadBtn.addEventListener("click", function () {
                (contentNode || w).dispatchEvent(new CustomEvent("tb:safari-nav", { detail: { action: "reload" } }));
            });
            field.addEventListener("click", function () {
                var fullUrl = (window.TB_CONFIG && window.TB_CONFIG.links && window.TB_CONFIG.links.github) || ("https://" + (spec.urlLabel || ""));
                if (navigator.clipboard && navigator.clipboard.writeText) {
                    navigator.clipboard.writeText(fullUrl).catch(function () {});
                }
                var prev = urlSpan.textContent;
                urlSpan.textContent = "Copied URL to clipboard";
                setTimeout(function () { urlSpan.textContent = prev; }, 1400);
            });

            bar.appendChild(backBtn);
            bar.appendChild(fwdBtn);
            bar.appendChild(field);
            bar.appendChild(reloadBtn);
            w.appendChild(bar);
        }

        var content = el("div", "tb-window-content");
        w.appendChild(content);
        contentNode = fillContent(app, spec, content);

        var count = Object.keys(windowsByApp).length;
        var cw = spec.width || Math.min(620, Math.max(480, root.clientWidth - 80));
        var ch = spec.height || Math.min(420, Math.max(320, root.clientHeight - 60));
        if (app === "releases") cw = Math.min(cw, Math.max(320, root.clientWidth - 28));
        w.style.width = cw + "px";
        w.style.height = ch + "px";
        w.style.left = Math.max(
            0,
            typeof spec.left === "number" ? Math.round(spec.left) : Math.round((root.clientWidth - cw) / 2 + count * 24)
        ) + "px";
        w.style.top = Math.max(
            0,
            typeof spec.top === "number" ? Math.round(spec.top) : Math.round((root.clientHeight - ch) / 2 + count * 24)
        ) + "px";
        if (app === "releases") {
            w.style.left = Math.max(14, Math.min(parseFloat(w.style.left), root.clientWidth - cw - 14)) + "px";
        }
        w.style.zIndex = String(++zCounter);

        var rec = {
            el: w,
            contentNode: contentNode,
            app: app,
            state: "open",
            zoomed: false,
            preZoom: null,
            token: 0,
        };
        traffic.children[0].addEventListener("click", function () { closeWindow(rec); });
        traffic.children[1].addEventListener("click", function () { minimizeWindow(rec); });
        traffic.children[2].addEventListener("click", function () { toggleZoom(rec); });
        w.addEventListener("pointerdown", function () { focusWindow(rec); }, true);
        attachDrag(rec, titlebar);
        attachTouchDragFallback(rec, titlebar);
        attachResize(rec);
        return rec;
    }

    /* ---- public open path ---- */
    function openApp(app, overrides) {
        if (!root) return;
        var base = APP_SPECS[app] || { title: app, chrome: "plain", emoji: "🪟" };
        var spec = {
            title: (overrides && overrides.title) || base.title,
            chrome: (overrides && overrides.chrome) || base.chrome,
            urlLabel: (overrides && overrides.urlLabel) || base.urlLabel || (base.chrome === "safari" ? safariUrlLabel() : ""),
            emoji: base.emoji,
            name: (overrides && overrides.name) || null,
            folder: (overrides && overrides.folder) || null,
            path: (overrides && overrides.path) || null,
            pane: (overrides && overrides.pane) || null,
            tab: (overrides && overrides.tab) || null,
            width: (overrides && overrides.width) || base.width || 0,
            height: (overrides && overrides.height) || base.height || 0,
            left: overrides && typeof overrides.left === "number" ? overrides.left : typeof base.left === "number" ? base.left : null,
            top: overrides && typeof overrides.top === "number" ? overrides.top : typeof base.top === "number" ? base.top : null,
        };
        var key = app + (spec.folder ? ":" + spec.folder : "") + (spec.path ? ":" + spec.path : "");
        var rec = windowsByApp[key];
        if (rec && rec.state === "minimized") {
            restoreWindow(rec);
            (rec.contentNode || rec.el).dispatchEvent(new CustomEvent("tb:app-navigate", { detail: spec }));
            return;
        }
        if (rec && rec.state === "open") {
            focusWindow(rec);
            (rec.contentNode || rec.el).dispatchEvent(new CustomEvent("tb:app-navigate", { detail: spec }));
            return;
        }
        rec = buildWindow(app, spec);
        windowsByApp[key] = rec;
        root.appendChild(rec.el);
        if (app === "releases" && window.innerWidth > 768) fitStore(rec);
        focusWindow(rec);
        dispatchState(app, "open");
    }

    /* ---- wiring ---- */
    function onOpenApp(e) {
        var d = e.detail || {};
        var app = d.app;
        if (!app || !APP_SPECS[app]) return;
        openApp(app, {
            title: typeof d.title === "string" && d.title ? d.title : undefined,
            name: typeof d.name === "string" && d.name ? d.name : undefined,
            folder: typeof d.folder === "string" && d.folder ? d.folder : undefined,
            path: typeof d.path === "string" && d.path ? d.path : undefined,
            pane: typeof d.pane === "string" && d.pane ? d.pane : undefined,
            tab: typeof d.tab === "string" && d.tab ? d.tab : undefined,
        });
    }

    function onWindowCmd(e) {
        var cmd = e.detail && e.detail.cmd;
        var top = topmostRecord();
        if (cmd === "close-top" && top) closeWindow(top);
        else if (cmd === "minimize-top" && top) minimizeWindow(top);
        else if (cmd === "zoom-top" && top) toggleZoom(top);
        else if (cmd === "tile-left" && top) tileWindow(top, "left");
        else if (cmd === "tile-right" && top) tileWindow(top, "right");
        else if (cmd === "bring-all") {
            Object.keys(windowsByApp).forEach(function (k) {
                var r = windowsByApp[k];
                if (r.state === "minimized") restoreWindow(r);
                else if (r.state === "open") focusWindow(r);
            });
        } else if (cmd === "close-all") {
            Object.keys(windowsByApp).slice().forEach(function (k) {
                if (windowsByApp[k]) closeWindow(windowsByApp[k]);
            });
        }
    }

    function init() {
        root = document.getElementById("windows-root");
        if (!root) return;
        window.TBWindows = {
            open: function (opts) {
                if (!opts || !opts.app) return;
                openApp(opts.app, opts);
            },
        };
        window.addEventListener("tb:open-app", onOpenApp);
        window.addEventListener("tb:window-cmd", onWindowCmd);
        var desktopShown = false;
        function showDesktop() {
            desktopShown = !desktopShown;
            root.classList.toggle("tb-show-desktop", desktopShown);
            root.inert = desktopShown;
            window.dispatchEvent(new CustomEvent("tb:desktop-state", { detail: { shown: desktopShown } }));
        }
        window.addEventListener("tb:show-desktop", showDesktop);
        window.addEventListener("tb:open-app", function () {
            if (desktopShown) showDesktop();
        });
        document.addEventListener("keydown", function (e) {
            var editing = e.target.closest('input, textarea, [contenteditable="true"]');
            if (e.key === "F11" || ((e.metaKey || e.ctrlKey) && e.shiftKey && e.key.toLowerCase() === "d")) {
                e.preventDefault(); showDesktop();
            } else if (!editing && (e.metaKey || e.ctrlKey) && (e.key.toLowerCase() === "w" || e.key.toLowerCase() === "m")) {
                var top = topmostRecord();
                if (top) {
                    e.preventDefault();
                    if (e.key.toLowerCase() === "w") closeWindow(top);
                    else minimizeWindow(top);
                }
            }
        });
        document.addEventListener("keydown", function (e) {
            if (e.key !== "Escape") return;
            var top = topmostRecord();
            if (top) closeWindow(top);
        });
        if (root.clientWidth > 900) {
            openApp("releases");
        }
        window.addEventListener("resize", function () {
            var store = windowsByApp.releases;
            if (store && store.state === "open" && window.innerWidth > 768) fitStore(store);
        });
    }

    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", init);
    } else {
        init();
    }
})();
