// Mission Control: every workspace of a screen at a glance, and every window
// of the one you're looking at laid out live (Exposé).
//
//   Super+Tab / four-finger pinch in   open (rice:overview)
//   Super+Tab again, Tab / Shift+Tab   next / previous window, on through the
//                                      spaces; let go of Super to go there
//   ←→↑↓                               pick a window; ↑ past the top row is
//                                      the spaces strip (←→ there, ↓ back)
//   1–9, 0 · Ctrl+←→ · PgUp/PgDn       look at another space (nothing moves
//                                      behind until you choose)
//   Enter                              go to the window, or the space
//   Delete / Ctrl+W, or its ✕ on hover close the window (not middle click: a
//                                      three-finger tap is one, and closed
//                                      windows when you lifted off a pinch)
//   click a window / a space           go there     drag a window onto a space   move it
//
// The strip shows this screen's spaces, then (past a divider) the other
// screen's: Tab, ←→ and Enter reach those too, and you go to that screen.
//   type                               filter: the windows of every space on
//                                      every screen whose title or app match
//                                      (Backspace edits; the first Esc clears)
//   Esc, or click the background       back
//
// One layer per screen (rice-overview: glass via the rice-* layer rule). Only
// the screen you invoke it on shows; the previews are live only while open.
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.config
import qs.components
import qs.services

