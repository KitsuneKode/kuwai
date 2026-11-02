// The clipboard island: the rice's dynamic island, at the top centre under
// the bar, doing its first job.
//
//   copy anything →      ╭──────────────────────────────╮
//                        │ ▣  Copied   npm run dev       │   (1.9s, then gone)
//                        ╰──────────────────────────────╯
//   Super+V → the pill melts down into a shelf of cards:
//   ╭──────────────────────────────────────────────────────────────╮
//   │ ⌕ [Images ×] search…                              All types ⌄ │
//   │ T ┌──────┐┌──────┐┌──────┐  Y ┌──────┐┌──────┐                │
//   │ O │ img  ││ </>  ││ ████ │  E │ x.com││ text │  …             │
//   │ D └──────┘└──────┘└──────┘  S └──────┘└──────┘                │
//   │ npm run dev                  Code · Bash · 11 characters      │
//   │ ⎘ Paste to Kitty ↵   Look Space                   Actions ⌃K  │
//   ╰──────────────────────────────────────────────────────────────╯
//
// One surface morphs between the two (Aceternity's fluid notch, Apple's
// island): width and radius on the moderate spring, height a touch ahead of
// width so it reads as melting down rather than scaling; the pill's words
// fade out early, the shelf's cards rise in late, 22ms apart. Interruptible
// both ways. Reduce Motion: it just appears.
//
// Keys: ←→ (or ↑↓) move · ↵ paste into the window you came from (named in
// the footer) · ⇧↵ copy · ⌃↵ open with its app · Space/⌃Y Quick Look ·
// ⌃K every action · ⌃E edit then paste · ⌃P pin · ⌃O text from an image ·
// ⌃S save image · ⇧⌦/⌃X delete · ⌃H show secret · ⌃R raw/rendered (Quick
// Look) · ⇥ filter · ⌥1–9 paste the nth (hold ⌥ to see) · ⌃⇧⌫ twice clears
// history · Esc: menu, Quick Look, search, filter, then closes.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import qs.config
import qs.components
import qs.services

