// The bell's list, as the island itself (right-click or hold the bell): what
// needs you first, then unread chats and mail, then the newest. The island
// grows into it like the T3 panel (one black glass, one morph), so it's
// attached by construction; it used to be a separate popup below the island,
// styled apart. A row reads it in the island (the whole message, Reply).
//   ↑ ↓ choose · ↵ read · Esc back
import QtQuick
import Quickshell
import qs.config
import qs.components
import qs.services

FocusScope {
    id: np
    focus: true
    implicitWidth: 420
    implicitHeight: col.implicitHeight + 36

    readonly property var quick: Notifs.bellQuickList(10)
    property int sel: 0
    onQuickChanged: sel = Math.min(sel, Math.max(0, quick.length - 1))
    function ago(t) {
        const m = Math.max(0, Math.round((Date.now() - t) / 60000));
        return m < 1 ? "now" : m < 60 ? m + "m" : m < 1440 ? Math.floor(m / 60) + "h" : Math.floor(m / 1440) + "d";
    }
    function read(item) { if (!item) return; Island.close(); Notifs.readInIsland(item); }

    Keys.onPressed: e => {
        if (e.key === Qt.Key_Down) sel = Math.min(quick.length - 1, sel + 1);
        else if (e.key === Qt.Key_Up) sel = Math.max(0, sel - 1);
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) read(quick[sel]);
        else return;
        list.positionViewAtIndex(sel, ListView.Contain);
        e.accepted = true;
    }

    Column {
        id: col
        x: 18; y: 18
        width: np.width - 36
        spacing: 10

        Item {
            width: parent.width
            height: 22
            Label {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                text: Notifs.missed.length ? "Need you" : Notifs.unread ? "Unread" : "Recent"
                size: Theme.tTitle3; weight: Theme.wSemibold
            }
            Label {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: Notifs.inbox > 0 ? (Notifs.inbox > 9 ? "9+" : String(Notifs.inbox)) + " in the center" : ""
                size: Theme.tFootnote; color: Theme.textTertiary
                font.features: ({ "tnum": 1 })
            }
        }

        // Empty: say so.
        Column {
            visible: np.quick.length === 0
            width: parent.width
            topPadding: 10; bottomPadding: 10
            spacing: 6
            Icon { anchors.horizontalCenter: parent.horizontalCenter; name: "bell"; size: 22; color: Theme.textTertiary }
            Label { anchors.horizontalCenter: parent.horizontalCenter; text: "You're all caught up"; size: Theme.tSub; color: Theme.textSecondary }
        }

        ListView {
            id: list
            visible: np.quick.length > 0
            width: parent.width
            height: Math.min(contentHeight, 360)
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            model: ScriptModel { values: np.quick; comparisonMode: ObjectComparison.Identity }
            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index
                readonly property bool fresh: modelData.time > Notifs.lastSeen && !modelData.discard
                readonly property bool hot: modelData.severity === "critical" || modelData.severity === "warning"
                readonly property color dot: modelData.severity === "critical" ? Theme.red : hot ? Theme.orange : Theme.accent
                width: list.width
                height: inner.implicitHeight + 20
                radius: Theme.r2
                color: rowArea.containsMouse || np.sel === index ? Qt.rgba(1, 1, 1, 0.07) : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.hoverMs } }
                Rectangle {
                    visible: row.fresh || row.hot
                    x: 10; y: 16
                    width: 6; height: 6; radius: 3
                    color: row.dot
                }
                Column {
                    id: inner
                    x: 24; y: 10
                    width: parent.width - 36
                    spacing: 3
                    Row {
                        width: parent.width
                        spacing: 6
                        Label {
                            width: Math.min(implicitWidth, parent.width - stamp.width - 6)
                            elide: Text.ElideRight
                            text: row.modelData.app || ""
                            size: Theme.tFootnote; weight: Theme.wMedium
                            color: row.hot ? row.dot : Theme.textTertiary
                        }
                        Label { id: stamp; text: "· " + np.ago(row.modelData.time); size: Theme.tFootnote; color: Theme.textTertiary }
                    }
                    Label {
                        width: parent.width
                        visible: text !== ""
                        elide: Text.ElideRight
                        text: row.modelData.title || ""
                        size: Theme.tBody; weight: Theme.wSemibold
                    }
                    Label {
                        width: parent.width
                        visible: text !== ""
                        wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                        text: Notifs.readable(Notifs.bodyForDisplay(row.modelData, true))
                        size: Theme.tSub; lineHeight: 1.3; color: Theme.textSecondary
                    }
                }
                MouseArea {
                    id: rowArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: np.read(row.modelData)
                }
            }
        }

        PillButton {
            width: parent.width
            text: "Open notification center"
            onClicked: { Island.close(); Notifs.toggleCenter("notifications", "pointer", Island.screen); }
        }
    }
}
