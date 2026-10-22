import AppKit

/// A browser the notch can script.
///
/// `isChromium` is the one thing that differs between them in AppleScript:
/// Chromium exposes a tab's JavaScript through `execute javascript` on the tab,
/// Safari and the WebKit browsers through `do JavaScript … in tab`.
struct BrowserTarget {
    let name: String
    let bundleID: String
    let isChromium: Bool
}

/// Asking a browser what it is playing, and telling it to stop or start.
///
/// The scan is media-shaped rather than site-shaped. It asks every http(s) tab
/// what it is playing and reports the page's own metadata: `mediaSession` where
/// the site publishes it, the video's poster frame, its duration and playhead,
/// the page title and host otherwise. It used to be YouTube-shaped — only
/// YouTube tabs were asked, and every item came back labelled YouTube — so a
/// Bilibili, Vimeo or Netflix video was invisible, and the notch saw such a
/// video only while the system's own now-playing session reported it: a few
/// seconds after a seek, then back to a YouTube tab that was not even playing.
///
/// Bounded on purpose: at most `tabScanLimit` tabs per browser are asked, so a
/// browser with a hundred tabs open cannot turn a two-second poll into a wall of
/// Apple events. Tabs are visited in the order the browser lists them, which
/// puts the active window's tabs first.
///
/// Every entry point is gated on Automation consent, and a probe nobody asked
/// for — the closed notch, the background poll — passes `avoidPrompt` so it can
/// never be what raises the system's Automation dialog.
enum BrowserMediaProbe {
    /// What one page said it is playing, before it becomes the player's
    /// `Snapshot`.
    ///
    /// `artist` is empty when the page named none — the caller fills it from the
    /// video's channel where it can. `videoID` is carried for exactly that
    /// lookup, and for the artwork of a page that could not be scripted.
    struct Reading {
        let title: String
        let artist: String
        let site: String
        let duration: TimeInterval
        let position: TimeInterval
        let isPlaying: Bool
        let playbackStateKnown: Bool
        let artworkURL: URL?
        let mediaURL: URL?
        let videoID: String?
        let browser: BrowserTarget
    }

    static let targets: [BrowserTarget] = [
        BrowserTarget(name: "Safari", bundleID: "com.apple.Safari", isChromium: false),
        BrowserTarget(name: "Google Chrome", bundleID: "com.google.Chrome", isChromium: true),
        BrowserTarget(name: "Google Chrome Canary", bundleID: "com.google.Chrome.canary", isChromium: true),
        BrowserTarget(name: "Arc", bundleID: "company.thebrowser.Browser", isChromium: true),
        BrowserTarget(name: "Brave Browser", bundleID: "com.brave.Browser", isChromium: true),
        BrowserTarget(name: "Microsoft Edge", bundleID: "com.microsoft.edgemac", isChromium: true),
        BrowserTarget(name: "Vivaldi", bundleID: "com.vivaldi.Vivaldi", isChromium: true),
        BrowserTarget(name: "Orion", bundleID: "com.kagi.kagisafari", isChromium: false),
        BrowserTarget(name: "Opera", bundleID: "com.operasoftware.Opera", isChromium: true),
        BrowserTarget(name: "Opera GX", bundleID: "com.operasoftware.OperaGX", isChromium: true),
        BrowserTarget(name: "Zen Browser", bundleID: "app.zen-browser.zen", isChromium: false),
        BrowserTarget(name: "Chromium", bundleID: "org.chromium.Chromium", isChromium: true)
    ]

    static func isBrowser(_ bundleID: String) -> Bool {
        targets.contains { $0.bundleID == bundleID }
    }

    // MARK: - Reading

