/* Notch web demo: native silhouette and hover timings from NotchSizing/NotchSettings. */
(function () {
    'use strict';
    var icons = {
        home: '<path d="m3 10 9-7 9 7v10h-6v-7H9v7H3z"/>',
        media: '<circle cx="12" cy="12" r="9"/><path d="m10 8 6 4-6 4z"/>',
        shelf: '<path d="M4 5h16l2 10v5H2v-5zM2 15h6l2 3h4l2-3h6"/>',
        notes: '<path d="M6 3h9l4 4v14H6zM9 10h7M9 14h7M9 18h4"/>',
        timer: '<circle cx="12" cy="14" r="8"/><path d="M12 10v5l3 2M9 2h6M12 2v4"/>',
        pin: '<path d="m9 3 6 0-1 6 4 4H6l4-4zM12 13v8"/>',
        play: '<path d="m8 5 11 7-11 7z"/>',
        pause: '<path d="M8 5v14M16 5v14"/>',
        previous: '<path d="M6 5v14m13-14L9 12l10 7z"/>',
        next: '<path d="M18 5v14M5 5l10 7-10 7z"/>',
        close: '<path d="m6 6 12 12M18 6 6 18"/>'
    };
    function svg(name) {
        return '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + icons[name] + '</svg>';
    }
    function ready(fn) {
        if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', fn);
        else fn();
    }
    ready(function () {
        var mount = document.getElementById('notch-root');
        if (!mount) return;
        var cfg = window.TB_CONFIG || {}, music = cfg.music || {};
        var track = { id: music.id || 'demo-track', name: music.title || 'Notch', artist: music.artist || 'Now playing demo', artworkUrl: music.artworkUrl || '', audioUrl: music.audioUrl || '' };
        var expanded = false, pinned = false, hovering = false, dismissed = false, keyboardFocus = false;
        var openTimer, closeTimer, audio = null, playing = false;
        var volume = (window.TB_SETTINGS || {}).volume;
        if (typeof volume !== 'number') volume = 0.8;
        mount.innerHTML = '<section class="tb-notch" aria-label="Notch demo">' +
            '<button class="tb-notch-trigger" type="button" aria-label="Open Notch; click to pin" aria-expanded="false" aria-controls="tb-notch-panel"><span class="tb-collapsed-art" aria-hidden="true"></span><span class="tb-camera-space" aria-hidden="true"></span><span class="tb-notch-eq" aria-hidden="true"><i></i><i></i><i></i><i></i><i></i></span></button>' +
            '<div class="tb-notch-panel" id="tb-notch-panel" inert><header class="tb-notch-header"><nav aria-label="Notch views">' +
            ['home', 'media', 'shelf', 'notes', 'timer'].map(function (name) { return '<button type="button" data-notch-view="' + name + '" aria-label="' + name.charAt(0).toUpperCase() + name.slice(1) + '" title="' + name.charAt(0).toUpperCase() + name.slice(1) + '" aria-pressed="' + (name === 'home') + '">' + svg(name) + '</button>'; }).join('') +
            '</nav><span class="tb-header-camera" aria-hidden="true"></span><div class="tb-notch-utilities"><span class="tb-demo-label">WEB DEMO</span><button type="button" class="tb-notch-pin" aria-label="Pin Notch open" aria-pressed="false">' + svg('pin') + '</button><button type="button" class="tb-notch-close" aria-label="Close Notch">' + svg('close') + '</button></div></header>' +
            '<div class="tb-notch-dashboard"><section class="tb-notch-music" aria-label="Now playing"><div class="tb-track-art"></div><div class="tb-track-copy"><strong class="tb-track-title"></strong><span class="tb-track-artist"></span><div class="tb-track-controls"><button type="button" disabled aria-label="Previous track">' + svg('previous') + '</button><button type="button" class="tb-track-play" aria-label="Play preview" disabled>' + svg('play') + '</button><button type="button" disabled aria-label="Next track">' + svg('next') + '</button></div></div></section>' +
            '<section class="tb-notch-weather" aria-label="Weather feature preview"><span class="tb-card-eyebrow">WEATHER</span><div class="tb-weather-preview"><svg viewBox="0 0 48 48" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><circle cx="24" cy="24" r="9"/><path d="M24 3v6m0 30v6M3 24h6m30 0h6M9 9l4 4m22 22 4 4M9 39l4-4m22-22 4-4"/></svg><strong>At a glance</strong></div><span class="tb-card-caption">Your local forecast in the app</span></section>' +
            '<section class="tb-notch-calendar" aria-label="Calendar"><span class="tb-card-eyebrow tb-calendar-month"></span><div class="tb-calendar-week"></div><span class="tb-card-caption">Your agenda, one hover away</span></section></div>' +
            '<div class="tb-notch-media" hidden><div class="tb-track-progress-row"><span class="tb-track-current">0:00</span><input class="tb-track-progress" type="range" min="0" max="100" value="0" aria-label="Preview progress" disabled><span class="tb-track-duration">--:--</span></div><p class="tb-preview-status" role="status">Loading audio preview…</p></div>' +
            '<section class="tb-notch-shelf tb-notch-tool" hidden aria-label="File Shelf"><div class="tb-tool-heading"><strong>File Shelf</strong><button type="button" class="tb-shelf-clear">Clear all</button></div><label class="tb-shelf-drop">Drop files here or choose files<input type="file" class="tb-shelf-input" multiple aria-label="Add files to Shelf"></label><div class="tb-shelf-items"></div><p class="tb-tool-status tb-shelf-status" role="status">Session only · files stay in this browser · up to 20 files / 50 MB</p></section>' +
            '<section class="tb-notch-notes tb-notch-tool" hidden aria-label="Quick Notes"><div class="tb-tool-heading"><strong>Quick Notes</strong><button type="button" class="tb-notes-export">Export .txt</button></div><textarea class="tb-notes-input" aria-label="Quick note" maxlength="20000" placeholder="A thought, a reminder, your next great idea…"></textarea><p class="tb-tool-status tb-notes-status" role="status">Saved on this browser, never uploaded.</p></section>' +
            '<section class="tb-notch-timer tb-notch-tool" hidden aria-label="Focus Timer"><div class="tb-tool-heading"><strong>Focus Timer</strong><span class="tb-timer-status" role="status">Ready when you are</span></div><div class="tb-timer-main"><output class="tb-timer-readout" aria-label="Time remaining">05:00</output><div class="tb-timer-presets"><button type="button" data-timer-seconds="300">5 min</button><button type="button" data-timer-seconds="900">15 min</button><button type="button" data-timer-seconds="1500">25 min</button><label>Minutes <input class="tb-timer-minutes" type="number" min="1" max="180" value="5" aria-label="Timer minutes"></label></div></div><div class="tb-timer-actions"><button type="button" class="tb-timer-start">Start timer</button><button type="button" class="tb-timer-reset">Reset</button></div></section>' +
            '</div></section>';
        var notch = mount.querySelector('.tb-notch'), trigger = mount.querySelector('.tb-notch-trigger');
        var panel = mount.querySelector('.tb-notch-panel'), pin = mount.querySelector('.tb-notch-pin');
        var progress = mount.querySelector('.tb-track-progress'), play = mount.querySelector('.tb-track-play');
        var status = mount.querySelector('.tb-preview-status');
        function setting(key) { return (window.TB_SETTINGS || {})[key] !== false; }
        function clearTimers() { clearTimeout(openTimer); clearTimeout(closeTimer); }
        function paintState() {
            notch.classList.toggle('expanded', expanded);
            notch.classList.toggle('is-peeking', hovering && !dismissed && setting('hoverPeek'));
            notch.classList.toggle('is-pinned', pinned);
            trigger.setAttribute('aria-expanded', String(expanded));
            trigger.setAttribute('aria-label', expanded ? 'Notch is open' : 'Open Notch; click to pin');
            pin.setAttribute('aria-pressed', String(pinned));
            pin.setAttribute('aria-label', pinned ? 'Unpin Notch' : 'Pin Notch open');
            panel.inert = !expanded;
            trigger.tabIndex = expanded ? -1 : 0;
        }
        function open(shouldPin) {
            clearTimers(); expanded = true; pinned = Boolean(shouldPin); dismissed = false; paintState();
        }
        function close(restoreFocus) {
            clearTimers(); expanded = false; pinned = false; dismissed = hovering;
            paintState();
            if (restoreFocus) trigger.focus();
        }
        function scheduleClose() {
            clearTimeout(openTimer); clearTimeout(closeTimer);
            if (!pinned && !(notch.contains(document.activeElement) && (keyboardFocus || document.activeElement.matches('input, textarea')))) closeTimer = setTimeout(function () { close(false); }, 200);
        }
        notch.addEventListener('pointerenter', function (e) {
            if (e.pointerType === 'touch') return;
            hovering = true; dismissed = false; clearTimers(); paintState();
            if (setting('hoverPeek') && !expanded) openTimer = setTimeout(function () { open(false); }, 220);
        });
        notch.addEventListener('pointerleave', function (e) {
            if (e.pointerType === 'touch') return;
            hovering = false; dismissed = false; paintState(); scheduleClose();
        });
        notch.addEventListener('focusin', function () { clearTimeout(closeTimer); });
        notch.addEventListener('focusout', function () {
            setTimeout(function () { if (!hovering) scheduleClose(); }, 0);
        });
        trigger.addEventListener('click', function () {
            open(setting('pinOnClick')); pin.focus({ preventScroll: true });
        });
        pin.addEventListener('click', function () { pinned = !pinned; paintState(); if (!pinned && !hovering) scheduleClose(); });
        mount.querySelector('.tb-notch-close').addEventListener('click', function () { close(true); });
        document.addEventListener('pointerdown', function (e) { keyboardFocus = false; if (expanded && !mount.contains(e.target)) close(false); });
        document.addEventListener('keydown', function (e) {
            if (e.key === 'Tab') keyboardFocus = true;
            if (e.key === 'Escape' && expanded) { e.preventDefault(); e.stopImmediatePropagation(); close(notch.contains(document.activeElement)); }
        });
        function selectView(view) {
            if (['home', 'media', 'shelf', 'notes', 'timer'].indexOf(view) === -1) return;
            notch.setAttribute('data-view', view);
            mount.querySelector('.tb-notch-dashboard').hidden = view !== 'home' && view !== 'media';
            mount.querySelector('.tb-notch-weather').hidden = view !== 'home';
            mount.querySelector('.tb-notch-calendar').hidden = view !== 'home';
            ['media', 'shelf', 'notes', 'timer'].forEach(function (name) { mount.querySelector('.tb-notch-' + name).hidden = view !== name; });
            Array.prototype.forEach.call(mount.querySelectorAll('[data-notch-view]'), function (item) { item.setAttribute('aria-pressed', String(item.getAttribute('data-notch-view') === view)); });
        }
        Array.prototype.forEach.call(mount.querySelectorAll('[data-notch-view]'), function (tab) {
            tab.addEventListener('click', function () { selectView(tab.getAttribute('data-notch-view')); });
        });
        window.addEventListener('tb:notch-view', function (e) { selectView((e.detail || {}).view); open(true); pin.focus(); });
        /* Browser-local tools: no upload endpoint or native permissions. */
        var noteInput = mount.querySelector('.tb-notes-input'), noteStatus = mount.querySelector('.tb-notes-status');
        try { noteInput.value = (localStorage.getItem('notch-quick-note') || '').slice(0, 20000); }
        catch (e) { noteStatus.textContent = 'Storage unavailable — export your note before leaving.'; }
        noteInput.addEventListener('input', function () {
            try { localStorage.setItem('notch-quick-note', noteInput.value); noteStatus.textContent = 'Saved on this browser · ' + noteInput.value.length + ' / 20,000 characters'; }
            catch (e) { noteStatus.textContent = 'Could not save — export your note before leaving.'; }
        });
        function downloadBlob(blob, name) {
            var url = URL.createObjectURL(blob), link = document.createElement('a');
            link.href = url; link.download = name; document.body.appendChild(link); link.click(); link.remove();
            setTimeout(function () { URL.revokeObjectURL(url); }, 1000);
        }
        mount.querySelector('.tb-notes-export').addEventListener('click', function () { downloadBlob(new Blob([noteInput.value], { type: 'text/plain;charset=utf-8' }), 'Notch-note.txt'); });
        var files = [], shelfList = mount.querySelector('.tb-shelf-items'), shelfStatus = mount.querySelector('.tb-shelf-status');
        function renderShelf() {
            shelfList.textContent = '';
            files.forEach(function (file, index) {
                var row = document.createElement('div'); row.className = 'tb-shelf-file';
                var name = document.createElement('span'); name.textContent = file.name; name.title = file.name;
                var size = document.createElement('small'); size.textContent = (file.size / 1024 / 1024).toFixed(1) + ' MB';
                var save = document.createElement('button'); save.type = 'button'; save.textContent = 'Save'; save.setAttribute('aria-label', 'Save ' + file.name);
                save.addEventListener('click', function () { downloadBlob(file, file.name); });
                var remove = document.createElement('button'); remove.type = 'button'; remove.textContent = '×'; remove.setAttribute('aria-label', 'Remove ' + file.name);
                remove.addEventListener('click', function () { files.splice(index, 1); renderShelf(); shelfStatus.textContent = files.length + ' files · session only'; });
                row.appendChild(name); row.appendChild(size); row.appendChild(save); row.appendChild(remove); shelfList.appendChild(row);
            });
            mount.querySelector('.tb-shelf-clear').disabled = !files.length;
        }
        function addFiles(incoming) {
            var rejected = 0, total = files.reduce(function (sum, f) { return sum + f.size; }, 0);
            Array.prototype.forEach.call(incoming, function (file) {
                if (files.length >= 20 || total + file.size > 50 * 1024 * 1024) { rejected++; return; }
                files.push(file); total += file.size;
            });
            renderShelf(); shelfStatus.textContent = files.length + ' files · ' + (total / 1024 / 1024).toFixed(1) + ' MB · session only' + (rejected ? ' · ' + rejected + ' skipped (20 files / 50 MB limit)' : '');
        }
        mount.querySelector('.tb-shelf-input').addEventListener('change', function (e) { addFiles(e.target.files); e.target.value = ''; });
        var dropZone = mount.querySelector('.tb-shelf-drop');
        dropZone.addEventListener('dragover', function (e) { e.preventDefault(); dropZone.classList.add('is-dragover'); });
        dropZone.addEventListener('dragleave', function () { dropZone.classList.remove('is-dragover'); });
        dropZone.addEventListener('drop', function (e) { e.preventDefault(); dropZone.classList.remove('is-dragover'); addFiles(e.dataTransfer.files); });
        notch.addEventListener('dragover', function (e) {
            if (Array.prototype.indexOf.call(e.dataTransfer.types, 'Files') === -1) return;
            e.preventDefault(); selectView('shelf'); open(true);
        });
        notch.addEventListener('drop', function (e) {
            if (!e.dataTransfer.files.length || dropZone.contains(e.target)) return;
            e.preventDefault(); selectView('shelf'); open(true); addFiles(e.dataTransfer.files);
        });
        mount.querySelector('.tb-shelf-clear').addEventListener('click', function () { files = []; renderShelf(); shelfStatus.textContent = 'Shelf cleared · files were never uploaded.'; });
        renderShelf();
        var timerMinutes = mount.querySelector('.tb-timer-minutes'), timerReadout = mount.querySelector('.tb-timer-readout');
        var timerStart = mount.querySelector('.tb-timer-start'), timerStatus = mount.querySelector('.tb-timer-status');
        var remaining = 300000, deadline = 0, timerTick = null;
        function renderTimer() {
            var seconds = Math.max(0, Math.ceil(remaining / 1000));
            timerReadout.textContent = String(Math.floor(seconds / 60)).padStart(2, '0') + ':' + String(seconds % 60).padStart(2, '0');
            timerStart.textContent = deadline ? 'Pause timer' : 'Start timer';
            notch.classList.toggle('timer-running', Boolean(deadline));
        }
        function tickTimer() {
            if (!deadline) return;
            remaining = Math.max(0, deadline - Date.now());
            if (!remaining) {
                deadline = 0; clearInterval(timerTick); timerStatus.textContent = 'Time’s up. Take a breath.';
                selectView('timer'); open(true);
                window.dispatchEvent(new CustomEvent('tb:notification', { detail: { title: 'Focus complete', message: 'Your Notch timer has finished.' } }));
            }
            renderTimer();
        }
        function resetTimer(seconds) {
            clearInterval(timerTick); deadline = 0; remaining = seconds * 1000;
            timerMinutes.value = seconds / 60; timerStatus.textContent = 'Ready when you are'; renderTimer();
        }
        function validatedMinutes() { return Math.max(1, Math.min(180, Math.round(Number(timerMinutes.value)) || 5)); }
        timerStart.addEventListener('click', function () {
            if (deadline) { remaining = Math.max(0, deadline - Date.now()); deadline = 0; clearInterval(timerTick); timerStatus.textContent = 'Paused'; }
            else { if (!remaining) remaining = validatedMinutes() * 60000; deadline = Date.now() + remaining; timerTick = setInterval(tickTimer, 250); timerStatus.textContent = 'A little space to focus'; }
            renderTimer();
        });
        timerMinutes.addEventListener('change', function () {
            var minutes = Math.round(Number(timerMinutes.value));
            if (!Number.isFinite(minutes) || minutes < 1 || minutes > 180) { timerMinutes.value = Math.max(1, Math.min(180, minutes || 5)); }
            resetTimer(Number(timerMinutes.value) * 60);
        });
        mount.querySelector('.tb-timer-reset').addEventListener('click', function () { resetTimer(validatedMinutes() * 60); });
        mount.querySelectorAll('[data-timer-seconds]').forEach(function (button) { button.addEventListener('click', function () { resetTimer(Number(button.getAttribute('data-timer-seconds'))); }); });
        document.addEventListener('visibilitychange', tickTimer);
        renderTimer();
        window.addEventListener('tb:settings', function () {
            if (audio) { var v = (window.TB_SETTINGS || {}).volume; if (typeof v === 'number') setVolume(v); }
            notch.classList.toggle('hide-meter', !setting('closedNotchMeter'));
            if (!setting('hoverPeek')) { clearTimeout(openTimer); if (!pinned && !notch.contains(document.activeElement)) close(false); }
            paintState();
        });
        function paintTrack() {
            mount.querySelector('.tb-track-title').textContent = track.name;
            mount.querySelector('.tb-track-artist').textContent = track.artist;
            Array.prototype.forEach.call(mount.querySelectorAll('.tb-track-art, .tb-collapsed-art'), function (el) {
                el.textContent = '';
                if (track.artworkUrl) { var img = document.createElement('img'); img.src = track.artworkUrl; img.alt = ''; el.appendChild(img); }
                else { var fallback = document.createElement('img'); fallback.src = 'assets/icon.png'; fallback.alt = ''; el.appendChild(fallback); }
            });
        }
        function formatTime(s) { s = Math.max(0, Math.floor(s || 0)); return Math.floor(s / 60) + ':' + String(s % 60).padStart(2, '0'); }
        function renderProgress() {
            var duration = audio && isFinite(audio.duration) ? audio.duration : 0;
            progress.value = duration ? audio.currentTime / duration * 100 : 0;
            progress.style.setProperty('--tb-progress', progress.value + '%');
            mount.querySelector('.tb-track-current').textContent = formatTime(audio ? audio.currentTime : 0);
            mount.querySelector('.tb-track-duration').textContent = duration ? formatTime(duration) : '--:--';
        }
        function dispatchState() {
            playing = Boolean(audio && !audio.paused && !audio.ended);
            notch.classList.toggle('is-playing', playing);
            play.innerHTML = svg(playing ? 'pause' : 'play');
            play.setAttribute('aria-label', playing ? 'Pause preview' : 'Play preview');
            window.dispatchEvent(new CustomEvent('tb:music-state', { detail: { playing: playing, stationId: track.id } }));
        }
        function startPlayback() { if (audio) audio.play().catch(function () { status.textContent = 'Preview unavailable. Please try again.'; }); }
        function bindAudio(url) {
            audio = new Audio(url); audio.preload = 'metadata'; audio.volume = volume;
            ['play', 'pause', 'ended'].forEach(function (event) { audio.addEventListener(event, dispatchState); });
            ['timeupdate', 'loadedmetadata'].forEach(function (event) { audio.addEventListener(event, renderProgress); });
            audio.addEventListener('error', function () { status.textContent = 'Audio preview is unavailable.'; play.disabled = true; progress.disabled = true; });
            play.disabled = false; progress.disabled = false; status.textContent = '30-second audio preview · not your Mac’s playback';
        }
        function setVolume(v) { volume = Math.min(1, Math.max(0, Number(v) || 0)); if (audio) audio.volume = volume; }
        play.addEventListener('click', function () { if (audio) { if (audio.paused) startPlayback(); else audio.pause(); } });
        progress.addEventListener('input', function () { if (audio && isFinite(audio.duration)) audio.currentTime = audio.duration * Number(progress.value) / 100; });
        paintTrack();
        if (track.audioUrl) bindAudio(track.audioUrl);
        else {
            var controller = new AbortController(), timeout = setTimeout(function () { controller.abort(); }, 6000);
            fetch('https://itunes.apple.com/search?term=' + encodeURIComponent(track.artist + ' ' + track.name) + '&media=music&entity=song&limit=1', { signal: controller.signal })
                .then(function (r) { if (!r.ok) throw new Error('Preview unavailable'); return r.json(); })
                .then(function (data) {
                    var hit = data.results && data.results[0];
                    if (!hit || !hit.previewUrl) throw new Error('No preview');
                    track.name = hit.trackName || track.name; track.artist = hit.artistName || track.artist;
                    if (!track.artworkUrl) track.artworkUrl = hit.artworkUrl100 || '';
                    paintTrack(); bindAudio(hit.previewUrl);
                }).catch(function () { status.textContent = 'Audio preview is unavailable. Explore the dashboard instead.'; })
                .finally(function () { clearTimeout(timeout); });
        }
        var now = new Date(), week = mount.querySelector('.tb-calendar-week');
        mount.querySelector('.tb-calendar-month').textContent = now.toLocaleDateString(undefined, { month: 'long', year: 'numeric' });
        for (var i = 0; i < 7; i++) {
            var date = new Date(now.getFullYear(), now.getMonth(), now.getDate() - now.getDay() + i);
            var day = document.createElement('span'); day.className = date.toDateString() === now.toDateString() ? 'is-today' : '';
            var label = document.createElement('small'); label.textContent = date.toLocaleDateString(undefined, { weekday: 'narrow' });
            var number = document.createElement('b'); number.textContent = date.getDate(); day.appendChild(label); day.appendChild(number); week.appendChild(day);
        }
        /* Port of NotchShape's continuous, outward top corners. Recalculate while the CSS dimensions animate. */
        function shape(width, height) {
            var top = expanded ? 26 : 16, bottom = expanded ? 30 : 18;
            var commands = [], corners = [
                [top, 0, 0, 1, -1, 0, top, height / 2, top],
                [top, height, 1, 0, 0, -1, bottom, width / 2 - top, height / 2],
                [width - top, height, 0, -1, -1, 0, bottom, height / 2, width / 2 - top],
                [width - top, 0, 1, 0, 0, 1, top, top, height / 2]
            ];
            corners.forEach(function (c, index) {
                var r = Math.min(c[6], c[7], c[8]), ru = Math.min(1.5286649466 * r, c[7]), rv = Math.min(1.5286649466 * r, c[8]);
                function point(u, v) { return (c[0] + c[2] * u + c[4] * v).toFixed(3) + ' ' + (c[1] + c[3] * u + c[5] * v).toFixed(3); }
                function control(flat, slope, reach) { var limit = r ? reach / r : 0; return (limit <= 1 ? flat * limit : flat + slope * (limit - 1)) * r; }
                commands.push((index ? 'L' : 'M') + point(0, rv));
                commands.push('C' + point(0, control(.96, .2430462, rv)) + ' ' + point(0, control(.82, .0915639, rv)) + ' ' + point(.0749114 * r, .6314939 * r));
                commands.push('C' + point(.16906 * r, .372824 * r) + ' ' + point(.372824 * r, .16906 * r) + ' ' + point(.6314939 * r, .0749114 * r));
                commands.push('C' + point(control(.82, .0915639, ru), 0) + ' ' + point(control(.96, .2430462, ru), 0) + ' ' + point(ru, 0));
            });
            return commands.join(' ') + ' Z';
        }
        new ResizeObserver(function () { notch.style.clipPath = 'path("' + shape(notch.offsetWidth, notch.offsetHeight) + '")'; }).observe(notch);
        window.addEventListener('tb:open-app', function (e) { if (e.detail && e.detail.app === 'music') { open(true); pin.focus(); } });
        window.TBMusic = { play: startPlayback, pause: function () { if (audio) audio.pause(); }, toggle: function () { if (audio) { if (audio.paused) startPlayback(); else audio.pause(); } }, next: function () {}, prev: function () {}, setVolume: setVolume, state: function () { return { playing: playing, station: track, volume: volume }; } };
        notch.classList.toggle('hide-meter', !setting('closedNotchMeter')); paintState(); dispatchState();
    });
}());
