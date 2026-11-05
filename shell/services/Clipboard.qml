pragma Singleton

// Clipboard history for the Super+V panel (modules/clipboard).
//
// History is cliphist's: HyDE's two wl-paste watchers store every copy,
// text and images. The rice adds what cliphist doesn't keep: when each
// entry was copied (a wl-paste watcher of our own stamps new ones), and
// pins, saved as files of their own so they outlive the 750-entry cap.
// bin/rice-clip does the decoding, pasting and opening.
//
// Search is fzf's: letters in order, scored for runs and word starts, with
// its extended syntax: 'exact  ^prefix  suffix$  !not.
//
// Nothing that looks like a secret (API keys, tokens, private keys, JWTs,
// long random strings) is shown in full until asked; see `secret`.
// (This header has no braces: Quickshell's scanner stops at the first one.)

import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.config
import Quickshell.Io

Singleton {
    id: root

    property bool open: false

    // ── Screen recording (bin/rice-rec), shown by the island ─────────────
    // recordSetup: the island's setup panel (source, audio, frame rate).
    property bool recordSetup: false
    property real recSince: 0                  // epoch seconds while recording, else 0
    property string recTarget: ""
    property var recSaved: null                // { at, duration, path, thumb } just after a stop
    readonly property string recBin: Paths.bin + "/rice-rec"
    readonly property string recState: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/rice/recording"
    function recordKey() {
        if (recSince > 0) { recCmd.command = [recBin, "stop"]; recCmd.running = true; return; }
        if (!recordSetup) { open = false; screen = Screens.screenNamed(Screens.focusedName); }
        recordSetup = !recordSetup;
    }
    function startRecording(source, audio, fps) {
        recordSetup = false;
        recCmd.command = [recBin, "start", source, audio, String(fps)];
        recStartLater.restart();                 // let the island fold away first (a region pick follows)
    }
    function stopRecording() { recCmd.command = [recBin, "stop"]; recCmd.running = true; }
    Timer { id: recStartLater; interval: 260; onTriggered: recCmd.running = true }
    Process { id: recCmd }
    FileView {
        path: root.recState
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { const f = text().trim().split(" "); root.recSince = f.length >= 4 ? Number(f[1]) : 0; root.recTarget = f.length >= 4 ? f[3] : ""; }
        onLoadFailed: { root.recSince = 0; root.recTarget = ""; }
    }
    FileView {
        path: root.recState + "-saved"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const f = text().trim().split(" ");
            if (f.length >= 3 && Date.now() / 1000 - Number(f[0]) < 8) {
                root.recSaved = { at: Number(f[0]), duration: Number(f[1]), path: f[2], thumb: f[3] || "" };
                savedClear.restart();
            }
        }
    }
    Timer { id: savedClear; interval: 5000; onTriggered: root.recSaved = null }
    property var screen: null
    property string startFilter: "all"

    property var items: []          // history, newest first: entry objects (see parse)
    property var pins: []           // pinned entries, newest pin first
    property var times: ({})        // cliphist id → when it was copied (ms)
    property bool loaded: false

    readonly property string bin: Paths.bin + "/rice-clip"
    readonly property string dataDir: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/rice/clipboard"
    readonly property string stateFile: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/rice/clipboard.json"
    readonly property string thumbDir: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/rice/clip/thumbs"

    // A window that opens while the shelf holds the keyboard (Satty after a
    // screenshot, a dialog, an app you launched) must get it: the shelf steps aside.
    Connections {
        target: typeof Hyprland !== "undefined" ? Hyprland : null
        function onRawEvent(event) { if (event.name === "openwindow" && (root.open || root.recordSetup)) { root.open = false; root.recordSetup = false; } }
    }
    function toggle(filter) {
        if (open && (!filter || filter === startFilter)) { open = false; return; }
        startFilter = filter || "all";
        refresh();
        targetProbe.running = true;
        // On the screen you're on: ask Hyprland (the shell's own idea of the
        // focused screen can lag behind).
        Screens.refresh(n => { root.screen = Screens.screenNamed(n); root.open = true; });
    }

    // Where ↵ will paste: the window that had focus when the panel opened.
    property var target: ({ cls: "", title: "" })
    Process {
        id: targetProbe
        command: ["hyprctl", "activewindow", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { const w = JSON.parse(text); root.target = { cls: w.class || "", title: w.title || "" }; }
                catch (e) { root.target = { cls: "", title: "" }; }
            }
        }
    }
    function targetName() {
        const c = target.cls || "";
        if (!c) return "";
        const known = { "kitty": "Kitty", "com.mitchellh.ghostty": "Ghostty", "zen": "Zen", "zen-browser": "Zen", "firefox": "Firefox", "google-chrome": "Chrome", "brave-browser": "Brave", "code": "VS Code", "code-oss": "VS Code", "cursor": "Cursor", "t3 code": "T3 Code", "t3code": "T3 Code", "obsidian": "Obsidian", "discord": "Discord", "vesktop": "Discord", "org.gnome.nautilus": "Files" };
        const k = c.toLowerCase();
        return known[k] || (c.split(".").pop().charAt(0).toUpperCase() + c.split(".").pop().slice(1));
    }

    // ── Reading ──────────────────────────────────────────────────────────
    function refresh() { if (!lister.running) lister.running = true; }
    Process {
        id: lister
        command: [root.bin, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const line of text.split("\n")) {
                    const tab = line.indexOf("\t");
                    if (tab < 1) continue;
                    out.push(root.parse(line.slice(0, tab), line.slice(tab + 1)));
                }
                root.stampNew(out);
                root.items = out;
                root.loaded = true;
            }
        }
    }

    // An entry from its cliphist preview:
    //   kind     image | file | link | color | path | email | code | text
    //   secret   looks like a credential (shown masked)
    function parse(id, preview, extra) {
        const e = Object.assign({ id: id, preview: preview, pin: "", kind: "text", ext: "", size: "", dims: "", secret: false }, extra || {});
        const img = preview.match(/^\[\[ binary data (\S+ \S+) (png|jpeg|jpg|gif|webp|bmp|svg\+xml|tiff|x-icon)(?: (\d+x\d+))? \]\]$/);
        if (img) {
            e.kind = "image";
            e.size = img[1];
            e.ext = img[2] === "jpeg" ? "jpg" : img[2] === "svg+xml" ? "svg" : img[2];
            e.dims = img[3] || "";
            return e;
        }
        if (/^\[\[ binary data/.test(preview)) { e.kind = "file"; return e; }
        const t = preview.trim();
        // Copied files: a list of file:// URIs (what a file manager puts on
        // the clipboard). They paste back as files (rice-clip copy).
        if (/^file:\/\//.test(t)) { e.kind = "files"; return e; }
        if (/^(https?|ftp):\/\/\S+$/i.test(t)) e.kind = "link";
        else if (/^mailto:\S+$|^[\w.+-]+@[\w-]+\.[\w.-]+$/.test(t)) e.kind = "email";
        else if (/^(#([0-9a-f]{3,4}|[0-9a-f]{6}|[0-9a-f]{8})|rgba?\([\d\s.,%]+\)|hsla?\([\d\s.,%deg]+\))$/i.test(t)) e.kind = "color";
        else if (/^(file:\/\/|~\/|\/)[^\s]*$/.test(t)) e.kind = "path";
        else if (/[{};]\s|=>|\bfunction\b|\bconst\b|\bimport\b|\bdef\b|\breturn\b|^\s*(\$|#!)|<\/?\w+>/.test(t)) e.kind = "code";
        e.secret = looksSecret(t);
        return e;
    }

    // ── Secrets ──────────────────────────────────────────────────────────
    function entropy(s) {
        const n = {};
        for (const c of s) n[c] = (n[c] || 0) + 1;
        let h = 0;
        for (const c in n) { const p = n[c] / s.length; h -= p * Math.log2(p); }
        return h;
    }
    function looksSecret(t) {
        if (/\b(sk-(ant-|proj-)?[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|glpat-[A-Za-z0-9_-]{20,}|xox[abpr]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{35}|npm_[A-Za-z0-9]{30,}|hf_[A-Za-z0-9]{30,})\b/.test(t)) return true;
        if (/eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\./.test(t)) return true;
        if (/-----BEGIN [A-Z ]*PRIVATE KEY-----/.test(t)) return true;
        // One long random-looking word: mixed classes, high entropy, no path or URL shape.
        if (/^\S{24,200}$/.test(t) && !/^(https?:|file:|\/|~)/.test(t)
            && /[a-z]/.test(t) && /[A-Z]/.test(t) && /\d/.test(t) && entropy(t) > 4.0) return true;
        return false;
    }

    // ── When things were copied ──────────────────────────────────────────
    // wl-paste prints a line on every clipboard change; the next list says
    // which id that was. Entries from before the shell started have no time.
    // A copy appends a line to times.tsv (rice-clip stamp): that's our cue
    // to re-read the list (no clipboard watcher of the shell's own: one per
    // reload was being left behind).
    Timer { id: stampSoon; interval: 400; onTriggered: root.refresh() }
    property bool firstList: true
    signal copied(var entry)
    // Copy times live in times.tsv ("id<TAB>ms" lines), written by
    // `rice-clip stamp` from its own wl-paste watcher at the moment of every
    // copy, whether or not this shell is running. Re-copying something moves
    // it to the top under the same id; its latest time wins.
    property string lastTop: ""
    function stampNew(list) {
        if (!list.length) return;
        const top = list[0].id;
        // The island shows what was just copied (not what was there at start).
        if (lastTop !== "" && top !== lastTop) {
            copied(list[0]);
            if (list[0].secret) expireSoon(list[0].id);
        }
        lastTop = top;
    }
    FileView {
        path: root.dataDir + "/times.tsv"
        watchChanges: true
        printErrors: false
        onFileChanged: { reload(); stampSoon.restart(); }
        onLoaded: {
            const t = {};
            for (const line of text().split("\n")) {
                const tab = line.indexOf("\t");
                if (tab > 0) t[line.slice(0, tab)] = Number(line.slice(tab + 1));
            }
            root.times = t;
        }
    }

    // ── Secrets leave history after a minute ─────────────────────────────
    // Password managers mark their copies (x-kde-passwordManagerHint), and
    // cliphist never stores those. What it can't know: an API key, a token,
    // a private key you copied by hand (looksSecret). Those stay long enough
    // to paste, then leave the history (not the clipboard itself, and never
    // a pin: pinning one is saying "keep it").
    readonly property int secretSecs: 60
    property var expiring: []                 // [{ id, at }]
    function expireSoon(id) {
        if (expiring.some(x => x.id === id)) return;
        expiring = [...expiring, { id: id, at: Date.now() + secretSecs * 1000 }];
    }
    Timer {
        interval: 5000; repeat: true
        running: root.expiring.length > 0
        onTriggered: {
            const now = Date.now();
            const due = root.expiring.filter(x => x.at <= now);
            if (!due.length) return;
            root.expiring = root.expiring.filter(x => x.at > now);
            for (const x of due) {
                const e = root.items.find(i => i.id === x.id);
                if (e && root.isPinned(e)) continue;
                root.items = root.items.filter(i => i.id !== x.id);
                root.run(["delete", x.id]);
            }
        }
    }

    // ── Pins ─────────────────────────────────────────────────────────────
    function isPinned(e) { return e.pin !== "" || pins.some(p => p.source === e.id && e.id !== ""); }
    function pinOf(e) { return e.pin !== "" ? pins.find(p => p.pin === e.pin) : pins.find(p => p.source === e.id); }
    function togglePin(e) {
        const p = pinOf(e);
        if (p) {
            run(["unpin", p.pin]);
            pins = pins.filter(x => x !== p);
            saveState();
            return;
        }
        const proc = pinner.createObject(root, { entry: e });
        proc.running = true;
    }
    Component {
        id: pinner
        Process {
            id: pinProc
            property var entry
            command: [root.bin, "pin", entry.id]
            stdout: StdioCollector {
                onStreamFinished: {
                    const file = text.trim();
                    if (!file) return;
                    const e = pinProc.entry;
                    root.pins = [Object.assign({}, e, { pin: file, source: e.id, pinnedAt: Date.now(), time: root.times[e.id] || 0 }), ...root.pins];
                    root.saveState();
                }
            }
            onExited: destroy(1000)
        }
    }

    // ── Actions ──────────────────────────────────────────────────────────
    function ref(e) { return e.pin !== "" ? "pin:" + e.pin : e.id; }
    function paste(e) { open = false; run(["paste", ref(e)]); }
    function copy(e) { open = false; run(["copy", ref(e)]); }
    function openWith(e) {
        open = false;
        const h = e.kind === "link" ? linkHandler(e.preview.trim()) : null;
        if (h) {
            const p = runner.createObject(root, { command: h.command });
            p.running = true;
        } else run(["open", ref(e)]);
    }
    function editIn(e) { open = false; run(["edit", ref(e)]); }

    // ── Links go to the app that's best at them ──────────────────────────
    // Apple Music → Cider, YouTube Music → its app, Discord → Vesktop, Zoom
    // → the meeting, a media file → mpv; anything else the default browser.
    // Only apps that are installed are used (probed once at start).
    property var apps: ({})
    Process {
        running: true
        command: ["sh", "-c", "for a in cider youtube-music vesktop zoom mpv obsidian; do command -v $a >/dev/null && echo $a; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const a = {};
                for (const n of text.split("\n")) if (n) a[n] = true;
                root.apps = a;
            }
        }
    }
    function linkHandler(url) {
        let u;
        try { u = new URL(url); } catch (err) { return null; }
        const host = u.hostname.replace(/^www\./, "");
        if (host === "music.apple.com" && apps.cider)
            return { name: "Cider", glyph: "\u{f0388}", command: ["xdg-open", "itmss://" + host + u.pathname + u.search] };
        if (host === "music.youtube.com" && apps["youtube-music"])
            return { name: "YouTube Music", glyph: "\u{f05c3}", command: ["youtube-music", url] };
        if ((host === "discord.com" || host === "discord.gg" || host === "canary.discord.com") && apps.vesktop)
            return { name: "Vesktop", glyph: "\u{f066f}", command: ["vesktop", url] };
        const zoom = host.endsWith("zoom.us") && u.pathname.match(/^\/j\/(\d+)/);
        if (zoom && apps.zoom)
            return { name: "Zoom", glyph: "\u{f0567}", command: ["xdg-open", "zoommtg://zoom.us/join?confno=" + zoom[1] + (u.searchParams.get("pwd") ? "&pwd=" + u.searchParams.get("pwd") : "")] };
        if (/\.(mp4|mkv|webm|mov|m3u8|mp3|flac|ogg|opus)(\?|$)/i.test(u.pathname) && apps.mpv)
            return { name: "mpv", glyph: "\u{f0567}", command: ["mpv", "--force-window=immediate", url] };
        return null;
    }
    // What "open" will do with this entry, in words.
    function openLabel(e) {
        if (!e) return "Open";
        if (e.kind === "link") {
            const h = linkHandler(e.preview.trim());
            if (h) return "Open in " + h.name;
            const host = e.preview.trim().replace(/^\w+:\/\//, "").split("/")[0].replace(/^www\./, "");
            return /(^|\.)youtube\.com$|youtu\.be$/.test(host) ? "Watch in browser" : "Open in browser";
        }
        return e.kind === "image" ? "Open in image viewer" : e.kind === "path" ? "Open the file" : "Open with default app";
    }
    function remove(e) {
        if (e.pin !== "") { togglePin(e); return; }
        items = items.filter(x => x.id !== e.id);
        run(["delete", e.id]);
    }
    function wipe() { items = []; run(["wipe"]); }
    // Edited or transformed text: copy it, or paste it where you were.
    function copyText(t) { open = false; run(["copy-text", t]); }
    function pasteText(t) { open = false; run(["paste-text", t]); }
    // Copied files, checked each time they're shown (moved? deleted?):
    // cb([{ path, name, exists, dir, type, size, pages, preview }]).
    property var fileInfo: ({})
    function files(e, cb) {
        const r = ref(e);
        capture(["files", r], out => {
            let d = [];
            try { d = JSON.parse(out); } catch (err) {}
            root.fileInfo = Object.assign({}, root.fileInfo, { [r]: d });
            if (cb) cb(d);
        });
    }

    // Rich rendering of text (markdown, highlighted code, mermaid), cached
    // per entry: cb({ kind, lang, html, image }).
    property var renders: ({})
    function render(e, cb) {
        const r = ref(e);
        if (renders[r]) { cb(renders[r]); return; }
        capture(["render", r], out => {
            let d = { kind: "text" };
            try { d = JSON.parse(out); } catch (err) {}
            root.renders[r] = d;
            cb(d);
        });
    }
    // Text out of an image; an image saved as a file. cb(output).
    function ocr(e, cb) { capture(["ocr", ref(e)], cb); }
    function save(e, cb) { capture(["save", ref(e)], cb); }
    function capture(args, cb) {
        const p = capturer.createObject(root, { command: [root.bin, ...args], done: cb });
        p.running = true;
    }
    Component {
        id: capturer
        Process {
            id: cap
            property var done
            stdout: StdioCollector { onStreamFinished: if (cap.done) cap.done(text.trim()) }
            onExited: destroy(1000)
        }
    }
    // Forget everything that looks like a secret, in one go.
    function forgetSecrets() {
        const s = items.filter(e => e.secret);
        items = items.filter(e => !e.secret);
        for (const e of s) run(["delete", e.id]);
    }

    function run(args) {
        const p = runner.createObject(root, { command: [root.bin, ...args] });
        p.running = true;
    }
    Component {
        id: runner
        Process { onExited: { destroy(); root.refresh(); } }
    }

    // Images: decoded into the cache once, on demand, for the rows on screen.
    property var thumbs: ({})       // ref → file path
    property var pending: ({})
    function thumb(e) {
        const r = ref(e);
        if (thumbs[r]) return thumbs[r];
        if (e.pin !== "") return "file://" + dataDir + "/pins/" + e.pin;
        if (!pending[r]) {
            pending[r] = true;
            const p = thumber.createObject(root, { key: r, command: [root.bin, "thumb", e.id, e.ext || "png"] });
            p.running = true;
        }
        return "";
    }
    Component {
        id: thumber
        Process {
            id: thumbProc
            property string key
            stdout: StdioCollector {
                onStreamFinished: {
                    const path = text.trim();
                    if (path) root.thumbs = Object.assign({}, root.thumbs, { [thumbProc.key]: "file://" + path });
                }
            }
            onExited: destroy(1000)
        }
    }

    // Full text of one entry, for the preview.
    signal textReady(string ref, string text)
    function fetchText(e) {
        if (e.kind === "image" || e.kind === "file") return;
        const p = texter.createObject(root, { key: ref(e), command: [root.bin, "text", ref(e)] });
        p.running = true;
    }
    Component {
        id: texter
        Process {
            id: textProc
            property string key
            stdout: StdioCollector { onStreamFinished: root.textReady(textProc.key, text) }
            onExited: destroy(1000)
        }
    }

    // ── State on disk: copy times and pins ───────────────────────────────
    FileView {
        id: state
        path: root.stateFile
        printErrors: false
        onLoaded: {
            try {
                const d = JSON.parse(text());
                root.pins = (d.pins || []).map(p => Object.assign(root.parse("", p.preview || "", { pin: p.pin, source: p.source || "" }), { pinnedAt: p.pinnedAt || 0, time: p.time || 0 }));
            } catch (e) {}
        }
    }
    function saveState() {
        state.setText(JSON.stringify({
            pins: pins.map(p => ({ pin: p.pin, source: p.source, preview: p.preview, pinnedAt: p.pinnedAt, time: p.time }))
        }));
    }
    Component.onCompleted: refresh()

    // ── fzf-style matching ───────────────────────────────────────────────
    // Terms are ANDed. A term is fuzzy (letters in order) unless marked:
    // 'exact  ^prefix  suffix$  !negated. Smart case: an uppercase letter
    // makes the term case-sensitive. Returns { score, pos } or null.
    function terms(q) {
        return q.split(/\s+/).filter(t => t).map(t => {
            const o = { neg: false, mode: "fuzzy", text: t };
            if (o.text.startsWith("!")) { o.neg = true; o.text = o.text.slice(1); o.mode = "exact"; }
            if (o.text.startsWith("'")) { o.mode = "exact"; o.text = o.text.slice(1); }
            if (o.text.startsWith("^")) { o.mode = "prefix"; o.text = o.text.slice(1); }
            if (o.text.endsWith("$") && o.text.length > 1) { o.mode = o.mode === "prefix" ? "equal" : "suffix"; o.text = o.text.slice(0, -1); }
            o.cased = /[A-Z]/.test(o.text);
            return o;
        }).filter(o => o.text);
    }
    function isBoundary(c) { return c === undefined || /[\s\/\\_\-.:,;()\[\]{}"'@#=+|]/.test(c); }
    function fuzzy(needle, hay) {
        // Forward: does it match at all, and where does it end?
        let i = 0, end = -1;
        for (let j = 0; j < hay.length && i < needle.length; j++) if (hay[j] === needle[i]) { i++; if (i === needle.length) end = j; }
        if (end < 0) return null;
        // Backward from the end: the tightest window (fzf v1).
        let start = end;
        for (let k = needle.length - 1, j = end; j >= 0; j--) if (hay[j] === needle[k]) { start = j; if (--k < 0) break; }
        // Score that window: 16 a letter, word starts +8 (first letter ×2),
        // runs +4 a step, gaps −1 a skipped char.
        const pos = [];
        let score = 0, run = 0, prev = -2;
        for (let k = 0, j = start; j <= end && k < needle.length; j++) {
            if (hay[j] !== needle[k]) continue;
            let s = 16;
            const atWord = isBoundary(hay[j - 1]) || (hay[j - 1] && /[a-z]/.test(hay[j - 1]) && /[A-Z]/.test(hay[j]));
            if (atWord) s += k === 0 ? 16 : 8;
            run = j === prev + 1 ? run + 1 : 0;
            s += run * 4;
            if (prev >= 0) s -= Math.min(8, j - prev - 1);
            score += s;
            pos.push(j);
            prev = j;
            k++;
        }
        return { score: score - Math.min(16, start) * 0.25, pos: pos };
    }
    function match(ts, text) {
        if (!ts.length) return { score: 0, pos: [] };
        const lower = text.toLowerCase();
        let score = 0, pos = [];
        for (const t of ts) {
            const hay = t.cased ? text : lower;
            const needle = t.cased ? t.text : t.text.toLowerCase();
            let m = null;
            if (t.mode === "fuzzy") m = fuzzy(needle, hay);
            else {
                const at = t.mode === "prefix" ? (hay.startsWith(needle) ? 0 : -1)
                         : t.mode === "suffix" ? (hay.endsWith(needle) ? hay.length - needle.length : -1)
                         : t.mode === "equal" ? (hay === needle ? 0 : -1)
                         : hay.indexOf(needle);
                if (at >= 0) m = { score: needle.length * 20 + (isBoundary(hay[at - 1]) ? 16 : 0), pos: [...Array(needle.length).keys()].map(x => x + at) };
            }
            if (t.neg) { if (m) return null; continue; }
            if (!m) return null;
            score += m.score;
            pos = pos.concat(m.pos);
        }
        return { score: score, pos: pos };
    }
    // Text with matched characters marked (StyledText), escaped.
    function marked(text, pos, color) {
        const esc = c => c === "&" ? "&amp;" : c === "<" ? "&lt;" : c === ">" ? "&gt;" : c;
        if (!pos || !pos.length) return [...text].map(esc).join("");
        const set = new Set(pos);
        let out = "", open = false;
        for (let i = 0; i < text.length; i++) {
            const on = set.has(i);
            if (on && !open) { out += `<font color="${color}"><b>`; open = true; }
            if (!on && open) { out += "</b></font>"; open = false; }
            out += esc(text[i]);
        }
        return out + (open ? "</b></font>" : "");
    }
}
