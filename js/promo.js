/* js/promo.js — left-edge Liquid Glass promo column.
   Four interactive cards: Download card (header opens Downloads window,
   Install steps opens Releases window), GitHub banner (opens Safari window
   or GitHub), Privacy banner (opens THIRD-PARTY-NOTICES.md in Preview),
   and Sticky note (opens Notes window + Notch Quick Notes). */
(function () {
    'use strict';

    var ICON_SRC = 'assets/icon.png';
    var STICKY_URL = 'https://github.com/Wub796/Notch';

    var DOWN_ARROW_SVG =
        '<svg class="tb-promo-download-glyph" viewBox="0 0 24 24" width="16" ' +
        'height="16" fill="none" stroke="currentColor" stroke-width="2.6" ' +
        'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
        '<path d="M12 4v13"/><path d="M6 12l6 6 6-6"/></svg>';

    function el(tag, className, text) {
        var node = document.createElement(tag);
        if (className) node.className = className;
        if (text !== undefined && text !== null) node.textContent = text;
        return node;
    }

    function configLinks() {
        var cfg = (typeof window.TB_CONFIG !== 'undefined' && window.TB_CONFIG) || {};
        return cfg.links || {};
    }

    function link(links, key) {
        var v = links[key];
        return (typeof v === 'string' && v.trim()) ? v : '';
    }

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

    function openApp(detail) {
        window.dispatchEvent(new CustomEvent('tb:open-app', { detail: detail }));
    }

    /* ---------- 1. download card ---------- */
    function renderDownload(links) {
        var card = el('section', 'tb-promo-card tb-promo-card--download');

        var head = el('div', 'tb-promo-dl-head');
        head.title = 'Open Downloads window';
        var icon = el('img', 'tb-promo-dl-icon');
        icon.src = ICON_SRC;
        icon.alt = 'Notch app icon';
        head.appendChild(icon);

        var titles = el('div', 'tb-promo-dl-titles');
        titles.appendChild(el('div', 'tb-promo-dl-title', 'Notch'));
        titles.appendChild(el('div', 'tb-promo-dl-sub', 'for macOS 14+ · Non-Commercial'));
        head.appendChild(titles);
        head.addEventListener('click', function () {
            openApp({ app: 'download' });
        });
        card.appendChild(head);

        var btn = outbound(el('a', 'tb-promo-download-btn'), link(links, 'githubReleases'));
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
        var ghLink = outbound(el('a', 'tb-promo-dl-github', 'Safari Preview →'), link(links, 'github'));
        ghLink.addEventListener('click', function (e) {
            if (e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
            e.preventDefault();
            openApp({ app: 'safari' });
        });
        meta.appendChild(ghLink);
        card.appendChild(meta);

        var install = el('a', 'tb-promo-install-link', 'Install steps →');
        install.href = '#';
        install.addEventListener('click', function (event) {
            if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
            event.preventDefault();
            openApp({ app: 'releases' });
        });
        card.appendChild(install);

        return card;
    }

    /* ---------- 2. GitHub banner ---------- */
    function renderGithub(links) {
        var card = el('section', 'tb-promo-card tb-promo-card--banner tb-promo-card--github');
        card.title = 'Open GitHub repository in Safari window';
        card.appendChild(el('span', 'tb-promo-chip tb-promo-chip--graphite', '🐙'));

        var text = el('div', 'tb-promo-banner-text');
        text.appendChild(el('div', 'tb-promo-banner-title', 'Source on GitHub'));
        text.appendChild(el('div', 'tb-promo-banner-sub', 'Swift 6 · Non-Commercial · issues & releases'));
        card.appendChild(text);

        var url = link(links, 'github');
        if (url) {
            var pill = outbound(el('a', 'tb-promo-pill', 'Open ↗'), url);
            pill.addEventListener('click', function (e) { e.stopPropagation(); });
            card.appendChild(pill);
        } else {
            card.appendChild(el('span', 'tb-promo-pill tb-promo-pill--soon', 'unavailable'));
        }
        card.addEventListener('click', function () {
            openApp({ app: 'safari' });
        });
        return card;
    }

    /* ---------- 3. privacy banner ---------- */
    function renderPrivacy(links) {
        var card = outbound(
            el('a', 'tb-promo-card tb-promo-card--banner tb-promo-card--privacy'),
            link(links, 'thirdParty')
        );
        card.style.cursor = 'pointer';
        card.title = 'Open THIRD-PARTY-NOTICES.md in Preview';
        card.setAttribute('aria-label', 'Read the third-party notices');
        card.appendChild(el('span', 'tb-promo-chip tb-promo-chip--blue', '🔒'));

        var text = el('div', 'tb-promo-banner-text');
        text.appendChild(el('div', 'tb-promo-banner-title', 'On-device by default'));
        text.appendChild(el('div', 'tb-promo-banner-sub', 'audio analysis in RAM · no telemetry'));
        card.appendChild(text);

        card.appendChild(el('span', 'tb-promo-banner-link', 'Notices →'));
        card.addEventListener('click', function (e) {
            if (e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
            e.preventDefault();
            openApp({ app: 'viewer', title: 'THIRD-PARTY-NOTICES.md', path: 'THIRD-PARTY-NOTICES.md' });
        });
        return card;
    }

    /* ---------- 4. sticky note ---------- */
    function renderSticky(links) {
        var note = outbound(
            el('a', 'tb-promo-card tb-promo-card--sticky'),
            link(links, 'github') || STICKY_URL
        );
        note.title = 'Open Notes app';
        note.appendChild(el('span', 'tb-promo-sticky-pin', '📌'));

        var text = el('div', 'tb-promo-sticky-text');
        text.appendChild(el('div', 'tb-promo-sticky-line', 'hover to peek · pin it open · esc to dismiss'));
        text.appendChild(el('div', 'tb-promo-sticky-url', 'Click to open Notes →'));
        note.appendChild(text);

        note.addEventListener('click', function (e) {
            if (e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
            e.preventDefault();
            openApp({ app: 'notes' });
        });
        return note;
    }

    function init() {
        var root = document.getElementById('promo-root');
        if (!root) return;

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
