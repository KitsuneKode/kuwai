// The palette, grown out of the island (Super+/, or hold Super): every
// shortcut, every kuwai feature and mode — searchable, and runnable.
//
// Data comes from kuwai itself (`hyprctl repl 'return kuwai.palette()'`), so it
// is always the truth of the running config; ↩ runs the chosen entry through
// `hyprctl eval 'kuwai.run(ID)'` (a bind's own action, a feature toggle, a
// mode). Without kuwai it falls back to `hyprctl binds -j`, read-only.
//
// Type to search (every word must match: title, group, keys, name).
// ↑↓ PgUp PgDn choose · ↩ run · Esc clears, then closes.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.config
import qs.components
import qs.services

FocusScope {
    id: pal
    focus: true
    implicitWidth: 760
    implicitHeight: 580

    property var items: []
    property bool runnable: true
    property string query: ""
    // When this panel appeared: rows cascade in only during the first moment.
    readonly property real born: Date.now()
    property int current: -1
    property var lastPointer: null

    // ── Data ─────────────────────────────────────────────────────────────
    readonly property var keyNames: ({
        SUPER: "Super", CTRL: "Ctrl", CONTROL: "Ctrl", ALT: "Alt", SHIFT: "Shift",
        RETURN: "↩", ESCAPE: "esc", DELETE: "Del", BACKSPACE: "⌫", TAB: "⇥", SPACE: "Space",
        LEFT: "←", RIGHT: "→", UP: "↑", DOWN: "↓", GRAVE: "`", SLASH: "/", BACKSLASH: "\\",
        COMMA: ",", PERIOD: ".", EQUAL: "=", MINUS: "−", BRACKETLEFT: "[", BRACKETRIGHT: "]",
        PRINT: "PrtSc", MOUSE_DOWN: "Scroll ↓", MOUSE_UP: "Scroll ↑", "MOUSE:274": "Middle click",
        XF86AUDIORAISEVOLUME: "Vol +", XF86AUDIOLOWERVOLUME: "Vol −", XF86AUDIOMUTE: "Mute",
        XF86AUDIOMICMUTE: "Mic", XF86MONBRIGHTNESSUP: "Bright +", XF86MONBRIGHTNESSDOWN: "Bright −",
        XF86AUDIOPLAY: "Play", XF86AUDIOPAUSE: "Pause", XF86AUDIONEXT: "Next", XF86AUDIOPREV: "Prev"
    })
    function capsOf(keys) {
        return String(keys).split("+").map(k => k.trim()).filter(k => k).map(k => {
            const u = k.toUpperCase();
            return keyNames[u] || (k.length === 1 ? k.toUpperCase() : k);
        });
    }
    function load(list, live) {
        // One row per action: several key combos for the same thing become
        // alternatives on one row ("⌘⇧V  or  ⌘⌥V"), not duplicate rows.
        const merged = [], byKey = {};
        for (const e of list) {
            const k = (e.kind || "bind") + "|" + (e.group || "") + "|" + (e.text || "");
            if (e.kind === "bind" && byKey[k]) { byKey[k].alt.push(e.keys); continue; }
            const c = Object.assign({ alt: [] }, e);
            merged.push(c);
            if (e.kind === "bind" || !e.kind) byKey[k] = c;
        }
        items = merged.map(e => {
            const parts = String(e.group || "Other").split("|");
            const caps = e.keys ? capsOf(e.keys) : [];
            return {
                id: e.id, kind: e.kind || "bind", group: parts[0], sub: parts.slice(1).join(" · "),
                text: e.text ? e.text.charAt(0).toUpperCase() + e.text.slice(1) : "",
                name: e.name || "", on: !!e.on, caps: caps,
                alt: (e.alt || []).slice(0, 1).map(capsOf),
                hay: [e.text, e.group, e.name, caps.join(" "), e.keys, (e.alt || []).join(" ")].join(" ").toLowerCase()
            };
        });
        runnable = live;
    }
    Process {
        running: true
        command: ["hyprctl", "repl", "return kuwai.palette()"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { pal.load(JSON.parse(text), true); }
                catch (e) { fallback.running = true; }
            }
        }
    }
    Process {
        id: fallback
        command: ["hyprctl", "binds", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                let all = [];
                try { all = JSON.parse(text); } catch (e) { return; }
                const mods = m => [[64, "SUPER"], [4, "CTRL"], [8, "ALT"], [1, "SHIFT"]].filter(([b]) => m & b).map(([, n]) => n);
                pal.load(all.filter(b => b.has_description && b.description).map((b, i) => {
                    const m = b.description.match(/^\[([^\]]+)\]\s*(.*)$/);
                    return { id: "x" + i, kind: "bind", group: m ? m[1] : "Other", text: m ? m[2] : b.description,
                             keys: [...mods(b.modmask), b.key].join(" + ") };
                }), false);
            }
        }
    }

    // ── Results ──────────────────────────────────────────────────────────
    // Order: the shell first, then the window manager, then features & modes.
    readonly property var groupOrder: ["Shell", "Launch", "Windows", "Columns", "Workspaces", "Screens", "Capture", "Dictation", "Apps", "Media", "Hardware", "Zoom", "Pickers", "Theming", "Utilities", "Features", "Modes"]
    function rankOf(g) { const i = groupOrder.indexOf(g); return i < 0 ? 50 : i; }
    readonly property var rows: {
        const words = query.trim().toLowerCase().split(/\s+/).filter(w => w);
        const hits = items.filter(e => words.every(w => e.hay.includes(w)));
        // While searching, entries whose title starts with the query come first.
        const lead = words.length ? words[0] : "";
        hits.sort((a, b) => rankOf(a.group) - rankOf(b.group)
                  || (lead ? (b.text.toLowerCase().startsWith(lead) - a.text.toLowerCase().startsWith(lead)) : 0)
                  || a.group.localeCompare(b.group));
        const out = [];
        let last = "";
        for (const e of hits) {
            if (e.group !== last) { out.push({ header: e.group }); last = e.group; }
            out.push(e);
        }
        return out;
    }
    readonly property int count: rows.length ? rows.filter(r => !r.header).length : 0
    onRowsChanged: {
        current = rows.findIndex(r => !r.header);
        list.positionViewAtBeginning();
    }
    function move(d) {
        if (!count) return;
        let i = current;
        do { i = (i + d + rows.length) % rows.length; } while (rows[i].header);
        current = i;
        list.positionViewAtIndex(current, ListView.Contain);
        if (current <= 1) list.positionViewAtBeginning();
    }
    function page(d) {
        for (let n = 0; n < 8; n++) move(d);
    }
    function run(e) {
        if (!e || e.header || !runnable) return;
        Island.close();
        // Over Hyprland's socket (no process); ids are kuwai's own: b12, f:name, m:name.
        if (/^(b\d+|[fm]:[A-Za-z0-9_]+)$/.test(e.id)) Hyprland.dispatch("kuwai.run('" + e.id + "')");
    }

    // ── Search ───────────────────────────────────────────────────────────
    Item {
        x: 20; y: 12
        width: parent.width - 40; height: 40
        Text { id: lens; anchors.verticalCenter: parent.verticalCenter; text: "\u{f0349}"; font.family: Theme.fontGlyph; font.pixelSize: 18; color: Theme.textTertiary }
        TextInput {
            id: field
            anchors { left: lens.right; leftMargin: 12; right: parent.right; verticalCenter: parent.verticalCenter }
            focus: true
            font.family: Theme.fontText
            font.pixelSize: 18
            color: Theme.textPrimary
            selectionColor: Qt.alpha(Theme.accent, 0.4)
            onTextChanged: pal.query = text
            Keys.onPressed: event => {
                const k = event.key;
                if (k === Qt.Key_Down) pal.move(1);
                else if (k === Qt.Key_Up) pal.move(-1);
                else if (k === Qt.Key_PageDown) pal.page(1);
                else if (k === Qt.Key_PageUp) pal.page(-1);
                else if (k === Qt.Key_Return || k === Qt.Key_Enter) pal.run(pal.rows[pal.current]);
                else if (k === Qt.Key_Escape) { if (text) text = ""; else Island.close(); }
                else return;
                event.accepted = true;
            }
            Label {
                visible: !field.text
                anchors.verticalCenter: parent.verticalCenter
                text: "Search " + pal.items.length + " shortcuts, features and modes"
                size: 18; color: Theme.textTertiary
            }
        }
    }
    Rectangle { x: 0; y: 63; width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.07) }

    ListView {
        id: list
        x: 8; y: 64
        width: parent.width - 16
        height: parent.height - y - 47
        clip: true
        reuseItems: true
        cacheBuffer: 400
        currentIndex: -1
        highlightFollowsCurrentItem: false
        boundsBehavior: Flickable.StopAtBounds
        model: pal.rows

        delegate: Item {
            id: row
            required property var modelData
            required property int index
            readonly property bool header: !!modelData.header
            readonly property bool on: index === pal.current
            width: list.width
            height: header ? 32 : 40

            // First paint after opening: rows cascade in (20 ms apart, the
            // first nine), rising 6 px. Afterwards results just appear —
            // typing must never replay this.
            property real enter: 1
            opacity: enter
            transform: Translate { y: 6 * (1 - row.enter) }
            Component.onCompleted: if (!Theme.reduceMotion && Date.now() - pal.born < 260 && index < 9) { enter = 0; cascade.start(); }
            SequentialAnimation {
                id: cascade
                PauseAnimation { duration: 40 + row.index * 20 }
                NumberAnimation { target: row; property: "enter"; to: 1; duration: 240; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
            }

            Rectangle {
                anchors.fill: parent
                anchors.leftMargin: 2; anchors.rightMargin: 2
                radius: 11
                visible: !row.header
                color: Qt.rgba(1, 1, 1, 0.10)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.06)
                opacity: row.on ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.reduceMotion ? 0 : 90; easing.type: Easing.OutCubic } }
            }

            Label {
                visible: row.header
                x: 14; anchors.bottom: parent.bottom; anchors.bottomMargin: 7
                text: row.modelData.header || ""
                size: 12; weight: Theme.wSemibold; color: Theme.textTertiary
            }

            Column {
                visible: !row.header
                anchors { left: parent.left; leftMargin: 14; right: trail.left; rightMargin: 14; verticalCenter: parent.verticalCenter }
                spacing: 1
                Label { width: parent.width; elide: Text.ElideRight; text: row.modelData.text || ""; size: 13; weight: Theme.wMedium }
                Label { visible: !!row.modelData.sub; width: parent.width; elide: Text.ElideRight; text: row.modelData.sub || ""; size: 11; color: Theme.textTertiary }
            }

            Row {
                id: trail
                visible: !row.header
                anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                spacing: 4
                // Shortcuts: the keys. Features: on/off. Modes: the current one.
                Repeater {
                    model: row.modelData.kind === "bind" ? (row.modelData.caps || []) : []
                    KeyCap { required property var modelData; anchors.verticalCenter: parent.verticalCenter; text: modelData }
                }
                Label {
                    visible: row.modelData.kind === "bind" && (row.modelData.alt || []).length > 0
                    anchors.verticalCenter: parent.verticalCenter
                    leftPadding: 4; rightPadding: 4
                    text: "or"; size: 11; color: Theme.textTertiary
                }
                Repeater {
                    model: row.modelData.kind === "bind" && row.modelData.alt && row.modelData.alt.length ? row.modelData.alt[0] : []
                    KeyCap { required property var modelData; anchors.verticalCenter: parent.verticalCenter; text: modelData }
                }
                Rectangle {
                    visible: row.modelData.kind === "feature" || row.modelData.kind === "mode"
                    anchors.verticalCenter: parent.verticalCenter
                    height: 20; radius: 10
                    width: stateLabel.implicitWidth + 16
                    color: row.modelData.on ? Qt.alpha(Theme.accent, 0.22) : Qt.rgba(1, 1, 1, 0.07)
                    Label {
                        id: stateLabel
                        anchors.centerIn: parent
                        text: row.modelData.kind === "mode" ? (row.modelData.on ? "Current" : "Switch") : (row.modelData.on ? "On" : "Off")
                        size: 11; weight: Theme.wMedium
                        color: row.modelData.on ? Theme.textPrimary : Theme.textSecondary
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                enabled: !row.header
                hoverEnabled: true
                cursorShape: pal.runnable ? Qt.PointingHandCursor : Qt.ArrowCursor
                // Only a pointer that really moves picks (rows appearing under a
                // resting pointer must not steal the keyboard's selection).
                onPositionChanged: mouse => {
                    const g = mapToGlobal(mouse.x, mouse.y);
                    const was = pal.lastPointer;
                    pal.lastPointer = g;
                    if (was && (g.x !== was.x || g.y !== was.y)) pal.current = row.index;
                }
                onClicked: pal.run(row.modelData)
            }
        }

        Label {
            visible: pal.count === 0 && pal.query.trim() !== ""
            anchors.centerIn: parent
            text: "Nothing matches “" + pal.query.trim() + "”"
            size: 13; color: Theme.textTertiary
        }
    }

    // ── Footer ───────────────────────────────────────────────────────────
    Rectangle { x: 0; y: parent.height - 46; width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.06) }
    Row {
        anchors { left: parent.left; leftMargin: 20; bottom: parent.bottom; bottomMargin: 14 }
        spacing: 16
        Repeater {
            model: pal.runnable ? [["↑↓", "Choose"], ["↩", "Run"], ["esc", "Close"]] : [["↑↓", "Choose"], ["esc", "Close"]]
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
        text: pal.query ? pal.count + (pal.count === 1 ? " match" : " matches") : "Hold Super anywhere to open this"
        size: 12; color: Theme.textTertiary
    }
}