    /// One reading of whatever the browsers are playing, whatever it is.
    ///
    /// A tab that is *playing* wins over one that is paused, so the item making
    /// sound is what comes back; a paused page is the answer only when nothing
    /// is making sound. Returns nil when no browser has anything to say.
    ///
    /// - Parameter avoidPrompt: whether a browser we may not script has to be
    ///   skipped.
    static func read(avoidPrompt: Bool) -> Reading? {
        var fallback: Reading?

        for browser in targets {
            guard !NSRunningApplication
                .runningApplications(withBundleIdentifier: browser.bundleID).isEmpty
            else { continue }
            // A background probe must not be what raises the Automation prompt;
            // only the interactive probe (notch open) may.
            if avoidPrompt, !IntegrationPermissions.canScript(browser.bundleID) { continue }

            let scriptSource = scanningScript(for: browser)
            var error: NSDictionary?
            guard let script = NSAppleScript(source: scriptSource) else { continue }
            let result = script.executeAndReturnError(&error)
            guard error == nil,
                  let raw = result.stringValue?
                      .trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty
            else { continue }

            // The DOM script returns JSON on its own — no "||" separator — so
            // the legacy tab-title path must only run when the reply is not
            // JSON. (An older guard demanded "||", which silently threw away
            // every Chromium reply and left "Nothing Playing" on screen while
            // YouTube played.)
            if let reading = jsonReading(raw, from: browser) {
                if reading.isPlaying { return reading }
                if fallback == nil { fallback = reading }
                continue
            }

            if fallback == nil, let reading = tabTitleReading(raw, from: browser) {
                fallback = reading
            }
        }
        return fallback
    }

    /// The DOM reply: `PLAYING||{…}` / `PAUSED||{…}`.
    private static func jsonReading(_ raw: String, from browser: BrowserTarget) -> Reading? {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawTitle = json["title"] as? String,
              !rawTitle.isEmpty
        else { return nil }

        let playing = boolValue(json["playing"])
        let mediaURL = validatedWebURL(json["sourceURL"] as? String)
        let duration = max(doubleValue(json["duration"]) ?? 0, 0)
        let videoID = mediaURL.flatMap { youtubeVideoID(from: $0.absoluteString) }

        return Reading(
            title: SourceArbitration.normalizedTitle(rawTitle),
            artist: (json["artist"] as? String) ?? "",
            site: siteLabel(for: mediaURL) ?? browser.name,
            duration: duration,
            position: max(doubleValue(json["currentTime"]) ?? 0, 0),
            isPlaying: playing ?? false,
            // A missing `playing` key is not "paused": the page answered without
            // it, so the reading has no state to report and must not be allowed
            // to assert one.
            playbackStateKnown: playing != nil,
            artworkURL: (json["artwork"] as? String).flatMap { URL(string: $0) },
            mediaURL: mediaURL,
            videoID: videoID,
            browser: browser
        )
    }

    /// The legacy tab-title path: `Title - YouTube||https://…`. Reached when the
    /// page could not be scripted, so the title is all there is.
    private static func tabTitleReading(_ raw: String, from browser: BrowserTarget) -> Reading? {
        guard raw.contains("||") else { return nil }
        let parts = raw.components(separatedBy: "||")
        guard parts.count >= 2 else { return nil }

        var title = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let mediaURL = validatedWebURL(parts[1])
        let site = siteLabel(for: mediaURL) ?? browser.name

        if title.hasSuffix(" - YouTube Music") {
            title = String(title.dropLast(" - YouTube Music".count))
        } else if title.hasSuffix(" - YouTube") {
            title = String(title.dropLast(" - YouTube".count))
        } else if title.hasSuffix(" - \(browser.name)") {
            title = String(title.dropLast(" - \(browser.name)".count))
        }

        let videoID = mediaURL.flatMap { youtubeVideoID(from: $0.absoluteString) }
        // A watch page's tab title carries no channel. The caller looks the
        // channel up from the video ID; the thumbnail is that video's.
        let artworkURL = videoID.flatMap {
            URL(string: "https://img.youtube.com/vi/\($0)/hqdefault.jpg")
        }

        return Reading(
            title: title,
            artist: "",
            site: site,
            duration: 0,
            position: 0,
            isPlaying: false,
            // The tab title says nothing about playback, so this reading must
            // not claim the video is paused — the now-playing channel answers
            // that instead, through the playback reconcile.
            playbackStateKnown: false,
            artworkURL: artworkURL,
            mediaURL: mediaURL,
            videoID: videoID,
            browser: browser
        )
    }

