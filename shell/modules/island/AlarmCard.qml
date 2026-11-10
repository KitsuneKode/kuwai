// An alarm ringing, a reminder due, or a timer done, grown out of the island
// (Moments.card with kind "alarm" | "reminder" | "timer"), as the Dynamic
// Island does for an iPhone alarm: the mark on the left, what it is and
// when, and the two answers on the right. It stays until answered (an
// alarm) or folds away after a while (a reminder lands in the center then).
//
//   card: { key, kind, title, sub, id, act: { primary: [label, fn], secondary: [label, fn] } }
//
// Motion: rare (a few times a day) and asking for attention, so it may
// move, but calmly and only while it asks.
//   in        the mark comes up from 0.9 (300 ms ease-out), the title then the
//             line under it rise 4 px (260 ms, 50 ms apart), the buttons last
//   alarm     the bell rings: a damped swing (±16° → 0 over 700 ms), a ring of
//             light breathing out of the disc with each swing, every 1.4 s
//   reminder  the disc's ring fills once (480 ms) and the bell swings once
//   timer     the ring fills, the tick lands
//   press     buttons sink to 0.96 (Theme.pressMs)
// Reduced motion: no swinging or breathing; the island's fade alone.
import QtQuick
import qs.config
import qs.components
import qs.services

