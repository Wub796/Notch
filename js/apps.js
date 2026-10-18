/* js/apps.js — content that lives INSIDE the windows.
   Exposes window.TBApps.render(appId, opts) -> HTMLElement. */
(function () {
    'use strict';

    function cfg() { return (typeof window.TB_CONFIG !== 'undefined' && window.TB_CONFIG) || {}; }
    function siteName() { var c = cfg(); return typeof c.appName === 'string' && c.appName ? c.appName : 'Notch'; }
    function link(key) { var c = cfg(); return (c.links && typeof c.links[key] === 'string' && c.links[key]) ? c.links[key] : '#'; }
    function esc(s) { return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;'); }
    function el(tag, className, html) {
        var node = document.createElement(tag);
        if (className) node.className = className;
        if (html !== undefined && html !== null) node.innerHTML = html;
        return node;
    }
    function clearKids(node) { while (node.firstChild) node.removeChild(node.firstChild); }
    function openDetail(detail) {
        try { window.dispatchEvent(new CustomEvent('tb:open-app', { detail: detail })); } catch (e) {}
    }
    function parseRepo(url) {
        var parts = String(url || '').replace(/\/+$/, '').split('/');
        return (parts.length >= 2 && parts[parts.length - 2] && parts[parts.length - 1])
            ? { org: parts[parts.length - 2], repo: parts[parts.length - 1] }
            : { org: 'Wub796', repo: 'Notch' };
    }
    function copyText(text, btn) {
        function done() {
            btn.textContent = 'Copied!';
            setTimeout(function () { btn.textContent = '📋 Copy'; }, 1600);
        }
        function legacy() {
            var ta = el('textarea');
            ta.value = text;
            ta.setAttribute('readonly', '');
            ta.style.cssText = 'position:absolute;left:-9999px';
            document.body.appendChild(ta);
            ta.select();
            try { document.execCommand('copy'); } catch (e) {}
            document.body.removeChild(ta);
            done();
        }
        if (typeof navigator !== 'undefined' && navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(text).then(done, legacy);
        } else legacy();
    }
    function setVersionInto(node) {
        var c = cfg();
        if (typeof c.getLatestTag !== 'function' || !node) return;
        c.getLatestTag(function (tag) {
            var els = node.querySelectorAll('.tb-live-version');
            for (var i = 0; i < els.length; i++) {
                var tpl = els[i].getAttribute('data-version-tpl');
                els[i].textContent = tpl ? tpl.replace('{v}', tag) : tag;
            }
        });
    }

    var SAFARI_REPO_FILES = [
        { glyph: '📁', name: 'css', meta: 'Liquid Glass stylesheets (9 files)', detail: { app: 'folder', name: 'css', path: 'css', title: 'css' } },
        { glyph: '📁', name: 'js', meta: 'Desktop & window modules (11 files)', detail: { app: 'folder', name: 'js', path: 'js', title: 'js' } },
        { glyph: '📄', name: 'README.md', meta: 'Architecture, modules & verification', detail: { app: 'viewer', title: 'README.md', path: 'README.md' } },
        { glyph: '⚖️', name: 'LICENSE', meta: 'Notch Non-Commercial License', detail: { app: 'viewer', title: 'LICENSE', path: 'LICENSE' } },
        { glyph: '📜', name: 'THIRD-PARTY-NOTICES.md', meta: 'Glance, InsightFace & FineTune notices', detail: { app: 'viewer', title: 'THIRD-PARTY-NOTICES.md', path: 'THIRD-PARTY-NOTICES.md' } },
        { glyph: '📄', name: 'index.html', meta: 'macOS 27 desktop shell', detail: { app: 'viewer', title: 'index.html', path: 'index.html' } }
    ];

    function renderSafari(opts) {
        var github = link('github'), repo = parseRepo(github);
        var cloneUrl = github === '#' ? '#' : github + '.git', name = siteName();
        var root = el('div', 'tb-gh-page',
            '<div class="tb-gh-header">' +
                '<div class="tb-gh-header-left">' +
                    '<span class="tb-gh-book">📖</span>' +
                    '<a class="tb-gh-org" href="' + esc(github) + '" target="_blank" rel="noopener">' + esc(repo.org) + '</a>' +
                    '<span class="tb-gh-slash">/</span>' +
                    '<a class="tb-gh-repo" href="' + esc(github) + '" target="_blank" rel="noopener">' + esc(repo.repo) + '</a>' +
                    '<span class="tb-gh-pill">Public</span>' +
                '</div>' +
                '<div class="tb-gh-header-right">' +
                    '<button type="button" class="tb-gh-btn" data-gh-act="watch">👁 Watch</button>' +
                    '<button type="button" class="tb-gh-btn" data-gh-act="fork">🍴 Fork</button>' +
                    '<button type="button" class="tb-gh-btn" data-gh-act="star">☆ Star</button>' +
                '</div>' +
            '</div>' +
            '<div class="tb-gh-tabs">' +
                '<button type="button" class="tb-gh-tab" data-gh-tab="code">&lt;&gt; Code</button>' +
                '<button type="button" class="tb-gh-tab" data-gh-tab="issues">⊙ Issues</button>' +
                '<button type="button" class="tb-gh-tab" data-gh-tab="pulls">⑂ Pull requests</button>' +
                '<button type="button" class="tb-gh-tab" data-gh-tab="actions">▶ Actions</button>' +
            '</div>' +
            '<div class="tb-gh-tab-body"></div>');

        root.querySelector('[data-gh-act="watch"]').addEventListener('click', function (e) {
            e.currentTarget.textContent = e.currentTarget.classList.toggle('is-active') ? '👁 Watching' : '👁 Watch';
        });
        root.querySelector('[data-gh-act="fork"]').addEventListener('click', function () {
            try { window.open(github + '/fork', '_blank', 'noopener'); } catch (e) {}
        });
        root.querySelector('[data-gh-act="star"]').addEventListener('click', function (e) {
            e.currentTarget.textContent = e.currentTarget.classList.toggle('is-active') ? '★ Starred' : '☆ Star';
        });

        var tabBody = root.querySelector('.tb-gh-tab-body');
        var tabBtns = root.querySelectorAll('[data-gh-tab]');
        var tabHistory = [(opts && opts.tab) || 'code'], tabHi = 0;

        function buildCodeTab() {
            var frag = el('div', '',
                '<div class="tb-gh-branch-row">' +
                    '<div class="tb-gh-branch-left">' +
                        '<button type="button" class="tb-gh-branch-pill" title="Browse repository in Finder">⑂ main</button>' +
                        '<span class="tb-gh-filecount">Swift 6 · macOS 14+ · Non-Commercial</span>' +
                    '</div>' +
                    '<div class="tb-gh-clone-wrap">' +
                        '<button type="button" class="tb-btn-secondary tb-gh-finder-btn">📁 Open in Finder</button>' +
                        '<button type="button" class="tb-gh-code-btn">‹› Code ▾</button>' +
                        '<div class="tb-gh-clone-box" style="display:none">' +
                            '<div class="tb-gh-clone-label">Clone with HTTPS</div>' +
                            '<div class="tb-gh-clone-row">' +
                                '<input class="tb-gh-clone-field" type="text" readonly value="' + esc(cloneUrl) + '">' +
                                '<button class="tb-gh-copy-btn" type="button">📋 Copy</button>' +
                            '</div>' +
                        '</div>' +
                    '</div>' +
                '</div>' +
                '<div class="tb-gh-files"></div>' +
                '<div class="tb-gh-readme">' +
                    '<div class="tb-gh-readme-head"><span>📄 README.md</span><button type="button" class="tb-gh-btn tb-gh-raw-btn">Open Raw in Preview →</button></div>' +
                    '<div class="tb-gh-readme-body">' +
                        '<h1 class="tb-gh-h1">🎧 ' + esc(name) + '</h1>' +
                        '<p class="tb-gh-badges">' +
                            '<span class="tb-badge"><i>version</i><b class="tb-badge-blue tb-live-version" data-version-tpl="{v}">…</b></span>' +
                            '<span class="tb-badge"><i>macOS</i><b class="tb-badge-green">14.0+ / 27 Ready</b></span>' +
                            '<span class="tb-badge"><i>swift</i><b class="tb-badge-brown">6.0</b></span>' +
                        '</p>' +
                        '<p class="tb-gh-p">Say hello to <b>' + esc(name) + '</b>, a native macOS utility that turns the area around your camera into an interactive workspace. Hover the notch to peek, click it to pin the panel open, and press <kbd>Esc</kbd> to dismiss it. Nothing here polls the network: an idle notch does nothing at all.</p>' +
                        '<ul class="tb-gh-ul">' +
                            '<li>🎧 now playing with scrubbers and live lyrics (Apple Music &amp; Spotify)</li>' +
                            '<li>🎛️ per-app audio mixer with boost up to 400% and a 10-band EQ</li>' +
                            '<li>📚 temporary file shelf with AirDrop and Quick Look</li>' +
                            '<li>👤 on-device Face ID unlock for the lock and wake screens</li>' +
                            '<li>📈 system telemetry, calendar, weather, Clock and Siri timers</li>' +
                            '<li>🖥️ physical notch, or simulated notch mode on any display</li>' +
                        '</ul>' +
                        '<div class="tb-dl-actions" style="justify-content:flex-start">' +
                            '<a class="tb-btn-primary" href="' + esc(github) + '" target="_blank" rel="noopener">View on GitHub ↗</a>' +
                            '<button type="button" class="tb-btn-secondary tb-gh-open-releases">Releases &amp; Install…</button>' +
                        '</div>' +
                    '</div>' +
                '</div>');

            var openProject = function () { openDetail({ app: 'folder', folder: 'project', title: 'notch-website' }); };
            frag.querySelector('.tb-gh-branch-pill').addEventListener('click', openProject);
            frag.querySelector('.tb-gh-finder-btn').addEventListener('click', openProject);
            var cloneBox = frag.querySelector('.tb-gh-clone-box');
            frag.querySelector('.tb-gh-code-btn').addEventListener('click', function () {
                cloneBox.style.display = cloneBox.style.display === 'none' ? 'block' : 'none';
            });
            var copyBtn = frag.querySelector('.tb-gh-copy-btn');
            copyBtn.addEventListener('click', function () { copyText(cloneUrl, copyBtn); });
            frag.querySelector('.tb-gh-raw-btn').addEventListener('click', function () {
                openDetail({ app: 'viewer', title: 'README.md', path: 'README.md' });
            });
            frag.querySelector('.tb-gh-open-releases').addEventListener('click', function () { openDetail({ app: 'releases' }); });

            var filesBox = frag.querySelector('.tb-gh-files');
            SAFARI_REPO_FILES.forEach(function (f) {
                var row = el('div', 'tb-gh-file-row',
                    '<span class="tb-gh-file-name">' + f.glyph + ' ' + esc(f.name) + '</span>' +
                    '<span class="tb-gh-file-meta">' + esc(f.meta) + '</span>');
                row.addEventListener('click', function () { openDetail(f.detail); });
                filesBox.appendChild(row);
            });
            setVersionInto(frag);
            return frag;
        }

        function buildSubTab(title, desc, actionLabel, detail, extUrl) {
            var box = el('div', 'tb-gh-readme',
                '<div class="tb-gh-readme-head">' + esc(title) + '</div>' +
                '<div class="tb-gh-readme-body">' +
                    '<p class="tb-gh-p">' + esc(desc) + '</p>' +
                    '<div class="tb-dl-actions" style="justify-content:flex-start">' +
                        '<button type="button" class="tb-btn-primary tb-sub-act">' + esc(actionLabel) + '</button>' +
                        (extUrl && extUrl !== '#' ? '<a class="tb-btn-secondary" href="' + esc(extUrl) + '" target="_blank" rel="noopener">Open on GitHub ↗</a>' : '') +
                    '</div>' +
                '</div>');
            box.querySelector('.tb-sub-act').addEventListener('click', function () { openDetail(detail); });
            return box;
        }

        var SUB_TABS = {
            issues: ['⊙ Issues & Feedback', 'Found a bug or have a feature request for Notch? Test commands in Terminal or open an issue on GitHub.', 'Open Terminal CLI', { app: 'terminal' }, link('issues')],
            pulls: ['⑂ Pull Requests & Source Tree', 'Inspect every stylesheet and script powering this desktop directly inside Finder or Preview.', 'Browse Source in Finder', { app: 'folder', folder: 'project', title: 'notch-website' }, github + '/pulls'],
            actions: ['▶ Release Builds & Verification', 'Every universal release is signed and packaged as Notch.zip for Apple Silicon and Intel Macs.', 'Open Releases & Install', { app: 'releases' }, link('githubReleases')]
        };

        function renderActiveTab(id, pushHistory) {
            if (id !== 'code' && !SUB_TABS[id]) id = 'code';
            if (pushHistory && tabHistory[tabHi] !== id) {
                tabHistory = tabHistory.slice(0, tabHi + 1);
                tabHistory.push(id);
                tabHi = tabHistory.length - 1;
            }
            for (var i = 0; i < tabBtns.length; i++) {
                tabBtns[i].classList.toggle('tb-gh-tab-active', tabBtns[i].getAttribute('data-gh-tab') === id);
            }
            clearKids(tabBody);
            tabBody.appendChild(id === 'code' ? buildCodeTab() : buildSubTab.apply(null, SUB_TABS[id]));
        }

        for (var i = 0; i < tabBtns.length; i++) {
            (function (b) {
                b.addEventListener('click', function () { renderActiveTab(b.getAttribute('data-gh-tab'), true); });
            })(tabBtns[i]);
        }

        root.addEventListener('tb:safari-nav', function (e) {
            var act = e.detail && e.detail.action;
            if (act === 'back' && tabHi > 0) { tabHi -= 1; renderActiveTab(tabHistory[tabHi], false); }
            else if (act === 'forward' && tabHi < tabHistory.length - 1) { tabHi += 1; renderActiveTab(tabHistory[tabHi], false); }
            else if (act === 'reload') renderActiveTab(tabHistory[tabHi], false);
        });
        root.addEventListener('tb:app-navigate', function (e) {
            if (e.detail && e.detail.tab) renderActiveTab(e.detail.tab, true);
        });

        renderActiveTab(tabHistory[0], false);
        return root;
    }

    function renderDownload() {
        var card = el('div', 'tb-card tb-card-pad32',
            '<img class="tb-dl-icon-img" src="assets/icon.png" alt="Notch app icon">' +
            '<div class="tb-card-title">' + esc(siteName()) + ' for macOS</div>' +
            '<div class="tb-card-sub tb-live-version" data-version-tpl="{v} · Universal (Apple Silicon + Intel) · Free for non-commercial use">…</div>' +
            '<div class="tb-dl-actions">' +
                '<a class="tb-btn-primary tb-btn-big" href="' + esc(link('githubReleases')) + '" target="_blank" rel="noopener">Download from GitHub Releases</a>' +
                '<button type="button" class="tb-btn-secondary tb-btn-big tb-dl-steps-btn">Install Steps…</button>' +
            '</div>' +
            '<div class="tb-card-caption">Requires macOS 14.0+ · Designed for macOS 27 Liquid Glass · 14.2+ for per-app audio mixer</div>');
        card.querySelector('.tb-dl-steps-btn').addEventListener('click', function () { openDetail({ app: 'releases' }); });
        setVersionInto(card);
        return card;
    }

    function renderReleases() {
        var qCmd = 'xattr -dr com.apple.quarantine "/Applications/Notch.app"';
        var card = el('div', 'tb-card tb-card-pad32',
            '<h2 class="tb-card-h2">Releases &amp; install</h2>' +
            '<p class="tb-card-p">Notch ships as a signed-zip release on GitHub. Every build is universal, so the same download runs on Apple Silicon and Intel.</p>' +
            '<div class="tb-card-sub tb-live-version" data-version-tpl="Latest release: {v}">Latest release: …</div>' +
            '<ol class="tb-dl-steps">' +
                '<li>Download <b>Notch.zip</b> from the Releases page and unzip it.</li>' +
                '<li>Move <b>Notch.app</b> into <code>/Applications</code>.</li>' +
                '<li>Launch it. Hover the notch to peek, click to pin, <kbd>Esc</kbd> to dismiss.</li>' +
            '</ol>' +
            '<p class="tb-card-p">If macOS blocks the first launch with an unidentified-developer warning, clear the quarantine flag once:</p>' +
            '<div class="tb-dl-cmd"><code class="tb-dl-cmd-text">' + esc(qCmd) + '</code><button type="button" class="tb-gh-copy-btn">📋 Copy</button></div>' +
            '<div class="tb-dl-actions">' +
                '<a class="tb-btn-primary" href="' + esc(link('githubReleases')) + '" target="_blank" rel="noopener">Open Releases ↗</a>' +
                '<button type="button" class="tb-btn-secondary tb-rel-readme">📄 Read README.md</button>' +
                '<button type="button" class="tb-btn-secondary tb-rel-settings">⚙️ Notch Settings</button>' +
            '</div>' +
            '<div class="tb-card-caption">Building from source needs Xcode 16 and Swift 6. Apple Developer ID signing is required for login-at-launch and Sparkle updates in production.</div>');
        var copyBtn = card.querySelector('.tb-gh-copy-btn');
        copyBtn.addEventListener('click', function () { copyText(qCmd, copyBtn); });
        card.querySelector('.tb-rel-readme').addEventListener('click', function () { openDetail({ app: 'viewer', title: 'README.md', path: 'README.md' }); });
        card.querySelector('.tb-rel-settings').addEventListener('click', function () { openDetail({ app: 'settings', pane: 'notch' }); });
        setVersionInto(card);
        return card;
    }

    function renderAbout() {
        var rows = [
            ['Chip', 'Apple M4 Pro'], ['Memory', '24 GB Unified'], ['Startup disk', 'Macintosh HD'],
            ['Serial', 'N0TCH-M4C27-2026'], ['macOS', '27.0 (Liquid Glass · Notch needs 14.0+)']
        ];
        var html = '<div class="tb-about-icon">💻</div><div class="tb-about-name">MacBook Pro — running Notch</div><div class="tb-about-rows">';
        rows.forEach(function (r) {
            html += '<div class="tb-about-row"><span class="tb-about-label">' + esc(r[0]) + '</span><span class="tb-about-value">' + esc(r[1]) + '</span></div>';
        });
        html += '</div><div class="tb-dl-actions">' +
            '<button type="button" class="tb-btn-primary tb-about-set">System Settings…</button>' +
            '<button type="button" class="tb-btn-secondary tb-about-more">More Info…</button></div>';
        var card = el('div', 'tb-card tb-card-pad28', html);
        card.querySelector('.tb-about-set').addEventListener('click', function () { openDetail({ app: 'settings', pane: 'about' }); });
        card.querySelector('.tb-about-more').addEventListener('click', function () { openDetail({ app: 'safari' }); });
        return card;
    }

    function vfDir(name, path, children) { return { name: name, path: path, dir: true, children: children }; }
    function vfFile(name, path, kind, size) { return { name: name, path: path, dir: false, kind: kind, size: size || null }; }
    function vfPairs(dirPath, kind, entries) {
        return entries.map(function (p) { return vfFile(p[0], (dirPath ? dirPath + '/' : '') + p[0], kind, p[1]); });
    }

    var VFS_ROOT = vfDir('notch-website', '', vfPairs('', 'text', [
        ['index.html', '6.7 KB'], ['README.md', '8.9 KB'], ['LICENSE', '1.6 KB'], ['THIRD-PARTY-NOTICES.md', '9.7 KB'],
        ['robots.txt', '101 B'], ['sitemap.xml', '261 B']
    ]).concat([
        vfDir('css', 'css', vfPairs('css', 'text', [
            ['apps.css', '21.4 KB'], ['desktop-icons.css', '2.9 KB'], ['dock.css', '5.8 KB'],
            ['main.css', '21.2 KB'], ['notch.css', '23.1 KB'], ['promo.css', '6.8 KB'],
            ['settings-app.css', '8.6 KB'], ['widgets.css', '9.1 KB'], ['windows.css', '8.2 KB']
        ])),
        vfDir('js', 'js', vfPairs('js', 'text', [
            ['apps.js', '35.2 KB'], ['config.js', '4.5 KB'], ['desktop-icons.js', '14.7 KB'],
            ['dock.js', '11.4 KB'], ['menubar.js', '33.8 KB'], ['notch.js', '28.4 KB'],
            ['promo.js', '6.8 KB'], ['settings-app.js', '18.2 KB'], ['widgets.js', '13.9 KB'],
            ['window-geometry.js', '2.6 KB'], ['windows.js', '18.5 KB']
        ])),
        vfDir('assets', 'assets', vfPairs('assets', 'image', [
            ['icon.png', '20.1 KB'], ['favicon.ico', '1.5 KB'], ['favicon-16x16.png', '650 B'],
            ['favicon-32x32.png', '1.5 KB'], ['apple-touch-icon.png', '15.6 KB'], ['og-image.png', '31.4 KB']
        ]).concat([
            vfFile('site.webmanifest', 'assets/site.webmanifest', 'text', '733 B'),
            vfDir('icons', 'assets/icons', vfPairs('assets/icons', 'image', [
                ['app-store.png', '6.4 KB'], ['facetime.png', '6.3 KB'], ['finder.png', '5.4 KB'],
                ['github.png', '8.4 KB'], ['maps.png', '11.5 KB'], ['messages.png', '7.4 KB'],
                ['notes.png', '3.7 KB'], ['safari.png', '10.6 KB'], ['settings.png', '12.5 KB'],
                ['spotify.png', '6.0 KB'], ['terminal.png', '5.7 KB'], ['xcode.png', '7.3 KB']
            ])),
            vfDir('wallpapers', 'assets/wallpapers', vfPairs('assets/wallpapers', 'image', [
                ['luca-bravo-ii5JY_46xH0-unsplash.jpg', '1.3 MB'],
                ['anders-jilden-cYrMQA7a3Wc-unsplash.jpg', '1.0 MB'],
                ['garrett-parker-DlkF4-dbCOU-unsplash.jpg', '853 KB'],
                ['ian-dooley-DuBNA1QMpPA-unsplash.jpg', '343 KB'],
                ['buzz-andersen-E4944K_4SvI-unsplash.jpg', '816 KB']
            ]))
        ])),
        vfDir('Trash', 'trash', [vfFile('README.md', 'README.md', 'text', '8.9 KB')])
    ]));

    function vfsResolve(path) {
        var clean = String(path || '').replace(/^\/+|\/+$/g, '');
        if (!clean) return VFS_ROOT;
        var node = VFS_ROOT, parts = clean.split('/');
        for (var i = 0; i < parts.length; i++) {
            if (!node || !node.dir) return null;
            var next = null;
            for (var j = 0; j < node.children.length; j++) {
                if (node.children[j].name.toLowerCase() === parts[i].toLowerCase()) { next = node.children[j]; break; }
            }
            node = next;
        }
        return node;
    }

    var FINDER_FAVORITES = [
        ['🏠', 'notch-website', ''], ['📁', 'css', 'css'], ['📁', 'js', 'js'],
        ['📁', 'icons', 'assets/icons'], ['🖼️', 'wallpapers', 'assets/wallpapers'], ['🗑️', 'Trash', 'trash']
    ];

    function resolveInitialFolder(opts) {
        if (!opts) return '';
        if (opts.name === 'wallpapers' || opts.folder === 'wallpapers') return 'assets/wallpapers';
        if (opts.name === 'trash' || opts.folder === 'trash') return 'trash';
        if (typeof opts.path === 'string' && opts.path) {
            var n = vfsResolve(opts.path);
            if (n && n.dir) return n.path;
        }
        return '';
    }

    function renderFolder(opts) {
        var startPath = resolveInitialFolder(opts);
        var root = el('div', 'tb-fx',
            '<div class="tb-fx-toolbar">' +
                '<button type="button" class="tb-fx-nav-btn tb-fx-back" aria-label="Back">‹</button>' +
                '<button type="button" class="tb-fx-nav-btn tb-fx-fwd" aria-label="Forward">›</button>' +
                '<div class="tb-fx-crumbs"></div>' +
            '</div>' +
            '<div class="tb-fx-body">' +
                '<div class="tb-fx-sidebar"><div class="tb-fx-side-head">Favorites</div></div>' +
                '<div class="tb-fx-list"></div>' +
            '</div>' +
            '<div class="tb-fx-status"></div>');

        var backBtn = root.querySelector('.tb-fx-back'), fwdBtn = root.querySelector('.tb-fx-fwd');
        var crumbs = root.querySelector('.tb-fx-crumbs'), sidebar = root.querySelector('.tb-fx-sidebar');
        var list = root.querySelector('.tb-fx-list'), status = root.querySelector('.tb-fx-status');

        var sideRows = FINDER_FAVORITES.map(function (fav) {
            var row = el('div', 'tb-fx-side-row',
                '<span class="tb-fx-side-glyph">' + fav[0] + '</span><span class="tb-fx-side-name">' + esc(fav[1]) + '</span>');
            row.addEventListener('click', function () { navigate(fav[2]); });
            sidebar.appendChild(row);
            return { path: fav[2], row: row };
        });

        var history = [startPath], hi = 0;

        function navigate(path) {
            var node = vfsResolve(path);
            if (!node || !node.dir) path = '';
            if (path === history[hi]) { render(); return; }
            history = history.slice(0, hi + 1);
            history.push(path);
            hi = history.length - 1;
            render();
        }

        function render() {
            var dir = vfsResolve(history[hi]) || VFS_ROOT;
            var segs = dir.path ? dir.path.split('/') : [];

            clearKids(crumbs);
            var labels = [VFS_ROOT.name].concat(segs);
            labels.forEach(function (label, i) {
                if (i > 0) crumbs.appendChild(el('span', 'tb-fx-sep', ' › '));
                var last = i === labels.length - 1;
                var crumb = el('span', last ? 'tb-fx-crumb tb-fx-crumb-cur' : 'tb-fx-crumb', esc(label));
                if (!last) {
                    (function (idx) {
                        crumb.addEventListener('click', function () { navigate(idx === 0 ? '' : segs.slice(0, idx).join('/')); });
                    })(i);
                }
                crumbs.appendChild(crumb);
            });

            sideRows.forEach(function (r) { r.row.classList.toggle('tb-fx-side-active', r.path === dir.path); });

            clearKids(list);
            var kids = dir.children.slice().sort(function (a, b) {
                if (a.dir !== b.dir) return a.dir ? -1 : 1;
                return a.name.toLowerCase().localeCompare(b.name.toLowerCase());
            });
            var selected = null;
            kids.forEach(function (node) {
                var glyph = node.dir ? (node.name === 'Trash' ? '🗑️' : '📁') : (node.kind === 'image' ? '🖼️' : '📄');
                var meta = node.dir ? (node.children.length + ' items') : (node.size || '—');
                var row = el('div', 'tb-fx-row',
                    '<span class="tb-fx-glyph">' + glyph + '</span>' +
                    '<span class="tb-fx-name">' + esc(node.name) + '</span>' +
                    '<span class="tb-fx-meta">' + esc(meta) + '</span>');
                row.addEventListener('click', function () {
                    if (selected) selected.classList.remove('tb-fx-row-sel');
                    selected = row;
                    row.classList.add('tb-fx-row-sel');
                });
                row.addEventListener('dblclick', function () {
                    if (node.dir) navigate(node.path);
                    else openDetail({ app: 'viewer', title: node.name, path: node.path });
                });
                list.appendChild(row);
            });

            status.textContent = kids.length + ' items';
            backBtn.disabled = hi <= 0;
            fwdBtn.disabled = hi >= history.length - 1;
        }

        backBtn.addEventListener('click', function () { if (hi > 0) { hi -= 1; render(); } });
        fwdBtn.addEventListener('click', function () { if (hi < history.length - 1) { hi += 1; render(); } });

        root.addEventListener('tb:app-navigate', function (e) { if (e.detail) navigate(resolveInitialFolder(e.detail)); });

        render();
        return root;
    }

    var VIEWER_MAX_LINES = 400;

    function viewerCard(icon, title, sub) {
        return el('div', 'tb-pv-card',
            '<div class="tb-pv-card-icon">' + icon + '</div>' +
            '<div class="tb-pv-card-title">' + esc(title) + '</div>' +
            (sub ? '<div class="tb-pv-card-sub">' + esc(sub) + '</div>' : ''));
    }

    function viewerTextPane(text) {
        var pane = el('div', 'tb-pv-text');
        var lines = String(text).replace(/\r\n?/g, '\n').split('\n'), total = lines.length;
        if (total > VIEWER_MAX_LINES) lines = lines.slice(0, VIEWER_MAX_LINES);
        var htmlLines = lines.map(function (ln, i) { return '<span class="tb-pv-ln">' + (i + 1) + '</span>' + esc(ln); });
        pane.appendChild(el('pre', 'tb-pv-pre', htmlLines.join('\n')));
        if (total > VIEWER_MAX_LINES) {
            pane.appendChild(el('div', 'tb-pv-trunc', '… truncated — showing ' + VIEWER_MAX_LINES + ' of ' + total + ' lines'));
        }
        return pane;
    }

    function renderViewer(opts) {
        var path = (opts && typeof opts.path === 'string') ? opts.path : '';
        var node = vfsResolve(path), root = el('div', 'tb-pv');

        if (!node || node.dir) {
            root.appendChild(viewerCard('🗂️', 'File not found', path ? '“' + path + '” isn’t part of this site’s filesystem.' : 'No file was specified.'));
            return root;
        }
        if (node.kind === 'image') {
            root.appendChild(el('div', 'tb-pv-image', '<img class="tb-pv-img" src="' + esc(node.path) + '" alt="' + esc(node.name) + '">'));
            return root;
        }
        root.appendChild(viewerCard('⏳', 'Loading…', node.name));
        if (typeof fetch !== 'function') {
            clearKids(root);
            root.appendChild(viewerCard('⚠️', 'Could not load file.', node.name));
            return root;
        }
        try {
            fetch(node.path).then(function (res) {
                if (!res || !res.ok) throw new Error('http ' + (res && res.status));
                return res.text();
            }).then(function (text) {
                clearKids(root);
                root.appendChild(viewerTextPane(text));
            }).catch(function () {
                clearKids(root);
                root.appendChild(viewerCard('⚠️', 'Could not load file.', '“' + node.name + '” couldn’t be fetched from this origin.'));
            });
        } catch (e) {
            clearKids(root);
            root.appendChild(viewerCard('⚠️', 'Could not load file.', node.name));
        }
        return root;
    }

    var MSG_PEOPLE = {
        notch: { name: 'Notch', grad: 'linear-gradient(135deg,#0a84ff,#5e5ce6)', quotes: ['Hover me to peek, click to pin me open, and Esc puts me away.', 'When the panel is closed I do nothing at all — no polling, no timers, no Dock icon.'] },
        mixer: { name: 'Audio Mixer', grad: 'linear-gradient(135deg,#ff9f43,#ff5e62)', quotes: ['An app stays untouched until you move its slider — that is when the process tap attaches.', 'Spotify at 75%, Safari at 130%, display speakers over DDC/CI. Boost up to 400%.'] },
        shelf: { name: 'File Shelf', grad: 'linear-gradient(135deg,#34c759,#0fa3a3)', quotes: ['Drop a file at the top of the screen and it lands here.', 'Space opens Quick Look. AirDrop is one drag away.'] },
        faceid: { name: 'Face ID', grad: 'linear-gradient(135deg,#bf5af2,#ff375f)', quotes: ['A 512-number ArcFace embedding is all I keep. No photos, ever.', 'The decryption key lives in your Keychain behind Touch ID.'] }
    };

    var MSG_GROUP_SCRIPT = [
        { kind: 'divider', text: 'Today 9:41 AM' },
        { kind: 'in', who: 'notch' },
        { kind: 'in', who: 'mixer', quote: 1 },
        { kind: 'in', who: 'shelf' },
        { kind: 'status', text: '🎚 10-band EQ · AutoEQ import · loudness compensation' },
        { kind: 'in', who: 'faceid', quote: 1 },
        { kind: 'in', who: 'notch', quote: 1 },
        { kind: 'out', text: 'pinned it open 🙌' },
        { kind: 'receipt', text: 'Read 9:44 AM' }
    ];

    var MSG_REPLIES = ['🎧 listening', '📚 stashed it', '🎚 level saved', '👤 matched on-device'];

    function msgTyping() {
        return el('div', 'tb-msg-bubble tb-msg-typing', '<span class="tb-msg-dot"></span><span class="tb-msg-dot"></span><span class="tb-msg-dot"></span>');
    }

    function msgAppend(content, item, state) {
        if (item.kind === 'divider' || item.kind === 'status' || item.kind === 'receipt') {
            var cls = item.kind === 'divider' ? 'tb-msg-day' : (item.kind === 'status' ? 'tb-msg-status' : 'tb-msg-receipt');
            var d = el('div', cls);
            d.textContent = item.text;
            content.appendChild(d);
            if (item.kind !== 'receipt') { state.lastWho = null; state.lastKind = item.kind; }
            return;
        }
        var out = item.kind === 'out', person = MSG_PEOPLE[item.who];
        if (!out && state.lastWho !== item.who) {
            var label = el('div', 'tb-msg-sender');
            label.textContent = person ? person.name.split(' ')[0] : '';
            content.appendChild(label);
        }
        var same = state.lastWho === (out ? 'me' : item.who) && state.lastKind === item.kind;
        var bubble = el('div', 'tb-msg-bubble tb-msg-anim' + (out ? ' tb-msg-out' : '') + (same ? ' tb-msg-cont' : ''));
        bubble.textContent = item.text || (person ? person.quotes[item.quote || 0] : '');
        if (!out) {
            bubble.addEventListener('dblclick', function () {
                var existing = bubble.querySelector('.tb-msg-tapback');
                if (existing) bubble.removeChild(existing);
                else bubble.appendChild(el('span', 'tb-msg-tapback', '❤️'));
            });
        }
        content.appendChild(bubble);
        state.lastWho = out ? 'me' : item.who;
        state.lastKind = item.kind;
    }

    function renderMessages() {
        var root = el('div', 'tb-msg',
            '<div class="tb-msg-side"><div class="tb-msg-side-head">Messages</div><div class="tb-msg-convs"></div></div>' +
            '<div class="tb-msg-main">' +
                '<div class="tb-msg-chat-head"><div class="tb-msg-chat-name"></div><div class="tb-msg-chat-sub">scripted demo ✨ every line is a real Notch feature</div></div>' +
                '<div class="tb-msg-thread"></div>' +
                '<div class="tb-msg-inputbar">' +
                    '<input type="text" class="tb-msg-input" placeholder="iMessage" aria-label="iMessage">' +
                    '<button type="button" class="tb-msg-send" aria-label="Send">↑</button>' +
                '</div>' +
            '</div>');

        var convList = root.querySelector('.tb-msg-convs'), headName = root.querySelector('.tb-msg-chat-name');
        var thread = root.querySelector('.tb-msg-thread'), input = root.querySelector('.tb-msg-input'), send = root.querySelector('.tb-msg-send');

        function scrollDown() { try { thread.scrollTop = thread.scrollHeight; } catch (e) {} }

        var contents = { group: el('div', 'tb-msg-conv-thread') };
        var convs = [
            { id: 'group', name: 'Notch — feature tour', icon: '🎧', grad: 'linear-gradient(135deg,#0a84ff,#5e5ce6)', time: '9:44 AM', preview: 'pinned it open 🙌' },
            { id: 'mixer', who: 'mixer', time: '9:43 AM', preview: MSG_PEOPLE.mixer.quotes[0] },
            { id: 'shelf', who: 'shelf', time: '9:42 AM', preview: MSG_PEOPLE.shelf.quotes[0] },
            { id: 'faceid', who: 'faceid', time: '9:41 AM', preview: MSG_PEOPLE.faceid.quotes[0] }
        ];

        ['mixer', 'shelf', 'faceid'].forEach(function (who, idx) {
            var c = el('div', 'tb-msg-conv-thread'), st = { lastWho: null, lastKind: null };
            msgAppend(c, { kind: 'divider', text: 'Today 9:4' + (idx + 1) + ' AM' }, st);
            MSG_PEOPLE[who].quotes.forEach(function (q, i) { msgAppend(c, { kind: 'in', who: who, quote: i }, st); });
            contents[who] = c;
        });

        var rows = [];
        function setActive(id) {
            rows.forEach(function (r) { r.row.classList.toggle('tb-msg-conv-sel', r.id === id); });
            var conv = convs.filter(function (c) { return c.id === id; })[0];
            headName.textContent = conv ? (conv.name || MSG_PEOPLE[conv.who].name) : '';
            clearKids(thread);
            thread.appendChild(contents[id]);
            scrollDown();
        }

        convs.forEach(function (conv) {
            var name = conv.name || MSG_PEOPLE[conv.who].name, grad = conv.grad || MSG_PEOPLE[conv.who].grad;
            var row = el('div', 'tb-msg-conv',
                '<div class="tb-msg-avatar" style="background:' + grad + '">' + esc(conv.icon || name.charAt(0)) + '</div>' +
                '<div class="tb-msg-conv-meta">' +
                    '<div class="tb-msg-conv-top"><span class="tb-msg-conv-name">' + esc(name) + '</span><span class="tb-msg-conv-time">' + esc(conv.time) + '</span></div>' +
                    '<div class="tb-msg-conv-prev">' + esc(conv.preview) + '</div>' +
                '</div>');
            row.addEventListener('click', function () { setActive(conv.id); });
            convList.appendChild(row);
            rows.push({ id: conv.id, row: row });
        });

        var groupState = { lastWho: null, lastKind: null };
        function replay(i) {
            if (!root.isConnected || i >= MSG_GROUP_SCRIPT.length) return;
            var item = MSG_GROUP_SCRIPT[i];
            if (item.kind === 'in') {
                var typing = msgTyping();
                contents.group.appendChild(typing);
                scrollDown();
                setTimeout(function () {
                    if (!root.isConnected) return;
                    if (typing.parentNode) typing.parentNode.removeChild(typing);
                    msgAppend(contents.group, item, groupState);
                    scrollDown();
                    setTimeout(function () { replay(i + 1); }, 300);
                }, 420);
            } else {
                msgAppend(contents.group, item, groupState);
                scrollDown();
                setTimeout(function () { replay(i + 1); }, item.kind === 'out' ? 300 : 180);
            }
        }
        setTimeout(function () { replay(0); }, 350);

        var replyIdx = 0;
        function sendMsg() {
            var text = String(input.value || '').replace(/^\s+|\s+$/g, '');
            if (!text) return;
            input.value = '';
            var st = { lastWho: null, lastKind: null };
            msgAppend(contents.group, { kind: 'out', text: text }, st);
            scrollDown();
            var typing = msgTyping();
            setTimeout(function () {
                if (!root.isConnected) return;
                contents.group.appendChild(typing);
                scrollDown();
                setTimeout(function () {
                    if (!root.isConnected) return;
                    if (typing.parentNode) typing.parentNode.removeChild(typing);
                    msgAppend(contents.group, { kind: 'in', who: 'notch', text: MSG_REPLIES[replyIdx++ % MSG_REPLIES.length] }, st);
                    scrollDown();
                }, 500);
            }, 700);
        }
        input.addEventListener('keydown', function (e) { if (e && e.key === 'Enter') sendMsg(); });
        send.addEventListener('click', sendMsg);

        setActive('group');
        return root;
    }

    function renderTerminal() {
        var root = el('div', 'tb-term'), PROMPT = 'you@macbook ~ % ', currentInput = null;
        function scrollBottom() { try { root.scrollTop = root.scrollHeight; } catch (e) {} }
        function print(text) {
            String(text).split('\n').forEach(function (line) { root.appendChild(el('div', 'tb-term-line', esc(line))); });
        }
        function spawnPrompt() {
            var row = el('div', 'tb-term-prompt',
                '<span class="tb-term-ps1">' + PROMPT + '</span>' +
                '<input type="text" size="1" spellcheck="false" autocomplete="off" aria-label="terminal input" class="tb-term-input">' +
                '<span class="tb-term-cursor"></span>');
            var input = row.querySelector('.tb-term-input'), cursor = row.querySelector('.tb-term-cursor');
            root.appendChild(row);
            input.addEventListener('input', function () { input.size = Math.max(1, String(input.value).length + 1); });
            input.addEventListener('keydown', function (e) {
                if (e && e.key === 'Enter') {
                    var line = String(input.value || '');
                    row.removeChild(input);
                    row.removeChild(cursor);
                    row.appendChild(el('span', 'tb-term-typed', esc(line)));
                    currentInput = null;
                    handle(line);
                }
            });
            currentInput = input;
            try { input.focus(); } catch (e) {}
            scrollBottom();
        }
        function cowsay(text) {
            text = String(text || 'moo').slice(0, 40);
            var w = text.length + 2;
            print([' ' + new Array(w + 1).join('_'), '< ' + text + ' >', ' ' + new Array(w + 1).join('-'),
                '        \\   ^__^', '         \\  (oo)\\_______', '            (__)\\       )\\/\\',
                '                ||----w |', '                ||     ||'].join('\n'));
        }
        var HELP = [
            '  help               this list',
            '  about              what is Notch',
            '  version            latest release tag',
            '  download           open Releases & Install window',
            '  repo               open Safari GitHub window',
            '  finder             open Finder window',
            '  notes              open Notes window',
            '  notch              open the notch panel',
            '  settings           open System Settings',
            '  cowsay <text>      moo',
            '  clear              wipe the screen'
        ].join('\n');

        var OPEN_CMDS = {
            download: [{ app: 'releases' }, 'opening Releases & Install…'],
            repo: [{ app: 'safari' }, 'opening Safari…'],
            finder: [{ app: 'folder', folder: 'project', title: 'notch-website' }, 'opening Finder…'],
            notes: [{ app: 'notes' }, 'opening Notes…'],
            settings: [{ app: 'settings' }, 'opening System Settings…'],
            notch: [{ app: 'music' }, '🎧 opening the notch panel…'],
            music: [{ app: 'music' }, '🎧 opening the notch panel…']
        };

        function handle(line) {
            var trimmed = String(line).replace(/^\s+|\s+$/g, '');
            var sp = trimmed.indexOf(' '), cmd = sp === -1 ? trimmed : trimmed.slice(0, sp), rest = sp === -1 ? '' : trimmed.slice(sp + 1);
            if (!cmd) { spawnPrompt(); return; }
            if (cmd === 'version') {
                if (typeof cfg().getLatestTag === 'function') {
                    cfg().getLatestTag(function (tag) { print('Notch ' + tag + ' (latest)'); spawnPrompt(); });
                } else { print('Notch v2.0.1 (latest)'); spawnPrompt(); }
                return;
            }
            if (OPEN_CMDS[cmd]) { openDetail(OPEN_CMDS[cmd][0]); print(OPEN_CMDS[cmd][1]); }
            else if (cmd === 'help') print(HELP);
            else if (cmd === 'about') print('Notch — a native macOS utility for the space around your camera.\nhover to peek · click to pin · esc to dismiss.\nfree for non-commercial use. running on macOS 27.0 (Liquid Glass).');
            else if (cmd === 'issues') { try { window.open(link('issues'), '_blank'); } catch (e) {} print('opening GitHub issues…'); }
            else if (cmd === 'cowsay') cowsay(rest || 'moo');
            else if (cmd === 'clear') clearKids(root);
            else if (cmd === 'sudo') print(trimmed === 'sudo make me a sandwich' ? 'ok ☕' : trimmed.split(' ')[0] + ': permission denied (nice try)');
            else if (cmd === 'hello') print('hi. yes. this is the terminal.');
            else print('zsh: command not found: ' + cmd);
            spawnPrompt();
            scrollBottom();
        }
        root.addEventListener('click', function () { if (currentInput) { try { currentInput.focus(); } catch (e) {} } });
        print('Last login: ' + new Date().toString().slice(0, 24) + ' on ttys000');
        print('Notch demo shell (macOS 27.0) — type `help`');
        spawnPrompt();
        return root;
    }

    function renderFaceTime() {
        var root = el('div', 'tb-ft',
            '<div class="tb-ft-stage">' +
                '<img class="tb-ft-icon" src="assets/icon.png" alt="Notch">' +
                '<div class="tb-ft-name">Camera mirror</div>' +
                '<div class="tb-ft-state">Framing preview — this page never opens your camera</div>' +
            '</div>' +
            '<div class="tb-ft-pip" title="Open Face ID Settings" style="cursor:pointer">' +
                '<div class="tb-ft-pip-emoji">🧑</div><div class="tb-ft-pip-label">You</div>' +
            '</div>' +
            '<div class="tb-ft-controls">' +
                '<button type="button" class="tb-ft-btn" data-ft="mic" aria-label="Mute microphone">🎤</button>' +
                '<button type="button" class="tb-ft-btn" data-ft="cam" aria-label="Toggle video">📹</button>' +
                '<button type="button" class="tb-ft-btn" data-ft="share" title="Open Notch Workspace" aria-label="Share screen">🖥️</button>' +
                '<button type="button" class="tb-ft-btn" data-ft="msg" title="Open Messages" aria-label="Open Messages">💬</button>' +
                '<button type="button" class="tb-ft-btn tb-ft-btn-end" data-ft="end" aria-label="End or restart preview">✕</button>' +
            '</div>');

        var icon = root.querySelector('.tb-ft-icon'), stateLine = root.querySelector('.tb-ft-state');
        var micBtn = root.querySelector('[data-ft="mic"]'), camBtn = root.querySelector('[data-ft="cam"]');
        var shareBtn = root.querySelector('[data-ft="share"]'), msgBtn = root.querySelector('[data-ft="msg"]'), endBtn = root.querySelector('[data-ft="end"]');
        icon.addEventListener('error', function () { icon.style.visibility = 'hidden'; });
        root.querySelector('.tb-ft-pip').addEventListener('click', function () { openDetail({ app: 'settings', pane: 'faceid' }); });

        var ended = false, sharing = false;
        micBtn.addEventListener('click', function () {
            stateLine.textContent = micBtn.classList.toggle('tb-ft-btn-off') ? 'Microphone muted' : 'Framing looks good — ready to join';
        });
        camBtn.addEventListener('click', function () {
            var off = camBtn.classList.toggle('tb-ft-btn-off');
            icon.classList.toggle('tb-ft-icon-ended', off);
            stateLine.textContent = off ? 'Camera paused' : 'Framing looks good — ready to join';
        });
        shareBtn.addEventListener('click', function () {
            sharing = !sharing;
            shareBtn.classList.toggle('tb-ft-btn-off', !sharing);
            stateLine.textContent = sharing ? 'Sharing Notch workspace preview' : 'Framing looks good — ready to join';
            openDetail({ app: 'music', view: 'home' });
        });
        msgBtn.addEventListener('click', function () { openDetail({ app: 'messages' }); });
        endBtn.addEventListener('click', function () {
            ended = !ended;
            stateLine.textContent = ended ? 'Mirror closed — click ↻ to resume preview' : 'Framing looks good — ready to join';
            icon.classList.toggle('tb-ft-icon-ended', ended);
            endBtn.textContent = ended ? '↻' : '✕';
            endBtn.style.background = ended ? '#30d158' : '';
            micBtn.disabled = camBtn.disabled = shareBtn.disabled = ended;
        });
        try { setTimeout(function () { if (!ended) stateLine.textContent = 'Framing looks good — ready to join'; }, 1800); } catch (e) {}
        return root;
    }

    var DEFAULT_NOTES = [
        { id: 'quick', title: 'Notch Quick Note', sub: 'Synced with Notch panel', storageKey: 'notch-quick-note', fallback: 'Notch turns the MacBook camera cutout into a live workspace.\n\n• Hover the notch to peek\n• Click to pin open\n• Press Esc to dismiss\n• Edit this note here or inside the Notch Quick Notes tab!' },
        { id: 'shortcuts', title: 'Keyboard Shortcuts', sub: 'Desktop & Notch controls', text: 'macOS 27 Desktop Shortcuts\n\n• ⌘Space — Open Spotlight Search\n• ⌘W — Close active window\n• ⌘M — Minimize active window\n• ⌘⇧D or F11 — Show / Hide Desktop\n• Esc — Dismiss open menus, Spotlight, or Notch' },
        { id: 'audio', title: 'Per-App Audio & EQ', sub: 'CoreAudio process tap notes', text: 'Per-App Audio Architecture\n\n• Zero overhead until a slider moves from 100%\n• Uses AudioHardwareCreateProcessTap on macOS 14.2+\n• Boost up to 400% (+12 dB) with a soft-knee limiter\n• 10-band parametric EQ + AutoEQ headphone profiles' }
    ];

    function renderNotes() {
        var root = el('div', 'tb-notes-app',
            '<div class="tb-notes-side">' +
                '<div class="tb-notes-side-top"><span class="tb-notes-side-title">Notes</span><button type="button" class="tb-notes-new-btn">+ New</button></div>' +
                '<div class="tb-notes-list"></div>' +
            '</div>' +
            '<div class="tb-notes-main">' +
                '<div class="tb-notes-toolbar">' +
                    '<span class="tb-notes-meta">Saved in browser</span>' +
                    '<div class="tb-tool-actions"><button type="button" class="tb-btn-secondary tb-notes-notch" style="padding:3px 10px;font-size:11.5px">Open in Notch ↗</button></div>' +
                '</div>' +
                '<textarea class="tb-notes-editor" aria-label="Note editor" placeholder="Write a note…"></textarea>' +
            '</div>');

        var listEl = root.querySelector('.tb-notes-list'), metaEl = root.querySelector('.tb-notes-meta'), editor = root.querySelector('.tb-notes-editor');
        root.querySelector('.tb-notes-notch').addEventListener('click', function () { openDetail({ app: 'music', view: 'notes' }); });

        var notes = DEFAULT_NOTES.map(function (n) {
            var text = n.text || '';
            if (n.storageKey) {
                try { text = localStorage.getItem(n.storageKey) || n.fallback; } catch (e) { text = n.fallback; }
            }
            return { id: n.id, title: n.title, sub: n.sub, storageKey: n.storageKey, text: text };
        });
        var activeId = 'quick';

        function updateMeta(note) {
            var chars = (note.text || '').length;
            var words = (note.text || '').trim() ? (note.text || '').trim().split(/\s+/).length : 0;
            metaEl.textContent = words + ' words · ' + chars + ' characters' + (note.storageKey ? ' · Synced with Notch' : '');
        }

        function renderList() {
            clearKids(listEl);
            notes.forEach(function (n) {
                var firstLine = (n.text || '').split('\n')[0] || n.title;
                var item = el('div', 'tb-notes-item' + (n.id === activeId ? ' is-active' : ''),
                    '<div class="tb-notes-item-title">' + esc(firstLine.slice(0, 36)) + '</div>' +
                    '<div class="tb-notes-item-sub">' + esc(n.sub) + '</div>');
                item.addEventListener('click', function () {
                    activeId = n.id;
                    editor.value = n.text;
                    updateMeta(n);
                    renderList();
                });
                listEl.appendChild(item);
            });
        }

        editor.addEventListener('input', function () {
            var cur = notes.filter(function (n) { return n.id === activeId; })[0];
            if (!cur) return;
            cur.text = editor.value;
            if (cur.storageKey) {
                try {
                    localStorage.setItem(cur.storageKey, cur.text);
                    window.dispatchEvent(new CustomEvent('tb:notes-sync', { detail: { text: cur.text, source: 'window' } }));
                } catch (e) {}
            }
            updateMeta(cur);
            renderList();
        });

        root.querySelector('.tb-notes-new-btn').addEventListener('click', function () {
            var created = { id: 'note-' + Date.now(), title: 'New Note', sub: 'Just now', text: 'New Note\n\n' };
            notes.unshift(created);
            activeId = created.id;
            editor.value = created.text;
            updateMeta(created);
            renderList();
            editor.focus();
        });

        window.addEventListener('tb:notes-sync', function onSync(e) {
            if (!root.isConnected) { window.removeEventListener('tb:notes-sync', onSync); return; }
            if (e.detail && e.detail.source !== 'window' && typeof e.detail.text === 'string') {
                notes[0].text = e.detail.text;
                if (activeId === 'quick') { editor.value = e.detail.text; updateMeta(notes[0]); }
                renderList();
            }
        });

        editor.value = notes[0].text;
        updateMeta(notes[0]);
        renderList();
        return root;
    }

    var LAUNCH_APPS = [
        { icon: 'assets/icon.png', label: 'Notch', detail: { app: 'music', view: 'home' }, cat: 'Media' },
        { icon: 'assets/icons/finder.png', label: 'Finder', detail: { app: 'folder', folder: 'project', title: 'notch-website' }, cat: 'Utilities' },
        { icon: 'assets/icons/safari.png', label: 'Safari', detail: { app: 'safari' }, cat: 'Utilities' },
        { icon: 'assets/icons/notes.png', label: 'Notes', detail: { app: 'notes' }, cat: 'Utilities' },
        { icon: 'assets/icons/messages.png', label: 'Messages', detail: { app: 'messages' }, cat: 'Social' },
        { icon: 'assets/icons/facetime.png', label: 'Camera Mirror', detail: { app: 'facetime' }, cat: 'Media' },
        { icon: 'assets/icons/terminal.png', label: 'Terminal', detail: { app: 'terminal' }, cat: 'Developer' },
        { icon: 'assets/icons/settings.png', label: 'System Settings', detail: { app: 'settings' }, cat: 'Utilities' },
        { icon: 'assets/icons/github.png', label: 'GitHub', detail: { app: 'safari' }, cat: 'Developer' },
        { icon: 'assets/icons/app-store.png', label: 'Releases & Install', detail: { app: 'releases' }, cat: 'Developer' },
        { icon: 'assets/icons/xcode.png', label: 'About This Mac', detail: { app: 'about' }, cat: 'Developer' },
        { icon: 'assets/icons/spotify.png', label: 'Now Playing', detail: { app: 'music', view: 'media' }, cat: 'Media' }
    ];

    var LAUNCH_CATS = ['All', 'Media', 'Utilities', 'Social', 'Developer'];

    function renderApps() {
        var root = el('div', 'tb-launch',
            '<div class="tb-launch-toolbar"><div class="tb-launch-title">Applications</div><div class="tb-launch-pills"></div></div>' +
            '<div class="tb-launch-grid"></div>');
        var pills = root.querySelector('.tb-launch-pills'), grid = root.querySelector('.tb-launch-grid');
        var active = 'All', pillEls = [];

        function renderGrid() {
            clearKids(grid);
            LAUNCH_APPS.forEach(function (entry) {
                if (active !== 'All' && entry.cat !== active) return;
                var cell = el('button', 'tb-launch-cell',
                    '<img class="tb-launch-icon" src="' + esc(entry.icon) + '" alt="' + esc(entry.label) + '">' +
                    '<span class="tb-launch-label">' + esc(entry.label) + '</span>');
                cell.type = 'button';
                var img = cell.querySelector('img');
                img.addEventListener('error', function () { img.style.visibility = 'hidden'; });
                cell.addEventListener('click', function () { openDetail(entry.detail); });
                grid.appendChild(cell);
            });
        }

        LAUNCH_CATS.forEach(function (cat) {
            var pill = el('button', 'tb-launch-pill' + (cat === active ? ' tb-launch-pill-active' : ''), esc(cat));
            pill.type = 'button';
            pill.addEventListener('click', function () {
                active = cat;
                pillEls.forEach(function (p) { p.el.classList.toggle('tb-launch-pill-active', p.cat === active); });
                renderGrid();
            });
            pillEls.push({ cat: cat, el: pill });
            pills.appendChild(pill);
        });

        renderGrid();
        return root;
    }

    var RENDERERS = {
        releases: renderReleases, safari: renderSafari, download: renderDownload, about: renderAbout,
        folder: renderFolder, viewer: renderViewer, messages: renderMessages, terminal: renderTerminal,
        facetime: renderFaceTime, notes: renderNotes, apps: renderApps,
        settings: function (opts) {
            return (typeof window.TBSettingsUI === 'function') ? window.TBSettingsUI(opts) : el('div', 'tb-app-unknown', 'Settings failed to load');
        }
    };
    window.TBApps = {
        render: function (appId, opts) {
            try { if (RENDERERS[appId]) return RENDERERS[appId](opts); } catch (e) {}
            return el('div', 'tb-app-unknown', 'Unknown app');
        }
    };
})();
