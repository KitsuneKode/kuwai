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
import Quickshell.Io

Singleton {
    id: root

    property bool open: false
    property var screen: null
    property string startFilter: "all"

    property var items: []          // history, newest first: entry objects (see parse)
    property var pins: []           // pinned entries, newest pin first
    property var times: ({})        // cliphist id → when it was copied (ms)
    property bool loaded: false

    readonly property string bin: Quickshell.env("HOME") + "/Projects/rice/bin/rice-clip"
    readonly property string dataDir: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/rice/clipboard"
    readonly property string stateFile: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/rice/clipboard.json"
    readonly property string thumbDir: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/rice/clip/thumbs"

    function toggle(filter) {
        if (open && (!filter || filter === startFilter)) { open = false; return; }
        startFilter = filter || "all";
        screen = Screens.focused;
        refresh();
        open = true;
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
    Process {
        running: true
        command: ["wl-paste", "--watch", "echo", "changed"]
        stdout: SplitParser { onRead: () => stampSoon.restart() }
    }
    Timer { id: stampSoon; interval: 400; onTriggered: root.refresh() }
    property bool firstList: true
    function stampNew(list) {
        if (!list.length) return;
        if (firstList) {
            // Known ids only: don't claim everything was copied just now.
            firstList = false;
            return;
        }
        const t = Object.assign({}, times);
        let changed = false;
        for (const e of list.slice(0, 5)) if (!(e.id in t)) { t[e.id] = Date.now(); changed = true; }
        if (changed) {
            const keep = new Set(list.map(e => e.id));
            for (const k in t) if (!keep.has(k)) delete t[k];
            times = t;
            saveState();
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
    function openWith(e) { open = false; run(["open", ref(e)]); }
    function remove(e) {
        if (e.pin !== "") { togglePin(e); return; }
        items = items.filter(x => x.id !== e.id);
        run(["delete", e.id]);
    }
    function wipe() { items = []; run(["wipe"]); }
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
                root.times = d.times || {};
                root.pins = (d.pins || []).map(p => Object.assign(root.parse("", p.preview || "", { pin: p.pin, source: p.source || "" }), { pinnedAt: p.pinnedAt || 0, time: p.time || 0 }));
            } catch (e) {}
        }
    }
    function saveState() {
        state.setText(JSON.stringify({
            times: times,
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
