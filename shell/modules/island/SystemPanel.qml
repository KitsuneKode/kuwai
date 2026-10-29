// System, grown out of the island (the rings in the expanded island, or the
// launcher): what Waybar's cpu, memory, gpuinfo, sensorsinfo and updates
// modules showed, laid out to be read at a glance, plus the quick switches
// that lived beside them (game mode, night light, caffeine, do not disturb).
//
//   System                                       up 1d 11h · load 2.1
//   CPU  23%  85°      ▁▃▂▅▁▁▂▇▃▁▂▁▄▂▁▃   (16 threads)    Fans 3700 · 4000 rpm
//   Memory  6.1 / 15.4 GB  ━━━━━━━━──────────   Swap 0 MB
//   GPU  RTX 4050  33%  72°  28 W  ━━━━────  VRAM 1.2 / 6 GB
//   [ Game mode ] [ Night light ] [ Caffeine ] [ Do not disturb ]    12 updates ⟶
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.components
import qs.services

FocusScope {
    id: sys
    focus: true
    implicitWidth: 620
    implicitHeight: col.implicitHeight + 40

    Component.onCompleted: { SystemStats.watch(); gameProbe.running = true; }
    Component.onDestruction: SystemStats.unwatch()

    // Game mode is HyDE's (animations and blur off); read it from Hyprland.
    property bool gameMode: false
    Process {
        id: gameProbe
        command: ["hyprctl", "getoption", "animations:enabled", "-j"]
        stdout: StdioCollector { onStreamFinished: { try { sys.gameMode = JSON.parse(text).int === 0; } catch (e) {} } }
    }
    function toggleGame() {
        Quickshell.execDetached(["hyde-shell", "gamemode"]);
        gameMode = !gameMode;
    }

    property string uptime: ""
    FileView {
        path: "/proc/uptime"
        onLoaded: {
            const s = Math.floor(parseFloat(text()));
            const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
            sys.uptime = "up " + (d ? d + "d " : "") + (d || h ? h + "h " : "") + m + "m";
        }
    }

    Column {
        id: col
        x: 22; y: 20
        width: parent.width - 44
        spacing: 14

        Item {
            width: parent.width; height: 26
            Label { anchors.verticalCenter: parent.verticalCenter; text: "System"; size: 20; weight: Theme.wSemibold }
            Label {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: sys.uptime + (SystemStats.load ? "  ·  load " + SystemStats.load.split(" ")[0] : "")
                size: 12; color: Theme.textTertiary
            }
        }

        // ── CPU ──────────────────────────────────────────────────────────
        Card {
            Row {
                spacing: 18
                Column {
                    width: 128
                    spacing: 2
                    Label { text: "CPU"; size: 11; weight: Theme.wMedium; color: Theme.textTertiary }
                    Row {
                        spacing: 8
                        Label { text: Math.round(SystemStats.cpu * 100) + "%"; size: 24; weight: Theme.wSemibold; rounded: true; font.features: ({ "tnum": 1 }) }
                        Label {
                            anchors.baseline: parent.children[0].baseline
                            visible: SystemStats.cpuTemp > 0
                            text: SystemStats.cpuTemp + "°"
                            size: 14; weight: Theme.wMedium; rounded: true
                            color: SystemStats.cpuTemp >= 90 ? Theme.red : SystemStats.cpuTemp >= 80 ? Theme.orange : Theme.textSecondary
                        }
                    }
                    Label { text: SystemStats.fans.length ? "Fans " + SystemStats.fans.join(" · ") + " rpm" : ""; size: 11; color: Theme.textTertiary }
                }
                // One bar per thread.
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4
                    Repeater {
                        model: SystemStats.cores.length
                        Item {
                            required property int index
                            readonly property real v: SystemStats.cores[index] || 0
                            width: 14; height: 48
                            Rectangle { anchors.fill: parent; radius: 4; color: Qt.rgba(1, 1, 1, 0.07) }
                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width; radius: 4
                                height: Math.max(3, parent.height * parent.v)
                                color: parent.v > 0.9 ? Theme.red : parent.v > 0.7 ? Theme.orange : Theme.accent
                                Behavior on height { NumberAnimation { duration: 400; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                            }
                        }
                    }
                }
            }
        }

        // ── Memory ───────────────────────────────────────────────────────
        Card {
            Meter {
                title: "Memory"
                value: SystemStats.mem
                detail: SystemStats.bytes(SystemStats.memUsed) + " of " + SystemStats.bytes(SystemStats.memTotal) + (SystemStats.swapUsed > 1048576 ? "  ·  swap " + SystemStats.bytes(SystemStats.swapUsed) : "")
            }
        }

        // ── GPU ──────────────────────────────────────────────────────────
        Card {
            visible: SystemStats.gpuState !== ""
            Meter {
                title: "GPU" + (SystemStats.gpuTemp ? "  ·  " + SystemStats.gpuTemp + "°" : "") + (SystemStats.gpuPower ? "  ·  " + Math.round(SystemStats.gpuPower) + " W" : "")
                value: SystemStats.gpu
                big: SystemStats.gpuState === "suspended" ? "Asleep" : Math.round(SystemStats.gpu * 100) + "%"
                detail: SystemStats.gpuState === "suspended" ? "The NVIDIA GPU is powered down (nothing is using it)"
                      : "VRAM " + (SystemStats.gpuMemUsed / 1024).toFixed(1) + " of " + (SystemStats.gpuMemTotal / 1024).toFixed(0) + " GB"
            }
        }

        // ── Quick switches and updates ───────────────────────────────────
        Row {
            spacing: 8
            Switch { glyph: "\u{f0eb5}"; label: "Game mode"; on: sys.gameMode; onClicked: sys.toggleGame() }
            Switch { glyph: "\u{f0594}"; label: "Night light"; on: Display.nightOn; onClicked: Display.toggleNight() }
            Switch { glyph: "\u{f0176}"; label: "Caffeine"; on: Caffeine.on; onClicked: Caffeine.on = !Caffeine.on }
            Switch { glyph: "\u{f009b}"; label: "Focus"; on: Notifs.dnd; onClicked: Notifs.dnd = !Notifs.dnd }
        }
        Item {
            width: parent.width; height: 34
            visible: SystemStats.updates > 0
            Rectangle {
                anchors.fill: parent; radius: 12
                color: updArea.containsMouse ? Qt.alpha(Theme.accent, 0.22) : Qt.alpha(Theme.accent, 0.12)
                Behavior on color { ColorAnimation { duration: Theme.colorMs } }
            }
            Row {
                anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                spacing: 8
                Text { anchors.verticalCenter: parent.verticalCenter; text: "\u{f06b0}"; font.family: Theme.fontGlyph; font.pixelSize: 15; color: Theme.accent }
                Label { anchors.verticalCenter: parent.verticalCenter; text: SystemStats.updates + (SystemStats.updates === 1 ? " update" : " updates") + " available"; size: 13; weight: Theme.wMedium }
            }
            Label { anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                text: "Update in a terminal ›"; size: 12; color: Theme.textSecondary }
            MouseArea { id: updArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { Island.close(); Quickshell.execDetached(["hyde-shell", "app", "system.update.sh", "up"]); } }
        }
    }

    component Card: Rectangle {
        default property alias content: inner.data
        width: parent ? parent.width : 576
        height: inner.childrenRect.height + 28
        radius: 14
        color: Qt.rgba(1, 1, 1, 0.05)
        Item { id: inner; x: 14; y: 14; width: parent.width - 28 }
    }
    component Meter: Column {
        property string title
        property real value
        property string big: Math.round(value * 100) + "%"
        property string detail
        width: parent ? parent.width : 400
        spacing: 6
        Item {
            width: parent.width; height: 26
            Label { anchors.verticalCenter: parent.verticalCenter; text: parent.parent.title; size: 11; weight: Theme.wMedium; color: Theme.textTertiary }
            Label { anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: parent.parent.big; size: 20; weight: Theme.wSemibold; rounded: true; font.features: ({ "tnum": 1 }) }
        }
        Item {
            width: parent.width; height: 8
            Rectangle { anchors.fill: parent; radius: 4; color: Qt.rgba(1, 1, 1, 0.08) }
            Rectangle {
                width: Math.max(8, parent.width * Math.min(1, parent.parent.value)); height: parent.height; radius: 4
                color: parent.parent.value > 0.9 ? Theme.red : parent.parent.value > 0.75 ? Theme.orange : Theme.accent
                Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
            }
        }
        Label { text: parent.detail; size: 11; color: Theme.textTertiary }
    }
    component Switch: Rectangle {
        id: sw
        property string glyph
        property string label
        property bool on
        signal clicked()
        height: 38; radius: 12
        width: 138
        color: on ? Qt.alpha(Theme.accent, 0.9) : swArea.containsMouse ? Theme.pillHover : Theme.pill
        scale: swArea.pressed ? 0.96 : 1
        Behavior on color { ColorAnimation { duration: Theme.colorMs } }
        Behavior on scale { NumberAnimation { duration: Theme.pressMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
        Row {
            anchors.centerIn: parent
            spacing: 7
            Text { anchors.verticalCenter: parent.verticalCenter; text: sw.glyph; font.family: Theme.fontGlyph; font.pixelSize: 15; color: sw.on ? "#111114" : Theme.textPrimary }
            Label { anchors.verticalCenter: parent.verticalCenter; text: sw.label; size: 12; weight: Theme.wMedium; color: sw.on ? "#111114" : Theme.textPrimary }
        }
        MouseArea { id: swArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: sw.clicked() }
    }
}
