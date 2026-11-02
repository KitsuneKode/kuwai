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
            exclusiveZone: showBar ? restH + top + (notch ? 2 : 6) : 0
            color: "transparent"
            WlrLayershell.namespace: "rice-islandbar"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: panelHere ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            mask: Region { item: frame.opacity > 0.01 ? frame : null }

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
            readonly property bool overPills: restRow.pillsHovered
            onOverPillsChanged: if (!overPills && hovered && !grown) intent.restart()
            // A banner on show stays a banner under the pointer (so its button
            // can be clicked): hovering only grows the island when there's none.
            Timer { id: intent; interval: Settings.hoverDelay; onTriggered: win.grown = win.hovered && !win.panelHere && !win.overPills && !win.bannerHere }
            // Open tray menus (TrayRow): the pointer is on the menu, not the
            // island, but the island must stay grown or the menu loses its anchor.
            property int menus: 0
            onMenusChanged: if (menus === 0 && !hovered) leave.restart()
            Timer { id: leave; interval: 260; onTriggered: if (!win.hovered && win.menus === 0) win.grown = false }
            onHoveredChanged: hovered ? intent.restart() : leave.restart()

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
            readonly property real targetW: panelHere ? panelSize.width : grown ? hoverSize.width : bannerHere ? 440 : restRow.implicitWidth + 32
            readonly property real targetH: panelHere ? panelSize.height : grown ? hoverSize.height : bannerHere ? 72 : restH
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
            // kuwai gives each screen its own block of ten (1–10, 11–20, …): pills are
            // numbered within this screen's block.
            readonly property int wsBase: Math.floor((Math.max(1, activeWs) - 1) / 10) * 10
            readonly property int wsCount: Math.max(Settings.workspaceCount, ...mine.map(w => w.id - wsBase), activeWs - wsBase)
            // The pills. kuwai gives each screen a block of ten (laptop 1–10, the
            // next screen 11–20…): show this screen's 1…N, N = the larger of the
            // minimum (Settings.workspaceCount), the highest one in use and the
            // current one. Workspaces from another screen's block that ended up
            // here (an unplugged monitor) follow after a gap, hollow.
            readonly property int wsBlock: {
                if (screenName.startsWith("eDP")) return 0;
                const counts = {};
                for (const w of mine) { const b = Math.floor((w.id - 1) / 10); if (b > 0) counts[b] = (counts[b] || 0) + 1; }
                let best = 1, n = -1;
                for (const b in counts) if (counts[b] > n) { n = counts[b]; best = Number(b); }
                return best;
            }
            readonly property var wsList: {
                const base = wsBlock * 10;
                const inBlock = id => id > base && id <= base + 10;
                const used = mine.filter(w => w.toplevels && w.toplevels.values.length > 0).map(w => w.id);
                let n = Settings.workspaceCount;
                for (const id of used.concat([activeWs])) if (inBlock(id)) n = Math.max(n, id - base);
                const out = [];
                for (let i = 1; i <= Math.min(10, n); i++) out.push({ id: base + i, guest: false });
                const guests = used.concat([activeWs]).filter(id => id > 0 && !inBlock(id));
                for (const id of [...new Set(guests)].sort((a, b) => a - b)) out.push({ id: id, guest: true });
                return out;
            }
            readonly property var player: Mpris.players.values.find(p => p.playbackState === MprisPlaybackState.Playing) || Mpris.players.values[0] || null
            readonly property bool showMedia: Settings.hoverMedia && player !== null
            property date now: new Date()
            Timer { interval: 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: win.now = new Date() }

            Component { id: calendarPanel; CalendarPanel {} }
            Component { id: powerPanel; PowerPanel {} }
            Component { id: launcherPanel; LauncherPanel {} }
            Component { id: settingsPanel; SettingsPanel {} }
            Component { id: systemPanel; SystemPanel {} }
            Component { id: themePanel; ThemePanel {} }
            Component { id: keysPanel; KeysPanel {} }
            Component { id: switcherPanel; SwitcherPanel {} }
            Component { id: updatesPanel; UpdatesPanel {} }

            Elevation {
                target: frame
                radius: Math.min(frame.height / 2, 30)
                strength: (0.25 + 0.75 * Math.max(m.value, pv.value)) * frame.opacity
            }
            Item {
                id: frame
                width: Math.max(0, sw.value) + win.ear * 2
                height: Math.max(0, sh.value)
                x: Math.round((win.width - width) / 2)
                y: win.top
                // Without the bar it is only there for a panel: it fades in as it grows.
                opacity: win.showBar ? 1 : Math.max(0, Math.min(1, Math.max(pv.value, bv.value) * 2.5))

                HoverHandler { onHoveredChanged: { win.hovered = hovered; if (win.bannerHere || !hovered) Alerts.held = hovered && win.bannerHere; } }

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

                    // ── At rest ──────────────────────────────────────────
                    IslandRest {
                        id: restRow
                        bar: win
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: Math.round((win.restH - height) / 2)
                        opacity: Math.max(0, 1 - Math.max(m.value, pv.value, bv.value) * 3)
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
                            sourceComponent: ({ calendar: calendarPanel, power: powerPanel, launcher: launcherPanel, settings: settingsPanel, system: systemPanel, theme: themePanel, keys: keysPanel, switcher: switcherPanel, updates: updatesPanel })[win.shownPanel] || null
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