Item {
    id: card
    required property var item
    required property var bar
    implicitWidth: 440
    implicitHeight: 84

    readonly property string kind: item ? item.kind || "" : ""
    readonly property color tone: kind === "timer" ? Theme.green : Theme.orange
    readonly property bool ringing: kind === "alarm"
    readonly property bool calm: Theme.reduceMotion

    property real enter: 1
    property real line1: 1
    property real line2: 1
    property real actsIn: 1
    property real swing: 0          // the bell's angle, degrees
    property real breathe: 1        // the ring of light: 0 at the disc → 1 gone
    property real fill: 1           // the disc's ring (reminder, timer)

    property string shownKey: ""
    onItemChanged: {
        if (!item || item.key + item.id === shownKey) return;
        shownKey = item.key + item.id;
        entering.stop(); ringOnce.stop();
        if (calm) { enter = 1; line1 = 1; line2 = 1; actsIn = 1; fill = 1; swing = 0; breathe = 1; return; }
        enter = 0; line1 = 0; line2 = 0; actsIn = 0; fill = ringing ? 1 : 0;
        entering.restart();
        if (!ringing) ringOnce.restart();
    }

    readonly property var ease: Theme.easeOut
    ParallelAnimation {
        id: entering
        SequentialAnimation {
            PauseAnimation { duration: Theme.hoverMs }
            NumberAnimation { target: card; property: "enter"; to: 1; duration: Theme.cardInMs; easing.type: Easing.BezierSpline; easing.bezierCurve: card.ease }
        }
        SequentialAnimation {
            PauseAnimation { duration: Theme.pressMs }
            NumberAnimation { target: card; property: "line1"; to: 1; duration: Theme.cardRiseMs; easing.type: Easing.BezierSpline; easing.bezierCurve: card.ease }
        }
        SequentialAnimation {
            PauseAnimation { duration: Theme.pressMs + Theme.revealStepMs + 10 }
            NumberAnimation { target: card; property: "line2"; to: 1; duration: Theme.cardRiseMs; easing.type: Easing.BezierSpline; easing.bezierCurve: card.ease }
        }
        SequentialAnimation {
            PauseAnimation { duration: Theme.cardRiseMs }
            NumberAnimation { target: card; property: "actsIn"; to: 1; duration: Theme.cardRiseMs; easing.type: Easing.BezierSpline; easing.bezierCurve: card.ease }
        }
    }
    // A reminder or a timer: the ring fills, the bell swings once.
    SequentialAnimation {
        id: ringOnce
        PauseAnimation { duration: Theme.enterMs }
        NumberAnimation { target: card; property: "fill"; to: 1; duration: Theme.ringDrawMs; easing.type: Easing.BezierSpline; easing.bezierCurve: card.ease }
        ScriptAction { script: if (card.kind === "reminder") swingOnce.restart() }
    }
    // One swing: out, back past the middle, settling (a damped pendulum).
    SequentialAnimation {
        id: swingOnce
        NumberAnimation { target: card; property: "swing"; to: 16; duration: Theme.swingMs * 0.13; easing.type: Easing.OutQuad }
        NumberAnimation { target: card; property: "swing"; to: -12; duration: Theme.swingMs * 0.21; easing.type: Easing.InOutQuad }
        NumberAnimation { target: card; property: "swing"; to: 8; duration: Theme.swingMs * 0.2; easing.type: Easing.InOutQuad }
        NumberAnimation { target: card; property: "swing"; to: -4; duration: Theme.swingMs * 0.19; easing.type: Easing.InOutQuad }
        NumberAnimation { target: card; property: "swing"; to: 0; duration: Theme.swingMs * 0.27; easing.type: Easing.OutQuad }
    }
    // An alarm: swing and breathe, again, while it rings and the card shows.
    Timer {
        interval: 1400; repeat: true; triggeredOnStart: true
        running: card.ringing && !card.calm && card.visible
        onTriggered: { swingOnce.restart(); breath.restart(); }
    }
    NumberAnimation { id: breath; target: card; property: "breathe"; from: 0; to: 1; duration: Theme.breathOutMs; easing.type: Easing.BezierSpline; easing.bezierCurve: card.ease }

    HoverHandler { onHoveredChanged: Moments.cardHeld = hovered }

    // ── The mark ─────────────────────────────────────────────────────────
    Item {
        id: mark
        x: 16; anchors.verticalCenter: parent.verticalCenter
        width: 52; height: 52
        opacity: card.enter
        scale: 0.9 + 0.1 * card.enter

        // The light breathing out of it.
        Rectangle {
            anchors.centerIn: parent
            width: parent.width * (1 + 0.45 * card.breathe); height: width; radius: width / 2
            color: "transparent"
            border.width: 2
            border.color: Qt.alpha(card.tone, 0.55 * (1 - card.breathe))
            visible: card.ringing && !card.calm
        }
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Qt.alpha(card.tone, 0.2)
        }
        StatRing {
            anchors.centerIn: parent
            visible: !card.ringing
            size: mark.width; stroke: 2.5
            value: card.fill
            color: card.tone
            text: ""; label: ""
        }
        Text {
            anchors.centerIn: parent
            text: card.kind === "timer" ? "\u{f012c}" : card.kind === "reminder" ? "\u{f009a}" : "\u{f0020}"
            font.family: Theme.fontGlyph; font.pixelSize: 24
            color: card.tone
            // The bell swings from its top, where it would hang.
            transform: Rotation { origin.x: 13; origin.y: 4; angle: card.swing }
        }
    }

    // ── What and when ────────────────────────────────────────────────────
    Column {
        anchors { left: mark.right; leftMargin: 14; right: acts.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
        spacing: 3
        Label {
            width: parent.width; elide: Text.ElideRight
            text: card.item ? card.item.title || "" : ""
            size: Theme.tHeadline; weight: Theme.wSemibold
            opacity: card.line1
            transform: Translate { y: 4 * (1 - card.line1) }
        }
        Label {
            width: parent.width; elide: Text.ElideRight
            text: card.item ? card.item.sub || "" : ""
            size: 13; weight: Theme.wMedium; rounded: true
            color: card.tone
            font.features: ({ "tnum": 1 })
            opacity: card.line2
            transform: Translate { y: 4 * (1 - card.line2) }
        }
    }

    // ── The answers ──────────────────────────────────────────────────────
    // Secondary: a tinted capsule (Snooze, Later). Primary: a round button
    // (Stop ✕, Done ✓), grey like iOS's stop, so the colour stays on the bell.
    Row {
        id: acts
        anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
        spacing: 10
        opacity: card.actsIn
        transform: Translate { x: 6 * (1 - card.actsIn) }
        readonly property var a: card.item && card.item.act ? card.item.act : ({})

        Rectangle {
            visible: !!acts.a.secondary
            anchors.verticalCenter: parent.verticalCenter
            width: secLabel.implicitWidth + 28; height: 40; radius: 20
            color: Qt.alpha(card.tone, secArea.containsMouse ? 0.34 : 0.24)
            scale: secArea.pressed ? 0.96 : 1
            Behavior on color { ColorAnimation { duration: Theme.colorMs } }
            Behavior on scale { NumberAnimation { duration: Theme.pressMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
            Label { id: secLabel; anchors.centerIn: parent; text: acts.a.secondary ? acts.a.secondary[0] : ""; size: 14; weight: Theme.wSemibold; color: card.tone }
            MouseArea { id: secArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { const f = acts.a.secondary[1]; Moments.dropCard(); f(); } }
            Accessible.role: Accessible.Button
            Accessible.name: acts.a.secondary ? acts.a.secondary[0] : ""
        }
        Rectangle {
            visible: !!acts.a.primary
            anchors.verticalCenter: parent.verticalCenter
            width: 40; height: 40; radius: 20
            color: priArea.containsMouse ? Theme.knobHover : Theme.knob
            scale: priArea.pressed ? 0.96 : 1
            Behavior on color { ColorAnimation { duration: Theme.colorMs } }
            Behavior on scale { NumberAnimation { duration: Theme.pressMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
            Text {
                anchors.centerIn: parent
                text: acts.a.primary && acts.a.primary[0] === "Done" ? "\u{f012c}" : "\u{f0156}"
                font.family: Theme.fontGlyph; font.pixelSize: 20
                color: Theme.textPrimary
            }
            MouseArea { id: priArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { const f = acts.a.primary[1]; Moments.dropCard(); f(); } }
            Accessible.role: Accessible.Button
            Accessible.name: acts.a.primary ? acts.a.primary[0] : ""
        }
    }
}
