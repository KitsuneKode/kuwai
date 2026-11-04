// A notification that matters, grown out of the island (Notifs.peek): the
// app's icon pops in, then who or what, the headline and a line of it, and
// Open. A click anywhere opens it (the app's own action, its window); the
// island folds back by itself after a few seconds, never while the pointer
// is on it. Critical ones carry their colour.
import QtQuick
import Quickshell.Widgets
import qs.config
import qs.components
import qs.services

Item {
    id: peek
    required property var item
    required property var bar
    implicitWidth: 460
    implicitHeight: 76
    readonly property bool loud: !!item && (item.severity === "critical" || item.severity === "warning")
    readonly property color tone: item && item.severity === "critical" ? Theme.red : Theme.orange
    readonly property color statusColor: !item ? Theme.textSecondary
        : item.statusTone === "positive" ? Theme.green : item.statusTone === "caution" ? Theme.orange
        : item.statusTone === "critical" ? Theme.red : Theme.textSecondary

    // The icon arrives with a little pop each time a new one peeks.
    property real pop: 1
    onItemChanged: if (item && !Theme.reduceMotion) popIn.restart()
    NumberAnimation { id: popIn; target: peek; property: "pop"; from: 0.6; to: 1; duration: 460; easing.type: Easing.OutBack; easing.overshoot: 2.2 }

    HoverHandler { onHoveredChanged: Notifs.peekHeld = hovered }
    TapHandler {
        onTapped: { const i = peek.item; Notifs.dropPeek(); if (i) Notifs.activate(i); }
    }

    Item {
        id: mark
        x: 16; anchors.verticalCenter: parent.verticalCenter
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
    Column {
        anchors { left: mark.right; leftMargin: 12; right: go.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
        spacing: 1
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
            visible: !!peek.item && !!peek.item.body
            width: parent.width; elide: Text.ElideRight
            maximumLineCount: 1
            text: peek.item ? String(peek.item.body || "").replace(/\s+/g, " ") : ""
            textFormat: Text.PlainText
            size: 12; color: Theme.textSecondary
        }
    }
    Rectangle {
        id: go
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
            onClicked: { const i = peek.item; Notifs.dropPeek(); if (i) Notifs.activate(i); }
        }
    }
}
