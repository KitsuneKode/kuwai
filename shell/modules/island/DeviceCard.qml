// A device, grown out of the island (Moments.card), as AirPods do on an
// iPhone: its photo (devices.json) or its kind, a badge for how it's
// attached (Bluetooth, USB), its name, what happened ("Connected", "via
// Audiocular D07", "Disconnected · Sound on Built-in Speakers") and its
// battery. Connecting, the link closes around it and pings out as it
// settles, then the battery ring fills; going, it greys and sinks a little.
// A click opens Sound in the center; it folds back by itself, never under
// the pointer.
import QtQuick
import QtQuick.Effects
import Quickshell.Widgets
import qs.config
import qs.components
import qs.services

Item {
    id: card
    required property var item
    required property var bar
    implicitWidth: 420
    implicitHeight: 84
    readonly property bool gone: !!item && item.gone
    readonly property real battery: item && item.battery >= 0 ? item.battery : -1

    property real settle: 1
    property real link: 0
    property real ping: 0
    property real fill: 1
    property string shownKey: ""
    onItemChanged: {
        if (!item || item.key + !!item.gone === shownKey) return;
        shownKey = item.key + !!item.gone;
        if (Theme.reduceMotion) return;
        connecting.stop(); going.stop();
        if (gone) { going.restart(); return; }
        settle = 0; link = 0; ping = 0; fill = 0;
        connecting.restart();
    }
    SequentialAnimation {
        id: connecting
        PauseAnimation { duration: 160 }
        NumberAnimation { target: card; property: "link"; to: 1; duration: 520; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
        ParallelAnimation {
            NumberAnimation { target: card; property: "ping"; to: 1; duration: 480; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
            NumberAnimation { target: card; property: "settle"; to: 1; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 1.4 }
            NumberAnimation { target: card; property: "fill"; to: 1; duration: 900; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
        }
    }
    NumberAnimation { id: going; target: card; property: "settle"; from: 1.12; to: 1; duration: 360; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }

    HoverHandler { onHoveredChanged: Moments.cardHeld = hovered }
    TapHandler {
        onTapped: { Moments.dropCard(); Notifs.toggleCenter("sound", "click", card.bar.screenName); }
    }

    Item {
        id: mark
        x: 18; anchors.verticalCenter: parent.verticalCenter
        width: 54; height: 54
        // Settling in from a little small; going, it sinks to a little small.
        scale: card.gone ? 0.94 + 0.06 * (card.settle - 1) / 0.12 : 0.86 + 0.14 * card.settle
        opacity: card.gone ? 0.5 : 0.55 + 0.45 * Math.min(1, card.settle)
        Behavior on opacity { NumberAnimation { duration: Theme.colorMs } }
        Image {
            id: photo
            anchors.fill: parent
            source: card.item ? card.item.image || "" : ""
            sourceSize: Qt.size(108, 108)
            fillMode: Image.PreserveAspectFit
            asynchronous: true; mipmap: true
            visible: status === Image.Ready
            layer.enabled: visible
            layer.effect: MultiEffect { saturation: card.gone ? -1 : 0 }
        }
        Rectangle {
            anchors.fill: parent
            visible: photo.status !== Image.Ready
            radius: width / 2
            color: Theme.platter
            Text {
                anchors.centerIn: parent
                text: card.item ? card.item.glyph || "\u{f00af}" : ""
                font.family: Theme.fontGlyph; font.pixelSize: 27
                color: Theme.textPrimary
            }
        }
    }
    LinkRing {
        anchors.centerIn: mark
        width: 64; height: 64
        draw: card.link; ping: card.ping
    }
    // How it's attached, on the device's shoulder.
    Rectangle {
        readonly property string linkGlyph: !card.item ? "" : card.item.link === "bluetooth" ? "\u{f00af}" : card.item.link === "usb" ? "\u{f0553}" : ""
        visible: linkGlyph !== ""
        x: mark.x + mark.width - width + 3; y: mark.y - 3
        width: 22; height: 22; radius: 11
        color: "#2c2c2e"
        border.width: 2; border.color: "black"
        scale: card.gone ? 1 : 0.4 + 0.6 * Math.min(1.1, card.settle)
        opacity: card.gone ? 0.6 : Math.min(1, card.settle * 1.5)
        Text {
            anchors.centerIn: parent
            text: parent.linkGlyph
            font.family: Theme.fontGlyph; font.pixelSize: 12
            color: card.gone ? Theme.textSecondary : card.item && card.item.link === "bluetooth" ? Theme.blue : Theme.textPrimary
        }
    }

    Column {
        anchors { left: mark.right; leftMargin: 14; right: trail.visible ? trail.left : parent.right; rightMargin: trail.visible ? 12 : 20; verticalCenter: parent.verticalCenter }
        spacing: 3
        Label {
            width: parent.width; elide: Text.ElideRight
            text: card.item ? card.item.title || "" : ""
            size: 16; weight: Theme.wSemibold
            color: card.gone ? Theme.textSecondary : Theme.textPrimary
        }
        Row {
            width: parent.width
            spacing: 6
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 6; height: 6; radius: 3
                color: card.item ? card.item.tone || Theme.green : Theme.green
            }
            Label {
                id: stateLabel
                anchors.verticalCenter: parent.verticalCenter
                text: card.item ? card.item.state || "" : ""
                size: 12; weight: Theme.wMedium
                color: card.item ? card.item.tone || Theme.green : Theme.green
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                visible: text !== ""
                width: Math.min(implicitWidth, parent.width - stateLabel.width - 18)
                elide: Text.ElideRight
                text: card.item && card.item.detail ? "·  " + card.item.detail : ""
                size: 12
                color: Theme.textSecondary
            }
        }
    }

    // The battery as a ring with its number, or a tick for "it's here".
    Item {
        id: trail
        anchors { right: parent.right; rightMargin: 20; verticalCenter: parent.verticalCenter }
        width: 44; height: 44
        visible: !card.gone
        StatRing {
            anchors.centerIn: parent
            visible: card.battery >= 0
            size: 44; stroke: 4
            value: Math.max(0, card.battery) * card.fill
            text: Math.round(Math.max(0, card.battery) * 100) + ""
            color: card.battery >= 0 && card.battery <= 0.2 ? Theme.red : Theme.green
            label: ""
        }
        Rectangle {
            anchors.centerIn: parent
            visible: card.battery < 0
            width: 30; height: 30; radius: 15
            scale: 0.5 + 0.5 * Math.min(1, card.settle)
            color: Qt.alpha(Theme.green, 0.18)
            Text {
                anchors.centerIn: parent
                text: "\u{f012c}"
                font.family: Theme.fontGlyph; font.pixelSize: 17
                color: Theme.green
            }
        }
    }
}
