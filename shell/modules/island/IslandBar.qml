// The island bar (docs/ISLAND.md): the rice's top bar as one island at the top
// centre of each monitor, a notch hanging from the top edge (or a floating
// pill: Settings.islandStyle). On with Settings.bar === "island" (`rice bar
// island`); otherwise it only appears to hold a panel, under Waybar.
//
//   rest     ◉  ● ▮ ● ●  23:29  ▂▄▆ ▭  0:07         (IslandRest: + live activities)
//   hover    app · window / clock · media or rings / workspaces · tray · battery   (IslandHover)
//   panel    calendar, power, launcher, settings, system, theme   (services/Island)
//
// Motion: width and height ride their own springs toward whatever is showing,
// so a change of mind mid-flight turns around without a seam. Growing uses a
// softer spring with a little give (Apple's island: response ≈ 0.42 s,
// damping ≈ 0.78); shrinking is firmer and a touch quicker. The old contents
// fade out early, the new ones fade in late and settle from 97 % scale, so
// the shape leads and the content follows.
//
// Mouse-only navigation: a panel opened from another one shows a back strip
// on top; a right click anywhere in a panel, or the mouse's back button, goes
// back (or closes the first panel). Keys: Esc. A click outside closes.
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import qs.config
import qs.components
import qs.services

