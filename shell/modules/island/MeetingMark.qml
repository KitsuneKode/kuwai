import QtQuick
import qs.config
import qs.components
import qs.services

Row {
    id: mark

    property bool lead: true
    property bool time: true
    property bool line: false
    property bool bars: false
    property bool moving: true
    property real now: Date.now()
    property real lineRoom: Theme.sp(260)

    readonly property string phase: Meeting.phase
    readonly property color tone: phase === "paused" || phase === "pausing" ? Theme.orange : phase === "live" ? Theme.red : Theme.textSecondary
    readonly property string said: Meeting.lineOf(Meeting.latest, 160)
    readonly property string words: phase === "paused" ? "Paused" : phase === "pausing" ? "Pausing" : phase === "resuming" ? "Resuming" : phase === "ending" ? "Saving" : phase === "starting" ? "Starting" : ""

    spacing: Theme.s2

    Item {
        visible: mark.lead
        width: Theme.glyphS; height: Theme.glyphS
        anchors.verticalCenter: parent.verticalCenter
        Rectangle {
            visible: mark.phase === "live" || mark.phase === "starting" || mark.phase === "resuming"
            anchors.centerIn: parent
            width: Theme.s2 + 2; height: width; radius: width / 2
            color: Theme.red
            SequentialAnimation on opacity {
                running: mark.moving && mark.visible && mark.phase === "live" && !Theme.reduceMotion
                loops: Animation.Infinite
                NumberAnimation { to: 0.45; duration: Theme.breatheMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeSine }
                NumberAnimation { to: 1; duration: Theme.breatheMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeSine }
            }
        }
        Row {
            visible: mark.phase === "paused" || mark.phase === "pausing"
            anchors.centerIn: parent
            spacing: 2
            Repeater {
                model: 2
                Rectangle { width: 3; height: Theme.s3 - 1; radius: 1.5; color: Theme.orange }
            }
        }
        Text {
            textFormat: Text.PlainText
            visible: mark.phase === "ending"
            anchors.centerIn: parent
            text: "\u{f0772}"
            font.family: Theme.fontGlyph; font.pixelSize: Theme.glyphS
            color: Theme.textSecondary
            RotationAnimation on rotation {
                running: mark.moving && mark.visible && mark.phase === "ending" && !Theme.reduceMotion
                loops: Animation.Infinite; from: 0; to: 360; duration: Theme.spinMs
            }
        }
    }
    Label {
        visible: mark.time
        anchors.verticalCenter: parent.verticalCenter
        text: mark.words !== "" && !mark.line ? mark.words : Meeting.clock(mark.now)
        size: Theme.tBody; weight: Theme.wSemibold; rounded: true
        color: mark.tone
        tabular: true
    }
    Row {
        id: levels
        visible: mark.bars
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        readonly property real level: Math.max(0, Meeting.micLevel, Meeting.callLevel)
        Repeater {
            model: 4
            Rectangle {
                required property int index
                readonly property real shape: [0.55, 1, 0.8, 0.6][index]
                anchors.verticalCenter: parent.verticalCenter
                width: 3; radius: 1.5
                height: Math.round(Math.max(3, 3 + (Theme.s3 + 1) * Math.min(1, levels.level * shape * (mark.moving ? 1 : 0.4))))
                color: Theme.red
                opacity: 0.9
            }
        }
    }
    Label {
        visible: mark.line
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, mark.lineRoom)
        elide: Text.ElideRight
        text: mark.words !== "" ? mark.words + (mark.said ? " · " + mark.said : "") : mark.said !== "" ? mark.said : Meeting.sharing ? "Listening · hidden while you share" : "Listening…"
        size: Theme.tSub; weight: Theme.wMedium
        color: Theme.textSecondary
    }
}
