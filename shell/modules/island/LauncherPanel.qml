// The launcher, grown out of the island (Super+A; replaces rofi's app
// finder). One field, one list: apps, open windows, the rice's own actions
// and a calculator, ranked by the clipboard's fuzzy matcher and by how often
// and how lately you used each (frecency). Empty, it shows what you use most.
//
//   ⌕  term│
//   ▣ Kitty              Terminal                     ↵
//   ▣ Kitty — ~/Projects  Window
//   = 1.5 × 4  → 6        Copy
//
// Keys: type to search, ↑↓ (or ⌃J ⌃K, ⌃N ⌃P, Tab) choose, ↵ open, Esc close.
// Uses: ~/.local/state/rice/launcher.json (counts and times, nothing else).
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Widgets
import qs.config
import qs.components
import qs.services

FocusScope {
    id: launcher
    focus: true

    property string query: ""
    property int current: 0
    property var lastPointer: null
    readonly property int rowH: 50
    readonly property int maxRows: 7

    // A fixed height: a launcher is used a hundred times a day, so it never
    // resizes under your typing (Raycast doesn't either).
    implicitWidth: 640
    implicitHeight: 64 + maxRows * rowH + 46

    // ── Frecency ─────────────────────────────────────────────────────────
    FileView {
        id: store
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/rice/launcher.json"
        printErrors: false
        onLoadFailed: error => { if (error === FileViewError.FileNotFound) writeAdapter(); }
        JsonAdapter {
            id: uses
            property var counts: ({})
        }
    }
    function frecency(id) {
        const u = uses.counts[id];
        if (!u) return 0;
        const days = (Date.now() - u.t) / 86400000;
        return u.n / (1 + days / 7);
    }
    function used(id) {
        const c = Object.assign({}, uses.counts);
        const u = c[id] || { n: 0, t: 0 };
        c[id] = { n: u.n + 1, t: Date.now() };
        uses.counts = c;
        store.writeAdapter();
    }

    // ── Sources ──────────────────────────────────────────────────────────
    readonly property var apps: DesktopEntries.applications.values.filter(e => !e.noDisplay)
    readonly property var actions: [
        { name: "Lock Screen", sub: "Lock now", glyph: "\u{f033e}", run: () => Quickshell.execDetached(["loginctl", "lock-session"]) },
        { name: "Power", sub: "Sleep, restart, shut down", glyph: "\u{f0425}", run: () => Qt.callLater(() => Island.open("power", Island.screen, "key")), keep: true },
        { name: "Settings", sub: "Bar, clock, notifications, motion", glyph: "\u{f0493}", run: () => Qt.callLater(() => Island.open("settings", Island.screen, "key")), keep: true },
        { name: "Themes", sub: "Switch the theme or the wallpaper", glyph: "\u{f03d8}", run: () => Qt.callLater(() => { Island.themeMode = "themes"; Island.open("theme", Island.screen, "key"); }), keep: true },
        { name: "System", sub: "CPU, memory, GPU, updates", glyph: "\u{f0ee0}", run: () => Qt.callLater(() => Island.open("system", Island.screen, "key")), keep: true },
        { name: "Calendar", sub: "This month", glyph: "\u{f00ed}", run: () => Qt.callLater(() => Island.open("calendar", Island.screen, "key")), keep: true },
        { name: "Clipboard", sub: "History and pins", glyph: "\u{f014c}", run: () => Clipboard.toggle("all") },
        { name: "Screen Recording", sub: "Choose a screen, audio and frame rate", glyph: "\u{f044a}", run: () => Clipboard.recordKey() },
        { name: "Screenshot", sub: "Pick an area or a window, then annotate", glyph: "\u{f0104}", run: () => Quickshell.execDetached([Quickshell.env("HOME") + "/Projects/rice/bin/rice-shot", "area"]) },
        { name: "Notifications", sub: "The center", glyph: "\u{f009a}", run: () => Notifs.toggleCenter("notifications", "key") },
        { name: "Do Not Disturb", sub: Notifs.dnd ? "On: turn off" : "Off: turn on", glyph: "\u{f0594}", run: () => { Notifs.dnd = !Notifs.dnd; } },
        { name: "Sound", sub: "Outputs, inputs, the microphone", glyph: "\u{f057e}", run: () => Notifs.toggleCenter("sound", "key") }
    ]

    // A plain arithmetic expression (digits, + - * / % ^ ( ) .) and its value.
    readonly property var calc: {
        const q = query.trim().replace(/×/g, "*").replace(/÷/g, "/").replace(/,/g, ".");
        if (!/^[\d\s+\-*/().%^]+$/.test(q) || !/\d/.test(q) || !/[+\-*/%^]/.test(q)) return null;
        try {
            const v = Function('"use strict"; return (' + q.replace(/\^/g, "**") + ");")();
            if (typeof v !== "number" || !isFinite(v)) return null;
            return { expr: q, value: Math.round(v * 1e10) / 1e10 };
        } catch (e) { return null; }
    }

    // How well `needle` matches: the name fuzzily (letters in order, word
    // starts count most); the other fields (generic name, keywords) only as
    // a whole word start, so "fire" finds Firefox, not every app whose
    // description has an f, an i, an r and an e somewhere.
    function score(needle, name, others) {
        const n = String(name || "").toLowerCase();
        let best = null, pos = [];
        const m = Clipboard.fuzzy(needle, n);
        if (m) {
            // Contiguous and at a word start beats scattered letters.
            const at = n.indexOf(needle);
            best = m.score + (at === 0 ? 60 : at > 0 && /[\s\-_.]/.test(n[at - 1]) ? 40 : at > 0 ? 15 : 0);
            pos = at >= 0 ? Array.from({ length: needle.length }, (_, k) => at + k) : m.pos;
        }
        for (const f of others || []) {
            const t = String(f || "").toLowerCase();
            const at = t.search(new RegExp("(^|[\\s\\-_.,;])" + needle.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
            if (at >= 0 && (best === null || 18 * needle.length > best)) best = Math.max(best || 0, 18 * needle.length);
        }
        return best === null ? null : { score: best, pos: pos };
    }

    // One list, in sections: the best match first (Top Hit), then by kind.
    // Empty: what you open most, then the rice's actions. Section headers are
    // rows the selection skips.
    readonly property var results: {
        const q = query.trim().toLowerCase();
        const out = [];
        const section = (title, rows) => { if (rows.length) out.push({ kind: "header", name: title }, ...rows); };
        if (!q) {
            const top = apps.map(e => ({ e: e, f: frecency(e.id) })).filter(x => x.f > 0).sort((a, b) => b.f - a.f).slice(0, 5);
            section("Frequent", top.map(x => ({ kind: "app", entry: x.e, name: x.e.name, sub: x.e.genericName || x.e.comment || "", icon: x.e.icon })));
            section("Actions", actions.slice().sort((a, b) => frecency("action:" + b.name) - frecency("action:" + a.name)).slice(0, top.length ? 4 : 8)
                                      .map(a => ({ kind: "action", action: a, name: a.name, sub: a.sub, glyph: a.glyph })));
            return out;
        }
        const appsHit = [], winHit = [], actHit = [];
        for (const e of apps) {
            const m = score(q, e.name, [e.genericName, (e.keywords || []).join(" "), e.id]);
            if (m) appsHit.push({ kind: "app", entry: e, name: e.name, pos: m.pos, sub: e.genericName || e.comment || "", icon: e.icon, rank: m.score + Math.min(40, frecency(e.id) * 8) });
        }
        for (const t of Hyprland.toplevels.values) {
            const cls = t.lastIpcObject ? (t.lastIpcObject.class || "") : "";
            const app = cls ? DesktopEntries.heuristicLookup(cls) : null;
            const m = score(q, t.title, [cls, app ? app.name : ""]);
            if (m) winHit.push({ kind: "window", toplevel: t, name: t.title || cls, pos: m.pos, sub: (app ? app.name : cls) + (t.workspace ? " · workspace " + t.workspace.name : ""), icon: app ? app.icon : cls.toLowerCase(), rank: m.score * 0.85 });
        }
        for (const a of actions) {
            const m = score(q, a.name, [a.sub]);
            if (m) actHit.push({ kind: "action", action: a, name: a.name, pos: m.pos, sub: a.sub, glyph: a.glyph, rank: m.score * 0.9 + Math.min(20, frecency("action:" + a.name) * 4) });
        }
        // Weak matches go when a strong one exists (fuzzy noise).
        const all = [...appsHit, ...winHit, ...actHit];
        const bestRank = all.reduce((b, r) => Math.max(b, r.rank), 0);
        const keep = r => r.rank >= bestRank * 0.35;
        const by = rows => rows.filter(keep).sort((a, b) => b.rank - a.rank);
        if (calc) section("Calculator", [{ kind: "calc", name: String(calc.value), sub: calc.expr + " =", glyph: "=" }]);
        const top = all.filter(keep).sort((a, b) => b.rank - a.rank)[0];
        if (top) section("Top Hit", [top]);
        section("Applications", by(appsHit).filter(r => r !== top).slice(0, 8));
        section("Windows", by(winHit).filter(r => r !== top).slice(0, 5));
        section("Actions", by(actHit).filter(r => r !== top).slice(0, 4));
        return out;
    }
    readonly property int selectable: results.filter(r => r.kind !== "header").length
    onResultsChanged: current = results.findIndex(r => r.kind !== "header")
    // A ListView drops a bound currentIndex when its model changes: set it.
    onCurrentChanged: Qt.callLater(() => { list.currentIndex = current; })

    function run(r) {
        if (!r) return;
        if (r.kind === "calc") {
            Quickshell.execDetached(["wl-copy", r.name]);
        } else if (r.kind === "app") {
            used(r.entry.id);
            r.entry.execute();
        } else if (r.kind === "window") {
            Hyprland.dispatch("focuswindow address:0x" + r.toplevel.address);
        } else if (r.kind === "action") {
            used("action:" + r.name);
            if (!r.action.keep) Island.close();
            r.action.run();
            return;
        }
        Island.close();
    }
    function marked(name, pos) {
        const esc = c => c === "<" ? "&lt;" : c === ">" ? "&gt;" : c === "&" ? "&amp;" : c;
        const hit = new Set(pos);
        let out = "";
        for (let i = 0; i < name.length; i++)
            out += hit.has(i) ? "<font color=\"" + Theme.accent + "\">" + esc(name[i]) + "</font>" : esc(name[i]);
        return out;
    }
    function move(d) {
        if (!selectable) return;
        let i = current;
        do { i = (i + d + results.length) % results.length; } while (results[i].kind === "header");
        current = i;
        list.positionViewAtIndex(current, ListView.Contain);
        if (current <= 1) list.positionViewAtBeginning();
    }

    // ── Search ───────────────────────────────────────────────────────────
    Item {
        id: search
        x: 18; y: 12
        width: parent.width - 36
        height: 40
        Text {
            id: lens
            anchors.verticalCenter: parent.verticalCenter
            text: "\u{f0349}"
            font.family: Theme.fontGlyph
            font.pixelSize: 18
            color: Theme.textTertiary
        }
        TextInput {
            id: field
            anchors { left: lens.right; leftMargin: 12; right: parent.right; verticalCenter: parent.verticalCenter }
            focus: true
            font.family: Theme.fontText
            font.pixelSize: 19
            font.variableAxes: ({ "opsz": Theme.opszFor(19), "wght": Theme.wRegular })
            color: Theme.textPrimary
            selectionColor: Qt.rgba(1, 1, 1, 0.25)
            selectedTextColor: Theme.textPrimary
            cursorDelegate: Rectangle { width: 2; radius: 1; color: Theme.blue; visible: field.cursorVisible }
            onTextChanged: { launcher.query = text; Island.lastQuery = text; }
            // The last search comes back, selected: typing replaces it, ↵ repeats it.
            Component.onCompleted: { text = Island.lastQuery; selectAll(); }
            Keys.onPressed: event => {
                const k = event.key, ctrl = event.modifiers & Qt.ControlModifier;
                if (k === Qt.Key_Down || k === Qt.Key_Tab || (ctrl && (k === Qt.Key_J || k === Qt.Key_N))) launcher.move(1);
                else if (k === Qt.Key_Up || k === Qt.Key_Backtab || (ctrl && (k === Qt.Key_K || k === Qt.Key_P))) launcher.move(-1);
                else if (k === Qt.Key_Return || k === Qt.Key_Enter) launcher.run(launcher.results[launcher.current]);
                else return;
                event.accepted = true;
            }
            Label {
                visible: !field.text
                anchors.verticalCenter: parent.verticalCenter
                text: "Search apps, windows and actions"
                size: 19
                color: Theme.textTertiary
            }
        }
    }
    Rectangle { x: 0; y: 63; width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.08) }

    // ── Results ──────────────────────────────────────────────────────────
    ListView {
        id: list
        x: 8; y: 64
        width: parent.width - 16
        height: launcher.maxRows * launcher.rowH
        clip: true
        model: launcher.results
        boundsBehavior: Flickable.StopAtBounds
        highlightMoveDuration: Theme.reduceMotion ? 0 : 110
        highlightMoveVelocity: -1
        highlight: Rectangle { radius: 12; color: Qt.rgba(1, 1, 1, 0.10) }

        delegate: Item {
            id: row
            required property var modelData
            required property int index
            readonly property bool on: index === launcher.current
            readonly property bool header: modelData.kind === "header"
            width: list.width
            height: header ? 30 : launcher.rowH

            Label {
                visible: row.header
                x: 14; anchors.bottom: parent.bottom; anchors.bottomMargin: 6
                text: row.modelData.name
                size: 11; weight: Theme.wSemibold; color: Theme.textTertiary
                extraTracking: 0.4
            }

            Item {
                id: iconBox
                visible: !row.header
                x: 12; anchors.verticalCenter: parent.verticalCenter
                width: 32; height: 32
                readonly property string path: row.modelData.icon ? Quickshell.iconPath(row.modelData.icon, true) : ""
                IconImage { anchors.fill: parent; visible: iconBox.path !== ""; source: iconBox.path; asynchronous: true }
                Rectangle {
                    visible: iconBox.path === ""
                    anchors.fill: parent; radius: 9
                    color: Theme.pill
                    Text {
                        anchors.centerIn: parent
                        text: row.modelData.glyph || "\u{f0b2a}"
                        font.family: row.modelData.kind === "calc" ? Theme.fontRounded : Theme.fontGlyph
                        font.pixelSize: row.modelData.kind === "calc" ? 18 : 17
                        color: Theme.textSecondary
                    }
                }
            }
            Column {
                visible: !row.header
                anchors { left: iconBox.right; leftMargin: 12; right: hint.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                spacing: 1
                // The letters you typed, in the accent.
                Label {
                    width: parent.width; elide: Text.ElideRight
                    textFormat: row.modelData.pos && row.modelData.pos.length ? Text.StyledText : Text.PlainText
                    text: row.modelData.pos && row.modelData.pos.length ? launcher.marked(row.modelData.name, row.modelData.pos) : row.modelData.name
                    size: row.modelData.kind === "calc" ? 17 : 14; weight: Theme.wMedium; rounded: row.modelData.kind === "calc"
                }
                Label { visible: text !== ""; width: parent.width; elide: Text.ElideRight; text: row.modelData.sub; size: 12; color: Theme.textTertiary }
            }
            Row {
                id: hint
                anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                spacing: 8
                opacity: row.on && !row.header ? 1 : 0
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: ({ app: "Open", window: "Switch to", action: "Run", calc: "Copy" })[row.modelData.kind]
                    size: 12
                    color: Theme.textSecondary
                }
                KeyCap { anchors.verticalCenter: parent.verticalCenter; text: "↩" }
            }
            MouseArea {
                anchors.fill: parent
                enabled: !row.header
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                // Only a pointer that moves picks: one resting where the list
                // opens must not steal the selection from the keyboard.
                // (Qt also reports a "move" when rows appear under a still
                // pointer: compare screen positions.)
                onPositionChanged: mouse => {
                    const g = mapToGlobal(mouse.x, mouse.y);
                    const was = launcher.lastPointer;
                    launcher.lastPointer = g;
                    if (was && (g.x !== was.x || g.y !== was.y)) launcher.current = row.index;
                }
                onClicked: launcher.run(row.modelData)
            }
        }

        Label {
            visible: launcher.selectable === 0 && launcher.query.trim() !== ""
            anchors.centerIn: parent
            text: "No results for “" + launcher.query.trim() + "”"
            size: 13
            color: Theme.textTertiary
        }
    }

    // ── Footer ───────────────────────────────────────────────────────────
    Rectangle { x: 0; y: parent.height - 46; width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.06) }
    Row {
        anchors { left: parent.left; leftMargin: 20; bottom: parent.bottom; bottomMargin: 14 }
        spacing: 16
        Repeater {
            model: [["↑↓", "Choose"], ["↩", "Open"], ["esc", "Close"]]
            Row {
                required property var modelData
                spacing: 6
                KeyCap { anchors.verticalCenter: parent.verticalCenter; text: parent.modelData[0] }
                Label { anchors.verticalCenter: parent.verticalCenter; text: parent.modelData[1]; size: 12; color: Theme.textTertiary }
            }
        }
    }
    Label {
        anchors { right: parent.right; rightMargin: 20; bottom: parent.bottom; bottomMargin: 15 }
        text: launcher.query ? launcher.selectable + (launcher.selectable === 1 ? " result" : " results") : ""
        size: 12
        color: Theme.textTertiary
    }
}
