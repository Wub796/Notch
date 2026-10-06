/* js/config.js — single source of truth. Owned by the MANAGER. Loaded FIRST.
   Every module reads window.TB_CONFIG; nobody else defines it. */
window.TB_CONFIG = {
    siteName: 'Notch',
    appName: 'Notch',

    /* Wallpaper rotation (local Unsplash photos). `wallpaper` is the first
       frame / legacy fallback; menubar.js crossfades through the list every
       wallpaperInterval ms with a wallpaperFade ms ease. */
    wallpaper: 'assets/wallpapers/luca-bravo-ii5JY_46xH0-unsplash.jpg',
    /* Licensed under the Unsplash License (free to use, attribution
       appreciated). The menubar shows a credit chip for the current photo and
       links out to its Unsplash page. */
    wallpapers: [
        { src: 'assets/wallpapers/luca-bravo-ii5JY_46xH0-unsplash.jpg', title: 'Luca Bravo', artist: 'Unsplash', year: '', link: 'https://unsplash.com/photos/ii5JY_46xH0' },
        { src: 'assets/wallpapers/anders-jilden-cYrMQA7a3Wc-unsplash.jpg', title: 'Anders Jildén', artist: 'Unsplash', year: '', link: 'https://unsplash.com/photos/cYrMQA7a3Wc' },
        { src: 'assets/wallpapers/garrett-parker-DlkF4-dbCOU-unsplash.jpg', title: 'Garrett Parker', artist: 'Unsplash', year: '', link: 'https://unsplash.com/photos/DlkF4-dbCOU' },
        { src: 'assets/wallpapers/ian-dooley-DuBNA1QMpPA-unsplash.jpg', title: 'Ian Dooley', artist: 'Unsplash', year: '', link: 'https://unsplash.com/photos/DuBNA1QMpPA' },
        { src: 'assets/wallpapers/buzz-andersen-E4944K_4SvI-unsplash.jpg', title: 'Buzz Andersen', artist: 'Unsplash', year: '', link: 'https://unsplash.com/photos/E4944K_4SvI' },
    ],
    wallpaperInterval: 15000,
    wallpaperFade: 1400,

    links: {
        github: 'https://github.com/Wub796/Notch',
        githubReleases: 'https://github.com/Wub796/Notch/releases',
        issues: 'https://github.com/Wub796/Notch/issues',
        readme: 'https://github.com/Wub796/Notch#readme',
        thirdParty: 'https://github.com/Wub796/Notch/blob/main/THIRD-PARTY-NOTICES.md',
        tagsApi: 'https://api.github.com/repos/Wub796/Notch/tags',
    },

    /* Live latest-tag lookup for the version labels (promo card, download card,
       Releases window). Cached in localStorage for 1h (GitHub allows 60
       req/hr/IP); silently falls back to the last known tag on any failure. */
    getLatestTag: function (cb) {
        var FALLBACK = 'v2.0.1';
        var KEY = 'tb-latest-tag';
        var TTL = 3600 * 1000;
        function done(tag) { if (typeof cb === 'function') cb(tag); }
        try {
            var cached = JSON.parse(localStorage.getItem(KEY) || 'null');
            if (cached && cached.tag && (Date.now() - cached.ts) < TTL) {
                done(cached.tag);
                return;
            }
        } catch (e) { /* no storage / corrupt cache → fetch */ }
        if (typeof fetch !== 'function') { done(FALLBACK); return; }
        var ctl = (typeof AbortController === 'function') ? new AbortController() : null;
        var timer = ctl ? setTimeout(function () { ctl.abort(); }, 6000) : 0;
        fetch(window.TB_CONFIG.links.tagsApi, ctl ? { signal: ctl.signal } : {})
            .then(function (r) { if (!r.ok) throw new Error('http ' + r.status); return r.json(); })
            .then(function (tags) {
                clearTimeout(timer);
                var tag = (tags && tags[0] && typeof tags[0].name === 'string' && tags[0].name) || FALLBACK;
                try { localStorage.setItem(KEY, JSON.stringify({ tag: tag, ts: Date.now() })); } catch (e) { }
                done(tag);
            })
            .catch(function () { clearTimeout(timer); done(FALLBACK); });
    },

    /* Notch now-playing demo. Empty audioUrl → iTunes Search 30s preview
       (Spotify's Web API no longer ships preview_url). The real app drives
       Apple Music / Spotify through the MediaRemote adapter. */
    music: {
        id: 'demo-track',
        title: 'Island in the Sun',
        artist: 'Weezer',
        artworkUrl: '',
        audioUrl: '',
    },
};

/* User-changeable settings — the System Settings app writes these via its
   commit() path (mutate + persist + dispatch 'tb:settings'); consumers read
   here and listen for the event. Defaults merge under any saved state. */
window.TB_SETTINGS = Object.assign({
    wallpaperInterval: 15000,
    wallpaperSrc: 'assets/wallpapers/luca-bravo-ii5JY_46xH0-unsplash.jpg',
    dockMagnification: true,
    dockMaxScale: 1.6,
    volume: 0.8,
    brightness: 100,
}, (function () {
    try { return JSON.parse(localStorage.getItem('tb-settings') || '{}'); }
    catch (e) { return {}; }
})());
