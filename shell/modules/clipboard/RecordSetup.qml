// Screen recording setup, in the island (Super+Shift+Alt+R): what to record,
// what to hear, how smooth; then Record (↵). The island folds back to a pill
// that holds the dot, the time and the stop button while it records.
//
//   ● Screen Recording                                              ✕
//   Source   [ eDP-1 ] [ DP-3 ] [ Region ]
//   Audio    [ System ] [ Mic ] [ Both ] [ None ]
//   Quality  [ 60 fps ] [ 30 fps ]
//                                                  ( ● Record  ↵ )
//
// Keys: ←→ source, A audio, F frame rate, ↵ record, Esc cancel.
// Choices are remembered for next time (in memory, for this session).
import QtQuick
import Quickshell
import qs.config
import qs.components
import qs.services

FocusScope {
    id: setup

    property var panel
    focus: true

    readonly property var sources: [...Quickshell.screens.map(s => ({ id: s.name, label: s.name, sub: s.width + "×" + s.height })),
                                    { id: "region", label: "Region", sub: "pick an area" }]
    readonly property var audios: [{ id: "system", label: "System" }, { id: "mic", label: "Mic" }, { id: "both", label: "Both" }, { id: "none", label: "None" }]
    readonly property var rates: [{ id: "60", label: "60 fps" }, { id: "30", label: "30 fps" }]
    property string source: Screens.focusedName || (sources.length ? sources[0].id : "region")
    property string audio: "system"
    property string fps: "60"

    function record() { Clipboard.startRecording(source, audio, Number(fps)); }
    function step(list, cur, d) { const i = list.findIndex(x => x.id === cur); return list[(i + d + list.length) % list.length].id; }

    Keys.onPressed: event => {
        const k = event.key;
        if (k === Qt.Key_Return || k === Qt.Key_Enter) record();
        else if (k === Qt.Key_Escape) Clipboard.recordSetup = false;
        else if (k === Qt.Key_Right) source = step(sources, source, 1);
        else if (k === Qt.Key_Left) source = step(sources, source, -1);
        else if (k === Qt.Key_A) audio = step(audios, audio, 1);
        else if (k === Qt.Key_F) fps = step(rates, fps, 1);
        else return;
        event.accepted = true;
    }

    // ── Title ────────────────────────────────────────────────────────────
    Row {
        id: title
        x: 22; y: 20
        spacing: 10
        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 10; height: 10; radius: 5; color: Theme.red }
        Label { anchors.verticalCenter: parent.verticalCenter; text: "Screen Recording"; size: Theme.tTitle3; weight: Theme.wSemibold }
    }
    Rectangle {
        anchors { right: parent.right; rightMargin: 16; verticalCenter: title.verticalCenter }
        width: 28; height: 28; radius: 14
        color: closeArea.containsMouse ? Qt.alpha(Theme.red, 0.85) : Theme.pill
        Text { anchors.centerIn: parent; text: "\u{f0156}"; font.family: Theme.fontGlyph; font.pixelSize: 12; color: closeArea.containsMouse ? "white" : Theme.textSecondary }
        MouseArea { id: closeArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Clipboard.recordSetup = false }
    }

    // ── Choices ──────────────────────────────────────────────────────────
    Column {
        x: 22
        anchors { top: title.bottom; topMargin: 18 }
        spacing: 12
        Repeater {
            model: [
                { label: "Source", key: "source", items: setup.sources, hint: "← →" },
                { label: "Audio", key: "audio", items: setup.audios, hint: "A" },
                { label: "Quality", key: "fps", items: setup.rates, hint: "F" }
            ]
            Row {
                id: line
                required property var modelData
                spacing: 8
                Label { width: 70; anchors.verticalCenter: parent.verticalCenter; text: line.modelData.label; size: 13; color: Theme.textSecondary }
                Repeater {
                    model: line.modelData.items
                    Rectangle {
                        id: chip
                        required property var modelData
                        readonly property bool on: setup[line.modelData.key] === modelData.id
                        height: 30; radius: 15
                        width: chipRow.implicitWidth + 24
                        color: on ? Qt.rgba(1, 1, 1, 0.92) : chipArea.containsMouse ? Theme.pillHover : Theme.pill
                        scale: chipArea.pressed ? 0.96 : 1
                        Behavior on color { ColorAnimation { duration: Theme.colorMs } }
                        Behavior on scale { NumberAnimation { duration: Theme.pressMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                        Row {
                            id: chipRow
                            anchors.centerIn: parent
                            spacing: 6
                            Label { anchors.verticalCenter: parent.verticalCenter; text: chip.modelData.label; size: 12; weight: chip.on ? Theme.wSemibold : Theme.wMedium; color: chip.on ? "#111114" : Theme.textPrimary }
                            Label { visible: !!chip.modelData.sub; anchors.verticalCenter: parent.verticalCenter; text: chip.modelData.sub || ""; size: 11; color: chip.on ? "#55555c" : Theme.textTertiary }
                        }
                        MouseArea { id: chipArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: setup[line.modelData.key] = chip.modelData.id }
                    }
                }
                KeyCap { anchors.verticalCenter: parent.verticalCenter; text: line.modelData.hint }
            }
        }
    }

    // ── Record ───────────────────────────────────────────────────────────
    Rectangle {
        id: rec
        anchors { right: parent.right; bottom: parent.bottom; rightMargin: 18; bottomMargin: 18 }
        height: 40; radius: 20
        width: recRow.implicitWidth + 32
        color: recArea.containsMouse ? Qt.lighter(Theme.red, 1.1) : Theme.red
        scale: recArea.pressed ? 0.96 : 1
        Behavior on scale { NumberAnimation { duration: Theme.pressMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
        Row {
            id: recRow
            anchors.centerIn: parent
            spacing: 8
            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 10; height: 10; radius: 5; color: "white" }
            Label { anchors.verticalCenter: parent.verticalCenter; text: "Record"; size: 14; weight: Theme.wSemibold; color: "white" }
            KeyCap { anchors.verticalCenter: parent.verticalCenter; text: "↵" }
        }
        MouseArea { id: recArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: setup.record() }
    }
    Label {
        anchors { left: parent.left; leftMargin: 22; verticalCenter: rec.verticalCenter }
        text: "Saved to ~/Videos/Recordings · encoded on the GPU"
        size: 11
        color: Theme.textTertiary
    }
}
