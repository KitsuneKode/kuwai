// A warning grown out of the island (services/Alerts): a mark in the
// alert's colour, what's wrong, the detail, and a way in. Tap the text to
// expand and scroll the detail; Details opens the System panel.
import QtQuick
import qs.config
import qs.components
import qs.services

Item {
    id: banner
    required property var alert
    required property var bar
    property bool expanded: false
    width: 440
    implicitHeight: expanded ? Math.min(140, 76 + Math.max(40, detailScroll.contentHeight + 8)) : 72
    readonly property color tone: !alert ? Theme.orange : alert.level === "crit" ? Theme.red : alert.level === "info" ? Theme.accent : Theme.orange

    HoverHandler { onHoveredChanged: Alerts.held = hovered }

    Rectangle {
        id: mark
        x: 18
        y: expanded ? 14 : undefined
        anchors.verticalCenter: expanded ? undefined : parent.verticalCenter
        width: 38; height: 38; radius: 19
        color: Qt.alpha(banner.tone, 0.2)
        Text { anchors.centerIn: parent; text: banner.alert ? banner.alert.glyph : ""; font.family: Theme.fontGlyph; font.pixelSize: 19; color: banner.tone }
    }
    Item {
        id: copy
        anchors {
            left: mark.right; leftMargin: 12
            right: go.left; rightMargin: 12
            top: expanded ? mark.top : undefined
            verticalCenter: expanded ? undefined : parent.verticalCenter
        }
        // Always the column's height: an Item with no height centres its top
        // edge, so the text hung below the mark.
        height: copyCol.implicitHeight
        TapHandler {
            onTapped: {
                if (!banner.alert || !banner.alert.detail || (!detailLine.truncated && !banner.expanded)) return;
                banner.expanded = !banner.expanded;
            }
        }
        Column {
            id: copyCol
            width: parent.width
            spacing: expanded ? 4 : 2
            Label { width: parent.width; elide: Text.ElideRight; text: banner.alert ? banner.alert.title : ""; size: 14; weight: Theme.wSemibold }
            Label {
                id: detailLine
                visible: !banner.expanded && text !== ""
                width: parent.width; elide: Text.ElideRight
                text: banner.alert ? banner.alert.detail || "" : ""
                size: 12; color: Theme.textSecondary
            }
            Item {
                visible: banner.expanded && !!banner.alert && !!banner.alert.detail
                width: parent.width
                height: Math.min(52, detailScroll.contentHeight)
                clip: true
                Flickable {
                    id: detailScroll
                    anchors.fill: parent
                    contentHeight: detailLbl.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds
                    Label {
                        id: detailLbl
                        width: detailScroll.width
                        wrapMode: Text.Wrap
                        text: banner.alert ? banner.alert.detail : ""
                        size: 12; lineHeight: 1.35; color: Theme.textSecondary
                    }
                }
            }
            Label {
                // Only when there is more to read than the line shows.
                visible: !banner.expanded && detailLine.truncated
                text: "Tap for more"
                size: 10; weight: Theme.wMedium; color: Theme.textTertiary
            }
        }
    }
    Rectangle {
        id: go
        anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
        height: 28; radius: 14
        width: goLabel.implicitWidth + 22
        color: goArea.containsMouse ? Qt.alpha(banner.tone, 0.35) : Qt.alpha(banner.tone, 0.2)
        Label { id: goLabel; anchors.centerIn: parent; text: banner.alert && banner.alert.action ? banner.alert.action : "Details"; size: 12; weight: Theme.wMedium; color: banner.tone }
        MouseArea {
            id: goArea
            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: {
                Alerts.dismiss();
                Island.open(banner.alert && banner.alert.panel ? banner.alert.panel : "system", banner.bar.screenName, "pointer", "island");
            }
        }
    }
}