    /// How many tabs per browser the probe asks, at most.
    ///
    /// Each tab costs one Apple event, and the probe runs every couple of
    /// seconds while a media surface is showing. Twelve covers every tab a
    /// person actually has a video on while keeping a scan in the tens of
    /// milliseconds; a hundred-tab browser would otherwise turn each poll into
    /// a second of scripting.
    ///
    /// The trade-off is deliberate: a video in the thirteenth tab of a browser
    /// is not seen by this scan, and is left to the system's own now-playing
    /// report. The scan stops at the first page that is playing, so the budget
    /// is only spent in full when nothing is, which is also when a page further
    /// down the strip would be paused anyway.
    static let tabScanLimit = 12

    /// The AppleScript that asks one browser every tab it will ask.
    ///
    /// Chromium exposes the page's JavaScript through `execute javascript` on
    /// the tab, everything else through `do JavaScript … in tab`. When that is
    /// refused — "Allow JavaScript from Apple Events" off, a page whose
    /// security blocks it — the tab's title is the fallback, and only for a URL
    /// on one of the sites whose tab title is worth reading.
    private static func scanningScript(for browser: BrowserTarget) -> String {
        browser.isChromium
            ? """
            tell application "\(browser.name)"
                set fallback to ""
                set seen to 0
                repeat with w in windows
                    repeat with t in tabs of w
                        if seen is greater than or equal to \(tabScanLimit) then exit repeat
                        try
                            set u to URL of t
                            if u starts with "http" then
                                set seen to seen + 1
                                set candidate to ""
                                try
                                    tell t
                                        set candidate to (execute javascript "\(mediaReadingScript)") as text
                                    end tell
                                on error
                                    if fallback is "" and (u contains "youtube.com" or u contains "youtu.be" or u contains "bilibili.com" or u contains "netflix.com" or u contains "vimeo.com" or u contains "twitch.tv" or u contains "soundcloud.com" or u contains "dailymotion.com" or u contains "open.spotify.com" or u contains "music.apple.com" or u contains "tv.apple.com" or u contains "primevideo.com") then
                                        set fallback to (title of t) & "||" & u
                                    end if
                                end try
                                if candidate begins with "PLAYING||" then return text 10 thru -1 of candidate
                                if fallback is "" and candidate begins with "PAUSED||" then set fallback to text 9 thru -1 of candidate
                            end if
                        end try
                    end repeat
                end repeat
                return fallback
            end tell
            """
            : """
            tell application "\(browser.name)"
                set fallback to ""
                set seen to 0
                repeat with w in windows
                    repeat with t in tabs of w
                        if seen is greater than or equal to \(tabScanLimit) then exit repeat
                        try
                            set u to URL of t
                            if u starts with "http" then
                                set seen to seen + 1
                                set candidate to ""
                                try
                                    set candidate to (do JavaScript "\(mediaReadingScript)" in t) as text
                                on error
                                    if fallback is "" and (u contains "youtube.com" or u contains "youtu.be" or u contains "bilibili.com" or u contains "netflix.com" or u contains "vimeo.com" or u contains "twitch.tv" or u contains "soundcloud.com" or u contains "dailymotion.com" or u contains "open.spotify.com" or u contains "music.apple.com" or u contains "tv.apple.com" or u contains "primevideo.com") then
                                        set fallback to (name of t) & "||" & u
                                    end if
                                end try
                                if candidate begins with "PLAYING||" then return text 10 thru -1 of candidate
                                if fallback is "" and candidate begins with "PAUSED||" then set fallback to text 9 thru -1 of candidate
                            end if
                        end try
                    end repeat
                end repeat
                return fallback
            end tell
            """
    }

