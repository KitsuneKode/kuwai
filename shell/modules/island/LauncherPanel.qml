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

    function score(needle, fields) {
        let best = null;
        for (let i = 0; i < fields.length; i++) {
            if (!fields[i]) continue;
            const m = Clipboard.fuzzy(needle, String(fields[i]).toLowerCase());
            if (m) {
                const s = m.score * (i === 0 ? 1 : 0.6);
                if (best === null || s > best) best = s;
            }
        }
        return best;
    }

    readonly property var results: {
        const q = query.trim().toLowerCase();
        const out = [];
        if (calc) out.push({ kind: "calc", name: String(calc.value), sub: calc.expr + " =", glyph: "=", rank: 1e9 });
        if (!q) {
            // What you use most, then the rice's actions.
            const top = apps.map(e => ({ e: e, f: frecency(e.id) })).filter(x => x.f > 0)
                            .sort((a, b) => b.f - a.f).slice(0, 6);
            for (const x of top) out.push({ kind: "app", entry: x.e, name: x.e.name, sub: x.e.genericName || x.e.comment || "", icon: x.e.icon, rank: 0 });
            if (!top.length)
                for (const e of apps.slice().sort((a, b) => a.name.localeCompare(b.name)).slice(0, 6))
                    out.push({ kind: "app", entry: e, name: e.name, sub: e.genericName || e.comment || "", icon: e.icon, rank: 0 });
            return out;
        }
        for (const e of apps) {
            const s = score(q, [e.name, e.genericName, (e.keywords || []).join(" "), e.comment, e.id]);
            if (s !== null) out.push({ kind: "app", entry: e, name: e.name, sub: e.genericName || e.comment || "", icon: e.icon, rank: s + Math.min(40, frecency(e.id) * 8) });
        }
        for (const t of Hyprland.toplevels.values) {
            const cls = t.lastIpcObject ? (t.lastIpcObject.class || "") : "";
            const s = score(q, [t.title, cls]);
            const app = cls ? DesktopEntries.heuristicLookup(cls) : null;
            if (s !== null) out.push({ kind: "window", toplevel: t, name: t.title || cls, sub: "Window · " + (app ? app.name : cls) + (t.workspace ? " · workspace " + t.workspace.name : ""), icon: app ? app.icon : cls.toLowerCase(), rank: s * 0.8 });
        }
        for (const a of actions) {
            const s = score(q, [a.name, a.sub]);
            if (s !== null) out.push({ kind: "action", action: a, name: a.name, sub: a.sub, glyph: a.glyph, rank: s * 0.9 });
        }
        return out.sort((a, b) => b.rank - a.rank).slice(0, 40);
    }
    onResultsChanged: current = 0

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
    function move(d) {
        if (!results.length) return;
        current = (current + d + results.length) % results.length;
        list.positionViewAtIndex(current, ListView.Contain);
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
            onTextChanged: launcher.query = text
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
        currentIndex: launcher.current
        boundsBehavior: Flickable.StopAtBounds
        highlightMoveDuration: Theme.reduceMotion ? 0 : 110
        highlightMoveVelocity: -1
        highlight: Rectangle { radius: 12; color: Qt.rgba(1, 1, 1, 0.10) }

        delegate: Item {
            id: row
            required property var modelData
            required property int index
            readonly property bool on: index === launcher.current
            width: list.width
            height: launcher.rowH

            Item {
                id: iconBox
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
                anchors { left: iconBox.right; leftMargin: 12; right: hint.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                spacing: 1
                Label { width: parent.width; elide: Text.ElideRight; text: row.modelData.name; size: row.modelData.kind === "calc" ? 17 : 14; weight: Theme.wMedium; rounded: row.modelData.kind === "calc" }
                Label { visible: text !== ""; width: parent.width; elide: Text.ElideRight; text: row.modelData.sub; size: 12; color: Theme.textTertiary }
            }
            Row {
                id: hint
                anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                spacing: 8
                opacity: row.on ? 1 : 0
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
            visible: list.count === 0
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
        text: launcher.query ? launcher.results.length + (launcher.results.length === 1 ? " result" : " results") : Object.keys(uses.counts).length ? "Frequent" : "Apps"
        size: 12
        color: Theme.textTertiary
    }
}
