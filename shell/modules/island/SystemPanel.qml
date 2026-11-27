// System, grown out of the island: one of the island's sections (Agents ·
// Usage · System · Cleanup, the strip at its top right; ⌥3). The machine at a
// glance (what Waybar's cpu, memory, gpuinfo, sensorsinfo and updates modules
// showed) and the quick switches that lived beside them. Opened by the rings
// in the expanded island, the hover view's gauge, the launcher, its shortcut,
// `kuwai system`. "vitals" (the old machine + usage panel) is an alias for it
// (Island.aliases); what that panel added is here (memory by app), and the
// agents' usage is the Usage section beside it.
//
//   System                                       up 1d 11h · load 2.1
//   CPU  23%  85°      ▁▃▂▅▁▁▂▇▃▁▂▁▄▂▁▃   (16 threads)    Fans 3700 · 4000 rpm
//   Memory  9.1 GB of 16 GB in use   ●●●●●●●○○○ (by app: point at the dots)
//   NVIDIA GPU · 72° · 28 W  33%  ━━━━────  VRAM 1.2 of 6 GB
//   [ Game mode ] [ Night light ] [ Caffeine ] [ Focus ]
//   12 updates available                                 Review and update ›
//
// Numbers that need a process (kuwai-procs, hyprctl) are read only while this
// is open: the poll lives in the panel and goes with it (Theme.panelPollMs).
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.components
import qs.components.ui
import qs.services

