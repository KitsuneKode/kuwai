// Clipboard (Super+V): history with previews, fzf search, pins.
//
//   ⌕ [Images ×] search…                                 All types ⌄
//   ┌ list ─────────────────┐ ┌ preview ───────────────────────────┐
//   │ PINNED                │ │ the entry in full: an image at its │
//   │ ▣ Image 2525 × 1352   │ │ size, a colour with its values,    │
//   │ TODAY                 │ │ text (mono for code); secrets      │
//   │ ⌘ npm run dev     2m  │ │ masked until ⌃H                    │
//   └───────────────────────┘ └────────────────────────────────────┘
//   ⎘ Paste to Kitty ↵   Copy ⇧↵                         Actions ⌃K
//
// It works like Raycast's clipboard: ↵ pastes into the window you came from
// (named in the footer; terminals get Ctrl+Shift+V), ⌃K opens every action
// with its shortcut, Space opens Quick Look (the row grows into the panel),
// ⌃E edits before pasting. Keys:
//   ↑↓ PgUp PgDn ⌃Home ⌃End   move           ⇥ ⇧⇥   filter
//   ↵ paste  ⇧↵ copy  ⌃↵ open with its app   ⌥1–9   paste the nth (hold ⌥ to see)
//   Space/⌃Y Quick Look  ⌃E edit  ⌃P pin      ⌃O     text from an image (OCR)
//   ⌃S save image  ⇧⌦/⌃X delete  ⌃H show secret  ⌃⇧⌫ twice: clear history
//   Esc: the menu, Quick Look, the search, the filter, then closes.
//
// Motion: it's opened from the keyboard many times a day, so the panel
// itself just appears (a 110ms fade); the first rows then settle in 18ms
// apart, which reads as the list arriving rather than as waiting. Menus and
// Quick Look morph out of what opened them on the moderate spring.
// Reduce Motion: no travel, no stagger.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
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
    property Item previewPane: null
    property Item actionMenu: null
    property Item filterMenu: null
    property Item quickLook: null

    readonly property var filters: [
        { id: "all", label: "All types", glyph: "\u{f014c}" }, { id: "pinned", label: "Pinned", glyph: "\u{f0403}" },
        { id: "text", label: "Text", glyph: "\u{f09ed}" }, { id: "image", label: "Images", glyph: "\u{f02e9}" },
        { id: "link", label: "Links", glyph: "\u{f0339}" }, { id: "code", label: "Code", glyph: "\u{f0169}" },
        { id: "color", label: "Colours", glyph: "\u{f03d8}" }
    ]
    function filterLabel(id) { return (filters.find(f => f.id === id) || filters[0]).label; }

    // ── Results ──────────────────────────────────────────────────────────
    readonly property var ts: Clipboard.terms(query)
    function searchText(e) {
        if (e.kind === "image") return "image " + e.ext + " " + e.dims;
        if (e.secret) return "secret key token";
        return e.preview;
    }
    function inFilter(e) {
        switch (filter) {
        case "pinned": return Clipboard.isPinned(e);
        case "text": return ["text", "email", "path"].includes(e.kind);
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
            if (!inFilter(x.e)) continue;
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
    onRowsChanged: if (entries && !current) selKey = entries.length ? entries[0].key : ""
    onQueryChanged: first()
    onFilterChanged: first()
    function first() {
        selKey = entries.length ? entries[0].key : "";
        if (listView) listView.positionViewAtBeginning();
    }
    onSelKeyChanged: {
        revealed = false;
        const i = rows.findIndex(r => r.key === selKey);
        if (i >= 0 && listView) listView.positionViewAtIndex(i, ListView.Contain);
    }
    function focusSearch() { if (searchField) searchField.forceActiveFocus(); }
    function select(key) { selKey = key; focusSearch(); }
    function move(step) {
        if (!entries.length) return;
        const i = entries.findIndex(r => r.key === selKey);
        selKey = entries[Math.max(0, Math.min(entries.length - 1, (i < 0 ? 0 : i) + step))].key;
    }

    // ── Actions ──────────────────────────────────────────────────────────
    // The full text if the preview has it, else what the list knows.
    function textOf(e) { return previewPane && previewPane.full ? previewPane.full : e.preview; }
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
        const t = txt ? (previewPane && previewPane.full ? previewPane.full : e.preview) : "";
        const where = Clipboard.targetName();
        const a = [
            { id: "paste", label: where ? "Paste to " + where : "Paste", glyph: "\u{f0192}", keys: ["↵"], section: "Entry" },
            { id: "copy", label: "Copy to clipboard", glyph: "\u{f018f}", keys: ["⇧", "↵"], section: "Entry" },
            { id: "open", label: e.kind === "link" ? "Open in browser" : img ? "Open in image viewer" : "Open with default app", glyph: "\u{f03cc}", keys: ["⌃", "↵"], section: "Entry" },
            { id: "quicklook", label: "Quick Look", glyph: "\u{f0208}", keys: ["Space"], section: "Entry" },
            { id: "pin", label: Clipboard.isPinned(e) ? "Unpin" : "Pin", glyph: "\u{f0403}", keys: ["⌃", "P"], section: "Entry" }
        ];
        if (txt) a.push({ id: "edit", label: "Edit, then paste", glyph: "\u{f03eb}", keys: ["⌃", "E"], section: "Entry" });
        if (img) {
            a.push({ id: "ocr", label: "Copy text from image", glyph: "\u{f05e7}", keys: ["⌃", "O"], section: "Image" });
            a.push({ id: "save", label: "Save to Pictures/Clipboard", glyph: "\u{f0193}", keys: ["⌃", "S"], section: "Image" });
        }
        if (txt) {
            a.push({ id: "trim", label: "Paste trimmed, one line", glyph: "\u{f0a73}", section: "Paste as" });
            a.push({ id: "upper", label: "Paste as UPPERCASE", glyph: "\u{f0b34}", section: "Paste as" });
            a.push({ id: "lower", label: "Paste as lowercase", glyph: "\u{f0b33}", section: "Paste as" });
            if (isJson(t)) a.push({ id: "json", label: "Paste formatted JSON", glyph: "\u{f0626}", section: "Paste as" });
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
        const e = entry;
        if (!e && id !== "wipe") return;
        const t = e ? textOf(e) : "";
        switch (id) {
        case "paste": Clipboard.paste(e); break;
        case "copy": Clipboard.copy(e); break;
        case "open": Clipboard.openWith(e); break;
        case "pin": Clipboard.togglePin(e); say(Clipboard.isPinned(e) ? "Unpinned" : "Pinned"); break;
        case "quicklook": toggleQuickLook(); break;
        case "edit": if (previewPane) previewPane.editing = true; break;
        case "reveal": revealed = !revealed; break;
        case "delete": move(1); if (entry === e) move(-1); Clipboard.remove(e); break;
        case "ocr":
            say("Reading text…", true);
            Clipboard.ocr(e, txt => {
                if (!txt) { say("No text found in the image"); return; }
                Clipboard.run(["copy-text", txt]);
                say(`Copied ${txt.length.toLocaleString()} characters of text`);
            });
            break;
        case "save": Clipboard.save(e, path => say(path ? "Saved " + path.replace(Quickshell.env("HOME"), "~") : "Couldn't save")); break;
        case "trim": Clipboard.pasteText(t.replace(/\s+/g, " ").trim()); break;
        case "upper": Clipboard.pasteText(t.toUpperCase()); break;
        case "lower": Clipboard.pasteText(t.toLowerCase()); break;
        case "json": Clipboard.pasteText(JSON.stringify(JSON.parse(t), null, 2)); break;
        case "urlenc": Clipboard.pasteText(encodeURIComponent(t.trim())); break;
        case "urldec": try { Clipboard.pasteText(decodeURIComponent(t.trim())); } catch (err) { say("Not a valid encoded URL"); } break;
        case "b64": { const d = b64decode(t); if (d) Clipboard.pasteText(d); else say("Not valid Base64 text"); } break;
        case "secrets": Clipboard.forgetSecrets(); say("Forgot everything that looked like a secret"); break;
        case "wipe":
            if (confirmWipe) { confirmWipe = false; Clipboard.wipe(); say("History cleared; pins kept"); }
            else { confirmWipe = true; wipeWindow.restart(); say("Press ⌃⇧⌫ again to clear all history", true); }
            break;
        }
    }
    property bool confirmWipe: false
    Timer { id: wipeWindow; interval: 3000; onTriggered: root.confirmWipe = false }

    // A short line of feedback above the footer.
    property string status: ""
    property bool statusSticky: false
    function say(msg, sticky) { status = msg; statusSticky = !!sticky; statusTimer.restart(); }
    Timer { id: statusTimer; interval: 2600; onTriggered: if (!root.statusSticky || !root.confirmWipe) root.status = "" }

    function toggleQuickLook() {
        if (!quickLook) return;
        if (quickLook.open) { quickLook.open = false; return; }
        if (!entry) return;
        quickLook.entry = entry;
        quickLook.from = selRow ? selRow.markItem.mapToItem(quickLook, 0, 0, selRow.markItem.width, selRow.markItem.height)
                                : Qt.rect(quickLook.width / 2 - 16, quickLook.height / 2 - 16, 32, 32);
        quickLook.open = true;
    }
    onEntryChanged: if (quickLook && quickLook.open && entry) quickLook.entry = entry

    // ── Presentation helpers (rows and preview use these) ─────────────────
    function glyphOf(e) {
        if (e.secret) return "\u{f0306}";                                     // key
        return ({ link: "\u{f0339}", path: "\u{f024b}", email: "\u{f01ee}", code: "\u{f0169}", file: "\u{f0214}" })[e.kind] || "\u{f09ed}";
    }
    function toneOf(e) {
        if (!e) return Theme.textSecondary;
        return ({ link: Theme.blue, path: "#64d2ff", email: "#5e5ce6", code: Theme.green, file: Theme.textSecondary })[e.kind] || Theme.textSecondary;
    }
    function ago(t) {
        if (!t) return "";
        const m = Math.floor((Date.now() - t) / 60000);
        return m < 1 ? "now" : m < 60 ? m + "m" : m < 1440 ? Math.floor(m / 60) + "h" : Math.floor(m / 1440) + "d";
    }
    function metaOf(e) {
        const kind = e.secret ? "Secret" : ({ image: "Image", link: "Link", path: "Path", email: "Email", code: "Code", color: "Colour", file: "File" })[e.kind] || "Text";
        const parts = [kind];
        if (e.kind === "image") parts.push([e.ext.toUpperCase(), e.size].filter(x => x).join(" · "));
        else if (e.kind === "link") parts.push(e.preview.replace(/^\w+:\/\//, "").split("/")[0]);
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

    // ── Open/close ───────────────────────────────────────────────────────
    property real p: 0
    Behavior on p {
        enabled: !Theme.reduceMotion
        NumberAnimation { duration: root.open ? 110 : 80; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
    }
    // Reveal clock: the rows' stagger reads it (reveal(ms) → 0…1).
    property real clock: 1000
    NumberAnimation { id: clockRun; target: root; property: "clock"; from: 0; to: 400; duration: 400 }
    function reveal(ms) {
        if (Theme.reduceMotion) return 1;
        const k = Math.max(0, Math.min(1, (clock - ms) / 150));
        return 1 - Math.pow(1 - k, 3);
    }
    onOpenChanged: {
        armed = false;
        altHeld = false;
        if (open) {
            query = "";
            if (searchField) searchField.text = "";
            filter = Clipboard.startFilter;
            first();
            confirmWipe = false;
            status = "";
            if (actionMenu) actionMenu.open = false;
            if (filterMenu) filterMenu.open = false;
            if (quickLook) { quickLook.open = false; }
            if (previewPane) previewPane.editing = false;
            clock = 0;
            armSoon.restart();
            showSoon.restart();
        } else {
            p = 0;
        }
    }
    // One frame for the surface to take its size, then in.
    Timer { id: showSoon; interval: 16; onTriggered: { root.p = root.open ? 1 : 0; if (root.open) clockRun.restart(); } }
    Timer { id: armSoon; interval: 140; onTriggered: { root.armed = root.open; if (root.open) root.focusSearch(); } }
    readonly property bool shownAtAll: open || p > 0.001

    // ── Surface: one per monitor, mapped for good ────────────────────────
    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: win
            required property ShellScreen modelData
            screen: modelData
            readonly property bool hosts: (Clipboard.screen || Quickshell.screens[0]) === modelData
            readonly property bool up: hosts && root.shownAtAll
            readonly property int cardW: Math.min(880, modelData.width - 80)
            readonly property int cardH: Math.min(580, modelData.height - 160)

            anchors.top: true
            margins.top: Math.round(modelData.height * 0.13)
            implicitWidth: up ? cardW + 120 : 1
            implicitHeight: up ? cardH + 110 : 1
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.namespace: "rice-clipboard"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: up && root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            mask: Region { item: win.up ? card : null }

            HyprlandFocusGrab {
                windows: [win]
                active: win.up && root.open && root.armed
                onCleared: Clipboard.open = false
            }

            Elevation { target: card; radius: card.radius; strength: root.p }
            GlassCard {
                id: card
                visible: win.up
                x: 60; y: 10
                width: win.cardW
                height: win.cardH
                radius: 22
                tint: Theme.glassTintElevated
                opacity: root.p
                scale: Theme.reduceMotion ? 1 : 0.985 + 0.015 * root.p
                transformOrigin: Item.Top

                // The content lives on the hosting monitor's surface only.
                Loader {
                    anchors.fill: parent
                    active: win.hosts
                    sourceComponent: body
                }
            }
        }
    }

    Component {
        id: body
        Item {
            id: bodyRoot

            // ── Search ───────────────────────────────────────────────────
            Item {
                id: head
                anchors { left: parent.left; right: parent.right; top: parent.top }
                height: 58
                Text {
                    id: glyph
                    x: 20
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u{f0349}"                                   // magnify
                    font.family: Theme.fontGlyph
                    font.pixelSize: 18
                    color: Theme.textTertiary
                }
                // Scope tag: the filter lives in the search, like Spotlight's
                // tokens; ⌫ on an empty search takes it off.
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
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.filter = "all"; root.focusSearch(); } }
                }
                TextInput {
                    id: search
                    Component.onCompleted: root.searchField = search
                    anchors { left: scope.visible ? scope.right : glyph.right; leftMargin: 12; right: typeBtn.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
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
                        text: root.filter === "all" ? "Search clipboard" : "Search " + root.filterLabel(root.filter).toLowerCase()
                        size: 18
                        color: Theme.textTertiary
                    }
                    Keys.onPressed: event => root.key(event)
                    Keys.onReleased: event => { if (event.key === Qt.Key_Alt) root.altHeld = false; }
                }
                // Type filter, Raycast-style: a quiet pill that opens a menu.
                Rectangle {
                    id: typeBtn
                    Component.onCompleted: root.typeButton = typeBtn
                    anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
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
                    MouseArea { id: typeArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { if (root.filterMenu) root.filterMenu.toggle(); root.focusSearch(); } }
                }
                Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: Qt.rgba(1, 1, 1, 0.07) }
            }

            // ── List ─────────────────────────────────────────────────────
            ListView {
                id: list
                Component.onCompleted: root.listView = list
                anchors { left: parent.left; top: head.bottom; bottom: foot.top; leftMargin: 8; topMargin: 6; bottomMargin: 4 }
                width: 350
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                cacheBuffer: 480
                model: ScriptModel { values: root.rows; objectProp: "key" }
                delegate: ClipRow { panel: root }
            }
            // Scroll edges fade into the glass instead of cutting (Skiper's
            // scroll fade): only where there's more to scroll to.
            Rectangle {
                anchors { left: list.left; right: list.right; top: list.top }
                height: 22
                opacity: list.contentY > 4 ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 120 } }
                gradient: Gradient {
                    GradientStop { position: 0; color: Theme.glassTintElevated }
                    GradientStop { position: 1; color: "transparent" }
                }
            }
            Rectangle {
                anchors { left: list.left; right: list.right; bottom: list.bottom }
                height: 28
                opacity: list.contentY + list.height < list.contentHeight - 4 ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 120 } }
                gradient: Gradient {
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 1; color: Theme.glassTintElevated }
                }
            }
            ScrollHint { flickable: list; anchors { right: list.right; top: list.top; bottom: list.bottom } }

            // Loading: the list's shape until cliphist answers.
            Column {
                visible: !Clipboard.loaded
                anchors { left: list.left; top: list.top; leftMargin: 8; topMargin: 8 }
                spacing: 14
                Repeater {
                    model: 7
                    Row {
                        required property int index
                        spacing: 11
                        Skeleton { width: 34; height: 34; radius: 9 }
                        Column {
                            spacing: 7
                            anchors.verticalCenter: parent.verticalCenter
                            Skeleton { width: 210 - (index % 3) * 44; height: 11 }
                            Skeleton { width: 92; height: 9 }
                        }
                    }
                }
            }

            // Empty / no results
            Column {
                visible: Clipboard.loaded && root.entries.length === 0
                anchors.centerIn: list
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
                    text: root.query ? `Nothing matches “${root.query}”.` : root.filter === "pinned" ? "⌃P pins the selected entry." : "Copy something and it shows up here."
                    size: 12
                    color: Theme.textTertiary
                }
            }

            Rectangle {
                id: split
                anchors { left: list.right; leftMargin: 8; top: head.bottom; bottom: foot.top }
                width: 1
                color: Qt.rgba(1, 1, 1, 0.07)
            }

            // ── Preview ──────────────────────────────────────────────────
            ClipPreview {
                id: preview
                Component.onCompleted: root.previewPane = preview
                panel: root
                entry: root.entry
                revealed: root.revealed
                opacity: root.reveal(60)
                anchors { left: split.right; right: parent.right; top: head.bottom; bottom: foot.top; leftMargin: 18; rightMargin: 18; topMargin: 16; bottomMargin: 12 }
            }

            // ── Feedback ─────────────────────────────────────────────────
            Rectangle {
                anchors { horizontalCenter: parent.horizontalCenter; bottom: foot.top; bottomMargin: 10 }
                width: statusLabel.implicitWidth + 28
                height: 30; radius: 15
                color: Qt.rgba(0.18, 0.18, 0.21, 0.97)
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

            // ── Footer: the primary action, and everything else under ⌃K ──
            Item {
                id: foot
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 46
                opacity: root.reveal(90)
                Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top } height: 1; color: Qt.rgba(1, 1, 1, 0.07) }
                Row {
                    x: 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 16
                    Row {
                        spacing: 7
                        visible: root.entry !== null
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "\u{f0192}"; font.family: Theme.fontGlyph; font.pixelSize: 14; color: Theme.textSecondary }
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.previewPane && root.previewPane.editing ? "Paste edited text" : Clipboard.targetName() ? "Paste to " + Clipboard.targetName() : "Paste"
                            size: 13
                            weight: Theme.wMedium
                        }
                        KeyCap { anchors.verticalCenter: parent.verticalCenter; text: root.previewPane && root.previewPane.editing ? "⌃↵" : "↵" }
                    }
                    Rectangle { width: 1; height: 16; anchors.verticalCenter: parent.verticalCenter; color: Qt.rgba(1, 1, 1, 0.1); visible: root.entry !== null }
                    Row {
                        spacing: 6
                        visible: root.entry !== null
                        Label { anchors.verticalCenter: parent.verticalCenter; text: "Quick Look"; size: 12; color: Theme.textTertiary }
                        KeyCap { anchors.verticalCenter: parent.verticalCenter; text: "Space" }
                    }
                }
                Rectangle {
                    id: actionsBtn
                    Component.onCompleted: root.actionsButton = actionsBtn
                    anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
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
                    MouseArea { id: actArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { if (root.actionMenu) root.actionMenu.toggle(); root.focusSearch(); } }
                }
            }

            // ── Overlays: Quick Look and the two menus ────────────────────
            QuickLook {
                id: ql
                Component.onCompleted: root.quickLook = ql
                panel: root
            }
            ActionMenu {
                id: actions
                Component.onCompleted: root.actionMenu = actions
                anchorItem: actionsBtn
                title: root.entry ? (root.entry.kind === "image" ? "Image" : root.entry.secret ? "Secret" : "Entry") + " actions" : "Actions"
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
        }
    }
    property Item typeButton: null
    property Item actionsButton: null

    // ── Keys ─────────────────────────────────────────────────────────────
    function key(event) {
        const k = event.key, m = event.modifiers;
        const ctrl = m & Qt.ControlModifier, shift = m & Qt.ShiftModifier, alt = m & Qt.AltModifier;
        const field = searchField;
        if (k === Qt.Key_Alt) { altHeld = true; return; }
        // Menus first: they take every key while open.
        if (filterMenu && filterMenu.open && filterMenu.key(event)) { event.accepted = true; return; }
        if (actionMenu && actionMenu.open && actionMenu.key(event)) { event.accepted = true; return; }
        // Quick Look: Space/Esc close it, arrows keep browsing.
        if (quickLook && quickLook.open && (k === Qt.Key_Escape || k === Qt.Key_Space || (ctrl && k === Qt.Key_Y))) {
            quickLook.open = false; event.accepted = true; return;
        }
        if (ctrl && k === Qt.Key_K) { if (actionMenu) actionMenu.toggle(); }
        else if (k === Qt.Key_Down || (ctrl && k === Qt.Key_N)) move(1);
        else if (k === Qt.Key_Up || (ctrl && k === Qt.Key_J && false)) move(-1);
        else if (k === Qt.Key_PageDown) move(8);
        else if (k === Qt.Key_PageUp) move(-8);
        else if (ctrl && k === Qt.Key_Home) move(-1e6);
        else if (ctrl && k === Qt.Key_End) move(1e6);
        else if ((k === Qt.Key_Return || k === Qt.Key_Enter) && ctrl) run("open");
        else if ((k === Qt.Key_Return || k === Qt.Key_Enter) && shift) run("copy");
        else if (k === Qt.Key_Return || k === Qt.Key_Enter) run("paste");
        else if ((k === Qt.Key_Space && field && field.text === "") || (ctrl && k === Qt.Key_Y)) run("quicklook");
        else if (ctrl && k === Qt.Key_P) run("pin");
        else if (ctrl && k === Qt.Key_E) run("edit");
        else if (ctrl && k === Qt.Key_O) run("ocr");
        else if (ctrl && k === Qt.Key_S) run("save");
        else if (ctrl && k === Qt.Key_H) run("reveal");
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
            else Clipboard.open = false;
        }
        else return;
        event.accepted = true;
    }
}
