/* js/promo.js — left-edge promo column. Owned by Dev 4 (Promo Column).
   Mounts one container into #promo-root (positioned by css/main.css; the
   root is click-through, .tb-promo re-enables pointer events). Four cards:
   the Notch DOWNLOAD card (the star), a GitHub/star banner, a
   privacy banner, and a yellow sticky note (the whole note links to the
   repo). All outbound hrefs come from window.TB_CONFIG.links and degrade to
   '#' when config is absent — zero console errors either way. */
(function () {
    'use strict';

    /* ---------- static data ---------- */

    var ICON_SRC = 'assets/icon.png';

    /* sticky note target — same URL as TB_CONFIG.links.github; hardcoded
       fallback so the note still links out when config never loads */
    var STICKY_URL = 'https://github.com/Wub796/Notch';

    /* Inline SVG down-arrow for the download button (no emoji — this glyph
       is what the bob keyframes animate). */
    var DOWN_ARROW_SVG =
        '<svg class="tb-promo-download-glyph" viewBox="0 0 24 24" width="16" ' +
        'height="16" fill="none" stroke="currentColor" stroke-width="2.6" ' +
        'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
        '<path d="M12 4v13"/><path d="M6 12l6 6 6-6"/></svg>';

    /* ---------- dom + config helpers ---------- */

    function el(tag, className, text) {
        var node = document.createElement(tag);
        if (className) { node.className = className; }
        if (text !== undefined && text !== null) { node.textContent = text; }
        return node;
    }

    /* window.TB_CONFIG.links, or {} when config never loaded. */
    function configLinks() {
        var cfg =
            (typeof window.TB_CONFIG !== 'undefined' && window.TB_CONFIG) || {};
        return cfg.links || {};
    }

    /* Trimmed non-empty link value, else ''. */
    function link(links, key) {
        var v = links[key];
        return (typeof v === 'string' && v.trim()) ? v : '';
    }

    /* Point an anchor at a real outbound URL (new tab, noopener) or at the
       inert '#' fallback (no target — a blank new tab would be noise). */
    function outbound(a, url) {
        if (url) {
            a.href = url;
            a.target = '_blank';
            a.rel = 'noopener';
        } else {
            a.href = '#';
        }
        return a;
    }

    /* ---------- 1. download card (the star) ---------- */

    function renderDownload(links) {
        var card = el('section', 'tb-promo-card tb-promo-card--download');

        var head = el('div', 'tb-promo-dl-head');
        var icon = el('img', 'tb-promo-dl-icon');
        icon.src = ICON_SRC;
        icon.alt = 'Notch app icon';
        head.appendChild(icon);

        var titles = el('div', 'tb-promo-dl-titles');
        titles.appendChild(el('div', 'tb-promo-dl-title', 'Notch'));
        titles.appendChild(
            el('div', 'tb-promo-dl-sub', 'for macOS 14+ · Free & Open Source'));
        head.appendChild(titles);
        card.appendChild(head);

        var btn =
            outbound(el('a', 'tb-promo-download-btn'), link(links, 'githubReleases'));
        btn.innerHTML = DOWN_ARROW_SVG;
        btn.appendChild(document.createTextNode('Download'));
        card.appendChild(btn);

        var meta = el('div', 'tb-promo-dl-meta');
        var ver = el('span', 'tb-promo-dl-version', '… · Universal');
        meta.appendChild(ver);
        if (typeof window.TB_CONFIG === 'object' && window.TB_CONFIG &&
            typeof window.TB_CONFIG.getLatestTag === 'function') {
            window.TB_CONFIG.getLatestTag(function (tag) {
                ver.textContent = tag + ' · Universal';
            });
        }
        meta.appendChild(
            outbound(el('a', 'tb-promo-dl-github', 'GitHub ↗'), link(links, 'github')));
        card.appendChild(meta);

        var install = el('a', 'tb-promo-install-link', 'Install steps →');
        install.href = '#';
        install.addEventListener('click', function (event) {
            if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey || !window.TBWindows) {
                return;
            }
            event.preventDefault();
            window.TBWindows.open({ app: 'releases' });
        });
        card.appendChild(install);

        return card;
    }

    /* ---------- 2. GitHub banner ---------- */

    function renderGithub(links) {
        var card = el('section', 'tb-promo-card tb-promo-card--banner tb-promo-card--github');
        card.appendChild(el('span', 'tb-promo-chip tb-promo-chip--graphite', '🐙'));

        var text = el('div', 'tb-promo-banner-text');
        text.appendChild(el('div', 'tb-promo-banner-title', 'Source on GitHub'));
        text.appendChild(el('div', 'tb-promo-banner-sub',
            'Swift 6 · MIT-ish · issues & releases'));
        card.appendChild(text);

        var url = link(links, 'github');
        if (url) {
            card.appendChild(
                outbound(el('a', 'tb-promo-pill', 'Open ↗'), url));
        } else {
            /* config missing → non-interactive placeholder, no href anywhere */
            card.appendChild(
                el('span', 'tb-promo-pill tb-promo-pill--soon', 'unavailable'));
        }
        return card;
    }

    /* ---------- 3. privacy banner ---------- */

    function renderPrivacy(links) {
        var card = outbound(
            el('a', 'tb-promo-card tb-promo-card--banner tb-promo-card--privacy'),
            link(links, 'thirdParty'));
        card.style.cursor = 'pointer';
        card.setAttribute('aria-label', 'Read the third-party notices');
        card.appendChild(el('span', 'tb-promo-chip tb-promo-chip--blue', '🔒'));

        var text = el('div', 'tb-promo-banner-text');
        text.appendChild(el('div', 'tb-promo-banner-title', 'On-device by default'));
        text.appendChild(el('div', 'tb-promo-banner-sub',
            'audio analysis in RAM · no telemetry'));
        card.appendChild(text);

        card.appendChild(el('span', 'tb-promo-banner-link', 'Notices ↗'));
        return card;
    }

    /* ---------- 4. sticky note (the whole note is one outbound link) ---------- */

    function renderSticky(links) {
        var note = outbound(
            el('a', 'tb-promo-card tb-promo-card--sticky'),
            link(links, 'github') || STICKY_URL);

        /* 📌 straddles the top edge via negative margin (see css/promo.css) */
        note.appendChild(el('span', 'tb-promo-sticky-pin', '📌'));

        var text = el('div', 'tb-promo-sticky-text');
        text.appendChild(
            el('div', 'tb-promo-sticky-line', 'hover to peek · pin it open · esc to dismiss'));
        text.appendChild(
            el('div', 'tb-promo-sticky-url', 'github.com/Wub796/Notch'));
        note.appendChild(text);

        return note;
    }

    /* ---------- mount ---------- */

    function init() {
        var root = document.getElementById('promo-root');
        if (!root) { return; }

        var links = configLinks();
        var col = el('div', 'tb-promo');
        col.appendChild(renderDownload(links));
        col.appendChild(renderGithub(links));
        col.appendChild(renderPrivacy(links));
        col.appendChild(renderSticky(links));
        root.appendChild(col);
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }
})();