    /// What a page says when asked what it is playing.
    ///
    /// Written as one expression with single quotes only: it is embedded in an
    /// AppleScript string literal, where a double quote would end the literal.
    /// It answers "" for a page with no media at all, so the scan can skip it
    /// without treating it as a paused item.
    static let mediaReadingScript = "(function(){try{var v=document.querySelector('video');var a=document.querySelector('audio');var m=(navigator.mediaSession&&navigator.mediaSession.metadata)||null;var ps=(navigator.mediaSession&&navigator.mediaSession.playbackState)||'';if(!v&&!a&&!m)return '';var el=(v&&!v.paused&&!v.ended)?v:((a&&!a.paused&&!a.ended)?a:null);var playing=!!el||ps==='playing';var title=(m&&m.title)||document.title||'';var artist=(m&&m.artist)||'';var art=(m&&m.artwork&&m.artwork.length&&m.artwork[m.artwork.length-1].src)||(v&&v.poster)||'';var media=el||v||a;var d=0;var c=0;if(media&&isFinite(media.duration)){d=media.duration;c=media.currentTime;}return (playing?'PLAYING||':'PAUSED||')+JSON.stringify({title:title,artist:artist,artwork:art,sourceURL:location.href,duration:d,currentTime:c,playing:playing});}catch(e){return '';}})();"

    // MARK: - Transport

    /// Pauses whatever is playing, in whichever tab has it.
    ///
    /// The pause pass is the one that does not need to know which page is on
    /// screen: the thing to stop is whatever is making sound, wherever it is. A
    /// browser can hold the paused YouTube tab the user left behind beside the
    /// video that is actually playing, and pausing the first tab that had media
    /// stopped the wrong page. Returns whether a page was found and paused.
    static func pauseAnything() -> Bool {
        let pause = "(function(){var els=document.querySelectorAll('video,audio');var playing=[];for(var i=0;i<els.length;i++){if(!els[i].paused&&!els[i].ended)playing.push(els[i]);}if(!playing.length)return 'none';for(var j=0;j<playing.length;j++){playing[j].pause();}return 'paused';})();"
        return run(pause, wantedURL: nil) != nil
    }

    /// Starts the player on the page at `url`.
    ///
    /// Only that page: its own address is what identifies it, and with no
    /// address there is no way to tell the video on screen from a tab reached
    /// by accident. Returns whether a page answered.
    static func play(url: URL) -> Bool {
        let play = "(function(){var e=document.querySelector('video,audio');if(!e)return 'none';e.play();return 'playing';})();"
        return run(play, wantedURL: url) != nil
    }

    /// Runs `js` in a running browser's tabs until one answers "paused" or
    /// "playing", and returns that answer.
    ///
    /// `wantedURL` limits the pass to the tab showing that page; nil means any
    /// tab is fair game. A tab is asked only when its address starts with
    /// `http`, so a browser's own `chrome://` pages and the like are never
    /// handed to a page script. A browser we may not script is skipped, so the
    /// caller falls through to the system now-playing channel.
    private static func run(_ js: String, wantedURL: URL?) -> String? {
        let escapedWanted = (wantedURL?.absoluteString ?? "")
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        for browser in targets {
            guard !NSRunningApplication
                .runningApplications(withBundleIdentifier: browser.bundleID).isEmpty
            else { continue }
            guard IntegrationPermissions.canScript(browser.bundleID) else { continue }

            let scriptSource = transportScript(for: browser, js: js, wanted: escapedWanted)
            var error: NSDictionary?
            guard let script = NSAppleScript(source: scriptSource) else { continue }
            let result = script.executeAndReturnError(&error)
            guard error == nil,
                  let answer = result.stringValue?
                      .trimmingCharacters(in: .whitespacesAndNewlines),
                  answer == "paused" || answer == "playing"
            else { continue }
            return answer
        }
        return nil
    }