Scope {
    id: root

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property ShellScreen modelData
            screen: modelData

            readonly property var monitor: Hyprland.monitorFor(modelData)
            readonly property string screenName: modelData ? modelData.name : screen ? screen.name : (Quickshell.screens[0] ? Quickshell.screens[0].name : "")
            // The dynamic island floats below the edge (the reference); the
            // notch hangs from it (Settings → Bar & Island → Shape).
            readonly property bool notch: Settings.islandStyle === "notch"
            readonly property int restH: 34
            readonly property real restW: restRow.implicitWidth + 32
            readonly property int top: notch ? 0 : 6
            readonly property real ear: notch ? 9 : 0

            readonly property bool showBar: Settings.bar === "island"
            // Tucked (Settings.islandTucked): no reserved strip; out only while
            // something is alive here or you're near it.
            readonly property bool tucked: showBar && Settings.islandTucked
            readonly property bool outNow: !tucked || panelHere || bannerHere || peekHere || deviceHere || grown || near || hovered
                                           || (Island.peek && Island.peekScreen === screenName) || restRow.activity !== ""
                                           || Notifs.missed.length > 0
            readonly property bool panelHere: Island.panel !== "" && Island.screen === screenName
            property string shownPanel: ""
            onPanelHereChanged: {
                if (panelHere) {
                    shownPanel = Island.panel;
                    grown = false;
                    armed = false;
                    arm.restart();
                    idle.restart();
                } else if (hovered) {
                    grown = true;           // back to the island you came from, not all the way down
                }
            }
            Connections {
                target: Island
                function onPanelChanged() { if (win.panelHere) win.shownPanel = Island.panel; }
            }
            // Another workspace: a panel left open would only be in the way (and its key would close it).
            Connections {
                target: win.monitor
                function onActiveWorkspaceChanged() { if (win.panelHere) Island.close(); }
            }
            // A panel left alone folds back by itself once the pointer has gone:
            // glance panels quickly, the ones you work in after a while.
            Timer {
                id: idle
                interval: ["calendar", "system", "power"].includes(win.shownPanel) ? 12000 : 30000
                running: win.panelHere && !win.hovered
                onTriggered: Island.close()
            }

            anchors.top: true
            // Wide enough for the widest panel (themes, 980) plus its shadow;
            // the mask keeps the empty sides click-through.
            implicitWidth: 1120
            implicitHeight: 640
            exclusiveZone: showBar && !tucked ? restH + top + (notch ? 2 : 6) : 0
            color: "transparent"
            WlrLayershell.namespace: "rice-islandbar"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: panelHere ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            mask: Region {
                item: frame.opacity > 0.01 ? frame : null
                // Minimal island: the strip along the top edge beside it counts too.
                Region { item: Settings.islandRest === "minimal" || win.tucked ? nearStrip : null }
                Region { item: win.hovered ? slop : null }
            }
            // Nearing the island: the pointer resting on the top edge over it
            // (its resting width and 80 px either side, not the grown one, so
            // passing along the edge to a tab doesn't catch it) shows the
            // minimal island's details, or the tucked island itself. A brief
            // rest (90 ms) tells reaching it from passing by. It folds away
            // 450 ms after the pointer has left both the edge and the island.
            property bool near: false
            Item {
                id: nearStrip
                width: Math.max(win.restW + 160, 360); height: 4
                x: Math.round((win.width - width) / 2); y: 0
                HoverHandler { id: nearHover; onHoveredChanged: { if (hovered) { nearOff.stop(); nearDwell.restart(); } else { nearDwell.stop(); if (win.near) nearOff.restart(); } } }
            }
            Timer { id: nearDwell; interval: 90; onTriggered: win.near = true }
            Timer { id: nearOff; interval: 450; onTriggered: if (!win.hovered && !nearHover.hovered) win.near = false }
            // Shown by nearing, the island grows only once the pointer comes
            // down onto it, not while it rests on the screen's edge.
            readonly property bool edgeOnly: (win.tucked || Settings.islandRest === "minimal") && frameHover.hovered && frameHover.point.position.y < 6

            property bool armed: false
            Timer { id: arm; interval: 160; onTriggered: win.armed = true }
            HyprlandFocusGrab {
                windows: [win]
                active: win.panelHere && win.armed
                onCleared: if (win.panelHere) Island.close()
            }

            // ── Hover, with intent ───────────────────────────────────────
            property bool hovered: false
            property bool grown: false
            // Over the workspace pills the island stays put: they're for clicking.
            readonly property bool overPills: restRow.pillsHovered || restRow.musicHovered || restRow.marksHovered
            // Minimal, reached on the island itself (not by the edge): the
            // compact row holds still under the pointer, so the art or a mark
            // you aimed at stays there; music opens Now Playing from it.
            property bool holdCompact: false
            // Reached by the island itself, kept by it and 8 px around (hit
            // slop): grazing its edge doesn't flicker it. A press there lets
            // go at once, so the next click reaches what's beneath.
            function syncHover() {
                const h = frameHover.hovered || (hovered && slopHover.hovered);
                if (h && !hovered) holdCompact = restRow.compact;
                if (!h) { holdCompact = false; pushed = false; }
                hovered = h;
                if (bannerHere || !h) Alerts.held = h && bannerHere;
                if (peekHere || !h) Notifs.peekHeld = h && peekHere;
                if (deviceHere || !h) Moments.cardHeld = h && deviceHere;
            }
            onOverPillsChanged: if (!overPills && hovered && !grown) intent.restart()
            // A banner on show stays a banner under the pointer (so its button
            // can be clicked): hovering only grows the island when there's none.
            Timer {
                id: intent; interval: Settings.hoverDelay
                onTriggered: {
                    if (win.hovered && win.edgeOnly && !win.grown) { restart(); return; }
                    if (win.hovered && win.holdCompact && restRow.activity === "media" && !win.panelHere && !win.pushed) { Island.preview("media", win.screenName); return; }
                    win.grown = win.hovered && !win.panelHere && !win.overPills && !win.bannerHere && !win.peekHere && !win.deviceHere && !win.pushed;
                }
            }
            // Open tray menus (TrayRow): the pointer is on the menu, not the
            // island, but the island must stay grown or the menu loses its anchor.
            property int menus: 0
            onMenusChanged: if (menus === 0 && !hovered) leave.restart()
            Timer { id: leave; interval: Theme.hoverLeaveMs; onTriggered: if (!win.hovered && win.menus === 0) win.grown = false }
            onHoveredChanged: {
                hovered ? intent.restart() : leave.restart();
                if (hovered) previewOut.stop(); else if (panelHere && Island.previewing) previewOut.restart();
                if (!hovered && near) nearOff.restart();
            }
            // A previewed panel (Now Playing from the music's art) folds when you leave.
            Timer { id: previewOut; interval: Theme.hoverLeaveMs; onTriggered: if (!win.hovered && win.panelHere && Island.previewing && win.menus === 0) Island.close() }
            // Super+Alt+I (Island.peek): grow here as if hovered, for a moment.
            readonly property bool peeked: Island.peek && Island.peekScreen === screenName
            onPeekedChanged: {
                if (peeked && !panelHere) { if (bannerHere) Alerts.dismiss(); grown = true; }
                else if (!peeked && !hovered && menus === 0) grown = false;
            }

            // Critically damped both ways (ratio 1.0): the shape lands without
            // overshoot, so quick back-to-back changes (a flick through the
            // switcher, a HUD pulse) never jiggle. Growing ~0.33 s, shrinking a
            // touch firmer and quicker.
            // From a key the same morph runs, just quicker (~0.15 s): it is the
            // same object whether you click or press Super+A, so it moves the
            // same way; it only must not make a keypress wait.
            readonly property bool keyed: Island.via === "key"
            readonly property var grow: keyed ? Theme.surfaceKeyIn : Theme.surfaceIn
            readonly property var shrink: keyed ? Theme.surfaceKeyOut : Theme.surfaceOut
            Spring { id: m; tier: win.grown ? win.grow : win.shrink; epsilon: 0.001; target: win.grown && !win.panelHere ? 1 : 0 }
            Spring { id: pv; tier: win.panelHere ? win.grow : win.shrink; epsilon: 0.001; target: win.panelHere ? 1 : 0 }

            readonly property real backH: Island.canBack ? 34 : 0
            readonly property size panelSize: panelLoader.item ? Qt.size(panelLoader.item.implicitWidth, panelLoader.item.implicitHeight + backH) : Qt.size(420, 300)
            readonly property size hoverSize: Qt.size(720, 148)
            // A warning grows the island too (below panels and hover in priority).
            readonly property bool bannerHere: Alerts.banner !== null && screenName === Screens.focusedName && !panelHere && !grown
            Spring { id: bv; tier: win.bannerHere ? win.grow : win.shrink; epsilon: 0.001; target: win.bannerHere ? 1 : 0 }
            // A notification that matters peeks the same way (below a warning).
            readonly property bool peekHere: Notifs.peek !== null && !Notifs.peek.discard && screenName === Screens.focusedName && !panelHere && !grown && !bannerHere
            Spring { id: nv; tier: win.peekHere ? win.grow : win.shrink; epsilon: 0.001; target: win.peekHere ? 1 : 0 }
            // A device connecting or going (Moments.card), below both.
            readonly property bool deviceHere: Moments.card !== null && screenName === Screens.focusedName && !panelHere && !grown && !bannerHere && !peekHere
            Spring { id: dv; tier: win.deviceHere ? win.grow : win.shrink; epsilon: 0.001; target: win.deviceHere ? 1 : 0 }

            // ── Pushing a card back ──────────────────────────────────────
            // A banner, notification or device card isn't something to sit
            // through: drag it up (it follows, rubber-banded, and goes on
            // release past 18 px or a flick), scroll on it, or right-click.
            // The island then stays at rest until the pointer leaves.
            readonly property bool cardHere: bannerHere || peekHere || deviceHere
            property real pull: 0
            property bool committing: false
            property bool pushed: false
            Behavior on pull { enabled: !pushDrag.active && !win.committing; NumberAnimation { duration: 260; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
            function rubber(d, dim) { return d * dim * 0.55 / (dim + 0.55 * d); }
            function pushBack(v) {
                committing = true;
                sh.value = sh.value - pull;
                sh.velocity = Math.min(0, v || 0);
                pull = 0;
                committing = false;
                pushed = true;
                Alerts.held = false; Notifs.peekHeld = false; Moments.cardHeld = false;
                if (bannerHere) Alerts.dismiss();
                else if (peekHere) Notifs.dropPeek();
                else if (deviceHere) Moments.dropCard();
            }
            readonly property real targetW: panelHere ? panelSize.width : grown ? hoverSize.width : bannerHere ? 440 : peekHere ? 460 : deviceHere ? 420 : restRow.implicitWidth + 32
            readonly property real targetH: panelHere ? panelSize.height : grown ? hoverSize.height : bannerHere ? 72 : peekHere ? 76 : deviceHere ? 84 : restH
            // Published so surfaces that grow out of the island (the HUD, the
            // clipboard) start from the shape actually on screen: rest, banner,
            // hover or panel. Changes with the state, not per frame.
            onTargetWChanged: Island.setRestWidth(screenName, targetW)
            Component.onCompleted: Island.setRestWidth(screenName, targetW)
            readonly property var restShape: [restW, restH, top, notch]
            onRestShapeChanged: Island.setRestShape(screenName, restW, restH, top, notch)
            Spring { id: sw; tier: win.targetW >= sw.value ? win.grow : win.shrink; epsilon: 0.3; target: win.targetW; Component.onCompleted: settle() }
            Spring { id: sh; tier: win.targetH >= sh.value ? win.grow : win.shrink; epsilon: 0.3; target: win.targetH; Component.onCompleted: settle() }

            // ── Data the parts share ─────────────────────────────────────
            readonly property int activeWs: monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : 1
            // The special (scratchpad) workspace open on this monitor, from Hyprland's events.
            property string special: ""
            Connections {
                target: Hyprland
                function onRawEvent(event) {
                    if (event.name !== "activespecial") return;
                    const [ws, mon] = event.data.split(",");
                    if (mon === win.screenName) win.special = ws || "";
                }
            }
            readonly property var mine: Hyprland.workspaces.values.filter(w => w.id > 0 && w.monitor === monitor)
            // kuwai gives each screen its own block of ten (laptop 1–10, the Acer
            // 11–20, …) and publishes it (Island.wsBases). Until it has, a guess
            // from the workspaces on this screen.
            readonly property int wsBlock: {
                const known = Island.wsBases[screenName];
                if (known !== undefined) return Math.floor(known / 10);
                if (screenName.startsWith("eDP")) return 0;
                const counts = {};
                for (const w of mine) { const b = Math.floor((w.id - 1) / 10); if (b > 0) counts[b] = (counts[b] || 0) + 1; }
                let best = 1, n = -1;
                for (const b in counts) if (counts[b] > n) { n = counts[b]; best = Number(b); }
                return best;
            }
            readonly property int wsBase: wsBlock * 10
            // The focused screen's island is "on" (where your keys act); the others are quieter.
            readonly property bool focusedHere: screenName === Screens.focusedName
            // The window this screen is showing: the focused window when it's
            // here, else the one you used last on this screen's workspace.
            readonly property var screenWin: {
                const a = Hyprland.activeToplevel;
                if (focusedHere && a && a.workspace && a.workspace.id === activeWs) return a;
                const here = Hyprland.toplevels.values.filter(t => t.workspace && t.workspace.id === activeWs && t.workspace.name !== "special:minimized");
                if (!here.length) return null;
                const rank = t => { const i = Switcher.mru.indexOf(t.address); return i < 0 ? 1e6 : i; };
                return here.slice().sort((x, y) => rank(x) - rank(y))[0];
            }
            // How many pills: this screen's 1…N, N = the larger of the minimum
            // (Settings.workspaceCount), the highest one in use and the current
            // one. Desktops: in use on any screen.
            readonly property var deskCount: {
                const count = {};
                if (!Island.desktops) return count;
                for (const w of Hyprland.workspaces.values) if (w.id > 0) { const n = (w.id - 1) % 10 + 1; count[n] = (count[n] || 0) + (w.toplevels ? w.toplevels.values.length : 0); }
                return count;
            }
            readonly property int wsNeed: {
                const inBlock = id => id > wsBase && id <= wsBase + 10;
                let n = Settings.workspaceCount;
                if (inBlock(activeWs)) n = Math.max(n, activeWs - wsBase);
                if (Island.desktops) { for (const k in deskCount) if (deskCount[k] > 0) n = Math.max(n, Number(k)); }
                else for (const w of mine) if (inBlock(w.id) && w.toplevels && w.toplevels.values.length > 0) n = Math.max(n, w.id - wsBase);
                return Math.min(10, n);
            }
            // The row grows at once but shrinks back only after a pause, and not
            // while you're on the island: it doesn't jump around under you.
            property int wsHeld: 0
            onWsNeedChanged: { if (wsNeed > wsHeld) wsHeld = wsNeed; wsShrink.restart(); }
            Timer { id: wsShrink; interval: 2500; onTriggered: { if (win.hovered) restart(); else win.wsHeld = win.wsNeed; } }
            readonly property int wsShown: Math.max(wsNeed, wsHeld)
            // Desktops (kuwai `desktops`): one row, the same on every screen.
            readonly property var deskList: {
                if (!Island.desktops) return null;
                const out = [];
                for (let i = 1; i <= wsShown; i++) out.push({ id: wsBase + i, desktop: i, guest: false, windows: deskCount[i] || 0, used: (deskCount[i] || 0) > 0 });
                return out;
            }
            // Workspaces from another screen's block that ended up here (an
            // unplugged monitor) follow after a gap, hollow.
            readonly property var wsList: deskList || (function() {
                const base = wsBase;
                const inBlock = id => id > base && id <= base + 10;
                const used = mine.filter(w => w.toplevels && w.toplevels.values.length > 0).map(w => w.id);
                const out = [];
                for (let i = 1; i <= wsShown; i++) out.push({ id: base + i, guest: false });
                const guests = used.concat([activeWs]).filter(id => id > 0 && !inBlock(id));
                for (const id of [...new Set(guests)].sort((a, b) => a - b)) out.push({ id: id, guest: true });
                return out;
            })()
            // The other screens, for the small dots beside the pills: what each
            // one shows and what's open there, on the side it sits (a screen to
            // the left of this one, left of the pills). A click goes there.
            // Desktops switch together, so there's nothing to show.
            readonly property var others: {
                if (Island.desktops || !modelData) return [];
                const out = [];
                for (const s of Quickshell.screens) {
                    if (!s || s.name === screenName) continue;
                    const hm = Hyprland.monitorFor(s);
                    if (!hm) continue;
                    const act = hm.activeWorkspace ? hm.activeWorkspace.id : 0;
                    const list = Hyprland.workspaces.values
                        .filter(w => w.id > 0 && w.monitor === hm && (w.id === act || (w.toplevels && w.toplevels.values.length > 0)))
                        .sort((a, b) => a.id - b.id)
                        .map(w => ({ id: w.id, on: w.id === act, windows: w.toplevels ? w.toplevels.values.length : 0 }));
                    if (!list.length) continue;
                    const make = ((hm.lastIpcObject || {}).make || "").split(" ")[0];
                    out.push({ screen: s.name, label: s.name.startsWith("eDP") ? "Laptop" : (make || s.name), x: s.x, left: s.x < modelData.x, list: list });
                }
                return out.sort((a, b) => a.x - b.x);
            }
            // One player for every part (services/Media: it stays the one you
            // used until another starts playing; pausing no longer swaps it).
            readonly property var player: Media.active
            readonly property bool showMedia: Settings.hoverMedia && player !== null
            property date now: new Date()
            // Once a minute, on the minute (the clock shows hours:minutes);
            // every second only when it shows seconds.
            Timer {
                running: true; repeat: true; triggeredOnStart: true
                interval: Settings.showSeconds ? 1000 : 60000 - (Date.now() % 60000) + 20
                onTriggered: {
                    win.now = new Date();
                    if (!Settings.showSeconds) interval = 60000 - (Date.now() % 60000) + 20;
                }
            }

            Component { id: calendarPanel; CalendarPanel {} }
            Component { id: powerPanel; PowerPanel {} }
            Component { id: launcherPanel; LauncherPanel {} }
            Component { id: settingsPanel; SettingsPanel {} }
            Component { id: systemPanel; SystemPanel {} }
            Component { id: themePanel; ThemePanel {} }
            Component { id: keysPanel; KeysPanel {} }
            Component { id: switcherPanel; SwitcherPanel {} }
            Component { id: updatesPanel; UpdatesPanel {} }
            Component { id: mediaPanel; MediaPanel {} }

            Elevation {
                target: frame
                radius: Math.min(frame.height / 2, 30)
                strength: (0.25 + 0.75 * Math.max(m.value, pv.value)) * frame.opacity
            }
            Item {
                id: slop
                x: frame.x - 8; y: 0
                width: frame.width + 16; height: frame.y + frame.height + 8
                HoverHandler { id: slopHover; onHoveredChanged: win.syncHover() }
                PointHandler { acceptedButtons: Qt.AllButtons; onActiveChanged: if (active && !frameHover.hovered) { win.hovered = false; win.syncHover(); } }
            }
            Item {
                id: frame
                width: Math.max(0, sw.value) + win.ear * 2
                height: Math.max(0, sh.value - win.pull)
                x: Math.round((win.width - width) / 2)
                y: win.top
                // Without the bar it is only there for a panel: it fades in as it grows.
                opacity: win.showBar ? (win.outNow ? 1 : 0) : Math.max(0, Math.min(1, Math.max(pv.value, bv.value, nv.value, dv.value) * 2.5))
                Behavior on opacity { enabled: win.tucked || !win.outNow; NumberAnimation { duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }

                HoverHandler { id: frameHover; onHoveredChanged: win.syncHover() }
                DragHandler {
                    id: pushDrag
                    enabled: win.cardHere
                    target: null
                    xAxis.enabled: false
                    onCentroidChanged: {
                        if (!active) return;
                        const dy = centroid.scenePosition.y - centroid.scenePressPosition.y;
                        win.pull = dy < 0 ? win.rubber(-dy, 80) : -win.rubber(dy, 30);
                    }
                    onActiveChanged: if (!active && win.cardHere) { if (win.pull > 18 || centroid.velocity.y < -400) win.pushBack(centroid.velocity.y); else win.pull = 0; }
                }
                WheelHandler {
                    enabled: win.cardHere
                    property real sum: 0
                    // Upward only (the wheel rolled up, or two fingers swiped up,
                    // whichever way natural scrolling flips the delta).
                    onWheel: event => {
                        const up = (event.inverted ? -1 : 1) * (event.pixelDelta.y || event.angleDelta.y);
                        sum = up > 0 ? sum + up : 0;
                        if (sum >= 60) { sum = 0; win.pushBack(-600); }
                    }
                }
                TapHandler { enabled: win.cardHere; acceptedButtons: Qt.RightButton; onTapped: win.pushBack(0) }

                // The island itself: a notch, or a floating black-glass pill.
                NotchShape {
                    visible: win.notch
                    w: Math.max(0, sw.value)
                    h: frame.height
                    ear: win.ear
                    radius: frame.height <= win.restH + 1 ? 14 : 30
                    fill: Qt.rgba(0, 0, 0, 0.94)
                }
                GlassCard {
                    visible: !win.notch
                    anchors.fill: parent
                    radius: Math.min(frame.height / 2, 30)
                    tint: Qt.rgba(0, 0, 0, 0.9)
                }

                Item {
                    id: body
                    x: win.ear
                    width: Math.max(0, sw.value)
                    height: frame.height
                    clip: true
                    opacity: 1 - 0.7 * Math.min(1, Math.max(0, win.pull) / 45)

                    // ── At rest ──────────────────────────────────────────
                    IslandRest {
                        id: restRow
                        bar: win
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: Math.round((win.restH - height) / 2)
                        opacity: Math.max(0, 1 - Math.max(m.value, pv.value, bv.value, nv.value, dv.value) * 3)
                        visible: opacity > 0.01
                    }

                    // ── Hovered ──────────────────────────────────────────
                    Loader {
                        id: hoverLoader
                        active: win.grown || m.value > 0.01
                        x: Math.round((body.width - win.hoverSize.width) / 2)
                        width: win.hoverSize.width
                        height: win.hoverSize.height
                        readonly property real k: Math.max(0, Math.min(1, (m.value - 0.25) / 0.5))
                        opacity: k * Math.max(0, 1 - pv.value * 3)
                        scale: 0.97 + 0.03 * k
                        transformOrigin: Item.Top
                        visible: opacity > 0.01
                        sourceComponent: IslandHover { bar: win }
                    }

                    // ── A warning ────────────────────────────────────────
                    Loader {
                        id: alertLoader
                        active: win.bannerHere || bv.value > 0.01
                        x: Math.round((body.width - 440) / 2)
                        readonly property real k: Math.max(0, Math.min(1, (bv.value - 0.3) / 0.5))
                        opacity: k * Math.max(0, 1 - Math.max(m.value, pv.value) * 3)
                        visible: opacity > 0.01
                        property var keep: null
                        // Keeps the last alert on screen while the island folds back.
                        sourceComponent: AlertBanner { alert: Alerts.banner || alertLoader.keep; bar: win }
                        Connections { target: Alerts; function onBannerChanged() { if (Alerts.banner) alertLoader.keep = Alerts.banner; } }
                    }

                    // ── A notification that matters ──────────────────────
                    Loader {
                        id: peekLoader
                        active: win.peekHere || nv.value > 0.01
                        x: Math.round((body.width - 460) / 2)
                        readonly property real k: Math.max(0, Math.min(1, (nv.value - 0.3) / 0.5))
                        opacity: k * Math.max(0, 1 - Math.max(m.value, pv.value, bv.value) * 3)
                        visible: opacity > 0.01
                        property var keep: null
                        sourceComponent: NotifPeek { item: Notifs.peek || peekLoader.keep; bar: win }
                        Connections { target: Notifs; function onPeekChanged() { if (Notifs.peek) peekLoader.keep = Notifs.peek; } }
                    }

                    // ── A device ─────────────────────────────────────────
                    Loader {
                        id: deviceLoader
                        active: win.deviceHere || dv.value > 0.01
                        x: Math.round((body.width - 420) / 2)
                        readonly property real k: Math.max(0, Math.min(1, (dv.value - 0.3) / 0.5))
                        opacity: k * Math.max(0, 1 - Math.max(m.value, pv.value, bv.value, nv.value) * 3)
                        visible: opacity > 0.01
                        property var keep: null
                        sourceComponent: DeviceCard { item: Moments.card || deviceLoader.keep; bar: win }
                        Connections { target: Moments; function onCardChanged() { if (Moments.card) deviceLoader.keep = Moments.card; } }
                    }

                    // ── A panel ──────────────────────────────────────────
                    FocusScope {
                        id: panelScope
                        width: win.panelSize.width
                        height: win.panelSize.height
                        x: Math.round((body.width - width) / 2)
                        focus: win.panelHere
                        readonly property real k: Math.max(0, Math.min(1, (pv.value - 0.5) / 0.4))
                        opacity: k
                        scale: 0.97 + 0.03 * k
                        transformOrigin: Item.Top
                        visible: opacity > 0.01 || win.panelHere
                        // Materialize: the content comes into focus while it drops the
                        // last few pixels out of the island, and goes back the same
                        // way. The blur layer exists only mid-transition (never at
                        // rest, so no offscreen texture while you use the panel).
                        transform: Translate { y: Theme.reduceMotion ? 0 : -8 * (1 - panelScope.k) }
                        layer.enabled: !Theme.reduceMotion && panelScope.k > 0.001 && panelScope.k < 0.995
                        layer.smooth: true
                        layer.effect: MultiEffect {
                            blurEnabled: true
                            blurMax: 24
                            blur: Math.pow(1 - panelScope.k, 1.5) * 0.7
                            autoPaddingEnabled: false
                        }
                        Keys.onEscapePressed: Island.back()
                        Keys.onPressed: event => { idle.restart(); event.accepted = false; }

                        // Back strip: where you came from, one click away.
                        Item {
                            id: backStrip
                            visible: Island.canBack
                            width: parent.width; height: win.backH
                            Rectangle {
                                x: 14; y: 10
                                height: 24; radius: 12
                                width: backRow.implicitWidth + 18
                                color: backArea.containsMouse ? Theme.pillHover : Theme.pill
                                Behavior on color { ColorAnimation { duration: Theme.colorMs } }
                                Row {
                                    id: backRow
                                    anchors.centerIn: parent
                                    spacing: 4
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: "\u{f0141}"; font.family: Theme.fontGlyph; font.pixelSize: 14; color: Theme.textSecondary }
                                    Label {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: Island.innerBackLabel || ({ calendar: "Calendar", power: "Power", launcher: "Search", settings: "Settings", system: "System", theme: "Themes", keys: "Shortcuts", switcher: "Windows", updates: "Software Update" })[Island.history[Island.history.length - 1]] || "Back"
                                        size: 12; weight: Theme.wMedium; color: Theme.textSecondary
                                    }
                                }
                                MouseArea { id: backArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Island.back() }
                            }
                        }
                        Loader {
                            id: panelLoader
                            y: win.backH
                            active: win.panelHere || pv.value > 0.01
                            focus: true
                            sourceComponent: ({ calendar: calendarPanel, power: powerPanel, launcher: launcherPanel, settings: settingsPanel, system: systemPanel, theme: themePanel, keys: keysPanel, switcher: switcherPanel, updates: updatesPanel, media: mediaPanel })[win.shownPanel] || null
                        }
                        // Right click (anywhere a control doesn't take it) or the mouse's back button: back.
                        TapHandler {
                            acceptedButtons: Qt.RightButton | Qt.BackButton
                            onTapped: Island.back()
                        }
                    }
                }
            }
        }
    }
}
