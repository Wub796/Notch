/* js/apps.js — content that lives INSIDE the windows.
   Exposes window.TBApps.render(appId, opts) -> HTMLElement. Renderers are
   self-contained; folder rows fire-and-forget 'tb:open-app' for the window
   manager. Outbound links come from window.TB_CONFIG and degrade to '#'. */
(function () {
    'use strict';

    /* ---------- config helpers (never throw when TB_CONFIG is missing) ---------- */

    function cfg() {
        return (typeof window.TB_CONFIG !== 'undefined' && window.TB_CONFIG) || {};
    }

    function siteName() {
        var c = cfg();
        return typeof c.appName === 'string' && c.appName ? c.appName : 'Notch';
    }

    function link(key) {
        var c = cfg();
        if (c.links && typeof c.links[key] === 'string' && c.links[key]) {
            return c.links[key];
        }
        return '#';
    }

    /* ---------- tiny DOM utilities ---------- */

    function esc(s) {
        return String(s)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    function el(tag, className, html) {
        var node = document.createElement(tag);
        if (className) node.className = className;
        if (html) node.innerHTML = html;
        return node;
    }

    function parseRepo(url) {
        var parts = String(url || '').replace(/\/+$/, '').split('/');
        if (parts.length >= 2 && parts[parts.length - 2] && parts[parts.length - 1]) {
            return { org: parts[parts.length - 2], repo: parts[parts.length - 1] };
        }
        return { org: 'Wub796', repo: 'Notch' };
    }

    function copyText(text, btn) {
        function done() {
            btn.textContent = 'Copied!';
            setTimeout(function () { btn.textContent = '📋 Copy'; }, 1600);
        }
        function legacy() {
            var ta = document.createElement('textarea');
            ta.value = text;
            ta.setAttribute('readonly', '');
            ta.style.position = 'absolute';
            ta.style.left = '-9999px';
            document.body.appendChild(ta);
            ta.select();
            try { document.execCommand('copy'); } catch (e) { /* best effort */ }
            document.body.removeChild(ta);
            done();
        }
        if (typeof navigator !== 'undefined' && navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(text).then(done, legacy);
        } else {
            legacy();
        }
    }

    /* ---------- safari: self-contained GitHub repo page replica ---------- */

    function renderSafari() {
        var github = link('github');
        var repo = parseRepo(github);
        var cloneUrl = github === '#' ? '#' : github + '.git';
        var name = siteName();
        var root = el('div', 'tb-gh-page');

        root.appendChild(el('div', 'tb-gh-header',
            '<div class="tb-gh-header-left">' +
            '<span class="tb-gh-book">📖</span>' +
            '<a class="tb-gh-org" href="' + esc(github) + '" target="_blank" rel="noopener">' + esc(repo.org) + '</a>' +
            '<span class="tb-gh-slash">/</span>' +
            '<a class="tb-gh-repo" href="' + esc(github) + '" target="_blank" rel="noopener">' + esc(repo.repo) + '</a>' +
            '<span class="tb-gh-pill">Public</span>' +
            '</div>' +
            /* no invented counters on the buttons: the real numbers live on
               GitHub, and a made-up star count is the kind of detail a reader
               cannot tell from a real one */
            '<div class="tb-gh-header-right">' +
            '<span class="tb-gh-btn">👁 Watch</span>' +
            '<span class="tb-gh-btn">🍴 Fork</span>' +
            '<span class="tb-gh-btn">★ Star</span>' +
            '</div>'));

        root.appendChild(el('div', 'tb-gh-tabs',
            '<span class="tb-gh-tab tb-gh-tab-active">&lt;&gt; Code</span>' +
            '<span class="tb-gh-tab">⊙ Issues</span>' +
            '<span class="tb-gh-tab">⑂ Pull requests</span>' +
            '<span class="tb-gh-tab">▶ Actions</span>'));

        root.appendChild(el('div', 'tb-gh-branch-row',
            '<span class="tb-gh-branch-pill">⑂ main</span>' +
            '<span class="tb-gh-filecount">Swift 6 · Xcode 16 · MIT-ish (see notices)</span>'));

        var cloneWrap = el('div', 'tb-gh-clone-wrap');
        var codeBtn = el('button', 'tb-gh-code-btn', '‹› Code ▾');
        codeBtn.type = 'button';
        var cloneBox = el('div', 'tb-gh-clone-box',
            '<div class="tb-gh-clone-label">Clone with HTTPS</div>' +
            '<div class="tb-gh-clone-row">' +
            '<input class="tb-gh-clone-field" type="text" readonly value="' + esc(cloneUrl) + '">' +
            '<button class="tb-gh-copy-btn" type="button">📋 Copy</button>' +
            '</div>');
        cloneBox.style.display = 'none';
        codeBtn.addEventListener('click', function () {
            cloneBox.style.display = cloneBox.style.display === 'none' ? 'block' : 'none';
        });
        var copyBtn = cloneBox.querySelector('.tb-gh-copy-btn');
        copyBtn.addEventListener('click', function () { copyText(cloneUrl, copyBtn); });
        cloneWrap.appendChild(codeBtn);
        cloneWrap.appendChild(cloneBox);
        root.appendChild(cloneWrap);

        root.appendChild(el('div', 'tb-gh-readme',
            '<div class="tb-gh-readme-head">📄 README.md</div>' +
            '<div class="tb-gh-readme-body">' +
            '<h1 class="tb-gh-h1">🎧 ' + esc(name) + '</h1>' +
            '<p class="tb-gh-badges">' +
            '<span class="tb-badge"><i>version</i><b class="tb-badge-blue tb-live-version" data-version-tpl="{v}">…</b></span>' +
            '<span class="tb-badge"><i>macOS</i><b class="tb-badge-green">14.0+</b></span>' +
            '<span class="tb-badge"><i>swift</i><b class="tb-badge-brown">6.0</b></span>' +
            '</p>' +
            '<p class="tb-gh-p">Say hello to <b>' + esc(name) + '</b>, a native macOS utility that turns the area ' +
            'around your camera into an interactive workspace. Hover the notch to peek, click it to pin the panel ' +
            'open, and press <kbd>Esc</kbd> to dismiss it. Nothing here polls the network: an idle notch does nothing at all.</p>' +
            '<ul class="tb-gh-ul">' +
            '<li>🎧 now playing with scrubbers and live lyrics (Apple Music &amp; Spotify)</li>' +
            '<li>🎛️ per-app audio mixer with boost up to 400% and a 10-band EQ</li>' +
            '<li>📚 temporary file shelf with AirDrop and Quick Look</li>' +
            '<li>👤 on-device Face ID unlock for the lock and wake screens</li>' +
            '<li>📈 system telemetry, calendar, weather, Clock and Siri timers</li>' +
            '<li>🖥️ physical notch, or simulated notch mode on any display</li>' +
            '</ul>' +
            '<a class="tb-btn-primary" href="' + esc(github) + '" target="_blank" rel="noopener">View on GitHub ↗</a>' +
            '</div>'));

        setVersionInto(root);
        return root;
    }

    /* live version labels: swaps the {v} slot of every .tb-live-version's
       data-version-tpl for the repo's latest tag (via config.js, cached). */
    function setVersionInto(node) {
        var cfg = (typeof window.TB_CONFIG === 'object' && window.TB_CONFIG) || null;
        if (!cfg || typeof cfg.getLatestTag !== 'function' || !node) { return; }
        cfg.getLatestTag(function (tag) {
            var els = node.querySelectorAll('.tb-live-version');
            for (var i = 0; i < els.length; i++) {
                var tpl = els[i].getAttribute('data-version-tpl');
                els[i].textContent = tpl ? tpl.replace('{v}', tag) : tag;
            }
        });
    }

    /* ---------- download: App-Store-style card ---------- */

    function renderDownload() {
        var card = el('div', 'tb-card tb-card-pad32',
            '<img class="tb-dl-icon-img" src="assets/icon.png" alt="Notch app icon">' +
            '<div class="tb-card-title">' + esc(siteName()) + ' for macOS</div>' +
            '<div class="tb-card-sub tb-live-version" data-version-tpl="{v} · Universal (Apple Silicon + Intel) · Free &amp; open source">…</div>' +
            '<a class="tb-btn-primary tb-btn-big" href="' + esc(link('githubReleases')) + '" target="_blank" rel="noopener">Download from GitHub Releases</a>' +
            '<div class="tb-card-caption">Requires macOS 14.0 Sonoma or later · 14.2+ for the per-app mixer and the closed-notch meter</div>');
        setVersionInto(card);
        return card;
    }

    /* ---------- releases: install steps + version, the honest replacement for
       a store window this app does not have ---------- */

    function renderReleases() {
        var card = el('div', 'tb-card tb-card-pad32');
        card.appendChild(el('h2', 'tb-card-h2', 'Releases & install'));
        card.appendChild(el('p', 'tb-card-p',
            'Notch ships as a signed-zip release on GitHub. Every build is universal, so the same download ' +
            'runs on Apple Silicon and Intel.'));
        card.appendChild(el('div', 'tb-card-sub tb-live-version',
            'data-version-tpl="Latest release: {v}"'));
        card.appendChild(el('ol', 'tb-dl-steps',
            '<li>Download <b>Notch.zip</b> from the Releases page and unzip it.</li>' +
            '<li>Move <b>Notch.app</b> into <code>/Applications</code>.</li>' +
            '<li>Launch it. Hover the notch to peek, click to pin, <kbd>Esc</kbd> to dismiss.</li>'));
        card.appendChild(el('p', 'tb-card-p',
            'If macOS blocks the first launch with an unidentified-developer warning, clear the quarantine ' +
            'flag once:'));
        var cmd = el('div', 'tb-dl-cmd');
        var field = el('code', 'tb-dl-cmd-text', 'xattr -dr com.apple.quarantine "/Applications/Notch.app"');
        var btn = el('button', 'tb-gh-copy-btn', '📋 Copy');
        btn.type = 'button';
        btn.addEventListener('click', function () {
            copyText('xattr -dr com.apple.quarantine "/Applications/Notch.app"', btn);
        });
        cmd.appendChild(field);
        cmd.appendChild(btn);
        card.appendChild(cmd);

        var actions = el('div', 'tb-dl-actions');
        var a1 = el('a', 'tb-btn-primary', 'Open Releases ↗');
        a1.href = link('githubReleases');
        a1.target = '_blank';
        a1.rel = 'noopener';
        var a2 = el('a', 'tb-btn-secondary', 'Read the README ↗');
        a2.href = link('readme');
        a2.target = '_blank';
        a2.rel = 'noopener';
        actions.appendChild(a1);
        actions.appendChild(a2);

        card.appendChild(el('div', 'tb-card-caption',
            'Building from source needs Xcode 16 and Swift 6. Apple Developer ID signing is required for ' +
            'login-at-launch and Sparkle updates in production.'));
        setVersionInto(card);
        return card;
    }

    /* ---------- about: About This Mac replica ---------- */

    function renderAbout() {
        /* Replica of the real About This Mac sheet — the values describe the
           machine the site pretends to be running on, not the visitor's. */
        var rows = [
            ['Chip', 'Apple Silicon'],
            ['Memory', '16 GB'],
            ['Startup disk', 'Macintosh HD'],
            ['Serial', 'N0TCH-D3M0-2026'],
            ['macOS', '14.2 Sonoma (Notch needs 14.0+)']
        ];
        var html = '<div class="tb-about-icon">💻</div>' +
            '<div class="tb-about-name">This Mac — running Notch</div>' +
            '<div class="tb-about-rows">';
        rows.forEach(function (r) {
            html += '<div class="tb-about-row">' +
                '<span class="tb-about-label">' + esc(r[0]) + '</span>' +
                '<span class="tb-about-value">' + esc(r[1]) + '</span></div>';
        });
        html += '</div>' +
            '<a class="tb-btn-secondary" href="' + esc(link('github')) + '" target="_blank" rel="noopener">More Info…</a>';
        return el('div', 'tb-card tb-card-pad28', html);
    }

    /* ---------- VFS: virtual filesystem mirroring the real project ----------
       Every text entry below is a real file on this origin, so Preview fetches
       and shows the actual source instead of a canned copy. */

    function vfDir(name, path, children) {
        return { name: name, path: path, dir: true, children: children };
    }

    function vfFile(name, path, kind, size) {
        return { name: name, path: path, dir: false, kind: kind, size: size || null };
    }

    function vfTexts(dirPath, names) {
        return names.map(function (n) { return vfFile(n, dirPath + '/' + n, 'text'); });
    }

    function vfImages(dirPath, entries) {
        return entries.map(function (pair) { return vfFile(pair[0], dirPath + '/' + pair[0], 'image', pair[1]); });
    }

    var VFS_ROOT = vfDir('notch-website', '', [
        vfFile('index.html', 'index.html', 'text', '6.7 KB'),
        vfFile('README.md', 'README.md', 'text', '8.9 KB'),
        vfFile('robots.txt', 'robots.txt', 'text', '101 B'),
        vfFile('sitemap.xml', 'sitemap.xml', 'text', '261 B'),
        vfDir('css', 'css', [
            vfFile('apps.css', 'css/apps.css', 'text', '26.2 KB'),
            vfFile('desktop-icons.css', 'css/desktop-icons.css', 'text', '2.9 KB'),
            vfFile('dock.css', 'css/dock.css', 'text', '5.6 KB'),
            vfFile('main.css', 'css/main.css', 'text', '17.5 KB'),
            vfFile('notch.css', 'css/notch.css', 'text', '22.2 KB'),
            vfFile('promo.css', 'css/promo.css', 'text', '6.4 KB'),
            vfFile('settings-app.css', 'css/settings-app.css', 'text', '8.0 KB'),
            vfFile('widgets.css', 'css/widgets.css', 'text', '8.6 KB'),
            vfFile('windows.css', 'css/windows.css', 'text', '7.4 KB')
        ]),
        vfDir('js', 'js', [
            vfFile('apps.js', 'js/apps.js', 'text', '50.5 KB'),
            vfFile('config.js', 'js/config.js', 'text', '4.5 KB'),
            vfFile('desktop-icons.js', 'js/desktop-icons.js', 'text', '14.7 KB'),
            vfFile('dock.js', 'js/dock.js', 'text', '12.3 KB'),
            vfFile('menubar.js', 'js/menubar.js', 'text', '39.3 KB'),
            vfFile('notch.js', 'js/notch.js', 'text', '15.1 KB'),
            vfFile('promo.js', 'js/promo.js', 'text', '7.3 KB'),
            vfFile('settings-app.js', 'js/settings-app.js', 'text', '19.5 KB'),
            vfFile('widgets.js', 'js/widgets.js', 'text', '16.7 KB'),
            vfFile('window-geometry.js', 'js/window-geometry.js', 'text', '2.6 KB'),
            vfFile('windows.js', 'js/windows.js', 'text', '23.3 KB')
        ]),
        vfDir('assets', 'assets', [
            vfFile('icon.png', 'assets/icon.png', 'image', '20.1 KB'),
            vfFile('favicon.ico', 'assets/favicon.ico', 'image', '1.5 KB'),
            vfFile('favicon-16x16.png', 'assets/favicon-16x16.png', 'image', '650 B'),
            vfFile('favicon-32x32.png', 'assets/favicon-32x32.png', 'image', '1.5 KB'),
            vfFile('apple-touch-icon.png', 'assets/apple-touch-icon.png', 'image', '15.6 KB'),
            vfFile('og-image.png', 'assets/og-image.png', 'image', '31.4 KB'),
            vfFile('site.webmanifest', 'assets/site.webmanifest', 'text', '733 B'),
            vfDir('icons', 'assets/icons', vfImages('assets/icons', [
                ['app-store.png', '6.4 KB'], ['facetime.png', '6.3 KB'],
                ['finder.png', '5.4 KB'], ['github.png', '8.4 KB'],
                ['maps.png', '11.5 KB'], ['messages.png', '7.4 KB'],
                ['notes.png', '3.7 KB'], ['safari.png', '10.6 KB'],
                ['settings.png', '12.5 KB'], ['spotify.png', '6.0 KB'],
                ['terminal.png', '5.7 KB'], ['xcode.png', '7.3 KB'],
            ])),
            vfDir('wallpapers', 'assets/wallpapers', vfImages('assets/wallpapers', [
                ['luca-bravo-ii5JY_46xH0-unsplash.jpg', '1.3 MB'],
                ['anders-jilden-cYrMQA7a3Wc-unsplash.jpg', '1.0 MB'],
                ['garrett-parker-DlkF4-dbCOU-unsplash.jpg', '853 KB'],
                ['ian-dooley-DuBNA1QMpPA-unsplash.jpg', '343 KB'],
                ['buzz-andersen-E4944K_4SvI-unsplash.jpg', '816 KB']
            ]))
        ])
    ]);

    function vfsResolve(path) {
        var clean = String(path || '').replace(/^\/+|\/+$/g, '');
        if (!clean) return VFS_ROOT;
        var node = VFS_ROOT;
        var parts = clean.split('/');
        for (var i = 0; i < parts.length; i++) {
            if (!node || !node.dir) return null;
            var next = null;
            for (var j = 0; j < node.children.length; j++) {
                if (node.children[j].name === parts[i]) { next = node.children[j]; break; }
            }
            node = next;
        }
        return node;
    }

    function clearKids(node) {
        while (node.firstChild) node.removeChild(node.firstChild);
    }

    /* ---------- folder: full Finder (toolbar, sidebar, navigable VFS) ---------- */

    var FINDER_FAVORITES = [
        ['🏠', 'notch-website', ''],
        ['📁', 'css', 'css'],
        ['📁', 'js', 'js'],
        ['📁', 'icons', 'assets/icons'],
        ['🖼️', 'wallpapers', 'assets/wallpapers']
    ];

    function finderGlyph(node) {
        if (node.dir) return '📁';
        return node.kind === 'image' ? '🖼️' : '📄';
    }

    function finderMeta(node) {
        if (node.dir) return node.children.length + ' items';
        return node.size || '—';
    }

    function renderFolder(opts) {
        var name = (opts && typeof opts.name === 'string' && opts.name) || '';
        var startPath = name === 'wallpapers' || (opts && opts.folder === 'wallpapers') ? 'assets/wallpapers' : '';
        var startNode = vfsResolve(startPath);
        if (!startNode || !startNode.dir) startPath = '';

        var root = el('div', 'tb-fx');

        /* toolbar: back/forward buttons + breadcrumb trail */
        var toolbar = el('div', 'tb-fx-toolbar');
        var backBtn = el('button', 'tb-fx-nav-btn', '‹');
        backBtn.type = 'button';
        backBtn.setAttribute('aria-label', 'Back');
        var fwdBtn = el('button', 'tb-fx-nav-btn', '›');
        fwdBtn.type = 'button';
        fwdBtn.setAttribute('aria-label', 'Forward');
        var crumbs = el('div', 'tb-fx-crumbs');
        toolbar.appendChild(backBtn);
        toolbar.appendChild(fwdBtn);
        toolbar.appendChild(crumbs);

        /* body: favorites sidebar + file list */
        var body = el('div', 'tb-fx-body');
        var sidebar = el('div', 'tb-fx-sidebar');
        sidebar.appendChild(el('div', 'tb-fx-side-head', 'Favorites'));
        var sideRows = FINDER_FAVORITES.map(function (fav) {
            var row = el('div', 'tb-fx-side-row');
            row.appendChild(el('span', 'tb-fx-side-glyph', fav[0]));
            row.appendChild(el('span', 'tb-fx-side-name', esc(fav[1])));
            row.addEventListener('click', function () { navigate(fav[2]); });
            sidebar.appendChild(row);
            return { path: fav[2], row: row };
        });
        var list = el('div', 'tb-fx-list');
        body.appendChild(sidebar);
        body.appendChild(list);

        var status = el('div', 'tb-fx-status');

        root.appendChild(toolbar);
        root.appendChild(body);
        root.appendChild(status);

        /* real history stack, private to this window instance */
        var history = [startPath];
        var hi = 0;

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

            /* breadcrumb: root name › each segment; every segment but the last jumps */
            clearKids(crumbs);
            var labels = [VFS_ROOT.name].concat(segs);
            labels.forEach(function (label, i) {
                if (i > 0) crumbs.appendChild(el('span', 'tb-fx-sep', ' › '));
                var last = i === labels.length - 1;
                var crumb = el('span', last ? 'tb-fx-crumb tb-fx-crumb-cur' : 'tb-fx-crumb', esc(label));
                if (!last) {
                    (function (idx) {
                        crumb.addEventListener('click', function () {
                            navigate(idx === 0 ? '' : segs.slice(0, idx).join('/'));
                        });
                    })(i);
                }
                crumbs.appendChild(crumb);
            });

            /* sidebar: highlight the favorite matching the current directory */
            sideRows.forEach(function (r) {
                r.row.classList.toggle('tb-fx-side-active', r.path === dir.path);
            });

            /* list: folders first, then files, alphabetical within each group */
            clearKids(list);
            var kids = dir.children.slice().sort(function (a, b) {
                if (a.dir !== b.dir) return a.dir ? -1 : 1;
                var an = a.name.toLowerCase();
                var bn = b.name.toLowerCase();
                return an < bn ? -1 : (an > bn ? 1 : 0);
            });
            var selected = null;
            kids.forEach(function (node) {
                var row = el('div', 'tb-fx-row');
                row.appendChild(el('span', 'tb-fx-glyph', finderGlyph(node)));
                row.appendChild(el('span', 'tb-fx-name', esc(node.name)));
                row.appendChild(el('span', 'tb-fx-meta', esc(finderMeta(node))));
                row.addEventListener('click', function () {
                    if (selected) selected.classList.remove('tb-fx-row-sel');
                    selected = row;
                    row.classList.add('tb-fx-row-sel');
                });
                row.addEventListener('dblclick', function () {
                    if (node.dir) {
                        navigate(node.path);
                    } else {
                        try {
                            window.dispatchEvent(new CustomEvent('tb:open-app', {
                                detail: { app: 'viewer', title: node.name, path: node.path }
                            }));
                        } catch (e) { /* fire-and-forget: nobody may be listening */ }
                    }
                });
                list.appendChild(row);
            });

            status.textContent = kids.length + ' items';
            backBtn.disabled = hi <= 0;
            fwdBtn.disabled = hi >= history.length - 1;
        }

        backBtn.addEventListener('click', function () {
            if (hi > 0) { hi -= 1; render(); }
        });
        fwdBtn.addEventListener('click', function () {
            if (hi < history.length - 1) { hi += 1; render(); }
        });

        render();
        return root;
    }

    /* ---------- viewer: file preview (live text fetch / image / embedded) ---------- */

    var VIEWER_MAX_LINES = 400;

    function viewerCard(icon, title, sub) {
        return el('div', 'tb-pv-card',
            '<div class="tb-pv-card-icon">' + icon + '</div>' +
            '<div class="tb-pv-card-title">' + esc(title) + '</div>' +
            (sub ? '<div class="tb-pv-card-sub">' + esc(sub) + '</div>' : ''));
    }

    function viewerTextPane(text) {
        var pane = el('div', 'tb-pv-text');
        var lines = String(text).replace(/\r\n?/g, '\n').split('\n');
        var total = lines.length;
        if (total > VIEWER_MAX_LINES) lines = lines.slice(0, VIEWER_MAX_LINES);
        var htmlLines = lines.map(function (ln, i) {
            return '<span class="tb-pv-ln">' + (i + 1) + '</span>' + esc(ln);
        });
        pane.appendChild(el('pre', 'tb-pv-pre', htmlLines.join('\n')));
        if (total > VIEWER_MAX_LINES) {
            pane.appendChild(el('div', 'tb-pv-trunc',
                '… truncated — showing ' + VIEWER_MAX_LINES + ' of ' + total + ' lines'));
        }
        return pane;
    }

    function renderViewer(opts) {
        var path = (opts && typeof opts.path === 'string') ? opts.path : '';
        var node = vfsResolve(path);
        var root = el('div', 'tb-pv');

        if (!node || node.dir) {
            root.appendChild(viewerCard('🗂️', 'File not found',
                path ? '“' + path + '” isn’t part of this site’s filesystem.' : 'No file was specified.'));
            return root;
        }

        if (node.kind === 'image') {
            var imgPane = el('div', 'tb-pv-image');
            var img = el('img', 'tb-pv-img');
            img.src = node.path;
            img.alt = node.name;
            imgPane.appendChild(img);
            root.appendChild(imgPane);
            return root;
        }

        /* real text file: fetched live, same-origin, via its VFS-whitelisted path */
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
                root.appendChild(viewerCard('⚠️', 'Could not load file.',
                    '“' + node.name + '” couldn’t be fetched from this origin.'));
            });
        } catch (e) {
            clearKids(root);
            root.appendChild(viewerCard('⚠️', 'Could not load file.', node.name));
        }
        return root;
    }

    /* ---------- messages: a scripted feature tour, sent by the app itself ----------
       Nobody real is quoted here. Every line describes something Notch genuinely
       does (see the README) and the senders are Notch's own subsystems, not
       customers — a demo thread rather than invented testimonials. */

    var MSG_PEOPLE = {
        notch: {
            name: 'Notch', grad: 'linear-gradient(135deg,#0a84ff,#5e5ce6)', quotes: [
                "Hover me to peek, click to pin me open, and Esc puts me away.",
                'When the panel is closed I do nothing at all — no polling, no timers, no Dock icon.'
            ]
        },
        mixer: {
            name: 'Audio Mixer', grad: 'linear-gradient(135deg,#ff9f43,#ff5e62)', quotes: [
                'An app stays untouched until you move its slider — that is when the process tap attaches.',
                'Spotify at 75%, Safari at 130%, display speakers over DDC/CI. Boost up to 400%.'
            ]
        },
        shelf: {
            name: 'File Shelf', grad: 'linear-gradient(135deg,#34c759,#0fa3a3)', quotes: [
                'Drop a file at the top of the screen and it lands here.',
                'Space opens Quick Look. AirDrop is one drag away.'
            ]
        },
        faceid: {
            name: 'Face ID', grad: 'linear-gradient(135deg,#bf5af2,#ff375f)', quotes: [
                'A 512-number ArcFace embedding is all I keep. No photos, ever.',
                'The decryption key lives in your Keychain behind Touch ID.'
            ]
        }
    };

    /* the feature-tour thread, scripted in replay order */
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

    var MSG_REPLIES = [
        '🎧 listening',
        '📚 stashed it',
        '🎚 level saved',
        '👤 matched on-device'
    ];

    /* ---------- messages: iMessage replica, testimonials as a live chat ---------- */

    function msgText(item) {
        if (item.text) return item.text;
        var p = MSG_PEOPLE[item.who];
        return p ? p.quotes[item.quote || 0] : '';
    }

    function msgTyping() {
        return el('div', 'tb-msg-bubble tb-msg-typing',
            '<span class="tb-msg-dot"></span><span class="tb-msg-dot"></span><span class="tb-msg-dot"></span>');
    }

    function msgToggleTapback(bubble) {
        var existing = bubble.querySelector('.tb-msg-tapback');
        if (existing) {
            bubble.removeChild(existing);
        } else {
            bubble.appendChild(el('span', 'tb-msg-tapback', '❤️'));
        }
    }

    /* appends one scripted item; state tracks last sender for group labels
       and reduced consecutive-bubble margins */
    function msgAppend(content, item, state) {
        if (item.kind === 'divider') {
            var day = el('div', 'tb-msg-day');
            day.textContent = item.text;
            content.appendChild(day);
            state.lastWho = null;
            state.lastKind = 'divider';
            return;
        }
        if (item.kind === 'status') {
            var st = el('div', 'tb-msg-status');
            st.textContent = item.text;
            content.appendChild(st);
            state.lastWho = null;
            state.lastKind = 'status';
            return;
        }
        if (item.kind === 'receipt') {
            var rc = el('div', 'tb-msg-receipt');
            rc.textContent = item.text;
            content.appendChild(rc);
            return;
        }
        var out = item.kind === 'out';
        if (!out && state.lastWho !== item.who) {
            var person = MSG_PEOPLE[item.who];
            var label = el('div', 'tb-msg-sender');
            label.textContent = person ? person.name.split(' ')[0] : '';
            content.appendChild(label);
        }
        var same = state.lastWho === (out ? 'me' : item.who) && state.lastKind === item.kind;
        var bubble = el('div', 'tb-msg-bubble tb-msg-anim' +
            (out ? ' tb-msg-out' : '') + (same ? ' tb-msg-cont' : ''));
        bubble.textContent = msgText(item);
        if (!out) {
            bubble.addEventListener('dblclick', function () { msgToggleTapback(bubble); });
        }
        content.appendChild(bubble);
        state.lastWho = out ? 'me' : item.who;
        state.lastKind = item.kind;
    }

    function renderMessages() {
        var root = el('div', 'tb-msg');

        /* left sidebar: header + 4 conversation rows */
        var side = el('div', 'tb-msg-side');
        side.appendChild(el('div', 'tb-msg-side-head', 'Messages'));
        var convList = el('div', 'tb-msg-convs');
        side.appendChild(convList);

        /* main column: chat header + thread + input bar */
        var main = el('div', 'tb-msg-main');
        var head = el('div', 'tb-msg-chat-head');
        var headName = el('div', 'tb-msg-chat-name');
        head.appendChild(headName);
        head.appendChild(el('div', 'tb-msg-chat-sub', 'scripted demo ✨ every line is a real Notch feature'));
        var thread = el('div', 'tb-msg-thread');
        var bar = el('div', 'tb-msg-inputbar');
        var input = el('input', 'tb-msg-input');
        input.type = 'text';
        input.placeholder = 'iMessage';
        input.setAttribute('aria-label', 'iMessage');
        var send = el('button', 'tb-msg-send', '↑');
        send.type = 'button';
        send.setAttribute('aria-label', 'Send');
        bar.appendChild(input);
        bar.appendChild(send);
        main.appendChild(head);
        main.appendChild(thread);
        main.appendChild(bar);

        root.appendChild(side);
        root.appendChild(main);

        function scrollDown() {
            try { thread.scrollTop = thread.scrollHeight; } catch (e) { /* shim-safe */ }
        }

        /* one content node per conversation; the group one fills live via replay */
        var contents = {};
        var convs = [
            {
                id: 'group', name: 'Notch — feature tour', icon: '🎧',
                grad: 'linear-gradient(135deg,#0a84ff,#5e5ce6)', time: '9:44 AM',
                preview: 'pinned it open 🙌'
            },
            { id: 'mixer', who: 'mixer', time: '9:43 AM', preview: MSG_PEOPLE.mixer.quotes[0] },
            { id: 'shelf', who: 'shelf', time: '9:42 AM', preview: MSG_PEOPLE.shelf.quotes[0] },
            { id: 'faceid', who: 'faceid', time: '9:41 AM', preview: MSG_PEOPLE.faceid.quotes[0] }
        ];

        /* the 1:1 threads are short: the subsystem's line(s), rendered instantly */
        ['mixer', 'shelf', 'faceid'].forEach(function (who, idx) {
            var c = el('div', 'tb-msg-conv-thread');
            var st = { lastWho: null, lastKind: null };
            msgAppend(c, { kind: 'divider', text: 'Today 9:4' + (idx + 1) + ' AM' }, st);
            MSG_PEOPLE[who].quotes.forEach(function (q, i) {
                msgAppend(c, { kind: 'in', who: who, quote: i }, st);
            });
            contents[who] = c;
        });
        contents.group = el('div', 'tb-msg-conv-thread');

        var rows = [];
        var active = 'group';

        function setActive(id) {
            active = id;
            rows.forEach(function (r) {
                r.row.classList.toggle('tb-msg-conv-sel', r.id === id);
            });
            var conv = null;
            for (var i = 0; i < convs.length; i++) {
                if (convs[i].id === id) { conv = convs[i]; break; }
            }
            headName.textContent = conv ? (conv.name || MSG_PEOPLE[conv.who].name) : '';
            clearKids(thread);
            thread.appendChild(contents[id]);
            scrollDown();
        }

        convs.forEach(function (conv) {
            var name = conv.name || MSG_PEOPLE[conv.who].name;
            var grad = conv.grad || MSG_PEOPLE[conv.who].grad;
            var row = el('div', 'tb-msg-conv');
            var avatar = el('div', 'tb-msg-avatar');
            avatar.style.background = grad;
            avatar.textContent = conv.icon || name.charAt(0);
            var meta = el('div', 'tb-msg-conv-meta');
            var top = el('div', 'tb-msg-conv-top');
            var nameEl = el('span', 'tb-msg-conv-name');
            nameEl.textContent = name;
            var timeEl = el('span', 'tb-msg-conv-time');
            timeEl.textContent = conv.time;
            top.appendChild(nameEl);
            top.appendChild(timeEl);
            var prev = el('div', 'tb-msg-conv-prev');
            prev.textContent = conv.preview;
            meta.appendChild(top);
            meta.appendChild(prev);
            row.appendChild(avatar);
            row.appendChild(meta);
            row.addEventListener('click', function () { setActive(conv.id); });
            convList.appendChild(row);
            rows.push({ id: conv.id, row: row });
        });

        /* live replay: typing indicator ~420ms -> bubble slides in; next ~300ms.
           Guards on root.isConnected so a closed window never throws. */
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

        /* the input works: your message + a rotating canned reply ~1.2s later */
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
                    msgAppend(contents.group, {
                        kind: 'in', who: 'notch',
                        text: MSG_REPLIES[replyIdx++ % MSG_REPLIES.length]
                    }, st);
                    scrollDown();
                }, 500);
            }, 700);
        }
        input.addEventListener('keydown', function (e) {
            if (e && e.key === 'Enter') sendMsg();
        });
        send.addEventListener('click', sendMsg);

        setActive('group');
        return root;
    }

    /* ---------- terminal: fake zsh with a Notch CLI ---------- */

    function renderTerminal() {
        var root = el('div', 'tb-term');

        var PROMPT = 'you@macbook ~ % ';
        var currentInput = null;

        function scrollBottom() {
            try { root.scrollTop = root.scrollHeight; } catch (e) { /* shim-safe */ }
        }

        /* output lines and prompt rows are appended straight to root, in order —
           async command output (version) then always lands after its command */
        function print(text) {
            String(text).split('\n').forEach(function (line) {
                root.appendChild(el('div', 'tb-term-line', esc(line)));
            });
        }

        function spawnPrompt() {
            var row = el('div', 'tb-term-prompt');
            row.appendChild(el('span', 'tb-term-ps1', PROMPT));
            var input = el('input', 'tb-term-input');
            input.type = 'text';
            input.size = 1;
            input.setAttribute('spellcheck', 'false');
            input.setAttribute('autocomplete', 'off');
            input.setAttribute('aria-label', 'terminal input');
            var cursor = el('span', 'tb-term-cursor');
            row.appendChild(input);
            row.appendChild(cursor);
            root.appendChild(row);
            input.addEventListener('input', function () {
                input.size = Math.max(1, String(input.value).length + 1);
            });
            input.addEventListener('keydown', function (e) {
                if (e && e.key === 'Enter') exec(input, row, cursor);
            });
            currentInput = input;
            try { input.focus(); } catch (e) { /* shim-safe */ }
            scrollBottom();
        }

        function openOut(url) {
            try { window.open(url, '_blank'); } catch (e) { /* best effort */ }
        }

        function fireApp(app) {
            try {
                window.dispatchEvent(new CustomEvent('tb:open-app', { detail: { app: app } }));
            } catch (e) { /* fire-and-forget */ }
        }

        function cowsay(text) {
            text = String(text || 'moo').slice(0, 40);
            var w = text.length + 2;
            print([
                ' ' + new Array(w + 1).join('_'),
                '< ' + text + ' >',
                ' ' + new Array(w + 1).join('-'),
                '        \\   ^__^',
                '         \\  (oo)\\_______',
                '            (__)\\       )\\/\\',
                '                ||----w |',
                '                ||     ||'
            ].join('\n'));
        }

        var HELP = [
            '  help               this list',
            '  about              what is Notch',
            '  version            latest release tag',
            '  download           open GitHub releases',
            '  repo               open the repo',
            '  issues             report a bug',
            '  notch              open the notch panel',
            '  settings           open System Settings',
            '  cowsay <text>      moo',
            '  clear              wipe the screen',
            '  hello              hi'
        ].join('\n');

        function handle(line) {
            var trimmed = String(line).replace(/^\s+|\s+$/g, '');
            var sp = trimmed.indexOf(' ');
            var cmd = sp === -1 ? trimmed : trimmed.slice(0, sp);
            var rest = sp === -1 ? '' : trimmed.slice(sp + 1);
            switch (cmd) {
                case '':
                    spawnPrompt();
                    break;
                case 'help':
                    print(HELP);
                    spawnPrompt();
                    break;
                case 'about':
                    print('Notch — a native macOS utility for the space around your camera.\n' +
                        'hover to peek · click to pin · esc to dismiss.\n' +
                        'free and open source. this terminal is fake. the rest is real.');
                    spawnPrompt();
                    break;
                case 'version':
                    if (typeof cfg().getLatestTag === 'function') {
                        cfg().getLatestTag(function (tag) {
                            print('Notch ' + tag + ' (latest)');
                            spawnPrompt();
                        });
                    } else {
                        print('Notch v2.0.1 (latest)');
                        spawnPrompt();
                    }
                    break;
                case 'download':
                    openOut(link('githubReleases'));
                    print('opening releases…');
                    spawnPrompt();
                    break;
                case 'repo':
                    openOut(link('github'));
                    print('opening github…');
                    spawnPrompt();
                    break;
                case 'issues':
                    openOut(link('issues'));
                    print('opening GitHub issues…');
                    spawnPrompt();
                    break;
                case 'settings':
                    fireApp('settings');
                    print('opening System Settings…');
                    spawnPrompt();
                    break;
                case 'notch':
                case 'music':
                    fireApp('music');
                    print('🎧 opening the notch panel…');
                    spawnPrompt();
                    break;
                case 'cowsay':
                    cowsay(rest || 'moo');
                    spawnPrompt();
                    break;
                case 'clear':
                    clearKids(root);
                    spawnPrompt();
                    break;
                case 'sudo':
                    if (trimmed === 'sudo make me a sandwich') {
                        print('ok ☕');
                    } else {
                        print(trimmed.split(' ')[0] + ': permission denied (nice try)');
                    }
                    spawnPrompt();
                    break;
                case 'hello':
                    print('hi. yes. this is the terminal.');
                    spawnPrompt();
                    break;
                default:
                    print('zsh: command not found: ' + cmd);
                    spawnPrompt();
            }
            scrollBottom();
        }

        function exec(inputEl, row, cursor) {
            var line = String(inputEl.value || '');
            row.removeChild(inputEl);
            row.removeChild(cursor);
            row.appendChild(el('span', 'tb-term-typed', esc(line)));
            currentInput = null;
            handle(line);
        }

        /* click anywhere focuses the live input */
        root.addEventListener('click', function () {
            if (currentInput) {
                try { currentInput.focus(); } catch (e) { /* shim-safe */ }
            }
        });

        print('Last login: ' + new Date().toString().slice(0, 24) + ' on ttys000');
        print('Notch demo shell (macOS 14.2) — type `help`');
        spawnPrompt();
        return root;
    }

    /* ---------- facetime: dark audio-call replica (no real media) ---------- */

    function fmtClock(totalSecs) {
        var m = Math.floor(totalSecs / 60);
        var s = totalSecs % 60;
        return m + ':' + (s < 10 ? '0' : '') + s;
    }

    function renderFaceTime() {
        var root = el('div', 'tb-ft');

        /* center stage: the pre-call framing mirror. Notch opens this window
           before a meeting so you can check where you sit in frame. */
        var stage = el('div', 'tb-ft-stage');
        var icon = el('img', 'tb-ft-icon');
        icon.src = 'assets/icon.png';
        icon.alt = 'Notch';
        icon.addEventListener('error', function () { icon.style.visibility = 'hidden'; });
        stage.appendChild(icon);
        stage.appendChild(el('div', 'tb-ft-name', 'Camera mirror'));
        var stateLine = el('div', 'tb-ft-state', 'Framing preview — this page never opens your camera');
        stage.appendChild(stateLine);
        root.appendChild(stage);

        /* PiP self-view, bottom-right */
        root.appendChild(el('div', 'tb-ft-pip',
            '<div class="tb-ft-pip-emoji">🧑</div><div class="tb-ft-pip-label">You</div>'));

        /* bottom control bar: mic / video / share / messages / end */
        var bar = el('div', 'tb-ft-controls');
        var micBtn = el('button', 'tb-ft-btn', '🎤');
        micBtn.type = 'button';
        micBtn.setAttribute('aria-label', 'Mute microphone');
        var camBtn = el('button', 'tb-ft-btn', '📹');
        camBtn.type = 'button';
        camBtn.setAttribute('aria-label', 'Toggle video');
        var shareBtn = el('button', 'tb-ft-btn', '🖥️');
        shareBtn.type = 'button';
        shareBtn.setAttribute('aria-label', 'Share screen');
        var msgBtn = el('button', 'tb-ft-btn', '💬');
        msgBtn.type = 'button';
        msgBtn.setAttribute('aria-label', 'Open Messages');
        var endBtn = el('button', 'tb-ft-btn tb-ft-btn-end', '✕');
        endBtn.type = 'button';
        endBtn.setAttribute('aria-label', 'End call');
        bar.appendChild(micBtn);
        bar.appendChild(camBtn);
        bar.appendChild(shareBtn);
        bar.appendChild(msgBtn);
        bar.appendChild(endBtn);
        root.appendChild(bar);

        var ended = false;
        var secs = 0;
        var timer = null;

        micBtn.addEventListener('click', function () {
            micBtn.classList.toggle('tb-ft-btn-off');
        });
        camBtn.addEventListener('click', function () {
            camBtn.classList.toggle('tb-ft-btn-off');
        });
        msgBtn.addEventListener('click', function () {
            try {
                window.dispatchEvent(new CustomEvent('tb:open-app', { detail: { app: 'messages' } }));
            } catch (e) { /* fire-and-forget */ }
        });
        endBtn.addEventListener('click', function () {
            if (ended) return;
            ended = true;
            if (timer !== null) {
                try { clearInterval(timer); } catch (e) { /* shim-safe */ }
                timer = null;
            }
            stateLine.textContent = 'Mirror closed';
            icon.classList.add('tb-ft-icon-ended');
            var btns = [micBtn, camBtn, shareBtn, msgBtn, endBtn];
            for (var i = 0; i < btns.length; i++) btns[i].disabled = true;
        });

        /* settle into the "framing looks good" state after a beat */
        try {
            setTimeout(function () {
                if (ended) return;
                stateLine.textContent = 'Framing looks good — ready to join';
                secs = 0;
            }, 1800);
        } catch (e) { /* timers unavailable — the initial state line stays */ }

        return root;
    }

    /* ---------- apps: macOS Applications window (launcher grid) ---------- */

    var LAUNCH_APPS = [
        { icon: 'assets/icon.png', label: 'Notch', app: 'music', cat: 'Media' },
        { icon: 'assets/icons/safari.png', label: 'Safari', app: 'safari', cat: 'Utilities' },
        { icon: 'assets/icons/messages.png', label: 'Messages', app: 'messages', cat: 'Social' },
        { icon: 'assets/icons/facetime.png', label: 'Camera Mirror', app: 'facetime', cat: 'Media' },
        { icon: 'assets/icons/terminal.png', label: 'Terminal', app: 'terminal', cat: 'Utilities' },
        { icon: 'assets/icons/settings.png', label: 'System Settings', app: 'settings', cat: 'Utilities' },
        { icon: 'assets/icons/finder.png', label: 'Finder', app: 'about', cat: 'Utilities' },
        { icon: 'assets/icons/github.png', label: 'GitHub', app: 'safari', cat: 'Developer' },
        { icon: 'assets/icons/app-store.png', label: 'Releases & Install', app: 'releases', cat: 'Developer' },
        { icon: 'assets/icons/spotify.png', label: 'Spotify', href: 'https://open.spotify.com', cat: 'Media' }
    ];

    var LAUNCH_CATS = ['All', 'Media', 'Utilities', 'Social', 'Developer'];

    function renderApps() {
        var root = el('div', 'tb-launch');

        /* toolbar: title + category filter pills */
        var toolbar = el('div', 'tb-launch-toolbar');
        toolbar.appendChild(el('div', 'tb-launch-title', 'Applications'));
        var pills = el('div', 'tb-launch-pills');
        toolbar.appendChild(pills);
        root.appendChild(toolbar);

        var grid = el('div', 'tb-launch-grid');
        root.appendChild(grid);

        var active = 'All';
        var pillEls = [];

        function openEntry(entry) {
            if (entry.href) {
                try { window.open(entry.href, '_blank'); } catch (e) { /* best effort */ }
                return;
            }
            try {
                window.dispatchEvent(new CustomEvent('tb:open-app', { detail: { app: entry.app } }));
            } catch (e) { /* fire-and-forget */ }
        }

        function renderGrid() {
            clearKids(grid);
            LAUNCH_APPS.forEach(function (entry) {
                if (active !== 'All' && entry.cat !== active) return;
                var cell = el('button', 'tb-launch-cell');
                cell.type = 'button';
                var img = el('img', 'tb-launch-icon');
                img.src = entry.icon;
                img.alt = entry.label;
                img.addEventListener('error', function () { img.style.visibility = 'hidden'; });
                cell.appendChild(img);
                cell.appendChild(el('span', 'tb-launch-label', esc(entry.label)));
                cell.addEventListener('click', function () { openEntry(entry); });
                grid.appendChild(cell);
            });
        }

        LAUNCH_CATS.forEach(function (cat) {
            var pill = el('button', 'tb-launch-pill' + (cat === active ? ' tb-launch-pill-active' : ''), esc(cat));
            pill.type = 'button';
            pill.addEventListener('click', function () {
                active = cat;
                pillEls.forEach(function (p) {
                    p.el.classList.toggle('tb-launch-pill-active', p.cat === active);
                });
                renderGrid();
            });
            pillEls.push({ cat: cat, el: pill });
            pills.appendChild(pill);
        });

        renderGrid();
        return root;
    }

    /* ---------- public API ---------- */

    window.TBApps = {
        render: function (appId, opts) {
            try {
                switch (appId) {
                    case 'releases': return renderReleases();
                    case 'safari': return renderSafari();
                    case 'download': return renderDownload();
                    case 'about': return renderAbout();
                    case 'folder': return renderFolder(opts);
                    case 'viewer': return renderViewer(opts);
                    case 'messages': return renderMessages();
                    case 'terminal': return renderTerminal();
                    case 'facetime': return renderFaceTime();
                    case 'apps': return renderApps();
                    case 'settings': return (typeof window.TBSettingsUI === 'function') ? window.TBSettingsUI(opts) : el('div', 'tb-app-unknown', 'Settings failed to load');
                    default: break;
                }
            } catch (e) {
                /* degrade silently — never throw into the window manager */
            }
            return el('div', 'tb-app-unknown', 'Unknown app');
        }
    };
})();
