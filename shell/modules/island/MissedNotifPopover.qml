// The bell's quick list (island hover): what needs you first, then unread
// chats and mail, then the newest. Built on components/Popover (focus grab,
// island count, enter/exit, Esc). Left-click on the bell opens the center;
// right-click, hold or Ctrl+click opens this.
import QtQuick
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
            spacing: 8
            boundsBehavior: Flickable.StopAtBounds
            model: pop.quick

            delegate: Rectangle {
                id: row
                required property var modelData
                readonly property bool fresh: modelData.time > Notifs.lastSeen && !modelData.discard
                readonly property bool hot: modelData.severity === "critical" || modelData.severity === "warning"
                readonly property color hue: modelData.severity === "critical" ? Theme.red : Theme.orange
                width: list.width
                height: inner.implicitHeight + 24
                radius: 14
                color: hot ? Qt.alpha(hue, 0.12) : fresh ? Qt.alpha(Theme.accent, 0.08) : Qt.rgba(1, 1, 1, 0.06)
                border.width: 1
                border.color: hot ? Qt.alpha(hue, 0.4) : fresh ? Qt.alpha(Theme.accent, 0.32) : Qt.rgba(1, 1, 1, 0.08)

                Column {
                    id: inner
                    x: 12; y: 12
                    width: parent.width - 24
                    spacing: 4
                    // App · time on one quiet line, the title under it.
                    Row {
                        width: parent.width
                        spacing: 6
                        Label {
                            width: Math.min(implicitWidth, parent.width - stamp.width - 6)
                            elide: Text.ElideRight
                            text: row.modelData.app || ""
                            size: Theme.tFootnote; weight: Theme.wMedium
                            color: row.hot ? row.hue : Theme.textTertiary
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
                        wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                        text: row.modelData.title || ""
                        size: Theme.tBody; weight: Theme.wSemibold
                    }
                    Item {
                        visible: bodyLbl.text !== ""
                        width: parent.width
                        height: Math.min(56, bodyFlick.contentHeight)
                        clip: true
                        Flickable {
                            id: bodyFlick
                            anchors.fill: parent
                            contentHeight: bodyLbl.implicitHeight
                            boundsBehavior: Flickable.StopAtBounds
                            Label {
                                id: bodyLbl
                                width: bodyFlick.width
                                wrapMode: Text.Wrap
                                text: Notifs.bodyForDisplay(row.modelData, true).replace(/<[^>]*>/g, "")
                                size: Theme.tSub; lineHeight: 1.35; color: Theme.textSecondary
                            }
                        }
                    }
                    Row {
                        topPadding: 4
                        spacing: 6
                        PillButton {
                            text: "Open"
                            onClicked: { pop.close(); Notifs.openInCenter(row.modelData, false, pop.screenName); }
                        }
                        PillButton {
                            visible: Notifs.canReply(row.modelData)
                            text: "Reply"
                            onClicked: { pop.close(); Notifs.openInCenter(row.modelData, true, pop.screenName); }
                        }
                    }
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