    private static func transportScript(
        for browser: BrowserTarget, js: String, wanted: String
    ) -> String {
        browser.isChromium
            ? """
            tell application "\(browser.name)"
                set wants to "\(wanted)"
                repeat with w in windows
                    repeat with t in tabs of w
                        try
                            set u to URL of t
                            if u starts with "http" and (wants is "" or u contains wants) then
                                set candidate to ""
                                try
                                    tell t
                                        set candidate to (execute javascript "\(js)") as text
                                    end tell
                                end try
                                if candidate is "paused" or candidate is "playing" then return candidate
                            end if
                        end try
                    end repeat
                end repeat
                return ""
            end tell
            """
            : """
            tell application "\(browser.name)"
                set wants to "\(wanted)"
                repeat with w in windows
                    repeat with t in tabs of w
                        try
                            set u to URL of t
                            if u starts with "http" and (wants is "" or u contains wants) then
                                set candidate to ""
                                try
                                    set candidate to (do JavaScript "\(js)" in t) as text
                                end try
                                if candidate is "paused" or candidate is "playing" then return candidate
                            end if
                        end try
                    end repeat
                end repeat
                return ""
            end tell
            """
    }

    // MARK: - Reading a page's own words

    /// A page URL a browser reported, accepted only when it is a plain http(s)
    /// address — the probe hands it to the player as a link, so a `file:`,
    /// `javascript:` or `chrome:` tab is never one.
    static func validatedWebURL(_ rawValue: String?) -> URL? {
        guard let rawValue,
              let components = URLComponents(
                  string: rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
              ),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = components.host,
              !host.isEmpty
        else { return nil }
        return components.url
    }

    /// The site a browser item belongs to, from its page URL.
    ///
    /// The media surfaces name the source, and it has to be that page's own
    /// site rather than a guess: every browser item used to be labelled
    /// "YouTube", so a Bilibili video on the notch said YouTube under it.
    /// Known sites get their proper name; anything else gets its own host,
    /// minus the `www.`.
    static func siteLabel(for url: URL?) -> String? {
        guard let rawHost = url?.host?.lowercased(), !rawHost.isEmpty else { return nil }
        let host = rawHost.hasPrefix("www.") ? String(rawHost.dropFirst(4)) : rawHost

        // Longest suffix first, so `music.youtube.com` is YouTube Music rather
        // than matching `youtube.com` on the way past.
        let known: [String: String] = [
            "music.youtube.com": "YouTube Music",
            "youtube.com": "YouTube",
            "youtu.be": "YouTube",
            "bilibili.com": "Bilibili",
            "b23.tv": "Bilibili",
            "netflix.com": "Netflix",
            "vimeo.com": "Vimeo",
            "twitch.tv": "Twitch",
            "soundcloud.com": "SoundCloud",
            "dailymotion.com": "Dailymotion",
            "disneyplus.com": "Disney+",
            "primevideo.com": "Prime Video",
            "tv.apple.com": "Apple TV",
            "music.apple.com": "Apple Music",
            "open.spotify.com": "Spotify",
            "tiktok.com": "TikTok",
            "instagram.com": "Instagram",
            "x.com": "X",
            "twitter.com": "X",
            "reddit.com": "Reddit",
        ]
        for key in known.keys.sorted(by: { $0.count > $1.count }) {
            if host == key || host.hasSuffix("." + key) {
                return known[key]
            }
        }
        return host
    }

    static func youtubeVideoID(from urlString: String) -> String? {
        guard let url = URL(string: urlString) else { return nil }

        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let v = components.queryItems?.first(where: { $0.name == "v" })?.value,
           !v.isEmpty {
            return v
        }

        if urlString.contains("youtu.be/") {
            if let id = url.pathComponents.dropFirst().first, !id.isEmpty {
                return id
                    .components(separatedBy: "?")[0]
                    .components(separatedBy: "&")[0]
                    .components(separatedBy: "#")[0]
            }
        }

        let pathComponents = url.pathComponents
        for prefix in ["shorts", "embed", "live", "v"] {
            if let idx = pathComponents.firstIndex(of: prefix), idx + 1 < pathComponents.count {
                let candidate = pathComponents[idx + 1]
                if !candidate.isEmpty {
                    return candidate
                        .components(separatedBy: "?")[0]
                        .components(separatedBy: "&")[0]
                        .components(separatedBy: "#")[0]
                }
            }
        }

        return nil
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? String { return Bool(value) }
        return nil
    }
}