Scope {
    id: root

    property bool open: false
    // Live previews are screen captures: tell kuwai they're ours, so its
    // screen-share privacy doesn't think you're sharing.
    onOpenChanged: {
        cycled = false;
        if (!open) { Hyprland.dispatch("kuwai.capture_hold(false)"); lingering = true; linger.restart(); }
    }
    // Built only while open (and a moment after, for the way out), only on
    // the screen it opens on: nothing of it sits in memory the rest of the
    // time (a full-screen layer per monitor did, with every preview).
    property bool lingering: false
    Timer { id: linger; interval: 700; onTriggered: root.lingering = false }
    property string screenName: ""

    function toggle() {
        if (open) {
            open = false;
            return;
        }
        Hyprland.dispatch("kuwai.capture_hold(true)");
        Hyprland.refreshToplevels();
        Hyprland.refreshWorkspaces();
        Hyprland.refreshMonitors();
        // The screen you're looking at (pointer and focus, kuwai.where), so it
        // opens there even when focus sits on the other screen.
        Screens.underPointer((looking, focused) => {
            root.screenName = looking || focused || Screens.focusedName || (Quickshell.screens[0] ? Quickshell.screens[0].name : "");
            root.open = true;
        });
    }

    GlobalShortcut {
        appid: "rice"
        name: "overview"
        description: "Mission Control: every workspace and window"
        // Open, it moves on to the next window (Super held: let go to go).
        onPressed: {
            if (root.open) { root.cycled = true; root.next(1); }
            else root.toggle();
        }
    }
    // Set by a second Super+Tab: letting go of Super then goes to the pick.
    property bool cycled: false
    signal next(int d)

    Variants {
        model: Quickshell.screens

        Scope {
        id: slot
        required property ShellScreen modelData
        LazyLoader {
        active: (root.open || root.lingering) && !!slot.modelData && slot.modelData.name === root.screenName
        PanelWindow {
            id: win
            readonly property ShellScreen modelData: slot.modelData
            screen: modelData

            readonly property var monitor: Hyprland.monitorFor(modelData)
            readonly property bool here: root.open && modelData && modelData.name === root.screenName
            readonly property int activeWs: monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : 1
            // This screen's block of ten (kuwai's wsbase, e.g. DP-3 = 10), so
            // its spaces read 1, 2, 3… like its pills.
            readonly property int base: modelData && Island.wsBases[modelData.name] !== undefined ? Island.wsBases[modelData.name]
                                      : Math.floor((Math.max(1, activeWs) - 1) / 10) * 10
            property int viewWs: activeWs            // the space whose windows are laid out
            property int picked: 0                   // the selection in the Exposé grid (keys and pointer)
            property string zone: "windows"          // or "spaces": the strip has the keys

            visible: here || show.value > 0.01
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; bottom: true; left: true; right: true }
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "rice-overview"
            WlrLayershell.keyboardFocus: here ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            onHereChanged: if (here) start()
            function start() { viewWs = activeWs; picked = 0; zone = "windows"; filter = ""; keys.forceActiveFocus(); }
            Component.onCompleted: if (here) start()
            Connections {
                target: root
                function onNext(d) { if (win.here) win.cycle(d); }
            }

            Spring { id: show; tier: win.here ? Theme.surfaceKeyIn : Theme.surfaceKeyOut;   // opened from the keyboard: the quick spring
            target: win.here ? 1 : 0 }

            // Monitor geometry in logical pixels, for placing windows in tiles.
            readonly property var mon: monitor && monitor.lastIpcObject ? monitor.lastIpcObject : ({})
            readonly property real monX: mon.x || 0
            readonly property real monY: mon.y || 0
            readonly property real monW: width
            readonly property real monH: height

            // This screen's spaces, then the other screens' (left to right).
            readonly property var spaces: {
                const all = Hyprland.workspaces.values.filter(w => w.id > 0 && w.monitor);
                const mx = w => (w.monitor.lastIpcObject && w.monitor.lastIpcObject.x) || 0;
                const mine = all.filter(w => w.monitor === win.monitor).sort((a, b) => a.id - b.id);
                const others = all.filter(w => w.monitor !== win.monitor).sort((a, b) => mx(a) - mx(b) || a.id - b.id);
                return mine.concat(others);
            }
            readonly property int mineCount: spaces.filter(w => w.monitor === win.monitor).length
            function screenLabel(m) {
                if (!m) return "";
                if (/^eDP/.test(m.name)) return "Laptop";
                const ipc = m.lastIpcObject || {};
                return (ipc.make || m.name).split(" ")[0];
            }
            function windowsOf(wsId) {
                return Hyprland.toplevels.values.filter(t => t.workspace && t.workspace.id === wsId && t.wayland);
            }
            // Typed: matching windows from every space on every screen.
            property string filter: ""
            readonly property var shown: {
                const f = filter.trim().toLowerCase();
                if (!f) return windowsOf(viewWs);
                const terms = f.split(/\s+/);
                return Hyprland.toplevels.values.filter(t => {
                    if (!t.wayland || !t.workspace || t.workspace.id <= 0) return false;
                    const ipc = t.lastIpcObject || {};
                    const hay = ((t.title || "") + " " + (ipc["class"] || "") + " " + (ipc.initialTitle || "")).toLowerCase();
                    return terms.every(x => hay.includes(x));
                });
            }
            onFilterChanged: picked = 0
            function focusWindow(t) {
                root.open = false;
                Hyprland.dispatch(`hl.dsp.focus({window = 'address:0x${t.address}'})`);
            }
            function closeWindow(t) {
                Hyprland.dispatch(`hl.dsp.window.close({window = 'address:0x${t.address}'})`);
                Qt.callLater(Hyprland.refreshToplevels);
            }
            // Look at a space's windows here; nothing switches behind.
            function browse(id) {
                if (!spaces.some(w => w.id === id)) return;
                viewWs = id;
                picked = 0;
            }
            function stepSpace(d) {
                const ids = spaces.map(w => w.id);
                const i = ids.indexOf(viewWs);
                if (i < 0) return;
                browse(ids[Math.max(0, Math.min(ids.length - 1, i + d))]);
            }
            // Next / previous window, on into the next space that has any.
            function cycle(d) {
                zone = "windows";
                const n = shown.length;
                if (n && picked + d >= 0 && picked + d < n) { picked += d; return; }
                const ids = spaces.map(w => w.id);
                const i = Math.max(0, ids.indexOf(viewWs));
                for (let k = 1; k <= ids.length; k++) {
                    const j = ((i + d * k) % ids.length + ids.length) % ids.length;
                    const m = windowsOf(ids[j]).length;
                    if (m) { viewWs = ids[j]; picked = d > 0 ? 0 : m - 1; return; }
                }
            }
            // Go there and close. (Not for the space you're on: with
            // workspace_back_and_forth that would bounce you to the last one.)
            function goSpace(id) {
                root.open = false;
                const w = spaces.find(x => x.id === id);
                if (w && w.monitor && w.monitor !== win.monitor) {
                    // The other screen: kuwai shows it there (or just focuses
                    // that screen if it already shows it, never a bounce).
                    Hyprland.dispatch("kuwai.go_ws(" + JSON.stringify(w.monitor.name) + ", " + id + ")");
                    return;
                }
                if (id !== activeWs) Hyprland.dispatch(`hl.dsp.focus({workspace = ${id}})`);
            }
            function nextFree() {
                for (let n = 1; n <= 10; n++)
                    if (!spaces.some(w => w.id === base + n)) return base + n;
                return base + 10;
            }

            // Backdrop: glass over the desktop; clicking it goes back.
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0.02, 0.02, 0.03, 0.42 * show.value)
                MouseArea { anchors.fill: parent; onClicked: root.open = false }
            }

            Item {
                id: keys
                anchors.fill: parent
                focus: win.here
                opacity: Math.min(1, show.value * 1.4)
                scale: 0.97 + 0.03 * show.value
                Keys.onPressed: event => {
                    const k = event.key;
                    const n = win.shown.length;
                    const cols = grid.cols;
                    const ctrl = event.modifiers & Qt.ControlModifier;
                    const enter = k === Qt.Key_Return || k === Qt.Key_Enter;
                    if (k === Qt.Key_Escape) { if (win.filter !== "") win.filter = ""; else root.open = false; }
                    else if (k === Qt.Key_Backspace && win.filter !== "") win.filter = win.filter.slice(0, -1);
                    else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && !ctrl
                             && !(event.modifiers & Qt.AltModifier) && !(win.filter === "" && (k === Qt.Key_Space || (k >= Qt.Key_0 && k <= Qt.Key_9)))) {
                        // Letters filter (digits pick a space until you've started typing).
                        win.filter += event.text;
                        win.zone = "windows";
                    }
                    else if (k === Qt.Key_Tab || k === Qt.Key_Backtab) win.cycle(k === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier) ? -1 : 1);
                    else if (k === Qt.Key_PageDown || (ctrl && k === Qt.Key_Right)) win.stepSpace(1);
                    else if (k === Qt.Key_PageUp || (ctrl && k === Qt.Key_Left)) win.stepSpace(-1);
                    else if (k >= Qt.Key_1 && k <= Qt.Key_9) { win.browse(win.base + (k - Qt.Key_0)); win.zone = "windows"; }
                    else if (k === Qt.Key_0) { win.browse(win.base + 10); win.zone = "windows"; }
                    else if (win.zone === "spaces") {
                        if (k === Qt.Key_Right) win.stepSpace(1);
                        else if (k === Qt.Key_Left) win.stepSpace(-1);
                        else if (k === Qt.Key_Down) win.zone = "windows";
                        else if (enter) win.goSpace(win.viewWs);
                        else return;
                    }
                    else if (k === Qt.Key_Right) win.picked = Math.min(n - 1, win.picked + 1);
                    else if (k === Qt.Key_Left) win.picked = Math.max(0, win.picked - 1);
                    else if (k === Qt.Key_Down) win.picked = Math.min(n - 1, win.picked + cols);
                    else if (k === Qt.Key_Up) { if (n === 0 || win.picked < cols) win.zone = "spaces"; else win.picked -= cols; }
                    else if (enter) { if (n > 0) win.focusWindow(win.shown[win.picked]); else win.goSpace(win.viewWs); }
                    else if ((k === Qt.Key_Delete || (ctrl && k === Qt.Key_W)) && n > 0) { win.closeWindow(win.shown[win.picked]); win.picked = Math.max(0, Math.min(win.picked, n - 2)); }
                    else return;
                    event.accepted = true;
                }
                // Cycling with Super held (Super+Tab, Tab, Tab): let go to go.
                Keys.onReleased: event => {
                    const k = event.key;
                    if (root.cycled && (k === Qt.Key_Super_L || k === Qt.Key_Super_R || k === Qt.Key_Meta)) {
                        root.cycled = false;
                        if (win.shown.length) win.focusWindow(win.shown[Math.min(win.picked, win.shown.length - 1)]);
                        else win.goSpace(win.viewWs);
                        event.accepted = true;
                    }
                }

                // ── Spaces strip ────────────────────────────────────────────
                Row {
                    id: strip
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: 56
                    spacing: 18
                    readonly property real tileW: Math.min(220, (win.width - 160) / Math.max(4, win.spaces.length + 1) - 18)
                    readonly property real tileH: tileW * win.monH / Math.max(1, win.monW)

                    Repeater {
                        model: win.spaces
                        delegate: Item {
                            id: tile
                            required property var modelData
                            readonly property bool current: modelData.id === win.viewWs
                            readonly property bool keyed: current && win.zone === "spaces"
                            required property int index
                            readonly property bool other: modelData.monitor !== win.monitor
                            readonly property bool firstOther: other && index === win.mineCount
                            readonly property real lead: firstOther ? 30 : 0
                            readonly property var tmon: (modelData.monitor && modelData.monitor.lastIpcObject) || ({})
                            width: strip.tileW + lead
                            scale: keyed ? 1.05 : 1
                            Behavior on scale { NumberAnimation { duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                            height: strip.tileH + 22

                            // The divider between this screen's spaces and the other's.
                            Rectangle {
                                visible: tile.firstOther
                                x: tile.lead / 2 - 1 - 9
                                y: strip.tileH * 0.15
                                width: 1; height: strip.tileH * 0.7
                                color: Qt.rgba(1, 1, 1, 0.16)
                            }
                            GlassCard {
                                id: frame
                                x: tile.lead
                                width: strip.tileW
                                height: strip.tileH
                                radius: 10
                                tint: tile.current ? Theme.glassTintElevated : Theme.glassTint
                                clip: true

                                Repeater {
                                    model: win.windowsOf(tile.modelData.id)
                                    delegate: ScreencopyView {
                                        required property var modelData
                                        readonly property var ipc: modelData.lastIpcObject || ({})
                                        // That space's own screen, for where its windows sit.
                                        readonly property real tw: tile.tmon.width ? tile.tmon.width / (tile.tmon.scale || 1) : win.monW
                                        readonly property real k: frame.width / Math.max(1, tw)
                                        x: ((ipc.at ? ipc.at[0] : 0) - (tile.tmon.width ? tile.tmon.x : win.monX)) * k
                                        y: ((ipc.at ? ipc.at[1] : 0) - (tile.tmon.width ? tile.tmon.y : win.monY)) * k
                                        width: (ipc.size ? ipc.size[0] : 0) * k
                                        height: (ipc.size ? ipc.size[1] : 0) * k
                                        captureSource: win.here ? modelData.wayland : null
                                        live: false
                                    }
                                }
                                Rectangle {
                                    anchors.fill: parent
                                    radius: parent.radius
                                    color: "transparent"
                                    border.width: tile.current || drop.containsDrag ? 2 : 1
                                    border.color: drop.containsDrag || tile.keyed ? Theme.accent : tile.current ? Qt.alpha(Theme.accent, 0.6) : tileHover.hovered ? Qt.rgba(1, 1, 1, 0.3) : Qt.rgba(1, 1, 1, 0.12)
                                }
                            }
                            Label {
                                anchors.horizontalCenter: frame.horizontalCenter
                                anchors.bottom: parent.bottom
                                text: (tile.other ? win.screenLabel(tile.modelData.monitor) + " · " : "") + String(((tile.modelData.id - 1) % 10) + 1)
                                size: 12
                                weight: tile.current ? Theme.wMedium : Theme.wRegular
                                color: tile.current ? Theme.textPrimary : Theme.textSecondary
                            }
                            HoverHandler { id: tileHover; cursorShape: Qt.PointingHandCursor }
                            MouseArea { anchors.fill: frame; onClicked: win.goSpace(tile.modelData.id) }
                            DropArea {
                                id: drop
                                anchors.fill: frame
                                keys: ["kuwai-window"]
                                onDropped: drop => {
                                    const t = drop.source && drop.source.toplevel;
                                    if (t) Hyprland.dispatch(`hl.dsp.window.move({window = 'address:0x${t.address}', workspace = ${tile.modelData.id}, follow = false})`);
                                    Qt.callLater(Hyprland.refreshToplevels);
                                }
                            }
                        }
                    }

                    // New space
                    Item {
                        width: strip.tileW * 0.55
                        height: strip.tileH + 22
                        GlassCard {
                            id: plus
                            width: parent.width
                            height: strip.tileH
                            radius: 10
                            Label { anchors.centerIn: parent; text: "+"; size: 22; color: Theme.textSecondary }
                        }
                        MouseArea { anchors.fill: plus; onClicked: win.goSpace(win.nextFree()) }
                        DropArea {
                            anchors.fill: plus
                            keys: ["kuwai-window"]
                            onDropped: drop => {
                                const t = drop.source && drop.source.toplevel;
                                if (t) Hyprland.dispatch(`hl.dsp.window.move({window = 'address:0x${t.address}', workspace = ${win.nextFree()}, follow = false})`);
                            }
                        }
                    }
                }

                // What the keys do, quietly along the bottom.
                Label {
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 22 }
                    text: win.zone === "spaces"
                        ? "←→  spaces     ↓  windows     Enter  go there     Esc  back"
                        : "←→↑↓  choose     Tab  next     1–9  a space     Enter  go     Del  close     Esc  back"
                    size: 12
                    color: Theme.textTertiary
                }

                // ── Exposé: the windows of the space you're looking at ──────
                Item {
                    id: grid
                    anchors.top: strip.bottom
                    anchors.topMargin: 36
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 64
                    readonly property int n: win.shown.length
                    readonly property int cols: Math.max(1, Math.min(n, Math.ceil(Math.sqrt(n * width / Math.max(1, height) * (win.monH / Math.max(1, win.monW))))))   // never more columns than windows
                    readonly property int rows: Math.max(1, Math.ceil(n / cols))
                    readonly property real cellW: width / cols
                    readonly property real cellH: height / rows

                    // The filter, while typing.
                    Rectangle {
                        visible: win.filter !== ""
                        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.top; bottomMargin: 8 }
                        height: 30; radius: 15
                        width: filterText.implicitWidth + 36
                        color: Qt.rgba(1, 1, 1, 0.1)
                        border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.16)
                        Label { id: filterText; anchors.centerIn: parent; text: "\u{f0349}  " + win.filter; size: 14; weight: Theme.wMedium }
                    }
                    Label {
                        anchors.centerIn: parent
                        visible: grid.n === 0
                        text: win.filter !== "" ? "No windows match “" + win.filter + "”" : "No windows on this space"
                        size: 15
                        color: Theme.textTertiary
                    }

                    Repeater {
                        model: win.shown
                        delegate: Item {
                            id: card
                            required property var modelData
                            required property int index
                            readonly property var toplevel: modelData
                            readonly property var ipc: modelData.lastIpcObject || ({})
                            readonly property real aw: Math.max(1, ipc.size ? ipc.size[0] : 16)
                            readonly property real ah: Math.max(1, ipc.size ? ipc.size[1] : 9)
                            readonly property real fit: Math.min((grid.cellW - 40) / aw, (grid.cellH - 64) / ah, 1)
                            readonly property real homeX: (index % grid.cols) * grid.cellW + (grid.cellW - aw * fit) / 2
                            readonly property real homeY: Math.floor(index / grid.cols) * grid.cellH + (grid.cellH - ah * fit - 26) / 2
                            readonly property bool chosen: win.zone === "windows" && win.picked === index

                            width: aw * fit
                            height: ah * fit + 26
                            x: homeX
                            y: homeY
                            z: mouse.drag.active ? 10 : 0
                            Drag.active: mouse.drag.active
                            Drag.keys: ["kuwai-window"]
                            Drag.source: card
                            Drag.hotSpot.x: width / 2
                            Drag.hotSpot.y: height / 2

                            Rectangle {
                                id: shot
                                width: parent.width
                                height: parent.height - 26
                                radius: 12
                                color: Qt.rgba(0, 0, 0, 0.25)
                                clip: true
                                scale: card.chosen && !mouse.drag.active ? 1.025 : 1
                                Behavior on scale { NumberAnimation { duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }

                                ScreencopyView {
                                    anchors.fill: parent
                                    captureSource: win.here ? card.toplevel.wayland : null
                                    live: win.here
                                }
                                Rectangle {
                                    anchors.fill: parent
                                    radius: parent.radius
                                    color: "transparent"
                                    border.width: card.chosen ? 2 : 1
                                    border.color: card.chosen ? Theme.accent : Qt.rgba(1, 1, 1, 0.10)
                                }
                            }
                            Label {
                                anchors.top: shot.bottom
                                anchors.topMargin: 8
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: Math.min(implicitWidth, parent.width)
                                elide: Text.ElideRight
                                text: card.toplevel.title || (card.ipc["class"] || "")
                                size: 12
                                color: card.chosen ? Theme.textPrimary : Theme.textSecondary
                            }

                            MouseArea {
                                id: mouse
                                anchors.fill: shot
                                acceptedButtons: Qt.LeftButton
                                drag.target: card
                                drag.threshold: 24      // a click that wobbles isn't a move
                                onReleased: {
                                    if (drag.active) {
                                        card.Drag.drop();
                                        card.x = Qt.binding(() => card.homeX);
                                        card.y = Qt.binding(() => card.homeY);
                                    }
                                }
                                onClicked: win.focusWindow(card.toplevel)
                            }
                            // Close, on hover (or Delete / Ctrl+W with it picked).
                            Rectangle {
                                id: closeBtn
                                visible: hover.hovered && !mouse.drag.active
                                z: 2
                                x: -8; y: -8
                                width: 24; height: 24; radius: 12
                                color: closeArea.containsMouse ? Theme.red : Qt.rgba(0.12, 0.12, 0.14, 0.92)
                                border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.18)
                                Text { anchors.centerIn: parent; text: "\u{f0156}"; font.family: Theme.fontGlyph; font.pixelSize: 13; color: Theme.textPrimary }
                                MouseArea { id: closeArea; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.closeWindow(card.toplevel) }
                            }
                            // The pointer moves the same selection the keys do.
                            HoverHandler {
                                id: hover
                                cursorShape: Qt.PointingHandCursor
                                onHoveredChanged: if (hovered) { win.picked = card.index; win.zone = "windows"; }
                            }
                        }
                    }
                }
            }
        }
        }
        }
    }
}
