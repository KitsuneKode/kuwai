// T3 Code at a glance, grown out of the island (hover the T3 mark on the
// notch, or click it). Like the "T3 · 24 active" live activity: the wordmark
// and how many are active, then each thread: what state it's in, its title,
// which agent runs it. Threads waiting for you come first, in orange.
//   Enter / click a row or the button: bring T3 Code forward. Esc closes.
import QtQuick
import Quickshell
import qs.config
import qs.components
import qs.services

FocusScope {
    id: t3
    focus: true
    implicitWidth: 400
    implicitHeight: col.implicitHeight + 40

    Keys.onPressed: e => {
        if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { T3Code.openBest(); Island.close(); e.accepted = true; }
    }

    readonly property var live: T3Code.items.filter(i => i.status !== "completed" && i.status !== "failed")
    function agentName(p) {
        const base = String(p || "").replace(/_\d+$/, "");
        return ({ claudeAgent: "Claude", codex: "Codex", cursor: "Cursor", antigravity: "Antigravity", opencode: "OpenCode", gemini: "Gemini" })[base]
            || (base ? base.charAt(0).toUpperCase() + base.slice(1) : "");
    }

    Column {
        id: col
        x: 20; y: 20
        width: t3.width - 40
        spacing: 14

        // ── The live activity line: identity leads, state trails ─────────
        Item {
            width: parent.width
            height: 26
            Label {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                text: "T3"
                size: Theme.tTitle2; weight: Theme.wBold; rounded: true
                color: Theme.cyan
            }
            Label {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: T3Code.waiting > 0 ? T3Code.waiting + " need" + (T3Code.waiting === 1 ? "s" : "") + " you · " + T3Code.running + " active"
                    : T3Code.running + " active"
                size: Theme.tCallout; weight: Theme.wSemibold
                color: T3Code.waiting > 0 ? Theme.orange : Theme.cyan
                font.features: ({ "tnum": 1 })
            }
        }

        // ── Empty ────────────────────────────────────────────────────────
        Label {
            visible: t3.live.length === 0 && T3Code.finished === 0
            width: parent.width
            topPadding: 4; bottomPadding: 4
            text: T3Code.alive ? "Nothing running in T3 Code." : "T3 Code isn't open."
            size: Theme.tBody; color: Theme.textTertiary
        }

        // ── Threads ──────────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 2
            Repeater {
                // Live threads only; finished ones fold into one line below
                // (three finished rows crowded out the two still working).
                model: ScriptModel { values: t3.live.slice(0, 6); objectProp: "title" }
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    readonly property bool waits: modelData.status === "waiting"
                    readonly property bool failed: modelData.status === "failed"
                    readonly property bool done: modelData.status === "completed" || failed
                    width: parent.width
                    height: 46
                    radius: 12
                    color: rowArea.containsMouse ? Qt.rgba(1, 1, 1, 0.07) : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.hoverMs } }

                    // State: an orange dot when it needs you, a turning arc while it works.
                    Item {
                        id: state
                        x: 10; anchors.verticalCenter: parent.verticalCenter
                        width: 14; height: 14
                        Rectangle {
                            visible: row.waits
                            anchors.centerIn: parent
                            width: 8; height: 8; radius: 4
                            color: Theme.orange
                        }
                        // Finished in the last 15 minutes: a check, still.
                        Text {
                            visible: row.done
                            anchors.centerIn: parent
                            text: "\u{f012c}"
                            font.family: Theme.fontGlyph; font.pixelSize: 14
                            color: Theme.green
                        }
                        Canvas {
                            visible: !row.waits && !row.done
                            anchors.fill: parent
                            onPaint: {
                                const c = getContext("2d");
                                c.reset(); c.lineWidth = 1.6; c.lineCap = "round";
                                c.strokeStyle = Qt.rgba(1, 1, 1, 0.16); c.beginPath(); c.arc(7, 7, 5.5, 0, Math.PI * 2); c.stroke();
                                c.strokeStyle = Theme.cyan; c.beginPath(); c.arc(7, 7, 5.5, -Math.PI / 2, Math.PI * 0.35); c.stroke();
                            }
                            RotationAnimation on rotation {
                                running: !row.waits && !row.done && t3.visible && !Theme.reduceMotion
                                from: 0; to: 360; duration: Theme.spinMs; loops: Animation.Infinite
                            }
                        }
                    }
                    Column {
                        anchors { left: state.right; leftMargin: 12; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        spacing: 2
                        Label {
                            width: parent.width; elide: Text.ElideRight
                            text: row.modelData.title || "Untitled thread"
                            size: Theme.tBody; weight: Theme.wSemibold
                        }
                        Label {
                            width: parent.width; elide: Text.ElideRight
                            text: (row.waits ? "Needs you" : row.failed ? "Failed" : row.done ? "Finished" : row.modelData.status === "running" ? "Working" : "Starting")
                                + (t3.agentName(row.modelData.provider) ? " · " + t3.agentName(row.modelData.provider) : "")
                            size: Theme.tFootnote
                            color: row.waits ? Theme.orange : Theme.textTertiary
                        }
                    }
                    MouseArea {
                        id: rowArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        // That thread, not just the window (T3 Code's own link).
                        onClicked: { T3Code.openThread(row.modelData.thread); Island.close(); }
                    }
                }
            }
        }

        Row {
            visible: T3Code.finished > 0
            leftPadding: 10
            spacing: 8
            Text { anchors.verticalCenter: parent.verticalCenter; text: "\u{f012c}"; font.family: Theme.fontGlyph; font.pixelSize: 13; color: Theme.green }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: T3Code.finished + " finished in the last 15 min"
                size: Theme.tFootnote; color: Theme.textTertiary
            }
        }

        // The way on: T3 itself, or every agent you run (kittymux's too) in
        // the center's Agents tab.
        Row {
            width: parent.width
            spacing: 8
            PillButton {
                width: (parent.width - 8) / 2
                text: "Open T3 Code"
                onClicked: { T3Code.focus(); Island.close(); }
            }
            PillButton {
                width: (parent.width - 8) / 2
                text: "All agents"
                onClicked: { Island.close(); Notifs.toggleCenter("agents", "pointer", Island.screen); }
            }
        }
    }
}
