// A device, grown out of the island (Moments.card), as AirPods do on an
// iPhone: its photo (devices.json) or its kind, a badge for how it's
// attached (Bluetooth, USB), its name, what happened ("Connected", "via
// Audiocular D07", "Disconnected · Sound on Built-in Speakers") and its
// battery. A click does the card's `open` (Sound in the center by default);
// it folds back by itself, never under the pointer.
//
// Motion: it's rare (gear comes and goes a few times a day), so connecting
// gets a moment, in order, as the island springs open:
//   the device slides in    320 ms ease-out, from 12 px left and 0.9
//   its name, then its state, 60 ms apart, rising 6 px   280 ms ease-out
//   the link closes around it    460 ms ease-out
//   and, as it closes: the ring pings out (420 ms), the device settles
//   (a 4 % overshoot), the badge lands, the state's dot ripples once, the
//   battery ring fills (StatRing's 400 ms glide) or the tick lands.
// Going, the same entrance, greyed, and the ring comes undone (420 ms
// ease-in-out): the link breaking. Picked in Sound (quiet), no link: just
// the entrance. Reduced motion: the island's fade alone.
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
    readonly property bool gone: !!(item && item.gone)
    readonly property bool quiet: !!(item && item.quiet)
    readonly property real battery: item && item.battery >= 0 ? item.battery : -1

    property real enter: 1            // the device sliding in
    property real line1: 1            // the name
    property real line2: 1            // the state
    property real link: 0             // the ring: drawn (connecting) or undone (going)
    property real ping: 0
    property real settle: 1
    property real ripple: 1
    property real fill: 1
    property string shownKey: ""
    onItemChanged: {
        if (!item || item.key + !!item.gone + !!item.quiet === shownKey) return;
        shownKey = item.key + !!item.gone + !!item.quiet;
        connecting.stop(); going.stop(); entering.stop();
        if (Theme.reduceMotion) { enter = 1; line1 = 1; line2 = 1; link = 0; ping = 0; settle = 1; ripple = 1; fill = 1; return; }
        enter = 0; line1 = 0; line2 = 0; ping = 0; ripple = 1;
        entering.restart();
        if (gone) { link = 1; settle = 1; fill = 1; going.restart(); }
        else if (quiet) { link = 0; settle = 1; fill = 1; }
        else { link = 0; settle = 0; fill = 0; ripple = 0; connecting.restart(); }
    }
    readonly property var ease: Theme.easeOut
    ParallelAnimation {
        id: entering
        SequentialAnimation {
            PauseAnimation { duration: 80 }
            NumberAnimation { target: card; property: "enter"; to: 1; duration: 320; easing.type: Easing.BezierSpline; easing.bezierCurve: card.ease }
        }
        SequentialAnimation {
            PauseAnimation { duration: 140 }
            NumberAnimation { target: card; property: "line1"; to: 1; duration: 280; easing.type: Easing.BezierSpline; easing.bezierCurve: card.ease }
        }
        SequentialAnimation {
            PauseAnimation { duration: 200 }
            NumberAnimation { target: card; property: "line2"; to: 1; duration: 280; easing.type: Easing.BezierSpline; easing.bezierCurve: card.ease }
        }
    }
    SequentialAnimation {
        id: connecting
        PauseAnimation { duration: 200 }
        NumberAnimation { target: card; property: "link"; to: 1; duration: 460; easing.type: Easing.BezierSpline; easing.bezierCurve: card.ease }
        ParallelAnimation {
            NumberAnimation { target: card; property: "ping"; to: 1; duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: card.ease }
            NumberAnimation { target: card; property: "settle"; to: 1; duration: 380; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
            NumberAnimation { target: card; property: "ripple"; to: 1; duration: 520; easing.type: Easing.BezierSpline; easing.bezierCurve: card.ease }
            PropertyAction { target: card; property: "fill"; value: 1 }      // StatRing glides there itself
        }
    }
    SequentialAnimation {
        id: going
        PauseAnimation { duration: 260 }
        NumberAnimation { target: card; property: "link"; to: 0; duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeInOut }
    }

    HoverHandler { onHoveredChanged: Moments.cardHeld = hovered }
    TapHandler {
        onTapped: {
            const open = card.item ? card.item.open : null;
            Moments.dropCard();
            if (open) open();
            else Notifs.toggleCenter("sound", "click", card.bar.screenName);
        }
    }

    Item {
        id: mark
        x: 18; anchors.verticalCenter: parent.verticalCenter
        width: 54; height: 54
        opacity: card.enter * (card.gone ? 0.5 : 1)
        // Connecting: in from a little small, a touch over as the link closes.
        scale: (0.9 + 0.1 * card.enter) * (card.gone ? 0.94 : 0.96 + 0.04 * card.settle)
        transform: Translate { x: -12 * (1 - card.enter) }
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
        draw: card.link; ping: card.gone ? 0 : card.ping
        color: card.gone ? Theme.textTertiary : Theme.green
    }
    // How it's attached, on the device's shoulder: it lands as the link closes.
    Rectangle {
        readonly property string linkGlyph: !card.item ? "" : card.item.link === "bluetooth" ? "\u{f00af}" : card.item.link === "usb" ? "\u{f0553}" : ""
        visible: linkGlyph !== ""
        x: mark.x + mark.width - width + 3; y: mark.y - 3
        width: 22; height: 22; radius: 11
        color: "#2c2c2e"
        border.width: 2; border.color: "black"
        scale: 0.6 + 0.4 * card.settle
        opacity: card.enter * Math.min(1, card.settle * 1.5) * (card.gone ? 0.6 : 1)
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
            opacity: card.line1
            transform: Translate { y: 6 * (1 - card.line1) }
        }
        Row {
            width: parent.width
            spacing: 6
            opacity: card.line2
            transform: Translate { y: 6 * (1 - card.line2) }
            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: 6; height: 6
                Rectangle {
                    anchors.fill: parent
                    radius: 3
                    color: card.item ? card.item.tone || Theme.green : Theme.green
                }
                // One ripple from the dot as the link closes.
                Rectangle {
                    anchors.centerIn: parent
                    width: 6; height: 6; radius: 3
                    color: "transparent"
                    border.width: 1.5; border.color: Theme.green
                    visible: card.ripple > 0.001 && card.ripple < 0.999
                    scale: 1 + 2.2 * card.ripple
                    opacity: 1 - card.ripple
                }
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

    // The battery as a ring with its number (greyed once it's on its own),
    // or a tick for "it's here".
    Item {
        id: trail
        anchors { right: parent.right; rightMargin: 20; verticalCenter: parent.verticalCenter }
        width: 44; height: 44
        visible: card.battery >= 0 || (!card.gone && !card.quiet)
        opacity: card.line2
        StatRing {
            anchors.centerIn: parent
            visible: card.battery >= 0
            size: 44; stroke: 4
            value: Math.max(0, card.battery) * card.fill
            text: Math.round(Math.max(0, card.battery) * 100) + ""
            color: card.gone ? Theme.textTertiary : card.battery >= 0 && card.battery <= 0.2 ? Theme.red : Theme.green
            label: ""
        }
        Rectangle {
            anchors.centerIn: parent
            visible: card.battery < 0
            width: 30; height: 30; radius: 15
            scale: 0.6 + 0.4 * card.settle
            opacity: Math.min(1, card.settle * 1.5)
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
