// A notification that matters, grown out of the island (Notifs.peek): icon,
// headline, a line of body, and explicit Open. Tap the text to dwell (taller
// island, more lines, Reply); Open runs the app's action; Reply hands off to
// the notification center. Critical ones carry their colour.
import QtQuick
import Quickshell.Widgets
import qs.config
import qs.components
import qs.services

Item {
    id: peek
    required property var item
    required property var bar
    property real reveal: 1
    width: 460
    height: parent ? parent.height : 76
    opacity: reveal
    readonly property bool expanded: Notifs.peekExpanded
    readonly property bool loud: !!item && (item.severity === "critical" || item.severity === "warning")
    readonly property bool canReply: Notifs.canReply(item)
    readonly property color tone: item && item.severity === "critical" ? Theme.red : Theme.orange
    readonly property color statusColor: !item ? Theme.textSecondary
        : item.statusTone === "positive" ? Theme.green : item.statusTone === "caution" ? Theme.orange
        : item.statusTone === "critical" ? Theme.red : Theme.textSecondary

    property real pop: 1
    onItemChanged: if (item && !Theme.reduceMotion) popIn.restart()
    NumberAnimation { id: popIn; target: peek; property: "pop"; from: 0.6; to: 1; duration: 460; easing.type: Easing.OutBack; easing.overshoot: 2.2 }

    HoverHandler { onHoveredChanged: Notifs.peekHeld = hovered }

    function openItem() {
        const i = peek.item;
        Notifs.dropPeek();
        if (i) Notifs.activate(i);
    }

    Item {
        id: mark
        x: 16
        y: peek.expanded ? 14 : undefined
        anchors.verticalCenter: peek.expanded ? undefined : parent.verticalCenter
        width: 42; height: 42
        scale: peek.pop
        ClippingRectangle {
            anchors.fill: parent
            radius: 11
            color: "transparent"
            visible: icon.status === Image.Ready
            Image { id: icon; anchors.fill: parent; source: peek.item ? peek.item.icon || "" : ""; sourceSize: Qt.size(84, 84); fillMode: Image.PreserveAspectCrop; asynchronous: true; mipmap: true }
        }
        Rectangle {
            anchors.fill: parent
            visible: icon.status !== Image.Ready
            radius: 21
            color: peek.loud ? Qt.alpha(peek.tone, 0.22) : Theme.platter
            Text {
                anchors.centerIn: parent
                text: !peek.item ? "" : peek.item.severity === "critical" ? "\u{f0026}" : peek.item.severity === "warning" ? "\u{f0029}" : "\u{f009a}"
                font.family: Theme.fontGlyph; font.pixelSize: 20
                color: peek.loud ? peek.tone : Theme.textPrimary
            }
        }
    }

    Item {
        id: copy
        anchors {
            left: mark.right; leftMargin: 12
            right: peek.expanded ? parent.right : go.left
            rightMargin: peek.expanded ? 16 : 12
            top: peek.expanded ? mark.top : undefined
            verticalCenter: peek.expanded ? undefined : parent.verticalCenter
        }
        height: peek.expanded ? copyCol.implicitHeight : undefined
        TapHandler {
            onTapped: {
                if (peek.expanded) return;
                Notifs.expandPeek();
            }
        }
        Column {
            id: copyCol
            width: parent.width
            spacing: peek.expanded ? 4 : 1
            Label {
                width: parent.width; elide: Text.ElideRight
                text: !peek.item ? "" : (peek.item.app || "Notification") + (peek.item.status ? "  ·  " + peek.item.status : "")
                size: 11; weight: Theme.wMedium
                color: peek.item && peek.item.status ? peek.statusColor : Theme.textTertiary
            }
            Label {
                width: parent.width; elide: Text.ElideRight
                text: peek.item ? peek.item.title || peek.item.app : ""
                size: 14; weight: Theme.wSemibold
            }
            Label {
                visible: !!peek.item && !!peek.item.body && !peek.expanded
                width: parent.width
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
                maximumLineCount: 1
                text: peek.item ? String(peek.item.body || "").replace(/\s+/g, " ") : ""
                textFormat: Text.PlainText
                size: 12; color: Theme.textSecondary
            }
            Label {
                visible: !!peek.item && !!peek.item.body && peek.expanded
                width: parent.width
                height: Math.min(bodyScroll.contentHeight, 72)
                clip: true
                Flickable {
                    id: bodyScroll
                    width: parent.width
                    height: parent.height
                    contentHeight: bodyLong.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds
                    Label {
                        id: bodyLong
                        width: bodyScroll.width
                        wrapMode: Text.Wrap
                        text: peek.item ? String(peek.item.body || "").replace(/\s+/g, " ") : ""
                        textFormat: Text.PlainText
                        size: 12; color: Theme.textSecondary
                    }
                }
            }
            Label {
                visible: !peek.expanded && !!peek.item
                width: parent.width
                text: "Tap for more"
                size: 10
                weight: Theme.wMedium
                color: Theme.textTertiary
            }
        }
    }

    Rectangle {
        id: go
        visible: !peek.expanded
        anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
        height: 28; radius: 14
        width: goLabel.implicitWidth + 22
        readonly property color c: peek.loud ? peek.tone : Theme.textPrimary
        color: goArea.containsMouse ? Qt.alpha(c, 0.3) : Qt.alpha(c, 0.16)
        Behavior on color { ColorAnimation { duration: Theme.colorMs } }
        Label { id: goLabel; anchors.centerIn: parent; text: "Open"; size: 12; weight: Theme.wMedium; color: go.c }
        MouseArea {
            id: goArea
            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: peek.openItem()
        }
    }

    Row {
        visible: peek.expanded
        anchors { left: mark.left; right: parent.right; rightMargin: 16; bottom: parent.bottom; bottomMargin: 12 }
        spacing: 6
        Rectangle {
            height: 28; radius: 14
            width: openLbl.implicitWidth + 22
            color: openArea.containsMouse ? Qt.rgba(1, 1, 1, 0.92) : Qt.rgba(1, 1, 1, 0.88)
            Label { id: openLbl; anchors.centerIn: parent; text: "Open"; size: 12; weight: Theme.wMedium; color: "#111111" }
            MouseArea {
                id: openArea
                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: peek.openItem()
            }
        }
        Rectangle {
            visible: peek.canReply
            height: 28; radius: 14
            width: replyLbl.implicitWidth + 22
            color: replyArea.containsMouse ? Theme.pillHover : Theme.pill
            Label { id: replyLbl; anchors.centerIn: parent; text: "Reply"; size: 12; weight: Theme.wMedium }
            MouseArea {
                id: replyArea
                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: {
                    const i = peek.item;
                    if (!i) return;
                    Notifs.openInCenter(i, true, peek.bar ? peek.bar.screenName : "");
                }
            }
        }
    }
}
