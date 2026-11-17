// Vitals: the machine and the agents in one look, grown out of the island
// (the gauge beside the bell in the hover view, or `rice island vitals`).
//
//   Machine                         Usage                         2 out · back in 1h
//   ┌ NVIDIA GPU · 61° · 28 W  33% ┐  [All] [Claude] [Codex] …
//   │ ━━━━━━━━──────────── VRAM … │  ▣ Claude   5-hour ━━━━━━━━──  82%  resets 3h
//   ┌ Intel GPU          1.1 GHz   ┐  ▣ Codex    weekly ━━━━━━━━━━  Out · back Thu
//   ┌ CPU   41° ━━━──────── 12%    ┐
//   ┌ Memory ━━━━━━──── 9.1 of 16  ┐
//                System details ›
//
// The left column reads SystemStats (polled only while this is open, like
// the System panel); the right is the Usage panel itself, tabs and keys
// included (Tab / Shift+Tab: the next agent). Esc closes (IslandBar).
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.components
import qs.components.ui
import qs.services

FocusScope {
    id: vitals
    focus: true
    readonly property bool compact: width < 760
    implicitWidth: Theme.panelL
    implicitHeight: 540

    Component.onCompleted: SystemStats.watch()
    Component.onDestruction: SystemStats.unwatch()
    property var memApps: []
    Process {
        id: memProbe
        command: [Paths.bin + "/rice-procs", "--by-app"]
        stdout: StdioCollector { onStreamFinished: { try { vitals.memApps = JSON.parse(text); } catch (e) {} } }
    }
    Timer { interval: Theme.panelPollMs; repeat: true; running: true; triggeredOnStart: true; onTriggered: memProbe.running = true }

    Flickable {
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: vitals.compact ? agents.y + agents.implicitHeight + 20 : Math.max(machine.y + machine.implicitHeight + 20, agents.implicitHeight)
    Column {
        id: machine
        x: 22; y: 20
        width: vitals.compact ? Math.max(0, vitals.width - 44) : 300
        spacing: 10

        Item {
            width: parent.width; height: 26
            Label { anchors.verticalCenter: parent.verticalCenter; text: "Machine"; size: 20; weight: Theme.wSemibold }
        }

        Card {
            visible: SystemStats.gpuState !== ""
            Meter {
                title: "NVIDIA GPU" + (SystemStats.gpuTemp ? "  ·  " + SystemStats.gpuTemp + "°" : "") + (SystemStats.gpuPower ? "  ·  " + Math.round(SystemStats.gpuPower) + " W" : "")
                value: SystemStats.gpuState === "suspended" ? 0 : SystemStats.gpu
                big: SystemStats.gpuState === "suspended" ? "Asleep" : Math.round(SystemStats.gpu * 100) + "%"
                detail: SystemStats.gpuState === "suspended" ? "Powered down: nothing is using it"
                      : "VRAM " + (SystemStats.gpuMemUsed / 1024).toFixed(1) + " of " + (SystemStats.gpuMemTotal / 1024).toFixed(0) + " GB"
            }
        }
        Card {
            visible: SystemStats.igpuMax > 0
            Meter {
                title: "Intel GPU"
                value: SystemStats.igpuMax ? SystemStats.igpuMHz / SystemStats.igpuMax : 0
                big: SystemStats.igpuMHz ? (SystemStats.igpuMHz / 1000).toFixed(1) + " GHz" : "Idle"
                detail: "Drives the laptop screen (its clock stands in for load)"
            }
        }
        Card {
            Meter {
                title: "CPU" + (SystemStats.cpuTemp > 0 ? "  ·  " + SystemStats.cpuTemp + "°" : "")
                value: SystemStats.cpu
                detail: SystemStats.cores.length + " threads" + (SystemStats.fans.length ? "  ·  fans " + SystemStats.fans.join(" · ") + " rpm" : "")
            }
        }
        // Memory, by what holds it (Clove's storage bar): one big number,
        // the dots by app, a legend that lights with the dots. PSS, so a
        // browser's twenty processes count once (rice-procs --by-app, every
        // 5 s while this is open).
        Card {
            LinkedBar {
                width: parent.width
                title: "Memory"
                big: SystemStats.bytes(SystemStats.memUsed)
                caption: "of " + SystemStats.bytes(SystemStats.memTotal) + " in use" + (vitals.memApps.length ? " · point at the dots" : "")
                total: SystemStats.memTotal / 1073741824
                unit: " GB"
                parts: {
                    const pal = [Theme.orange, Theme.blue, Theme.green, Theme.indigo, Theme.cyan, Theme.yellow, Theme.red];
                    const used = SystemStats.memUsed / 1073741824;
                    const top = vitals.memApps.slice(0, 6).map((a, i) => ({ label: a.app, value: a.mb / 1024, color: pal[i],
                        detail: a.count + (a.count === 1 ? " process" : " processes") }));
                    const rest = Math.max(0, used - top.reduce((n, p) => n + p.value, 0));
                    return rest > 0.05 ? top.concat([{ label: "Everything else", value: rest, color: Theme.gray, detail: "the system, caches the kernel can't drop, the rest" }]) : top;
                }
            }
        }

        // The full picture (per-thread bars, updates, game mode) is the System panel.
        Item {
            width: parent.width; height: 28
            Label {
                id: more
                anchors.centerIn: parent
                text: "System details ›"
                size: 12
                color: moreArea.containsMouse ? Theme.textPrimary : Theme.textSecondary
                Behavior on color { ColorAnimation { duration: Theme.hoverMs } }
            }
            MouseArea { id: moreArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Island.open("system", Island.screen, "pointer", "island") }
        }
    }

    UsagePanel {
        id: agents
        x: vitals.compact ? 22 : machine.x + machine.width
        y: vitals.compact ? machine.y + machine.implicitHeight + 20 : 0
        width: vitals.compact ? Math.max(0, vitals.width - 44) : Math.max(0, vitals.width - x - 22)
        height: implicitHeight
        focus: true
        // The list ends where the machine column does (it scrolls for more).
        listMax: Math.max(80, vitals.height - listTop - 40)
    }
    }
}
