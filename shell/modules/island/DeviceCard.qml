// A device, grown out of the island (Moments.card), as AirPods do on an
// iPhone: its photo (devices.json) or its kind, a badge for how it's
// attached (Bluetooth, USB), its name, what happened ("Connected", "via
// Audiocular D07", "Disconnected · Sound on Built-in Speakers") and its
// battery. A click does the card's `open` (Sound in the center by default);
// it folds back by itself, never under the pointer.
//
// Motion: it's rare (gear comes and goes a few times a day), so connecting
// gets a moment, in order, as the island springs open. Nothing overshoots:
// nothing was thrown.
//   the device comes up, dim, from 0.92           300 ms ease-out
//   its name, then its state, 50 ms apart, rising 4 px   260 ms ease-out
//   a ring of light closes around it              480 ms ease-out
//   and, as it closes: the device lights up, the ring breathes out and
//   fades (450 ms), the badge lands, the state's dot ripples once, the
//   battery ring fills (StatRing's 400 ms glide) or the tick lands.
//   Sound gear then says how loud: "Connected" hands its line to the level,
//   which fills from empty (220 ms crossfade, 600 ms fill).
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

    property real enter: 1            // the device coming up
    property real line1: 1            // the name
    property real line2: 1            // the state
    property real link: 0             // the ring: drawn (connecting) or undone (going)
    property real ping: 0
    property real settle: 1
    property real ripple: 1
    property real fill: 1
    // Sound gear: its level (0..1), once "Connected" has been read.
    readonly property real level: item && item.level >= 0 ? item.level : -1
    property real swap: 0
    property real levelFill: 1
    property string shownKey: ""
    onItemChanged: {
        if (!item || item.key + !!item.gone + !!item.quiet === shownKey) return;
        shownKey = item.key + !!item.gone + !!item.quiet;
        connecting.stop(); going.stop(); entering.stop();
        swap = 0; levelFill = 1;
        if (Theme.reduceMotion) { enter = 1; line1 = 1; line2 = 1; link = 0; ping = 0; settle = 1; ripple = 1; fill = 1; swap = level >= 0 && !gone && !quiet ? 1 : 0; return; }
        enter = 0; line1 = 0; line2 = 0; ping = 0; ripple = 1;
        entering.restart();
        if (gone) { link = 1; settle = 1; fill = 1; going.restart(); }
        else if (quiet) { link = 0; settle = 1; fill = 1; }
        else { link = 0; settle = 0; fill = 0; ripple = 0; connecting.restart(); }
    }
    // The level can arrive a moment after the link (the sound moving to it).
    onLevelChanged: if (level >= 0 && !gone && !quiet && swap === 0 && !connecting.running && !Theme.reduceMotion && shownKey !== "") toLevel.restart()
    readonly property var ease: Theme.easeOut
    ParallelAnimation {
        id: entering
        SequentialAnimation {
            PauseAnimation { duration: Theme.hoverMs }
            NumberAnimation { target: card; property: "enter"; to: 1; duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: card.ease }
        }
        SequentialAnimation {
            PauseAnimation { duration: 140 }
            NumberAnimation { target: card; property: "line1"; to: 1; duration: 260; easing.type: Easing.BezierSpline; easing.bezierCurve: card.ease }
        }
        SequentialAnimation {
            PauseAnimation { duration: 190 }
            NumberAnimation { target: card; property: "line2"; to: 1; duration: 260; easing.type: Easing.BezierSpline; easing.bezierCurve: card.ease }
        }
    }
    SequentialAnimation {
        id: connecting
        PauseAnimation { duration: Theme.enterMs }
        NumberAnimation { target: card; property: "link"; to: 1; duration: 480; easing.type: Easing.BezierSpline; easing.bezierCurve: card.ease }
        ParallelAnimation {
            NumberAnimation { target: card; property: "ping"; to: 1; duration: 450; easing.type: Easing.BezierSpline; easing.bezierCurve: card.ease }
            NumberAnimation { target: card; property: "settle"; to: 1; duration: 320; easing.type: Easing.BezierSpline; easing.bezierCurve: card.ease }
            NumberAnimation { target: card; property: "ripple"; to: 1; duration: Theme.pulseMs; easing.type: Easing.BezierSpline; easing.bezierCurve: card.ease }
            PropertyAction { target: card; property: "fill"; value: 1 }      // StatRing glides there itself
        }
        ScriptAction { script: if (card.level >= 0) toLevel.restart() }
    }
    SequentialAnimation {
        id: toLevel
        PauseAnimation { duration: Theme.breatheMs }
        PropertyAction { target: card; property: "levelFill"; value: 0 }
        NumberAnimation { target: card; property: "swap"; to: 1; duration: 220; easing.type: Easing.BezierSpline; easing.bezierCurve: card.ease }
        NumberAnimation { target: card; property: "levelFill"; to: 1; duration: 600; easing.type: Easing.BezierSpline; easing.bezierCurve: card.ease }
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
        // Connecting: up from a little small and dim; lit as the link closes.
        opacity: card.enter * (card.gone ? 0.5 : 0.6 + 0.4 * card.settle)
        scale: (0.92 + 0.08 * card.enter) * (card.gone ? 0.94 : 1)
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
        width: 76; height: 76
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
        scale: 0.8 + 0.2 * card.settle
        opacity: card.enter * card.settle * (card.gone ? 0.6 : 1)
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
            size: Theme.tHeadline; weight: Theme.wSemibold
            color: card.gone ? Theme.textSecondary : Theme.textPrimary
            opacity: card.line1
            transform: Translate { y: 4 * (1 - card.line1) }
        }
        Item {
            width: parent.width
            height: stateRow.height
            opacity: card.line2
            transform: Translate { y: 4 * (1 - card.line2) }
            Row {
                id: stateRow
                width: parent.width
                spacing: 6
                opacity: 1 - card.swap
                visible: card.swap < 1
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
            // Sound gear, connected: how loud, filling from empty.
            Row {
                anchors.verticalCenter: stateRow.verticalCenter
                width: parent.width
                spacing: 10
                visible: card.swap > 0
                opacity: card.swap
                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - levelText.width - 10
                    height: 6
                    Rectangle { anchors.fill: parent; radius: 3; color: Theme.track }
                    Rectangle {
                        height: parent.height; radius: 3
                        width: Math.max(height, parent.width * Math.max(0, Math.min(1, card.level)) * card.levelFill)
                        visible: card.level * card.levelFill > 0.004
                        color: card.item && card.item.muted ? Theme.fillDim : Theme.fill
                    }
                }
                Label {
                    id: levelText
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(26, implicitWidth); horizontalAlignment: Text.AlignRight
                    text: card.item && card.item.muted ? "Muted" : String(Math.round(Math.max(0, card.level) * 100 * card.levelFill))
                    size: 12; weight: Theme.wMedium
                    color: Theme.textSecondary
                    font.features: { "tnum": 1 }
                }
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
            scale: 0.8 + 0.2 * card.settle
            opacity: card.settle
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