Scope {
    id: root

    readonly property bool open: Clipboard.open
    property string query: ""
    property string filter: "all"
    property string selKey: ""
    property bool revealed: false
    property bool armed: false
    property bool altHeld: false
    property Item selRow: null
    property Item searchField: null
    property Item listView: null
    property Item actionMenu: null
    property Item filterMenu: null
    property Item quickLook: null
    property Item typeButton: null
    property Item actionsButton: null
    property Item tips: null
    property Item keySheet: null
    property Item datePicker: null
    property Item dateButton: null

    // ── When: a date range from the calendar, or @today / @yesterday / @7d /
    // @month typed in the search (the token wins while it's there) ─────────
    property real dateFrom: 0
    property real dateTo: 0
    property string dateLabel: ""
    function setDate(from, to, label) { dateFrom = from; dateTo = to; dateLabel = label; }
    readonly property var typedDate: {
        const m = query.match(/(^|\s)@(today|yesterday|7d|week|month)\b/i);
        if (!m) return null;
        const day = 86400000, now = new Date(), today = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
        const w = m[2].toLowerCase();
        return w === "today" ? { from: today, to: today + day, label: "Today" }
             : w === "yesterday" ? { from: today - day, to: today, label: "Yesterday" }
             : w === "month" ? { from: new Date(now.getFullYear(), now.getMonth(), 1).getTime(), to: today + day, label: "This month" }
             : { from: today - 6 * day, to: today + day, label: "Last 7 days" };
    }
    readonly property real fromMs: typedDate ? typedDate.from : dateFrom
    readonly property real toMs: typedDate ? typedDate.to : dateTo
    readonly property string whenLabel: typedDate ? typedDate.label : dateLabel
    function timeOf(e) { return e.pin !== "" ? (e.pinnedAt || 0) : (Clipboard.times[e.id] || 0); }
    function inDate(e) {
        if (!fromMs && !toMs) return true;
        const t = timeOf(e);
        return t > 0 && t >= fromMs && (!toMs || t < toMs);
    }
    readonly property var dayCounts: {
        const c = {};
        const add = t => { if (!t) return; const d = new Date(t); const k = d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0"); c[k] = (c[k] || 0) + 1; };
        for (const id in Clipboard.times) add(Clipboard.times[id]);
        for (const p of Clipboard.pins) add(p.pinnedAt);
        return c;
    }
    // Reading: Quick Look grows past the shelf into a large reading view.
    property bool reading: false
    onReadingChanged: if (reading && quickLook && !quickLook.open) toggleQuickLook()
    function tip(item, on, text, keys) { if (!tips) return; if (on) tips.show(item, text, keys); else tips.hide(item); }

    readonly property var filters: [
        { id: "all", label: "All types", glyph: "\u{f014c}" }, { id: "pinned", label: "Pinned", glyph: "\u{f0403}" },
        { id: "text", label: "Text", glyph: "\u{f09ed}" }, { id: "image", label: "Images", glyph: "\u{f02e9}" },
        { id: "files", label: "Files", glyph: "\u{f0214}" },
        { id: "link", label: "Links", glyph: "\u{f0339}" }, { id: "code", label: "Code", glyph: "\u{f0169}" },
        { id: "color", label: "Colours", glyph: "\u{f03d8}" }
    ]
    function filterLabel(id) { return (filters.find(f => f.id === id) || filters[0]).label; }

    // ── Results ──────────────────────────────────────────────────────────
    readonly property var ts: Clipboard.terms(query.replace(/(^|\s)@(today|yesterday|7d|week|month)\b/gi, " "))
    function searchText(e) {
        if (e.kind === "image") return "image " + e.ext + " " + e.dims;
        if (e.kind === "files") return "file " + decodeURIComponent(e.preview.replace(/file:\/\//g, " "));
        if (e.secret) return "secret key token";
        return e.preview;
    }
    function inFilter(e) {
        switch (filter) {
        case "pinned": return Clipboard.isPinned(e);
        case "text": return ["text", "email"].includes(e.kind);
        case "files": return e.kind === "files" || e.kind === "path";
        case "image": return e.kind === "image";
        case "link": return e.kind === "link";
        case "code": return e.kind === "code";
        case "color": return e.kind === "color";
        }
        return true;
    }
    readonly property var rows: {
        const pinned = new Set(Clipboard.pins.map(p => p.source).filter(x => x));
        const pool = [...Clipboard.pins.map(p => ({ e: p, pin: true })),
                      ...Clipboard.items.filter(e => !pinned.has(e.id)).map(e => ({ e: e, pin: false }))];
        const hits = [];
        for (let i = 0; i < pool.length; i++) {
            const x = pool[i];
            if (!inFilter(x.e) || !inDate(x.e)) continue;
            const m = Clipboard.match(ts, searchText(x.e));
            if (m) hits.push({ key: x.pin ? "p:" + x.e.pin : "i:" + x.e.id, e: x.e, m: m, pin: x.pin, order: i });
        }
        if (ts.length) {
            // Best match first; recency breaks ties (and nudges near-ties).
            hits.sort((a, b) => (b.m.score - b.order * 0.02) - (a.m.score - a.order * 0.02));
            return hits;
        }
        // Browsing: pins, then by when it was copied.
        const out = [];
        let last = "";
        const day = 86400000, today = new Date().setHours(0, 0, 0, 0);
        for (const h of hits) {
            const t = h.pin ? 0 : (Clipboard.times[h.e.id] || 0);
            const sec = h.pin ? "Pinned" : t >= today ? "Today" : t >= today - day ? "Yesterday" : "Earlier";
            if (sec !== last) { out.push({ key: "h:" + sec, header: sec }); last = sec; }
            out.push(h);
        }
        return out;
    }
    readonly property var entries: rows.filter(r => !r.header)
    readonly property var current: entries.find(r => r.key === selKey) || null
    readonly property var entry: current ? current.e : null
    // When the selected card leaves the list (pinned, unpinned, deleted), land
    // on its neighbour (the next card, or the previous one if it was last)
    // instead of jumping back to the first.
    property string anchorKey: ""
    function anchorAround(keys) {
        const idx = keys.map(k => entries.findIndex(r => r.key === k)).filter(i => i >= 0);
        if (!idx.length) { anchorKey = ""; return; }
        const gone = new Set(keys);
        const after = entries.slice(Math.max(...idx) + 1).find(r => !gone.has(r.key));
        const before = entries.slice(0, Math.min(...idx)).reverse().find(r => !gone.has(r.key));
        anchorKey = (after || before || { key: "" }).key;
        anchorExpiry.restart();
    }
    Timer { id: anchorExpiry; interval: 4000; onTriggered: root.anchorKey = "" }
    onRowsChanged: {
        if (!entries || current) return;
        if (anchorKey && entries.some(r => r.key === anchorKey)) selKey = anchorKey;
        else selKey = entries.length ? entries[0].key : "";
        anchorKey = "";
        // Marks on cards that are gone go with them.
        const keep = {};
        for (const k in marked) if (entries.some(r => r.key === k)) keep[k] = true;
        marked = keep;
    }

    // ── Several at once ──────────────────────────────────────────────────
    // ⌃-click marks a card, ⇧-click marks the run up to it, ⇧←/→ extends,
    // ⌃A marks everything shown; Esc clears. With cards marked, pin, delete,
    // copy and paste act on all of them (text joined by new lines).
    property var marked: ({})
    readonly property int markedCount: Object.keys(marked).length
    readonly property var markedEntries: entries.filter(r => marked[r.key])
    function mark(key, on) {
        const m = Object.assign({}, marked);
        if (on === undefined ? !m[key] : on) m[key] = true; else delete m[key];
        marked = m;
    }
    function markRange(toKey) {
        const a = entries.findIndex(r => r.key === selKey), b = entries.findIndex(r => r.key === toKey);
        if (a < 0 || b < 0) return;
        const m = Object.assign({}, marked);
        for (let i = Math.min(a, b); i <= Math.max(a, b); i++) m[entries[i].key] = true;
        marked = m;
        selKey = toKey;
    }
    function clearMarks() { marked = ({}); }
    function markAll() { const m = {}; for (const r of entries) m[r.key] = true; marked = m; }
    // Text of every marked card, in list order, joined by new lines.
    function joinedText(cb) {
        const list = markedEntries.map(r => r.e).filter(e => e.kind !== "image");
        const parts = new Array(list.length);
        let left = list.length;
        if (!left) { cb(""); return; }
        list.forEach((e, i) => withText(e, t => { parts[i] = t; if (--left === 0) cb(parts.join("\n")); }));
    }
    function runMarked(id) {
        const rs = markedEntries;
        if (!rs.length) return false;
        switch (id) {
        case "pin": {
            const pinAll = rs.some(r => !Clipboard.isPinned(r.e));
            anchorAround(rs.map(r => r.key));
            for (const r of rs) if (Clipboard.isPinned(r.e) !== pinAll) Clipboard.togglePin(r.e);
            say((pinAll ? "Pinned " : "Unpinned ") + rs.length);
            break;
        }
        case "delete":
            anchorAround(rs.map(r => r.key));
            for (const r of rs) Clipboard.remove(r.e);
            say("Removed " + rs.length);
            break;
        case "copy": joinedText(t => { if (t) { Clipboard.run(["copy-text", t]); say("Copied " + rs.length + " as one"); } }); break;
        case "paste": joinedText(t => { if (t) Clipboard.pasteText(t); }); break;
        default: return false;
        }
        clearMarks();
        return true;
    }
    onQueryChanged: first()
    onFilterChanged: first()
    onFromMsChanged: first()
    function first() {
        selKey = entries.length ? entries[0].key : "";
        if (listView) listView.positionViewAtBeginning();
    }
    onSelKeyChanged: {
        revealed = false;
        const i = rows.findIndex(r => r.key === selKey);
        if (i < 0 || !listView) return;
        // Glide to it (fast): where it needs to be, then animate there.
        const from = listView.contentX;
        listView.positionViewAtIndex(i, ListView.Contain);
        const to = listView.contentX;
        if (Math.abs(to - from) > 1 && !Theme.reduceMotion) { listView.contentX = from; shelfGlide.to = to; shelfGlide.restart(); }
    }
    NumberAnimation { id: shelfGlide; target: root.listView; property: "contentX"; duration: 140; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
    // Where you were last time (the item selected when it closed): ⌥← returns there.
    property string lastKey: ""
    function backToLast() { if (lastKey && entries.some(r => r.key === lastKey)) selKey = lastKey; }
    function focusSearch() { if (searchField) searchField.forceActiveFocus(); }
    function select(key) { selKey = key; focusSearch(); }
    function move(step) {
        if (!entries.length) return;
        const i = entries.findIndex(r => r.key === selKey);
        selKey = entries[Math.max(0, Math.min(entries.length - 1, (i < 0 ? 0 : i) + step))].key;
    }

    // ── Actions ──────────────────────────────────────────────────────────
    // The entry's full text: Quick Look may already have it; else fetch.
    function withText(e, fn) {
        if (quickLook && quickLook.entry === e && quickLook.full) fn(quickLook.full);
        else Clipboard.capture(["text", Clipboard.ref(e)], fn);
    }
    function isJson(t) { try { const v = JSON.parse(t); return typeof v === "object" && v !== null; } catch (e) { return false; } }
    function isB64(t) { return /^[A-Za-z0-9+/=\s]{16,}$/.test(t) && t.replace(/\s/g, "").length % 4 === 0; }
    function b64decode(t) {
        const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        t = t.replace(/[^A-Za-z0-9+/]/g, "");
        let bits = 0, n = 0, bytes = [];
        for (const c of t) { n = (n << 6) | chars.indexOf(c); bits += 6; if (bits >= 8) { bits -= 8; bytes.push((n >> bits) & 255); } }
        try { return decodeURIComponent(bytes.map(b => "%" + b.toString(16).padStart(2, "0")).join("")); } catch (e) { return ""; }
    }
    readonly property var actionItems: {
        const e = entry;
        if (!e) return [];
        const img = e.kind === "image", txt = !img && e.kind !== "file";
        const t = e.preview;
        const where = Clipboard.targetName();
        const a = [
            { id: "paste", label: where ? "Paste to " + where : "Paste", glyph: "\u{f0192}", keys: ["↵"], section: "Entry" },
            { id: "copy", label: "Copy to clipboard", glyph: "\u{f018f}", keys: ["⇧", "↵"], section: "Entry" },
            { id: "open", label: Clipboard.openLabel(e), glyph: "\u{f03cc}", keys: ["⌃", "↵"], section: "Entry" },
            { id: "quicklook", label: "Quick Look", glyph: "\u{f0208}", keys: ["Space"], section: "Entry" },
            { id: "read", label: "Read it large", glyph: "\u{f0293}", keys: ["⇧", "Space"], section: "Entry" },
            { id: "pin", label: Clipboard.isPinned(e) ? "Unpin" : "Pin", glyph: "\u{f0403}", keys: ["⌃", "P"], section: "Entry" }
        ];
        if (txt) a.push({ id: "edit", label: "Edit, then paste", glyph: "\u{f03eb}", keys: ["⌃", "E"], section: "Entry" });
        if (txt) a.push({ id: "nvim", label: "Edit in Neovim (the edit is copied)", glyph: "\u{f06e5}", keys: ["⌃", "⇧", "E"], section: "Entry" });
        if (img) {
            a.push({ id: "ocr", label: "Copy text from image", glyph: "\u{f05e7}", keys: ["⌃", "O"], section: "Image" });
            a.push({ id: "save", label: "Save to Screenshots…", glyph: "\u{f0193}", keys: ["⌃", "S"], section: "Image" });
        }
        if (txt) {
            a.push({ id: "trim", label: "Paste trimmed, one line", glyph: "\u{f0a73}", section: "Paste as" });
            a.push({ id: "upper", label: "Paste as UPPERCASE", glyph: "\u{f0b34}", section: "Paste as" });
            a.push({ id: "lower", label: "Paste as lowercase", glyph: "\u{f0b33}", section: "Paste as" });
            if (t.trim().startsWith("{") || t.trim().startsWith("[")) a.push({ id: "json", label: "Paste formatted JSON", glyph: "\u{f0626}", section: "Paste as" });
            if (e.kind === "link") a.push({ id: "urldec", label: "Paste URL decoded", glyph: "\u{f0339}", section: "Paste as" });
            else a.push({ id: "urlenc", label: "Paste URL encoded", glyph: "\u{f0339}", section: "Paste as" });
            if (isB64(t)) a.push({ id: "b64", label: "Paste Base64 decoded", glyph: "\u{f0bb4}", section: "Paste as" });
        }
        if (e.secret) a.push({ id: "reveal", label: revealed ? "Hide secret" : "Show secret", glyph: "\u{f0208}", keys: ["⌃", "H"], section: "Entry" });
        a.push({ id: "delete", label: "Delete entry", glyph: "\u{f0a7a}", keys: ["⇧", "⌦"], danger: true, section: "Manage" });
        if (Clipboard.items.some(x => x.secret)) a.push({ id: "secrets", label: "Forget everything that looks secret", glyph: "\u{f0306}", danger: true, section: "Manage" });
        a.push({ id: "wipe", label: "Clear history (pins stay)", glyph: "\u{f0a7a}", keys: ["⌃", "⇧", "⌫"], danger: true, section: "Manage" });
        return a;
    }
    function run(id) {
        if (markedCount && runMarked(id)) return;
        const e = entry;
        if (!e && id !== "wipe") return;
        switch (id) {
        case "paste": Clipboard.paste(e); break;
        case "copy": Clipboard.copy(e); break;
        case "open": Clipboard.openWith(e); break;
        case "pin": say(Clipboard.isPinned(e) ? "Unpinned" : "Pinned"); anchorAround([selKey]); Clipboard.togglePin(e); break;
        case "quicklook": toggleQuickLook(); break;
        case "read": reading = !reading; break;
        case "nvim": Clipboard.editIn(e); break;
        case "edit":
            if (e.secret) revealed = true;
            if (!quickLook.open) toggleQuickLook();
            quickLook.editing = true;
            break;
        case "reveal": revealed = !revealed; break;
        case "delete": anchorAround([selKey]); move(1); if (entry === e) move(-1); Clipboard.remove(e); break;
        case "ocr":
            say("Reading text…", true);
            Clipboard.ocr(e, txt => {
                if (!txt) { say("No text found in the image"); return; }
                Clipboard.run(["copy-text", txt]);
                say(`Copied ${txt.length.toLocaleString()} characters of text`);
            });
            break;
        case "save":
            // Images get a name first (prefilled; Enter keeps it), then go to ~/Pictures/Screenshots.
            if (e.kind === "image") { naming = true; nameField.text = "Screenshot_" + new Date().toISOString().replace(/[-:]/g, "").replace("T", "_").slice(0, 15); nameField.selectAll(); nameField.forceActiveFocus(); }
            else Clipboard.save(e, path => say(path ? "Saved " + path.replace(Quickshell.env("HOME"), "~") : "Couldn't save"));
            break;
        case "trim": withText(e, t => Clipboard.pasteText(t.replace(/\s+/g, " ").trim())); break;
        case "upper": withText(e, t => Clipboard.pasteText(t.toUpperCase())); break;
        case "lower": withText(e, t => Clipboard.pasteText(t.toLowerCase())); break;
        case "json": withText(e, t => { if (isJson(t)) Clipboard.pasteText(JSON.stringify(JSON.parse(t), null, 2)); else say("Not valid JSON"); }); break;
        case "urlenc": withText(e, t => Clipboard.pasteText(encodeURIComponent(t.trim()))); break;
        case "urldec": withText(e, t => { try { Clipboard.pasteText(decodeURIComponent(t.trim())); } catch (err) { say("Not a valid encoded URL"); } }); break;
        case "b64": withText(e, t => { const d = b64decode(t); if (d) Clipboard.pasteText(d); else say("Not valid Base64 text"); }); break;
        case "secrets": Clipboard.forgetSecrets(); say("Forgot everything that looked like a secret"); break;
        case "wipe":
            if (confirmWipe) { confirmWipe = false; Clipboard.wipe(); say("History cleared; pins kept"); }
            else { confirmWipe = true; wipeWindow.restart(); say("Press ⌃⇧⌫ again to clear all history", true); }
            break;
        }
    }
    readonly property var keySections: [
        { title: "Paste and copy", items: [
            { k: ["↵"], t: "Paste into the window you came from" },
            { k: ["⇧", "↵"], t: "Copy, don't paste" },
            { k: ["⌥", "1–9"], t: "Paste the nth card (hold ⌥ to see)" },
            { k: ["⌃", "E"], t: "Edit, then paste" },
            { k: ["⌃", "⇧", "E"], t: "Edit in Neovim; the edit is copied" } ] },
        { title: "Look", items: [
            { k: ["Space"], t: "Quick Look" },
            { k: ["⇧", "Space"], t: "Read it large" },
            { k: ["⌃", "R"], t: "Rendered or raw (Markdown, code)" },
            { k: ["⌃", "H"], t: "Show or hide a secret" },
            { k: ["⌃", "↵"], t: "Open it where it belongs (Cider, browser…)" } ] },
        { title: "Move", items: [
            { k: ["←", "→"], t: "Previous or next card" },
            { k: ["⇧", "← →"], t: "Mark several (⌃-click one, ⇧-click a run, ⌃A all)" },
            { k: ["PgUp", "PgDn"], t: "Five at a time" },
            { k: ["⌃", "Home"], t: "First or last (⌃End)" },
            { k: ["⇥"], t: "Next filter (⇧⇥ back)" },
            { k: ["⌫"], t: "Clear the filter (empty search)" } ] },
        { title: "Keep and tidy", items: [
            { k: ["⌃", "P"], t: "Pin or unpin" },
            { k: ["⇧", "⌦"], t: "Delete the card (or ⌃X)" },
            { k: ["⌃", "⇧", "⌫"], t: "Clear history, twice (pins stay)" } ] },
        { title: "Images", items: [
            { k: ["⌃", "O"], t: "Copy the text in it (OCR)" },
            { k: ["⌃", "S"], t: "Save to Screenshots, named" } ] },
        { title: "When", items: [
            { k: ["⌃", "D"], t: "Calendar: a day, ⇧-click a range" },
            { k: ["@today"], t: "Also @yesterday, @7d, @month" } ] },
        { title: "Search", items: [
            { k: ["'word"], t: "Exact match" },
            { k: ["^word"], t: "Starts with" },
            { k: ["word$"], t: "Ends with" },
            { k: ["!word"], t: "Leave out" },
            { k: ["⌃", "K"], t: "Every action for the card" },
            { k: ["Esc"], t: "Back out, step by step" },
            { k: ["Alt", "←"], t: "Back to where you were last time" } ] }
    ]

    // Naming a screenshot before it's saved (⌃S on an image).
    property bool naming: false
    property Item nameField: null
    function finishNaming(save) {
        const e = entry;
        naming = false;
        focusSearch();
        if (!save || !e) return;
        Clipboard.capture(["save-as", Clipboard.ref(e), nameField.text.trim()],
                          path => say(path ? "Saved " + path.replace(Quickshell.env("HOME"), "~") : "Couldn't save"));
    }

    property bool confirmWipe: false
    Timer { id: wipeWindow; interval: 3000; onTriggered: root.confirmWipe = false }

    // A short line of feedback over the footer.
    property string status: ""
    function say(msg) { status = msg; statusTimer.restart(); }
    Timer { id: statusTimer; interval: 2600; onTriggered: root.status = "" }

    function toggleQuickLook() {
        if (!quickLook) return;
        if (quickLook.open) { quickLook.open = false; reading = false; return; }
        if (!entry) return;
        quickLook.entry = entry;
        quickLook.from = selRow ? selRow.markItem.mapToItem(quickLook, 0, 0, selRow.markItem.width, selRow.markItem.height)
                                : Qt.rect(quickLook.width / 2 - 16, quickLook.height / 2 - 16, 32, 32);
        quickLook.open = true;
        // An image or a file preview opens big: the island grows to the reading size with it (a tall screenshot
        // fitted into the shelf's height came out a few hundred pixels wide).
        if (["image", "files"].includes(entry.kind) || entry.kind === "path") reading = true;
    }
    onEntryChanged: if (quickLook && quickLook.open && entry) {
        quickLook.entry = entry;
        if (selRow) quickLook.from = selRow.markItem.mapToItem(quickLook, 0, 0, selRow.markItem.width, selRow.markItem.height);
    }

    // ── Presentation helpers (cards and Quick Look use these) ─────────────
    function glyphOf(e) {
        if (e.secret) return "\u{f0306}";
        return ({ link: "\u{f0339}", path: "\u{f024b}", email: "\u{f01ee}", code: "\u{f0169}", file: "\u{f0214}", image: "\u{f02e9}", color: "\u{f03d8}" })[e.kind] || "\u{f09ed}";
    }
    function ago(t) {
        if (!t) return "";
        const m = Math.floor((Date.now() - t) / 60000);
        return m < 1 ? "now" : m < 60 ? m + "m" : m < 1440 ? Math.floor(m / 60) + "h" : Math.floor(m / 1440) + "d";
    }
    function kindOf(e) {
        return e.secret ? "Secret" : ({ image: "Image", link: "Link", path: "Path", email: "Email", code: "Code", color: "Colour", file: "File" })[e.kind] || "Text";
    }
    function metaOf(e) {
        const parts = [kindOf(e)];
        if (e.kind === "image") parts.push([e.ext.toUpperCase(), e.size].filter(x => x).join(" · "));
        const t = e.pin !== "" ? e.pinnedAt : Clipboard.times[e.id];
        if (t) parts.push(ago(t));
        return parts.filter(x => x).join("  ·  ");
    }
    function detailOf(e, full) {
        if (e.kind === "image") return [e.ext.toUpperCase(), e.dims.replace("x", " × "), e.size].filter(x => x).join("  ·  ");
        const t = full || e.preview;
        const lines = t ? t.split("\n").length : 0;
        const words = t.trim() ? t.trim().split(/\s+/).length : 0;
        return `${t.length.toLocaleString()} characters  ·  ${words} words  ·  ${lines} ${lines === 1 ? "line" : "lines"}`;
    }
    function colorOf(s) {
        s = s.trim();
        let m = s.match(/^rgba?\(\s*([\d.]+%?)[\s,]+([\d.]+%?)[\s,]+([\d.]+%?)(?:[\s,\/]+([\d.]+%?))?\s*\)$/i);
        const n = (v, max) => v.endsWith("%") ? parseFloat(v) / 100 : parseFloat(v) / max;
        if (m) return Qt.rgba(n(m[1], 255), n(m[2], 255), n(m[3], 255), m[4] ? n(m[4], 1) : 1);
        m = s.match(/^hsla?\(\s*([\d.]+)(?:deg)?[\s,]+([\d.]+)%[\s,]+([\d.]+)%(?:[\s,\/]+([\d.]+%?))?\s*\)$/i);
        if (m) return Qt.hsla(parseFloat(m[1]) / 360, parseFloat(m[2]) / 100, parseFloat(m[3]) / 100, m[4] ? n(m[4], 1) : 1);
        return Qt.color(s);
    }
    function colorValues(c) {
        const h = v => Math.round(v * 255).toString(16).padStart(2, "0");
        return [
            "#" + h(c.r) + h(c.g) + h(c.b) + (c.a < 1 ? h(c.a) : ""),
            `rgb(${Math.round(c.r * 255)}, ${Math.round(c.g * 255)}, ${Math.round(c.b * 255)})`,
            `hsl(${Math.round(Math.max(0, c.hslHue) * 360)}, ${Math.round(c.hslSaturation * 100)}%, ${Math.round(c.hslLightness * 100)}%)`
        ];
    }

    // ── The island's states ──────────────────────────────────────────────
    // Live: a copy shows in the pill for a moment (not while the shelf is open).
    property var toastEntry: null
    property bool toasting: false
    property var toastScreen: null
    Connections {
        target: Clipboard
        function onCopied(e) {
            if (Clipboard.open) return;
            root.toastEntry = e;
            root.toastScreen = Screens.focused;
            root.toasting = true;
            toastTimer.restart();
        }
    }
    Timer { id: toastTimer; interval: 1900; onTriggered: root.toasting = false }

    // Recording (bin/rice-rec, state in the Clipboard service): the pill holds
    // a red dot, the time and a stop button while it lasts; after a stop it
    // shows "Recording saved" with a frame of it for a few seconds.
    readonly property bool recording: Clipboard.recSince > 0
    readonly property bool saved: Clipboard.recSaved !== null
    readonly property bool setup: Clipboard.recordSetup
    // The island is open as the shelf (Super+V) or the recording setup.
    readonly property bool expanded: open || setup
    property real nowSec: Date.now() / 1000
    Timer { running: root.recording; interval: 250; repeat: true; triggeredOnStart: true; onTriggered: root.nowSec = Date.now() / 1000 }
    function elapsed(s) { s = Math.max(0, Math.floor(s)); return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0"); }
    Process { id: opener }
    // A copied image's pill: a click opens it in Satty to annotate.
    Process { id: annotate }
    function pillClicked() {
        if (recording) { Clipboard.stopRecording(); return; }
        if (saved) { opener.command = ["xdg-open", Clipboard.recSaved.path]; opener.running = true; Clipboard.recSaved = null; return; }
        const e = toastEntry;
        if (e && e.kind === "image") {
            const src = Clipboard.thumb(e).replace(/^file:\/\//, "");
            if (src) {
                annotate.command = ["satty", "--filename", src, "--output-filename",
                    Quickshell.env("HOME") + "/Pictures/Screenshots/Screenshot_" + new Date().toISOString().replace(/[-:T]/g, "").slice(0, 15) + ".png",
                    "--copy-command", "wl-copy", "--early-exit"];
                annotate.running = true;
                toasting = false;
            }
        } else Clipboard.toggle("all");
    }

    // pill: 0 gone → 1 there (it swells out of a dot). melt: 0 pill → 1 shelf.
    Spring { id: pill; tier: Theme.springFast; epsilon: 0.002; target: root.expanded || root.toasting || root.recording || root.saved ? 1 : 0 }
    Spring { id: melt; tier: Theme.springModerate; epsilon: 0.001; target: root.expanded ? 1 : 0 }
    Spring { id: read; tier: Theme.springModerate; epsilon: 0.001; target: root.open && root.reading ? 1 : 0 }
    readonly property bool shownAtAll: expanded || toasting || recording || saved || pill.value > 0.003 || melt.value > 0.003
    readonly property var hostScreen: expanded ? (Clipboard.screen || Quickshell.screens[0]) : (toastScreen || Clipboard.screen || Quickshell.screens[0])

    // Reveal clock for the cards' rise.
    property real clock: 1000
    NumberAnimation { id: clockRun; target: root; property: "clock"; from: 0; to: 500; duration: 500 }
    function reveal(ms) {
        if (Theme.reduceMotion) return 1;
        const k = Math.max(0, Math.min(1, (clock - ms - 90) / 160));
        return 1 - Math.pow(1 - k, 3);
    }
    onSetupChanged: { armed = false; if (setup) setupArm.restart(); }
    Timer { id: setupArm; interval: 160; onTriggered: { root.armed = root.setup; if (root.setupPanel) root.setupPanel.forceActiveFocus(); } }
    property Item setupPanel: null
    onOpenChanged: {
        armed = false;
        altHeld = false;
        if (open) {
            toasting = false;
            toastEntry = null;
            query = "";
            if (searchField) searchField.text = "";
            filter = Clipboard.startFilter;
            first();
            confirmWipe = false;
            status = "";
            if (actionMenu) actionMenu.open = false;
            if (filterMenu) filterMenu.open = false;
            if (quickLook) quickLook.open = false;
            if (keySheet) keySheet.open = false;
            if (datePicker) datePicker.open = false;
            setDate(0, 0, "");
            reading = false;
            clock = 0;
            clockRun.restart();
            armSoon.restart();
            if (Theme.reduceMotion) { pill.settle(); melt.settle(); }
        } else {
            if (selKey) lastKey = selKey;          // ⌥← brings you back here next time
            if (Theme.reduceMotion) { pill.settle(); melt.settle(); }
        }
    }
    // Left alone, it puts itself away: 45s without a key or the pointer on
    // it (never while you're reading, editing or in a menu).
    property bool pointerIn: false
    readonly property bool busy: pointerIn || reading || naming || (quickLook && quickLook.editing) || (actionMenu && actionMenu.open)
                                 || (datePicker && datePicker.open) || (keySheet && keySheet.open)
    function touched() { if (open) idle.restart(); }
    onBusyChanged: touched()
    Timer {
        id: idle
        interval: 45000
        running: root.open && !root.busy
        onTriggered: Clipboard.open = false
    }
    Timer { id: armSoon; interval: 160; onTriggered: { root.armed = root.open; if (root.open) root.focusSearch(); } }

    // ── Surface: one per monitor, mapped for good (1×1 while idle) ────────
    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: win
            required property ShellScreen modelData
            screen: modelData
            readonly property bool hosts: root.hostScreen === modelData
            readonly property bool up: hosts && root.shownAtAll

            // The shelf, and the pill it melts out of.
            readonly property real shelfW: root.setup ? 540 : Math.min(1000, modelData.width - 80)
            readonly property real shelfH: root.setup ? 262 : 476
            // Reading size: most of the screen, still clear of its edges.
            readonly property real readW: Math.min(1280, modelData.width - 80)
            readonly property real readH: Math.min(1020, modelData.height - 150)
            readonly property real rd: read.value
            readonly property real side: 64
            // The chip states (just copied, recording, saved) have their own
            // width; opening and closing the shelf go straight from and back to
            // the island's own shape, with no label pill in between.
            readonly property bool chip: root.toasting || root.recording || root.saved
            readonly property real pillW: !chip ? (inIsland ? islandW : 180)
                : root.saved && !root.toasting ? savedRow.implicitWidth + 30
                : root.recording && !root.toasting ? recRow.implicitWidth + 30
                : Math.max(170, Math.min(470, toastRow.implicitWidth + 36))
            // With the island bar, the clipboard *is* the island growing: it
            // starts from the island's own width, height and corners.
            readonly property bool inIsland: Settings.bar === "island"
            readonly property bool notch: inIsland && Settings.islandStyle !== "floating"
            readonly property real islandW: Island.restWidths[modelData.name] || 220
            readonly property real pillH: inIsland ? 34 : 40

            anchors.top: true
            // Sized for good (input is masked to the frame): resizing the
            // surface as it opens costs a round trip, and the first frames of
            // the grow arrived late and jumped.
            implicitWidth: Math.max(shelfW, readW) + side * 2
            implicitHeight: Math.max(shelfH, readH) + 96
            // On the island it must sit where the island is, not under the
            // island's reserved strip.
            exclusionMode: inIsland ? ExclusionMode.Ignore : ExclusionMode.Normal
            color: "transparent"
            WlrLayershell.namespace: "rice-island"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: up && root.expanded ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            mask: Region { item: win.up && (root.expanded || root.toasting || root.recording || root.saved) ? frame : null }

            HyprlandFocusGrab {
                windows: [win]
                active: win.up && root.expanded && root.armed
                onCleared: { Clipboard.open = false; Clipboard.recordSetup = false; }
            }
            HoverHandler { onHoveredChanged: if (win.hosts) root.pointerIn = hovered }

            function lerp(a, b, k) { return a + (b - a) * k; }
            readonly property real m: melt.value
            readonly property real pv: pill.value
            // Height runs a little ahead of width: it melts down, not scales.
            readonly property real mh: Math.pow(Math.max(0, Math.min(1, m)), 0.78)

            Elevation { target: frame; radius: frame.radius; strength: Math.min(1, win.pv) * (0.55 + 0.45 * Math.min(1, win.m)) }
            Rectangle {
                id: frame
                visible: win.up
                // Grows from the island's own size when the island is the bar.
                readonly property real baseW: win.lerp(win.inIsland ? win.islandW : 44, win.pillW, Math.min(1, win.pv))
                width: Math.max(1, win.lerp(win.lerp(baseW, win.shelfW, win.m), win.readW, win.rd))
                height: Math.max(1, win.lerp(win.lerp(win.pillH, win.shelfH, win.mh), win.readH, win.rd))
                x: Math.round((win.width - width) / 2)
                // With the island bar, the clipboard is the island growing:
                // flush with the top edge (or the floating pill's place), black.
                y: win.inIsland ? (win.notch ? 0 : 6) : 6
                // From the island's own corners (a floating capsule's are half
                // its height; the notch's 14) to the shelf's.
                radius: win.lerp(win.notch ? 14 : win.pillH / 2, 26, Math.min(1, win.m))
                // The same liquid glass (and grain) as the center and the
                // toasts: one material across the rice. The pill is the
                // glass's elevated tint, a touch denser so words read on it.
                color: "transparent"
                opacity: Math.min(1, win.pv * 2.5)
                clip: true
                GlassCard {
                    visible: !win.notch
                    anchors.fill: parent
                    radius: frame.radius
                    tint: win.inIsland ? Qt.rgba(0, 0, 0, 0.9) : Theme.glassTintElevated
                }
                NotchShape {
                    visible: win.notch
                    ear: 9
                    w: frame.width - 18
                    h: frame.height
                    radius: Math.min(frame.radius, 30)
                    fill: Qt.rgba(0, 0, 0, 0.94)
                }

                // ── Pill: what was just copied ───────────────────────────
                Row {
                    id: toastRow
                    anchors.centerIn: parent
                    spacing: 10
                    opacity: root.toasting ? Math.max(0, 1 - win.m * 4) : 0
                    visible: opacity > 0.01
                    readonly property var e: root.toastEntry
                    ClippingRectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 24; height: 24; radius: 7
                        color: toastRow.e && toastRow.e.kind === "color" ? root.colorOf(toastRow.e.preview) : Qt.rgba(1, 1, 1, 0.1)
                        Image {
                            anchors.fill: parent
                            visible: toastRow.e && toastRow.e.kind === "image"
                            source: visible ? Clipboard.thumb(toastRow.e) : ""
                            sourceSize: Qt.size(64, 64)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: !(toastRow.e && (toastRow.e.kind === "image" || toastRow.e.kind === "color"))
                            text: toastRow.e ? root.glyphOf(toastRow.e) : "\u{f014c}"
                            font.family: Theme.fontGlyph
                            font.pixelSize: 13
                            color: toastRow.e && toastRow.e.secret ? Theme.orange : Theme.textSecondary
                        }
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.open && !root.toastEntry ? "Clipboard" : "Copied"
                        size: 13
                        weight: Theme.wSemibold
                        color: Theme.green
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, 300)
                        elide: Text.ElideRight
                        text: !toastRow.e ? ""
                            : toastRow.e.kind === "image" ? "Image " + toastRow.e.dims.replace("x", " × ")
                            : toastRow.e.secret ? "Something secret (hidden)"
                            : toastRow.e.preview.replace(/\s+/g, " ").slice(0, 80)
                        size: 13
                        color: Theme.textSecondary
                    }
                }

                // ── Pill: recording (Skiper's island: dot, time, label, stop) ──
                Row {
                    id: recRow
                    anchors.centerIn: parent
                    spacing: 10
                    opacity: root.recording && !root.toasting && !root.saved ? Math.max(0, 1 - win.m * 4) : 0
                    visible: opacity > 0.01
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 9; height: 9; radius: 4.5
                        color: Theme.red
                        SequentialAnimation on opacity {
                            running: root.recording && !Theme.reduceMotion
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
                        }
                    }
                    Label { anchors.verticalCenter: parent.verticalCenter; text: root.elapsed(root.nowSec - Clipboard.recSince); size: 13; rounded: true; weight: Theme.wSemibold; color: Theme.red; font.features: ({ "tnum": 1 }) }
                    Label { anchors.verticalCenter: parent.verticalCenter; text: "Screen Recording"; size: 13; weight: Theme.wMedium }
                    // Stop: a red square in a ring that sweeps once a second.
                    Item {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 26; height: 26
                        Rectangle { anchors.fill: parent; radius: 13; color: "transparent"; border.width: 2; border.color: Qt.rgba(1, 1, 1, 0.16) }
                        Canvas {
                            id: sweep
                            anchors.fill: parent
                            property real f: (root.nowSec - Clipboard.recSince) % 1
                            onFChanged: requestPaint()
                            onPaint: {
                                const c = getContext("2d"); c.reset();
                                c.strokeStyle = "#ff453a"; c.lineWidth = 2; c.lineCap = "round";
                                c.beginPath(); c.arc(13, 13, 12, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * Math.max(0.02, f)); c.stroke();
                            }
                        }
                        Rectangle { anchors.centerIn: parent; width: 10; height: 10; radius: 3; color: Theme.red }
                    }
                }
                // ── Pill: recording saved ────────────────────────────────
                Row {
                    id: savedRow
                    anchors.centerIn: parent
                    spacing: 10
                    opacity: root.saved && !root.toasting ? Math.max(0, 1 - win.m * 4) : 0
                    visible: opacity > 0.01
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "\u{f012c}"; font.family: Theme.fontGlyph; font.pixelSize: 15; color: Theme.green }
                    Label { anchors.verticalCenter: parent.verticalCenter; text: root.saved ? root.elapsed(Clipboard.recSaved.duration) : ""; size: 13; rounded: true; weight: Theme.wSemibold; font.features: ({ "tnum": 1 }) }
                    Label { anchors.verticalCenter: parent.verticalCenter; text: "Recording saved · click to open"; size: 13; color: Theme.textSecondary }
                    ClippingRectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.saved && Clipboard.recSaved.thumb !== ""
                        width: 46; height: 28; radius: 7
                        color: Qt.rgba(1, 1, 1, 0.08)
                        Image { anchors.fill: parent; source: parent.visible ? "file://" + Clipboard.recSaved.thumb : ""; fillMode: Image.PreserveAspectCrop; asynchronous: true; cache: false; sourceSize: Qt.size(92, 56) }
                    }
                }
                // The pill is a button while it's a pill: stop a recording, annotate a copied image.
                MouseArea {
                    anchors.fill: parent
                    enabled: !root.expanded
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.pillClicked()
                }

                // ── Shelf ────────────────────────────────────────────────
                Loader {
                    active: win.hosts
                    // Laid out at the shelf's size, pinned to its centre: the
                    // growing island reveals it.
                    x: Math.round((frame.width - win.shelfW) / 2)
                    y: 0
                    width: win.shelfW
                    height: win.shelfH
                    opacity: root.setup ? 0 : Math.max(0, Math.min(1, (win.m - 0.55) / 0.4))
                    visible: opacity > 0.01 || root.open
                    sourceComponent: shelfBody
                }
                Loader {
                    active: win.hosts
                    anchors.fill: parent
                    opacity: root.setup ? Math.max(0, Math.min(1, (win.m - 0.55) / 0.4)) : 0
                    visible: opacity > 0.01
                    sourceComponent: RecordSetup { id: rs; panel: root; Component.onCompleted: root.setupPanel = rs }
                }
                // Quick Look lives on the island itself, so reading can grow
                // it past the shelf.
                Loader {
                    anchors.fill: parent
                    active: win.hosts
                    z: 30
                    sourceComponent: QuickLook { panel: root }
                    onLoaded: root.quickLook = item
                }
            }
        }
    }

    Component {
        id: shelfBody
        Item {
            id: bodyRoot

            // ── Search ───────────────────────────────────────────────────
            Item {
                id: head
                anchors { left: parent.left; right: parent.right; top: parent.top }
                height: 58
                Text {
                    id: glyph
                    x: 22
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u{f0349}"
                    font.family: Theme.fontGlyph
                    font.pixelSize: 18
                    color: Theme.textTertiary
                }
                Rectangle {
                    id: scope
                    visible: root.filter !== "all"
                    anchors { left: glyph.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
                    width: visible ? scopeRow.implicitWidth + 16 : 0
                    height: 26; radius: 8
                    color: Qt.alpha(Theme.blue, 0.22)
                    border.width: 1
                    border.color: Qt.alpha(Theme.blue, 0.4)
                    Row {
                        id: scopeRow
                        anchors.centerIn: parent
                        spacing: 6
                        Label { anchors.verticalCenter: parent.verticalCenter; text: root.filterLabel(root.filter); size: 12; weight: Theme.wSemibold }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "\u{f0156}"; font.family: Theme.fontGlyph; font.pixelSize: 10; color: Theme.textSecondary }
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onContainsMouseChanged: root.tip(scope, containsMouse, "Show everything", ["⌫"])
                        onClicked: { root.tip(scope, false); root.filter = "all"; root.focusSearch(); }
                    }
                }
                Rectangle {
                    id: whenTag
                    visible: root.whenLabel !== "" && !root.typedDate
                    anchors { left: scope.visible ? scope.right : glyph.right; leftMargin: scope.visible ? 6 : 10; verticalCenter: parent.verticalCenter }
                    width: visible ? whenRow.implicitWidth + 16 : 0
                    height: 26; radius: 8
                    color: Qt.alpha(Theme.orange, 0.20)
                    border.width: 1
                    border.color: Qt.alpha(Theme.orange, 0.42)
                    Row {
                        id: whenRow
                        anchors.centerIn: parent
                        spacing: 6
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "\u{f00ed}"; font.family: Theme.fontGlyph; font.pixelSize: 11; color: Theme.orange }
                        Label { anchors.verticalCenter: parent.verticalCenter; text: root.whenLabel; size: 12; weight: Theme.wSemibold }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "\u{f0156}"; font.family: Theme.fontGlyph; font.pixelSize: 10; color: Theme.textSecondary }
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onContainsMouseChanged: root.tip(whenTag, containsMouse, "Any time")
                        onClicked: { root.tip(whenTag, false); root.setDate(0, 0, ""); root.focusSearch(); }
                    }
                }
                TextInput {
                    id: search
                    Component.onCompleted: root.searchField = search
                    anchors { left: whenTag.visible ? whenTag.right : scope.visible ? scope.right : glyph.right; leftMargin: 12; right: dateBtn.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    color: Theme.textPrimary
                    selectionColor: Qt.alpha(Theme.blue, 0.5)
                    font.family: Theme.fontText
                    font.pixelSize: 18
                    font.variableAxes: ({ "opsz": Theme.opszFor(18), "wght": Theme.wRegular })
                    font.letterSpacing: Theme.tracking(18, false)
                    renderType: Text.NativeRendering
                    cursorDelegate: SpringCaret {}
                    clip: true
                    onTextChanged: root.query = text
                    Label {
                        visible: search.text === ""
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.filter === "all" ? "Search your clipboard" : "Search " + root.filterLabel(root.filter).toLowerCase()
                        size: 18
                        color: Theme.textTertiary
                    }
                    Keys.onPressed: event => root.key(event)
                    Keys.onReleased: event => { if (event.key === Qt.Key_Alt) root.altHeld = false; }
                }
                Rectangle {
                    id: dateBtn
                    Component.onCompleted: root.dateButton = dateBtn
                    anchors { right: typeBtn.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
                    height: 30; radius: 10
                    width: dateRow.implicitWidth + 20
                    color: dateArea.containsMouse || (root.datePicker && root.datePicker.open) ? Theme.pillHover : Theme.pill
                    Row {
                        id: dateRow
                        anchors.centerIn: parent
                        spacing: 6
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "\u{f00ed}"; font.family: Theme.fontGlyph; font.pixelSize: 13; color: Theme.textSecondary }
                        Label { anchors.verticalCenter: parent.verticalCenter; text: root.whenLabel || "Any time"; size: 12; weight: Theme.wMedium }
                    }
                    MouseArea {
                        id: dateArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onContainsMouseChanged: root.tip(dateBtn, containsMouse && !(root.datePicker && root.datePicker.open), "When it was copied", ["⌃", "D"])
                        onClicked: { root.tip(dateBtn, false); if (root.datePicker) root.datePicker.toggle(); root.focusSearch(); }
                    }
                }
                // Close by mouse (Esc, a click outside, or the idle timeout too).
                Rectangle {
                    id: closeBtn
                    anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                    width: 30; height: 30; radius: 15
                    color: closeArea.containsMouse ? Qt.alpha(Theme.red, 0.85) : Theme.pill
                    scale: closeArea.pressed ? 0.92 : 1
                    Behavior on color { ColorAnimation { duration: 80 } }
                    Behavior on scale { NumberAnimation { duration: Theme.pressMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                    Text { anchors.centerIn: parent; text: "\u{f0156}"; font.family: Theme.fontGlyph; font.pixelSize: 13; color: closeArea.containsMouse ? "white" : Theme.textSecondary }
                    MouseArea {
                        id: closeArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onContainsMouseChanged: root.tip(closeBtn, containsMouse, "Close", ["Esc"])
                        onClicked: { root.tip(closeBtn, false); Clipboard.open = false; }
                    }
                }
                Rectangle {
                    id: typeBtn
                    anchors { right: closeBtn.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
                    height: 30; radius: 10
                    width: typeRow.implicitWidth + 20
                    color: typeArea.containsMouse || (root.filterMenu && root.filterMenu.open) ? Theme.pillHover : Theme.pill
                    Row {
                        id: typeRow
                        anchors.centerIn: parent
                        spacing: 6
                        Label { anchors.verticalCenter: parent.verticalCenter; text: root.filterLabel(root.filter); size: 12; weight: Theme.wMedium }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "\u{f0140}"; font.family: Theme.fontGlyph; font.pixelSize: 14; color: Theme.textSecondary }
                    }
                    MouseArea {
                        id: typeArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onContainsMouseChanged: root.tip(typeBtn, containsMouse && !(root.filterMenu && root.filterMenu.open), "Filter by type", ["⇥"])
                        onClicked: { root.tip(typeBtn, false); if (root.filterMenu) root.filterMenu.toggle(); root.focusSearch(); }
                    }
                }
            }

            // ── Shelf of cards ───────────────────────────────────────────
            ListView {
                id: shelf
                Component.onCompleted: root.listView = shelf
                anchors { left: parent.left; right: parent.right; top: head.bottom; leftMargin: 14; rightMargin: 14 }
                height: 252
                orientation: ListView.Horizontal
                spacing: 8
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                cacheBuffer: 600
                model: ScriptModel { values: root.rows; objectProp: "key" }
                delegate: ClipCard { panel: root }
                // Scrolling steps through the items: one wheel notch = one item
                // (the selection moves and the shelf glides to it, 140 ms); a
                // touchpad steps once per 56 px of travel, either axis.
                property real swipe: 0
                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: event => {
                        const px = event.pixelDelta, ad = event.angleDelta;
                        if (px.x !== 0 || px.y !== 0) {
                            shelf.swipe += Math.abs(px.x) > Math.abs(px.y) ? -px.x : -px.y;
                            while (Math.abs(shelf.swipe) >= 56) { root.move(shelf.swipe > 0 ? 1 : -1); shelf.swipe -= shelf.swipe > 0 ? 56 : -56; }
                        } else {
                            const d = Math.abs(ad.x) > Math.abs(ad.y) ? ad.x : ad.y;
                            root.move(d > 0 ? -1 : 1);
                        }
                        event.accepted = true;
                    }
                }
            }
            // Edges fade into the island where there's more to see.
            Rectangle {
                anchors { left: shelf.left; top: shelf.top; bottom: shelf.bottom }
                width: 36
                opacity: shelf.contentX > 4 ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 120 } }
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Theme.glassTintElevated }
                    GradientStop { position: 1; color: "transparent" }
                }
            }
            Rectangle {
                anchors { right: shelf.right; top: shelf.top; bottom: shelf.bottom }
                width: 48
                opacity: shelf.contentX + shelf.width < shelf.contentWidth - 4 ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 120 } }
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 1; color: Theme.glassTintElevated }
                }
            }

            // Loading: the shelf's shape until cliphist answers.
            Row {
                visible: !Clipboard.loaded
                anchors { left: shelf.left; top: shelf.top; leftMargin: 4; topMargin: 4 }
                spacing: 8
                Repeater {
                    model: 5
                    Column {
                        spacing: 10
                        Skeleton { width: 176; height: 182; radius: 16 }
                        Skeleton { width: 130; height: 11 }
                        Skeleton { width: 80; height: 9 }
                    }
                }
            }
            // Empty / no results
            Column {
                visible: Clipboard.loaded && root.entries.length === 0
                anchors.centerIn: shelf
                spacing: 6
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.query ? "\u{f0349}" : "\u{f014c}"
                    font.family: Theme.fontGlyph
                    font.pixelSize: 28
                    color: Theme.textTertiary
                }
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.query ? "No matches" : root.filter === "pinned" ? "No pins yet" : "Nothing here yet"
                    size: 14
                    weight: Theme.wSemibold
                    color: Theme.textSecondary
                }
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.query ? `Nothing matches “${root.query}”.` : root.filter === "pinned" ? "⌃P pins the selected card." : "Copy something and it lands here."
                    size: 12
                    color: Theme.textTertiary
                }
            }

            // ── The selected card, in words ──────────────────────────────
            Item {
                id: detail
                anchors { left: parent.left; right: parent.right; top: shelf.bottom; leftMargin: 22; rightMargin: 22; topMargin: 10 }
                height: 44
                opacity: root.reveal(160)
                Label {
                    id: detailTitle
                    anchors { left: parent.left; right: detailMeta.left; rightMargin: 16; verticalCenter: parent.verticalCenter }
                    elide: Text.ElideRight
                    textFormat: Text.StyledText
                    text: !root.entry ? ""
                        : root.entry.kind === "image" ? "Image"
                        : root.entry.secret && !root.revealed ? "Looks like a secret · ⌃H to show"
                        : Clipboard.marked(root.entry.preview.replace(/\s+/g, " ").slice(0, 200), root.current && root.current.m ? root.current.m.pos : [], Theme.yellow)
                    size: 14
                    weight: Theme.wMedium
                    font.family: root.entry && root.entry.kind === "code" ? Theme.fontMono : Theme.fontText
                }
                Label {
                    id: detailMeta
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    text: root.entry ? root.kindOf(root.entry) + "  ·  " + root.detailOf(root.entry, "") : ""
                    size: 12
                    color: Theme.textTertiary
                }
            }

            // ── Naming a screenshot (⌃S) ─────────────────────────────────
            Rectangle {
                anchors { horizontalCenter: parent.horizontalCenter; bottom: foot.top; bottomMargin: 8 }
                width: 460; height: 40; radius: 13
                z: 21
                visible: opacity > 0.01
                opacity: root.naming ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                color: Qt.rgba(0.11, 0.11, 0.13, 0.98)
                border.width: 1
                border.color: Qt.alpha(Theme.blue, 0.6)
                Text { id: saveGlyph; x: 12; anchors.verticalCenter: parent.verticalCenter; text: "\u{f0193}"; font.family: Theme.fontGlyph; font.pixelSize: 14; color: Theme.textSecondary }
                TextInput {
                    id: nameInput
                    Component.onCompleted: root.nameField = nameInput
                    anchors { left: saveGlyph.right; leftMargin: 10; right: ext.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
                    color: Theme.textPrimary
                    selectionColor: Qt.alpha(Theme.blue, 0.5)
                    font.family: Theme.fontText
                    font.pixelSize: 14
                    renderType: Text.NativeRendering
                    cursorDelegate: SpringCaret {}
                    clip: true
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.finishNaming(true); event.accepted = true; }
                        else if (event.key === Qt.Key_Escape) { root.finishNaming(false); event.accepted = true; }
                    }
                }
                Label { id: ext; anchors { right: hint.left; rightMargin: 10; verticalCenter: parent.verticalCenter } text: "." + (root.entry && root.entry.ext ? root.entry.ext : "png"); size: 13; color: Theme.textTertiary }
                Label { id: hint; anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter } text: "↵ save to Screenshots · esc"; size: 11; color: Theme.textTertiary }
            }

            // ── Feedback ─────────────────────────────────────────────────
            Rectangle {
                anchors { horizontalCenter: parent.horizontalCenter; bottom: foot.top; bottomMargin: 8 }
                width: statusLabel.implicitWidth + 28
                height: 30; radius: 15
                color: Qt.rgba(0.18, 0.18, 0.21, 0.98)
                border.width: 1
                border.color: root.confirmWipe ? Qt.alpha(Theme.red, 0.5) : Qt.rgba(1, 1, 1, 0.12)
                opacity: root.status ? 1 : 0
                visible: opacity > 0.01
                scale: root.status || Theme.reduceMotion ? 1 : 0.96
                z: 20
                Behavior on opacity { NumberAnimation { duration: root.status ? 140 : 100; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                Label { id: statusLabel; anchors.centerIn: parent; text: root.status; size: 12; weight: Theme.wMedium; color: root.confirmWipe ? Theme.red : Theme.textPrimary }
            }

            // ── Footer: the primary action, everything else under ⌃K ──────
            Item {
                id: foot
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 48
                opacity: root.reveal(200)
                Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 14; rightMargin: 14 } height: 1; color: Qt.rgba(1, 1, 1, 0.07) }
                Row {
                    x: 20
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 16
                    visible: root.entry !== null
                    Row {
                        spacing: 7
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "\u{f0192}"; font.family: Theme.fontGlyph; font.pixelSize: 14; color: Theme.textSecondary }
                        Label { anchors.verticalCenter: parent.verticalCenter; text: Clipboard.targetName() ? "Paste to " + Clipboard.targetName() : "Paste"; size: 13; weight: Theme.wMedium }
                        KeyCap { anchors.verticalCenter: parent.verticalCenter; text: "↵" }
                    }
                    Rectangle { width: 1; height: 16; anchors.verticalCenter: parent.verticalCenter; color: Qt.rgba(1, 1, 1, 0.1) }
                    Row {
                        spacing: 6
                        Label { anchors.verticalCenter: parent.verticalCenter; text: "Look"; size: 12; color: Theme.textTertiary }
                        KeyCap { anchors.verticalCenter: parent.verticalCenter; text: "Space" }
                    }
                    Row {
                        spacing: 6
                        Label { anchors.verticalCenter: parent.verticalCenter; text: "Copy"; size: 12; color: Theme.textTertiary }
                        KeyCap { anchors.verticalCenter: parent.verticalCenter; text: "⇧" }
                        KeyCap { anchors.verticalCenter: parent.verticalCenter; text: "↵" }
                    }
                }
                Row {
                    anchors { right: actionsBtn.left; rightMargin: 14; verticalCenter: parent.verticalCenter }
                    spacing: 6
                    Label { anchors.verticalCenter: parent.verticalCenter; text: "Shortcuts"; size: 12; color: Theme.textTertiary }
                    KeyCap { anchors.verticalCenter: parent.verticalCenter; text: "?" }
                }
                Rectangle {
                    id: actionsBtn
                    anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                    height: 30; radius: 10
                    width: actRow.implicitWidth + 20
                    color: actArea.containsMouse || (root.actionMenu && root.actionMenu.open) ? Theme.pillHover : "transparent"
                    scale: actArea.pressed ? 0.97 : 1
                    Behavior on scale { NumberAnimation { duration: Theme.pressMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                    Row {
                        id: actRow
                        anchors.centerIn: parent
                        spacing: 6
                        Label { anchors.verticalCenter: parent.verticalCenter; text: "Actions"; size: 12; weight: Theme.wMedium; color: Theme.textSecondary }
                        KeyCap { anchors.verticalCenter: parent.verticalCenter; text: "⌃" }
                        KeyCap { anchors.verticalCenter: parent.verticalCenter; text: "K" }
                    }
                    MouseArea {
                        id: actArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onContainsMouseChanged: root.tip(actionsBtn, containsMouse && !(root.actionMenu && root.actionMenu.open), "Every action for this card")
                        onClicked: { root.tip(actionsBtn, false); if (root.actionMenu) root.actionMenu.toggle(); root.focusSearch(); }
                    }
                }
            }

            // ── Overlays ─────────────────────────────────────────────────
            DatePicker {
                id: dates
                Component.onCompleted: root.datePicker = dates
                anchorItem: dateBtn
                counts: root.dayCounts
                from: root.fromMs
                to: root.toMs
                onPicked: (from, to, label) => { root.setDate(from, to, label); if (searchField) root.focusSearch(); }
            }
            KeySheet {
                id: sheet
                Component.onCompleted: root.keySheet = sheet
                title: "Clipboard shortcuts"
                sections: root.keySections
            }
            ActionMenu {
                id: actions
                Component.onCompleted: root.actionMenu = actions
                anchorItem: actionsBtn
                title: root.entry ? root.kindOf(root.entry) + " actions" : "Actions"
                items: root.actionItems
                onPicked: id => root.run(id)
            }
            ActionMenu {
                id: types
                Component.onCompleted: root.filterMenu = types
                anchorItem: typeBtn
                below: true
                menuW: 220
                title: "Show"
                items: root.filters.map(f => ({ id: f.id, label: f.label, glyph: f.glyph, keys: f.id === root.filter ? ["✓"] : [] }))
                onPicked: id => { root.filter = id; root.focusSearch(); }
            }
            Tips {
                id: tipLayer
                Component.onCompleted: root.tips = tipLayer
            }
        }
    }

    // ── Keys ─────────────────────────────────────────────────────────────
    function key(event) {
        const k = event.key, m = event.modifiers;
        const ctrl = m & Qt.ControlModifier, shift = m & Qt.ShiftModifier, alt = m & Qt.AltModifier;
        const field = searchField;
        touched();
        if (k === Qt.Key_Alt) { altHeld = true; return; }
        if (keySheet && keySheet.open && keySheet.key(event)) { event.accepted = true; return; }
        if (k === Qt.Key_F1 || (ctrl && k === Qt.Key_Slash) || (k === Qt.Key_Question && field && field.text === "")) {
            if (keySheet) keySheet.open = true;
            event.accepted = true;
            return;
        }
        if (filterMenu && filterMenu.open && filterMenu.key(event)) { event.accepted = true; return; }
        if (datePicker && datePicker.open && datePicker.key(event)) { event.accepted = true; return; }
        if (ctrl && k === Qt.Key_D) { if (datePicker) datePicker.toggle(); event.accepted = true; return; }
        if (alt && k === Qt.Key_Left) { backToLast(); event.accepted = true; return; }
        if (actionMenu && actionMenu.open && actionMenu.key(event)) { event.accepted = true; return; }
        const ql = quickLook && quickLook.open;
        if (ql && k === Qt.Key_Space && shift) { reading = !reading; event.accepted = true; return; }
        if (ql && (k === Qt.Key_Escape || k === Qt.Key_Space || (ctrl && k === Qt.Key_Y))) { quickLook.open = false; reading = false; event.accepted = true; return; }
        if (ctrl && k === Qt.Key_K) { if (actionMenu) actionMenu.toggle(); }
        else if (shift && (k === Qt.Key_Right || k === Qt.Key_Left) && field && field.text === "") {
            const i = entries.findIndex(r => r.key === selKey);
            const j = Math.max(0, Math.min(entries.length - 1, i + (k === Qt.Key_Right ? 1 : -1)));
            if (i >= 0 && entries[j]) { mark(selKey, true); markRange(entries[j].key); }
        }
        else if (ctrl && k === Qt.Key_A && field && field.text === "") markAll();
        else if (k === Qt.Key_Escape && markedCount) clearMarks();
        else if (k === Qt.Key_Right || k === Qt.Key_Down || (ctrl && k === Qt.Key_N)) {
            // → moves the caret while it isn't at the end of the search.
            if (k === Qt.Key_Right && field && field.cursorPosition < field.text.length && !ql) return;
            move(1);
        }
        else if (k === Qt.Key_Left || k === Qt.Key_Up) {
            // ← moves the caret while there's search text to move in.
            if (k === Qt.Key_Left && field && field.text !== "" && field.cursorPosition > 0 && !ql) return;
            move(-1);
        }
        else if (k === Qt.Key_PageDown) move(5);
        else if (k === Qt.Key_PageUp) move(-5);
        else if (ctrl && k === Qt.Key_Home) move(-1e6);
        else if (ctrl && k === Qt.Key_End) move(1e6);
        else if ((k === Qt.Key_Return || k === Qt.Key_Enter) && ctrl) run("open");
        else if ((k === Qt.Key_Return || k === Qt.Key_Enter) && shift) run("copy");
        else if (k === Qt.Key_Return || k === Qt.Key_Enter) run("paste");
        else if (k === Qt.Key_Space && shift && field && field.text === "") reading = true;
        else if ((k === Qt.Key_Space && field && field.text === "") || (ctrl && k === Qt.Key_Y)) run("quicklook");
        else if (ctrl && shift && k === Qt.Key_E) run("nvim");
        else if (ctrl && k === Qt.Key_P) run("pin");
        else if (ctrl && k === Qt.Key_E) run("edit");
        else if (ctrl && k === Qt.Key_O) run("ocr");
        else if (ctrl && k === Qt.Key_S) run("save");
        else if (ctrl && k === Qt.Key_H) run("reveal");
        else if (ctrl && k === Qt.Key_R) { if (quickLook) quickLook.raw = !quickLook.raw; }
        else if (ctrl && shift && k === Qt.Key_Backspace) run("wipe");
        else if ((shift && k === Qt.Key_Delete) || (ctrl && k === Qt.Key_X && field && !field.selectedText)) run("delete");
        else if (k === Qt.Key_Backspace && field && field.text === "" && filter !== "all") filter = "all";
        else if (k === Qt.Key_Tab || k === Qt.Key_Backtab) {
            const i = filters.findIndex(f => f.id === filter);
            filter = filters[(i + (k === Qt.Key_Backtab ? filters.length - 1 : 1)) % filters.length].id;
        }
        else if (alt && k >= Qt.Key_1 && k <= Qt.Key_9) {
            const r = entries[k - Qt.Key_1];
            if (r) { selKey = r.key; run("paste"); }
        }
        else if (k === Qt.Key_Escape) {
            if (field && field.text !== "") field.text = "";
            else if (filter !== "all") filter = "all";
            else if (dateFrom || dateTo) setDate(0, 0, "");
            else Clipboard.open = false;
        }
        else return;
        event.accepted = true;
    }
}
