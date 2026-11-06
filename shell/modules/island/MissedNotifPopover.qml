// The bell's quick list (island hover): what needs you first, then unread
// chats and mail, then the newest. Built on components/Popover (focus grab,
// island count, enter/exit, Esc). Left-click on the bell opens the center;
// right-click, hold or Ctrl+click opens this.
import QtQuick
import Quickshell
import qs.config
import qs.components
import qs.services

Popover {
    id: pop
    // Opened by a deliberate gesture: it stays until a click elsewhere.
    property bool dismissOnAnchorLeave: true
    sticky: !dismissOnAnchorLeave
    cardWidth: 320
    maxHeight: 440
    // One list per change, and only while shown (not on every notification).
    readonly property var quick: pop.shown ? Notifs.bellQuickList(8) : []
    readonly property string screenName: pop.window ? pop.window.screenName : ""
    function ago(t) {
        const m = Math.max(0, Math.round((Date.now() - t) / 60000));
        return m < 1 ? "now" : m < 60 ? m + "m" : m < 1440 ? Math.floor(m / 60) + "h" : Math.floor(m / 1440) + "d";
    }

    Column {
        id: col
        width: parent.width
        spacing: 10

        // ── Header: what this list is ─────────────────────────────────
        Column {
            width: parent.width
            spacing: 2
            Label {
                text: Notifs.missed.length ? "Need you"
                    : Notifs.unread ? "Unread · " + (Notifs.inbox > 9 ? "9+" : Notifs.inbox)
                    : "Recent"
                size: Theme.tCallout; weight: Theme.wSemibold
            }
            Label {
                visible: pop.quick.length > 0
                text: Notifs.missed.length ? "Act on these first" : "Newest first"
                size: Theme.tFootnote; color: Theme.textTertiary
            }
        }

        // ── Empty: say so, and offer the way in ────────────────────────
        Column {
            visible: pop.quick.length === 0
            width: parent.width
            topPadding: 6; bottomPadding: 6
            spacing: 6
            Icon { anchors.horizontalCenter: parent.horizontalCenter; name: "bell"; size: 22; color: Theme.textTertiary }
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "You're all caught up"
                size: Theme.tSub; color: Theme.textSecondary
            }
        }

        // ── The list ──────────────────────────────────────────────────
        ListView {
            id: list
            visible: pop.quick.length > 0
            width: parent.width
            height: Math.min(contentHeight, 300)
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            // ScriptModel keeps the rows that stay (a plain array re-creates
            // every delegate on each change: Quickshell docs). Same objects as
            // Notifs.items, so identity is the right comparison.
            model: ScriptModel { values: pop.quick; comparisonMode: ObjectComparison.Identity }

            // A row each, flat: a dot for its state (accent unread, orange or
            // red urgent), app · age, the title, two lines of it. The whole row
            // reads it in the island (the expanded peek: all of it, Reply).
            // (Bordered tinted cards with Open/Reply in each were boxes in a
            // box, and Open left the island for the center.)
            delegate: Rectangle {
                id: row
                required property var modelData
                readonly property bool fresh: modelData.time > Notifs.lastSeen && !modelData.discard
                readonly property bool hot: modelData.severity === "critical" || modelData.severity === "warning"
                readonly property color dot: modelData.severity === "critical" ? Theme.red : hot ? Theme.orange : Theme.accent
                width: list.width
                height: inner.implicitHeight + 20
                radius: Theme.r2
                color: rowArea.containsMouse ? Qt.rgba(1, 1, 1, 0.07) : "transparent"
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
                        Label {
                            id: stamp
                            text: "· " + pop.ago(row.modelData.time)
                            size: Theme.tFootnote; color: Theme.textTertiary
                        }
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
                        text: Notifs.bodyForDisplay(row.modelData, true).replace(/<[^>]*>/g, "")
                        size: Theme.tSub; lineHeight: 1.3; color: Theme.textSecondary
                    }
                }
                MouseArea {
                    id: rowArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { pop.close(); Notifs.readInIsland(row.modelData); }
                }
            }
        }

        // ── Always: the way to everything ─────────────────────────────
        PillButton {
            width: parent.width
            text: "Open notification center"
            onClicked: { pop.close(); Notifs.toggleCenter("notifications", "pointer", pop.screenName); }
        }
    }
}
