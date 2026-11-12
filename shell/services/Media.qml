pragma Singleton

// What's playing, for every surface (the island at rest, its hover card, the
// Now Playing panel): one player, chosen so it doesn't jump around.
//
// The old pick ("the playing one, else the first") switched players the
// moment you paused — a browser tab took over and the card no longer
// controlled what you'd just paused. Now the player you used stays until
// another one starts playing, or it goes away.
//
// Also: the position, ticking while someone watches (MPRIS only says it on
// a seek), and the album art's colour for the waveform and the scrubber.
// (No braces before the pragma: Quickshell's scanner stops at the first.)

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.config

Singleton {
    id: root

    // Players with something to show: a title, or playing. (Chromium apps
    // like T3 Code register an empty player that read "Unknown".)
    readonly property var players: Mpris.players.values.filter(p => (p.trackTitle || "").trim() !== "" || p.playbackState === MprisPlaybackState.Playing)
    property var active: null
    readonly property bool playing: !!active && active.playbackState === MprisPlaybackState.Playing

    // A browser's player (a tab: YouTube, a course video) often keeps saying
    // Playing in the background; a music app playing at the same time is the
    // one you hear, so it wins (Cider lost to a Zen tab).
    function isBrowser(p) {
        const id = String((p && (p.desktopEntry || p.dbusName || p.identity)) || "").toLowerCase();
        return /firefox|zen|chrom|brave|vivaldi|opera|edge|librewolf|floorp|epiphany|qutebrowser/.test(id);
    }
    function pick() {
        const ps = players;
        const alive = active && ps.indexOf(active) >= 0;
        const playing = ps.filter(p => p.playbackState === MprisPlaybackState.Playing);
        const now = playing.find(p => !isBrowser(p)) || playing[0];
        if (!alive) active = now || ps[0] || null;
        // Another one started while yours is paused or stopped: follow it.
        else if (now && now !== active && active.playbackState !== MprisPlaybackState.Playing) active = now;
        // Both playing: the music app over a browser tab.
        else if (now && now !== active && isBrowser(active) && !isBrowser(now)) active = now;
    }
    onPlayersChanged: pick()
    // Playback states change without the list changing; a cheap look each second.
    Timer { interval: 1000; running: root.players.length > 1 || !root.active; repeat: true; triggeredOnStart: true; onTriggered: root.pick() }

    // ── Position ─────────────────────────────────────────────────────────
    // Surfaces that show the time say so (watch/unwatch); then it ticks.
    property int watchers: 0
    function watch() { watchers++; }
    function unwatch() { watchers = Math.max(0, watchers - 1); }
    Timer {
        interval: 500; repeat: true
        running: root.watchers > 0 && root.playing
        onTriggered: if (root.active) root.active.positionChanged()
    }
    readonly property real length: active && active.lengthSupported ? active.length : 0
    readonly property real position: active && active.positionSupported ? active.position : 0
    readonly property real fraction: length > 0 ? Math.max(0, Math.min(1, position / length)) : 0
    function seekTo(f) {
        if (!active || !active.canSeek || !(length > 0)) return;
        active.position = Math.max(0, Math.min(length - 0.5, f * length));
    }
    function clock(s) {
        s = Math.max(0, Math.floor(s || 0));
        const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), ss = String(s % 60).padStart(2, "0");
        return h ? h + ":" + String(m).padStart(2, "0") + ":" + ss : m + ":" + ss;
    }

    // ── The art's colour ─────────────────────────────────────────────────
    readonly property string art: active ? (active.trackArtUrl || "") : ""
    // ColorQuantizer only reads local files: a player that gives a web URL
    // (Cider, Spotify, YouTube Music) got no colours, so the waveform fell
    // back to white. Those are fetched once into ~/.cache/rice/art (https
    // only, 6 MB and 6 s at most, a week kept) and quantized from there.
    readonly property bool artRemote: /^https:\/\//.test(art)
    readonly property string artCache: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/rice/art"
    property string artLocal: ""
    onArtChanged: fetchArt()
    Component.onCompleted: fetchArt()        // a song already playing when the shell starts
    function fetchArt() {
        artLocal = "";
        if (!artRemote) return;
        artFetch.want = art;
        artFetch.file = artCache + "/" + Qt.md5(art);
        artFetch.running = false;
        Qt.callLater(() => { artFetch.running = true; });
    }
    Process {
        id: artFetch
        property string want: ""
        property string file: ""
        command: ["sh", "-c", 'mkdir -p "$1" || exit 1; if [ ! -s "$2" ]; then curl -fsS --proto =https --max-time 6 --max-filesize 6000000 -o "$2.tmp" "$3" && mv -f "$2.tmp" "$2" || { rm -f "$2.tmp"; exit 1; }; fi; find "$1" -type f -mtime +7 -delete 2>/dev/null; exit 0',
                  "sh", root.artCache, file, want]
        onExited: code => { if (code === 0 && want === root.art) root.artLocal = "file://" + file; }
    }
    ColorQuantizer {
        id: quant
        source: root.artRemote ? root.artLocal : root.art
        depth: 3
        rescaleSize: 64
    }
    // The most vivid of the art's colours, lifted until it reads on black.
    readonly property color artColor: {
        const cs = quant.colors || [];
        let best = null, score = -1;
        for (const c of cs) {
            const max = Math.max(c.r, c.g, c.b), min = Math.min(c.r, c.g, c.b);
            const sat = max > 0 ? (max - min) / max : 0;
            const s = sat * 0.7 + max * 0.3;
            if (s > score) { score = s; best = c; }
        }
        // Grey art: white, not the accent (that means "where you are").
        if (!best || score < 0.25) return Theme.textPrimary;
        let c = best;
        for (let i = 0; i < 4 && Math.max(c.r, c.g, c.b) < 0.75; i++) c = Qt.lighter(c, 1.25);
        return c;
    }

    // The waveform's other end: the art's most vivid colour of a clearly
    // different hue (a gradient across the bars, from artColor to this),
    // lifted the same way. Art with one colour: artColor, a little lighter,
    // so the bars still read as one colour, not two. Set once per track.
    readonly property color artColor2: {
        const a = artColor;
        const cs = quant.colors || [];
        let best = null, score = -1;
        for (const c of cs) {
            const max = Math.max(c.r, c.g, c.b), min = Math.min(c.r, c.g, c.b);
            const sat = max > 0 ? (max - min) / max : 0;
            if (sat < 0.25) continue;
            let dh = Math.abs(c.hsvHue - a.hsvHue); dh = Math.min(dh, 1 - dh);
            if (dh < 0.08) continue;
            const s = sat * 0.7 + max * 0.3;
            if (s > score) { score = s; best = c; }
        }
        if (!best) return Qt.lighter(a, 1.18);
        let c = best;
        for (let i = 0; i < 4 && Math.max(c.r, c.g, c.b) < 0.75; i++) c = Qt.lighter(c, 1.25);
        return c;
    }
    // A colour between the two (t: 0 → artColor, 1 → artColor2).
    function artAt(t) {
        const a = artColor, b = artColor2;
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1);
    }

    // Take you to what's playing: the window showing this track (a browser
    // tab: "ADDICTED - YouTube"), else the player app's window, else ask the
    // player to raise itself (MPRIS Raise).
    function goTo(p) {
        p = p || active;
        if (!p) return;
        const norm = x => String(x || "").toLowerCase();
        const keys = [norm(p.desktopEntry), norm(p.identity).split(" ").pop(), norm(p.dbusName).replace(/^org\.mpris\.mediaplayer2\./, "").split(".")[0]].filter(k => k.length > 1);
        const wins = Hyprland.toplevels.values.filter(t => t.lastIpcObject);
        const cls = t => norm(t.lastIpcObject.class) + " " + norm(t.lastIpcObject.initialClass);
        const ofApp = wins.filter(t => keys.some(k => cls(t).includes(k)));
        const title = norm(p.trackTitle);
        const byTitle = title.length > 2 ? (ofApp.length ? ofApp : wins).find(t => norm(t.title).includes(title)) : null;
        const t = byTitle || ofApp[0] || null;
        if (t) Hyprland.dispatch(`hl.dsp.focus({window = 'address:0x${t.address}'})`);
        else if (p.canRaise) p.raise();
    }
}
