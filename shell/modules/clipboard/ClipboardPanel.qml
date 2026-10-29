// Clipboard (Super+V): history with previews, fzf search, pins.
//
//   ⌕ search                                         48 of 750
//   All  Pinned  Text  Images  Links  Code  Colors
//   ┌ list ───────────────┐ ┌ preview ─────────────────────┐
//   │ PINNED              │ │ the entry in full: image at   │
//   │ ▣ screenshot.png    │ │ size, colour swatch + values, │
//   │ TODAY               │ │ text (mono for code), secrets │
//   │ ⌘ npm run dev   2m  │ │ masked                        │
//   └─────────────────────┘ └───────────────────────────────┘
//   ↵ Paste  ⇧↵ Copy  ⌃↵ Open  ⌃P Pin  ⇧⌦ Delete  ⇥ Filter
//
// Keys: ↑↓ PgUp PgDn move; ↵ pastes into the window you were in (terminals
// get Ctrl+Shift+V); ⇧↵ only copies; ⌃↵ opens it with the default app (a
// link in the browser, a path in its app, an image in the viewer); ⌃P pins
// (pins outlive history); ⇧⌦ or ⌃X deletes; ⌃H shows a masked secret;
// Alt+1–9 pastes the nth result; ⇥/⇧⇥ filters; ⌃⇧⌫ twice clears history;
// Esc clears the search, then the filter, then closes. Double-click pastes.
//
// Motion: it's opened by keyboard many times a day, so it barely moves:
// 110ms fade with a 1.5% scale, 80ms out; none with Reduce Motion. Like the
// center, its surface stays mapped (1×1 while closed) so it opens at once.
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

    readonly property var filters: [
        { id: "all", label: "All" }, { id: "pinned", label: "Pinned" }, { id: "text", label: "Text" },
        { id: "image", label: "Images" }, { id: "link", label: "Links" }, { id: "code", label: "Code" },
        { id: "color", label: "Colors" }
    ]

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
    onRowsChanged: if (entries && !current) selKey = entries.length ? entries[0].key : ""
    onQueryChanged: { selKey = entries.length ? entries[0].key : ""; if (listView) listView.positionViewAtBeginning(); }
    onFilterChanged: { selKey = entries.length ? entries[0].key : ""; if (listView) listView.positionViewAtBeginning(); }
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
    function act(what) {
        const e = current ? current.e : null;
        if (!e) return;
        if (what === "paste") Clipboard.paste(e);
        else if (what === "copy") Clipboard.copy(e);
        else if (what === "open") Clipboard.openWith(e);
        else if (what === "pin") Clipboard.togglePin(e);
        else if (what === "delete") { move(1); if (current && current.e === e) move(-1); Clipboard.remove(e); }
    }

    // ⌃⇧⌫ asks once, clears on the second press within 3s.
    property bool confirmWipe: false
    Timer { id: wipeWindow; interval: 3000; onTriggered: root.confirmWipe = false }

    // ── Presentation helpers (rows and preview use these) ─────────────────
    function glyphOf(e) {
        if (e.secret) return "\u{f0306}";                                     // key
        return ({ link: "\u{f0339}", path: "\u{f024b}", email: "\u{f01ee}", code: "\u{f0169}", file: "\u{f0214}" })[e.kind] || "\u{f09ed}";
    }
    function ago(t) {
        if (!t) return "";
        const m = Math.floor((Date.now() - t) / 60000);
        return m < 1 ? "now" : m < 60 ? m + "m" : m < 1440 ? Math.floor(m / 60) + "h" : Math.floor(m / 1440) + "d";
    }
    function metaOf(e) {
        const kind = e.secret ? "Secret" : ({ image: "Image", link: "Link", path: "Path", email: "Email", code: "Code", color: "Colour", file: "File" })[e.kind] || "Text";
        const parts = [kind];
        if (e.kind === "image") parts.push([e.dims.replace("x", "×"), e.size].filter(x => x).join(" · "));
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
    onOpenChanged: {
        armed = false;
        if (open) {
            query = "";
            if (searchField) searchField.text = "";
            filter = Clipboard.startFilter;
            selKey = entries.length ? entries[0].key : "";
            confirmWipe = false;
            if (listView) listView.positionViewAtBeginning();
            armSoon.restart();
            showSoon.restart();
        } else {
            p = 0;
        }
    }
    // One frame for the surface to take its size, then in.
    Timer { id: showSoon; interval: 16; onTriggered: root.p = root.open ? 1 : 0 }
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
            readonly property int cardW: Math.min(820, modelData.width - 80)
            readonly property int cardH: Math.min(540, modelData.height - 160)

            anchors.top: true
            margins.top: Math.round(modelData.height * 0.14)
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
            // ── Search ───────────────────────────────────────────────────
            Item {
                id: head
                anchors { left: parent.left; right: parent.right; top: parent.top }
                height: 54
                Text {
                    id: glyph
                    x: 20
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u{f014c}"                                   // clipboard
                    font.family: Theme.fontGlyph
                    font.pixelSize: 18
                    color: Theme.textTertiary
                }
                TextInput {
                    id: search
                    Component.onCompleted: root.searchField = search
                    anchors { left: glyph.right; leftMargin: 12; right: count.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    color: Theme.textPrimary
                    selectionColor: Qt.alpha(Theme.blue, 0.5)
                    font.family: Theme.fontText
                    font.pixelSize: 17
                    font.variableAxes: ({ "opsz": Theme.opszFor(17), "wght": Theme.wRegular })
                    renderType: Text.NativeRendering
                    clip: true
                    onTextChanged: root.query = text
                    Label {
                        visible: search.text === ""
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Search clipboard   ('exact  ^start  end$  !not)"
                        size: 17
                        color: Theme.textTertiary
                    }
                    Keys.onPressed: event => root.key(event)
                }
                Label {
                    id: count
                    anchors { right: parent.right; rightMargin: 20; verticalCenter: parent.verticalCenter }
                    text: !Clipboard.loaded ? "" : root.ts.length || root.filter !== "all"
                        ? `${root.entries.length} of ${Clipboard.items.length + Clipboard.pins.length}`
                        : `${Clipboard.items.length} items`
                    size: 12
                    rounded: true
                    font.features: ({ "tnum": 1 })
                    color: Theme.textTertiary
                }
                Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: Qt.rgba(1, 1, 1, 0.07) }
            }

            // ── Filters ──────────────────────────────────────────────────
            Row {
                id: chips
                anchors { left: parent.left; leftMargin: 14; top: head.bottom; topMargin: 10 }
                spacing: 6
                Repeater {
                    model: root.filters
                    Rectangle {
                        id: chip
                        required property var modelData
                        readonly property bool on: root.filter === modelData.id
                        height: 26; radius: 13
                        width: chipLabel.implicitWidth + 22
                        color: on ? Qt.rgba(1, 1, 1, 0.9) : chipArea.containsMouse ? Theme.pillHover : Theme.pill
                        Behavior on color { ColorAnimation { duration: Theme.colorMs } }
                        Label {
                            id: chipLabel
                            anchors.centerIn: parent
                            text: chip.modelData.label
                            size: 12
                            weight: chip.on ? Theme.wSemibold : Theme.wMedium
                            color: chip.on ? "#111114" : Theme.textPrimary
                        }
                        MouseArea { id: chipArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.filter = chip.modelData.id; search.forceActiveFocus(); } }
                    }
                }
            }

            // ── List ─────────────────────────────────────────────────────
            ListView {
                id: list
                Component.onCompleted: root.listView = list
                anchors { left: parent.left; top: chips.bottom; bottom: foot.top; leftMargin: 8; topMargin: 8; bottomMargin: 6 }
                width: 330
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                reuseItems: true
                cacheBuffer: 400
                model: ScriptModel { values: root.rows; objectProp: "key" }
                delegate: ClipRow { panel: root }
            }

            // Loading: the list's shape until cliphist answers.
            Column {
                visible: !Clipboard.loaded
                anchors { left: list.left; top: list.top; leftMargin: 8 }
                spacing: 14
                Repeater {
                    model: 7
                    Row {
                        required property int index
                        spacing: 10
                        Skeleton { width: 32; height: 32; radius: 8 }
                        Column {
                            spacing: 6
                            anchors.verticalCenter: parent.verticalCenter
                            Skeleton { width: 200 - (index % 3) * 40; height: 11 }
                            Skeleton { width: 90; height: 9 }
                        }
                    }
                }
            }

            // Empty / no results
            Column {
                visible: Clipboard.loaded && root.entries.length === 0
                anchors.centerIn: list
                spacing: 6
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.query ? "No matches" : root.filter === "pinned" ? "No pins yet" : "Nothing copied yet"
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
                anchors { left: list.right; leftMargin: 8; top: chips.bottom; bottom: foot.top; topMargin: 8; bottomMargin: 8 }
                width: 1
                color: Qt.rgba(1, 1, 1, 0.07)
            }

            // ── Preview + actions ────────────────────────────────────────
            Row {
                id: actions
                anchors { right: parent.right; rightMargin: 16; top: chips.bottom; topMargin: 8 }
                spacing: 6
                visible: root.current !== null
                Repeater {
                    model: [
                        { a: "paste", g: "\u{f0192}", t: "Paste" },
                        { a: "open", g: "\u{f03cc}", t: "Open" },
                        { a: "pin", g: "\u{f0403}", t: "" },
                        { a: "delete", g: "\u{f0a7a}", t: "" }
                    ]
                    Rectangle {
                        id: btn
                        required property var modelData
                        readonly property bool on: modelData.a === "pin" && root.current && Clipboard.isPinned(root.current.e)
                        height: 26; radius: 13
                        width: btnRow.implicitWidth + 18
                        color: btnArea.containsMouse ? Theme.pillHover : Theme.pill
                        scale: btnArea.pressed ? 0.96 : 1
                        Behavior on scale { NumberAnimation { duration: Theme.pressMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                        Row {
                            id: btnRow
                            anchors.centerIn: parent
                            spacing: 5
                            Text { anchors.verticalCenter: parent.verticalCenter; text: btn.modelData.g; font.family: Theme.fontGlyph; font.pixelSize: 13; color: btn.on ? Theme.yellow : btn.modelData.a === "delete" && btnArea.containsMouse ? Theme.red : Theme.textPrimary }
                            Label { visible: btn.modelData.t !== ""; anchors.verticalCenter: parent.verticalCenter; text: btn.modelData.t; size: 12; weight: Theme.wMedium }
                        }
                        MouseArea { id: btnArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.act(btn.modelData.a) }
                    }
                }
            }
            ClipPreview {
                panel: root
                entry: root.current ? root.current.e : null
                revealed: root.revealed
                anchors { left: split.right; right: parent.right; top: actions.bottom; bottom: foot.top; leftMargin: 16; rightMargin: 16; topMargin: 12; bottomMargin: 10 }
            }

            // ── Keys ─────────────────────────────────────────────────────
            Item {
                id: foot
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 40
                Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top } height: 1; color: Qt.rgba(1, 1, 1, 0.07) }
                Row {
                    x: 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 14
                    Repeater {
                        model: root.confirmWipe ? [{ k: ["⌃", "⇧", "⌫"], t: "again to clear all history (pins stay)" }]
                            : [{ k: ["↵"], t: "Paste" }, { k: ["⇧", "↵"], t: "Copy" }, { k: ["⌃", "↵"], t: "Open" },
                               { k: ["⌃", "P"], t: "Pin" }, { k: ["⇧", "⌦"], t: "Delete" }, { k: ["⇥"], t: "Filter" }]
                            .concat(root.current && root.current.e.secret ? [{ k: ["⌃", "H"], t: root.revealed ? "Hide" : "Show" }] : [])
                        Row {
                            id: hint
                            required property var modelData
                            spacing: 5
                            Row {
                                spacing: 3
                                anchors.verticalCenter: parent.verticalCenter
                                Repeater { model: hint.modelData.k; KeyCap { required property string modelData; text: modelData } }
                            }
                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                text: hint.modelData.t
                                size: 12
                                color: root.confirmWipe ? Theme.red : Theme.textTertiary
                            }
                        }
                    }
                }
            }
        }
    }
    property Item searchField: null
    property Item listView: null

    // ── Keys ─────────────────────────────────────────────────────────────
    function key(event) {
        const k = event.key, m = event.modifiers;
        const ctrl = m & Qt.ControlModifier, shift = m & Qt.ShiftModifier, alt = m & Qt.AltModifier;
        const field = searchField;
        if (k === Qt.Key_Down || (ctrl && k === Qt.Key_N)) move(1);
        else if (k === Qt.Key_Up) move(-1);
        else if (k === Qt.Key_PageDown) move(8);
        else if (k === Qt.Key_PageUp) move(-8);
        else if (ctrl && k === Qt.Key_Home) move(-1e6);
        else if (ctrl && k === Qt.Key_End) move(1e6);
        else if ((k === Qt.Key_Return || k === Qt.Key_Enter) && ctrl) act("open");
        else if ((k === Qt.Key_Return || k === Qt.Key_Enter) && shift) act("copy");
        else if (k === Qt.Key_Return || k === Qt.Key_Enter) act("paste");
        else if (ctrl && k === Qt.Key_P) act("pin");
        else if (ctrl && k === Qt.Key_H) revealed = !revealed;
        else if (ctrl && shift && k === Qt.Key_Backspace) {
            if (confirmWipe) { confirmWipe = false; Clipboard.wipe(); }
            else { confirmWipe = true; wipeWindow.restart(); }
        }
        else if ((shift && k === Qt.Key_Delete) || (ctrl && k === Qt.Key_X && field && !field.selectedText)) act("delete");
        else if (k === Qt.Key_Tab || k === Qt.Key_Backtab) {
            const i = filters.findIndex(f => f.id === filter);
            filter = filters[(i + (k === Qt.Key_Backtab ? filters.length - 1 : 1)) % filters.length].id;
        }
        else if (alt && k >= Qt.Key_1 && k <= Qt.Key_9) {
            const r = entries[k - Qt.Key_1];
            if (r) { selKey = r.key; act("paste"); }
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
