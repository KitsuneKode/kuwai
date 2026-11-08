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
import qs.config
import qs.components
import qs.components.ui
import qs.services

FocusScope {
    id: vitals
    focus: true
    implicitWidth: machine.x + machine.width + agents.implicitWidth
    implicitHeight: Math.max(machine.implicitHeight + 40, agents.implicitHeight)

    Component.onCompleted: SystemStats.watch()
    Component.onDestruction: SystemStats.unwatch()

    Column {
        id: machine
        x: 22; y: 20
        width: 300
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
        Card {
            Meter {
                title: "Memory"
                value: SystemStats.mem
                detail: SystemStats.bytes(SystemStats.memUsed) + " of " + SystemStats.bytes(SystemStats.memTotal)
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
        x: machine.x + machine.width
        width: implicitWidth
        height: implicitHeight
        focus: true
    }
}
