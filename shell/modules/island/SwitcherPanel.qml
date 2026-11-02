// The switcher, grown out of the island (services/Switcher has the flow and
// keys). One row of live window previews in most-recently-used order: the
// selected one wears the accent ring; its app, title and workspace below.
//   ←→ step · ↵ switch · Esc cancel · Q close it · W only this workspace
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.config
import qs.components
import qs.services

FocusScope {
    id: sw
    focus: true
    readonly property int cardW: 216
    readonly property int shotH: 128
    readonly property int count: Switcher.list.length
    implicitWidth: Math.min(1160, Math.max(3, count) * (cardW + 12) + 28)
    implicitHeight: shotH + 112

    Keys.onPressed: event => {
        const k = event.key;
        if (k === Qt.Key_Right || k === Qt.Key_Tab) Switcher.step(1);
        else if (k === Qt.Key_Left || k === Qt.Key_Backtab) Switcher.step(-1);
        else if (k === Qt.Key_Return || k === Qt.Key_Enter) Switcher.commit();
        else if (k === Qt.Key_Q) Switcher.closeSelected();
        else if (k === Qt.Key_W) Switcher.toggleWorkspaceOnly();
        else return;
        event.accepted = true;
    }

    function iconFor(t) {
        const cls = Switcher.classOf(t);
        const app = cls ? DesktopEntries.heuristicLookup(cls) : null;
        return app && app.icon ? Quickshell.iconPath(app.icon, true) : "";
    }
    function appName(t) {
        const cls = Switcher.classOf(t);
        const app = cls ? DesktopEntries.heuristicLookup(cls) : null;
        return app ? app.name : cls;
    }

    ListView {
        id: row
        x: 14; y: 14
        width: parent.width - 28
        height: sw.shotH + 64
        orientation: ListView.Horizontal
        spacing: 12
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: Switcher.list
        currentIndex: Switcher.index
        highlightFollowsCurrentItem: false
        onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

        delegate: Item {
            id: card
            required property var modelData
            required property int index
            readonly property bool on: index === Switcher.index
            readonly property var ipc: modelData.lastIpcObject || ({})
            width: sw.cardW
            height: row.height

            Rectangle {
                id: frame
                width: parent.width
                height: sw.shotH
                radius: 14
                color: Qt.rgba(1, 1, 1, 0.05)
                clip: true
                scale: card.on ? 1 : 0.97
                Behavior on scale { NumberAnimation { duration: Theme.reduceMotion ? 0 : 140; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }

                ScreencopyView {
                    anchors.fill: parent
                    anchors.margins: 1
                    captureSource: Switcher.shown ? card.modelData.wayland : null
                    live: Switcher.shown
                }
                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: "transparent"
                    border.width: card.on ? 2 : 1
                    border.color: card.on ? Theme.accent : Qt.rgba(1, 1, 1, 0.10)
                }
                // App icon, or its initial when there is none.
                Rectangle {
                    x: 8; y: parent.height - height - 8
                    width: 30; height: 30; radius: 9
                    color: Qt.rgba(0, 0, 0, 0.55)
                    IconImage {
                        id: ico
                        anchors.fill: parent; anchors.margins: 3
                        source: sw.iconFor(card.modelData)
                        visible: source !== ""
                        asynchronous: true
                    }
                    Label {
                        visible: !ico.visible
                        anchors.centerIn: parent
                        text: (Switcher.classOf(card.modelData) || "?").charAt(0).toUpperCase()
                        size: 15; weight: Theme.wSemibold
                    }
                }
                // Workspace number (special ones show their name).
                Rectangle {
                    readonly property var ws: card.modelData.workspace
                    visible: !!ws
                    anchors { right: parent.right; top: parent.top; margins: 8 }
                    height: 20; radius: 10
                    width: wsLabel.implicitWidth + 14
                    color: Qt.rgba(0, 0, 0, 0.55)
                    Label {
                        id: wsLabel
                        anchors.centerIn: parent
                        text: parent.ws ? (parent.ws.id > 0 ? String(((parent.ws.id - 1) % 10) + 1) : parent.ws.name.replace("special:", "")) : ""
                        size: 11; weight: Theme.wMedium; rounded: true
                    }
                }
            }
            Column {
                anchors { top: frame.bottom; topMargin: 9; left: parent.left; right: parent.right }
                spacing: 1
                Label {
                    width: parent.width; elide: Text.ElideRight
                    text: sw.appName(card.modelData)
                    size: 13; weight: Theme.wMedium
                    color: card.on ? Theme.textPrimary : Theme.textSecondary
                }
                Label {
                    width: parent.width; elide: Text.ElideRight
                    text: card.modelData.title || ""
                    size: 11; color: Theme.textTertiary
                }
            }
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: Switcher.index = card.index
                onClicked: { Switcher.index = card.index; Switcher.commit(); }
            }
        }
    }

    // ── Footer ───────────────────────────────────────────────────────────
    Row {
        anchors { left: parent.left; leftMargin: 20; bottom: parent.bottom; bottomMargin: 12 }
        spacing: 14
        Repeater {
            model: [["⇥", "Next"], ["↩", "Switch"], ["Q", "Close"], ["W", Switcher.workspaceOnly ? "All workspaces" : "This workspace"], ["esc", "Cancel"]]
            Row {
                required property var modelData
                spacing: 6
                KeyCap { anchors.verticalCenter: parent.verticalCenter; text: parent.modelData[0] }
                Label { anchors.verticalCenter: parent.verticalCenter; text: parent.modelData[1]; size: 12; color: Theme.textTertiary }
            }
        }
    }
    Label {
        anchors { right: parent.right; rightMargin: 20; bottom: parent.bottom; bottomMargin: 13 }
        text: Switcher.appOnly ? "This app" : Switcher.workspaceOnly ? "This workspace" : (sw.count + " windows")
        size: 12; color: Theme.textTertiary
    }
}