FocusScope {
    id: sys
    property bool inStrip: false
    property string tab: "overview"
    readonly property bool overview: tab === "overview"
    readonly property string headerMeta: uptime + (SystemStats.load ? " · load " + SystemStats.load.split(" ")[0] : "")
    focus: true
    implicitWidth: Theme.panelM
    implicitHeight: col.implicitHeight + 40

    Component.onCompleted: { SystemStats.watch(); gameProbe.running = true; }
    Component.onDestruction: SystemStats.unwatch()
    Keys.onPressed: e => {
        if (e.key === Qt.Key_Tab && (e.modifiers & Qt.ControlModifier)) { tab = overview ? "activity" : "overview"; e.accepted = true; }
    }

    // Memory by what holds it: PSS, so a browser's twenty processes count once.
    property var memApps: []
    Process {
        id: memProbe
        command: [Paths.bin + "/kuwai-procs", "--by-app"]
        stdout: StdioCollector { onStreamFinished: { try { sys.memApps = JSON.parse(text); } catch (e) {} } }
    }
    Timer { interval: Theme.panelPollMs; repeat: true; running: sys.overview; triggeredOnStart: true; onTriggered: memProbe.running = true }

    // Game mode: HyDE's when it's installed, else kuwai's own gaming mode (the
    // same as Super+Alt+G); both turn animations off, which is what's read.
    property bool gameMode: false
    Process {
        id: gameProbe
        command: ["hyprctl", "getoption", "animations:enabled", "-j"]
        stdout: StdioCollector { onStreamFinished: { try { sys.gameMode = JSON.parse(text).int === 0; } catch (e) {} } }
    }
    function toggleGame() {
        if (Hyde.hasShell) Quickshell.execDetached(["hyde-shell", "gamemode"]);
        else Quickshell.execDetached(["hyprctl", "eval", "kuwai.mode_toggle('gaming')"]);
        gameMode = !gameMode;
    }

    property string uptime: ""
    FileView {
        path: "/proc/uptime"
        blockLoading: true          // read now: an async read finishing after the panel closed could crash
        onLoaded: {
            const s = Math.floor(parseFloat(text()));
            const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
            sys.uptime = "up " + (d ? d + "d " : "") + (d || h ? h + "h " : "") + m + "m";
        }
    }

    // The tallest a panel may be: the island's surface (IslandBar: at most
    // 640, the screen less 24), less its 40 of margin and the 34 of the
    // section strip above the panel. What's left after the header, the CPU
    // card and the switches is the readings' room.
    readonly property bool hasNvidia: SystemStats.gpuState !== ""
    readonly property bool hasIntel: SystemStats.igpuMax > 0
    readonly property real ceiling: Math.min(640, Theme.screenSize(Screen, "height", 1080) - 24) - 40 - Theme.sp(34)
    readonly property real room: Math.max(120, ceiling - 40 - head.height - tabs.height - cpuCard.height - tiles.height
        - (SystemStats.updates > 0 ? upd.height + col.spacing : 0) - col.spacing * 4)
    readonly property real activityRoom: Math.min(ceiling, Theme.panelMaxH - (inStrip ? Theme.sp(34) : 0) - 40)
        - (inStrip ? 0 : head.height + col.spacing) - tabs.height - col.spacing

    Column {
        id: col
        x: 22; y: sys.inStrip ? Theme.s2 : 20
        width: parent.width - 44
        spacing: 14

        Item {
            id: head
            visible: !sys.inStrip
            width: parent.width; height: 26
            Label { anchors.verticalCenter: parent.verticalCenter; text: "System"; size: Theme.tTitle3; weight: Theme.wSemibold }
            Label {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: sys.uptime + (SystemStats.load ? "  ·  load " + SystemStats.load.split(" ")[0] : "")
                size: Theme.tSub; color: Theme.textTertiary
            }
        }

        Segmented {
            id: tabs
            width: implicitWidth
            options: [{ id: "overview", label: "Overview" }, { id: "activity", label: "Activity" }]
            current: sys.tab
            onPicked: id => sys.tab = id
        }

        Loader {
            id: activityTab
            width: parent.width
            active: !sys.overview
            visible: active
            focus: active
            sourceComponent: ActivityView { maxHeight: sys.activityRoom }
        }

        // ── CPU ──────────────────────────────────────────────────────────
        Card {
            id: cpuCard
            visible: sys.overview
            Row {
                spacing: 18
                Column {
                    width: 128
                    spacing: 2
                    Label { text: "CPU"; size: Theme.tFootnote; weight: Theme.wMedium; color: Theme.textTertiary }
                    Row {
                        spacing: 8
                        Label { text: Math.round(SystemStats.cpu * 100) + "%"; size: Theme.tTitle1; weight: Theme.wSemibold; rounded: true; tabular: true }
                        Label {
                            anchors.baseline: parent.children[0].baseline
                            visible: SystemStats.cpuTemp > 0
                            text: SystemStats.cpuTemp + "°"
                            size: Theme.tCallout; weight: Theme.wMedium; rounded: true
                            color: SystemStats.cpuTemp >= 90 ? Theme.red : SystemStats.cpuTemp >= 80 ? Theme.orange : Theme.textSecondary
                        }
                    }
                    Label { text: SystemStats.fans.length ? "Fans " + SystemStats.fans.join(" · ") + " rpm" : ""; size: Theme.tFootnote; color: Theme.textTertiary }
                }
                // One bar per thread, narrower when there are many (32
                // threads at 14 px ran out of the card).
                Row {
                    id: bars
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4
                    readonly property real room: col.width - 28 - 128 - 18
                    readonly property real barW: Math.max(3, Math.min(14, (room + spacing) / Math.max(1, SystemStats.cores.length) - spacing))
                    Repeater {
                        model: SystemStats.cores.length
                        Item {
                            required property int index
                            readonly property real v: SystemStats.cores[index] || 0
                            width: bars.barW; height: 48
                            HoverHandler { id: coreHover }
                            Tip {
                                text: "Thread " + parent.index + " · " + SystemStats.coreKind(parent.index) + " · " + Math.round(parent.v * 100) + "%" + (SystemStats.coreMHz[parent.index] ? " · " + (SystemStats.coreMHz[parent.index] / 1000).toFixed(1) + " GHz" : "")
                                shown: coreHover.hovered
                            }
                            Rectangle { anchors.fill: parent; radius: 4; color: Theme.wash(1) }
                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width; radius: 4
                                height: Math.max(3, parent.height * parent.v)
                                color: parent.v > 0.9 ? Theme.red : parent.v > 0.7 ? Theme.orange : Theme.accent
                                Behavior on height { NumberAnimation { duration: Theme.glideMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                            }
                        }
                    }
                }
            }
        }

        // The readings below the CPU scroll when they would not fit; the
        // switches under them never leave the panel. (Memory by app made the
        // column taller than the island's ceiling: on a 1080-high screen the
        // four switches were cut off at the bottom edge, seen 2026-11-17.)
        Item {
          visible: sys.overview
          width: parent.width
          height: readings.height
        Flickable {
            id: readings
            width: parent.width
            height: Math.min(readCol.implicitHeight, sys.room)
            contentHeight: readCol.implicitHeight
            clip: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height
        Column {
            id: readCol
            width: readings.width
            spacing: col.spacing

        // ── Memory, by what holds it (Clove's storage bar) ───────────────
        // One big number, the dots by app, a legend that lights with them.
        Card {
            LinkedBar {
                width: parent.width
                title: "Memory"
                big: SystemStats.bytes(SystemStats.memUsed)
                caption: "of " + SystemStats.bytes(SystemStats.memTotal) + " in use"
                    + (SystemStats.swapUsed > 1048576 ? " · swap " + SystemStats.bytes(SystemStats.swapUsed) : "")
                    + (sys.memApps.length ? " · point at the dots" : "")
                total: SystemStats.memTotal / 1073741824
                unit: " GB"
                parts: {
                    const pal = [Theme.orange, Theme.blue, Theme.green, Theme.indigo, Theme.cyan, Theme.yellow, Theme.red];
                    const used = SystemStats.memUsed / 1073741824;
                    const top = sys.memApps.slice(0, 6).map((a, i) => ({ label: a.app, value: a.mb / 1024, color: pal[i],
                        detail: a.count + (a.count === 1 ? " process" : " processes") }));
                    const rest = Math.max(0, used - top.reduce((n, p) => n + p.value, 0));
                    return rest > 0.05 ? top.concat([{ label: "Everything else", value: rest, color: Theme.gray, detail: "the system, caches the kernel can't drop, the rest" }]) : top;
                }
            }
        }

        // ── GPU ──────────────────────────────────────────────────────────
        // Two GPUs sit side by side: one row instead of two cards' height.
        Row {
            width: parent.width
            spacing: col.spacing
            // From the readings, not from the cards' own `visible`: an item
            // inside a hidden row reports false, so the row asking its cards
            // never showed (both GPU cards vanished, seen 2026-11-17).
            visible: sys.hasNvidia || sys.hasIntel
        Card {
            id: nvidia
            width: sys.hasIntel ? (parent.width - parent.spacing) / 2 : parent.width
            visible: sys.hasNvidia
            Meter {
                title: (SystemStats.gpuVendor === "amd" ? "AMD GPU" : "NVIDIA GPU") + (SystemStats.gpuTemp ? "  ·  " + SystemStats.gpuTemp + "°" : "") + (SystemStats.gpuPower ? "  ·  " + Math.round(SystemStats.gpuPower) + " W" : "")
                value: SystemStats.gpuState === "suspended" ? 0 : SystemStats.gpu
                big: SystemStats.gpuState === "suspended" ? "Asleep" : Math.round(SystemStats.gpu * 100) + "%"
                detail: SystemStats.gpuState === "suspended" ? "Powered down: nothing is using it"
                      : "VRAM " + (SystemStats.gpuMemUsed / 1024).toFixed(1) + " of " + (SystemStats.gpuMemTotal / 1024).toFixed(0) + " GB"
            }
        }

        // The Intel GPU (it drives the laptop screen; no busy % is exposed, so its clock stands in).
        Card {
            id: intel
            width: sys.hasNvidia ? (parent.width - parent.spacing) / 2 : parent.width
            visible: sys.hasIntel
            Meter {
                title: "Intel GPU (integrated)"
                value: SystemStats.igpuMax ? SystemStats.igpuMHz / SystemStats.igpuMax : 0
                big: SystemStats.igpuMHz ? SystemStats.igpuMHz + " MHz" : "Idle"
                detail: "Clock " + SystemStats.igpuMHz + " of " + SystemStats.igpuMax + " MHz"
            }
        }

        }   // the GPU row
        }   // readCol
        }   // readings
        ScrollFade { flickable: readings }
        ScrollHint { flickable: readings; anchors { right: parent.right; top: parent.top; bottom: parent.bottom; rightMargin: -10 } }
        }

        // ── Game mode, and the rest of the switches where they live ──────
        Grid {
            id: tiles
            visible: sys.overview
            width: parent.width
            columnSpacing: 8; rowSpacing: 8
            columns: 2
            readonly property real cellW: (width - columnSpacing) / 2
            Tile { id: game; width: tiles.cellW; glyph: "\u{f0eb5}"; label: "Game mode"; on: sys.gameMode; onClicked: sys.toggleGame() }
            Tile { id: ctl; width: tiles.cellW; glyph: "\u{f0493}"; label: "Controls"; on: false; onClicked: Notifs.openControls("", "pointer", Island.screen) }
        }
        Item {
            id: upd
            width: parent.width; height: 34
            visible: sys.overview && SystemStats.updates > 0
            readonly property real radius: 12           // FocusRing follows it
            function go() { Island.open("updates", Island.screen, updArea.containsMouse ? "pointer" : "key", "island"); }
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: SystemStats.updates + (SystemStats.updates === 1 ? " update" : " updates") + " available: review and update"
            Accessible.onPressAction: upd.go()
            Keys.onPressed: e => { if (e.key === Qt.Key_Space || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { upd.go(); e.accepted = true; } }
            FocusRing {}
            Rectangle {
                anchors.fill: parent; radius: Theme.r2
                color: updArea.containsMouse ? Qt.alpha(Theme.accent, 0.22) : Qt.alpha(Theme.accent, 0.12)
                Behavior on color { ColorAnimation { duration: Theme.colorMs } }
            }
            Row {
                anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                spacing: 8
                Text { anchors.verticalCenter: parent.verticalCenter; text: "\u{f06b0}"; font.family: Theme.fontGlyph; font.pixelSize: 15; color: Theme.accent }
                Label { anchors.verticalCenter: parent.verticalCenter; text: SystemStats.updates + (SystemStats.updates === 1 ? " update" : " updates") + " available"; size: Theme.tBody; weight: Theme.wMedium }
            }
            Label { anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                text: "Review and update ›"; size: Theme.tSub; color: Theme.textSecondary }
            MouseArea { id: updArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: upd.go() }
        }
    }
    // Card, Meter, Tile: components/ui. LinkedBar, FocusRing: components.
}
