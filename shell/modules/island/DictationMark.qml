import QtQuick
import qs.config
import qs.components
import qs.services

Item {
    id: mark

    property bool lead: true
    property bool moving: true
    property real room: Theme.sp(180)

    readonly property string phase: DictationLive.phase
    readonly property bool live: DictationLive.live
    readonly property bool writing: DictationLive.writing
    readonly property bool still: Theme.reduceMotion || !moving
    readonly property bool hasGlyph: DictationLive.glyph !== ""
    readonly property color liveTone: phase === "listening" ? Theme.textPrimary : Theme.orange

    implicitWidth: lead ? leadRow.implicitWidth : trail.implicitWidth
    implicitHeight: Math.max(Theme.glyphS, lead ? leadRow.implicitHeight : trail.implicitHeight)

    Row {
        id: leadRow
        visible: mark.lead
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.s2

        Item {
            visible: mark.phase === "listening" || mark.phase === "quiet"
            width: Theme.s2 + 2; height: Theme.glyphS
            anchors.verticalCenter: parent.verticalCenter
            Rectangle {
                anchors.centerIn: parent
                width: parent.width; height: width; radius: width / 2
                color: Theme.red
                SequentialAnimation on opacity {
                    running: mark.visible && mark.lead && mark.phase === "listening" && !mark.still
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.45; duration: Theme.breatheMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeSine }
                    NumberAnimation { to: 1; duration: Theme.breatheMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeSine }
                }
            }
        }
        Row {
            id: wave
            visible: mark.phase === "listening" || mark.phase === "quiet" || mark.writing
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            property real sweep: 0
            NumberAnimation on sweep {
                running: mark.visible && mark.lead && mark.writing && !mark.still
                from: 0; to: 1; duration: Theme.shimmerMs; loops: Animation.Infinite
            }
            Repeater {
                model: 5
                Rectangle {
                    required property int index
                    readonly property real shape: [0.55, 0.8, 1, 0.8, 0.55][index]
                    readonly property real lit: {
                        if (!mark.writing) return 1;
                        if (mark.still) return 0.75;
                        const d = Math.abs(wave.sweep * 1.6 - 0.3 - index / 4);
                        return 0.3 + 0.7 * Math.max(0, 1 - d * 2.5);
                    }
                    anchors.verticalCenter: parent.verticalCenter
                    width: 3; radius: 1.5
                    height: mark.writing ? Math.round(Math.max(4, (Theme.s3 + 1) * shape * 0.7))
                          : Math.round(Math.max(3, 3 + (Theme.s3 + 1) * (mark.still ? shape * 0.35 : (DictationLive.bars[index] || 0))))
                    color: mark.writing ? Theme.accent : mark.phase === "quiet" ? Theme.orange : Theme.red
                    opacity: lit * (mark.phase === "quiet" ? 0.7 : 0.95)
                    Behavior on color { ColorAnimation { duration: Theme.colorMs } }
                }
            }
        }
        Icon {
            id: icon
            visible: mark.hasGlyph
            anchors.verticalCenter: parent.verticalCenter
            name: DictationLive.glyph
            size: Theme.glyphS
            color: DictationLive.tone
            style: mark.phase === "delivered" || mark.phase === "cancelled" || mark.phase === "nothing" ? "bold" : "duotone"
            transformOrigin: Item.Center
            property string was: ""
            onNameChanged: {
                if (name !== "" && was !== name && !Theme.reduceMotion) { scale = 0.6; pop.restart(); }
                was = name;
            }
            NumberAnimation { id: pop; target: icon; property: "scale"; to: 1; duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
        }
    }

    Row {
        id: trail
        visible: !mark.lead
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.s2
        Label {
            visible: mark.live
            anchors.verticalCenter: parent.verticalCenter
            text: DictationLive.clock
            size: Theme.tBody; weight: Theme.wSemibold; rounded: true
            color: mark.liveTone
            tabular: true
        }
        Icon {
            visible: DictationLive.privateTake && (mark.live || mark.writing)
            anchors.verticalCenter: parent.verticalCenter
            name: "lock-simple"
            size: Theme.glyphS
            color: Theme.textSecondary
        }
        Shimmer {
            visible: mark.writing
            anchors.verticalCenter: parent.verticalCenter
            text: DictationLive.app ? "Writing into " + DictationLive.app : "Writing it out"
            size: Theme.tBody; weight: Theme.wMedium
            color: Theme.textSecondary
            active: mark.visible && !mark.lead && !Theme.reduceMotion
        }
        Label {
            readonly property string words: DictationLive.privateTake && mark.live && mark.phase === "listening" ? DictationLive.saidPrivate : DictationLive.said
            visible: !mark.writing && words !== ""
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, mark.room)
            elide: Text.ElideRight
            text: words
            size: mark.live ? Theme.tSub : Theme.tBody
            weight: mark.live ? Theme.wMedium : Theme.wSemibold
            color: mark.live ? (mark.phase === "listening" ? Theme.textSecondary : Theme.orange)
                 : mark.phase === "delivered" ? Theme.textPrimary
                 : mark.phase === "cancelled" || mark.phase === "nothing" || mark.phase === "private" ? Theme.textSecondary
                 : DictationLive.tone
        }
        Rectangle {
            visible: DictationLive.queued > 0
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(height, count.implicitWidth + Theme.s2)
            height: count.implicitHeight + 2
            radius: height / 2
            color: Theme.wash(2)
            Label {
                id: count
                anchors.centerIn: parent
                text: "+" + DictationLive.queued
                size: Theme.tCaption; weight: Theme.wSemibold; rounded: true
                color: Theme.textSecondary
                tabular: true
            }
            HoverHandler { id: queuedHover; margin: Theme.s2 }
            Tip { text: DictationLive.queued === 1 ? "One more take is being written" : DictationLive.queued + " more takes are being written"; shown: queuedHover.hovered; below: true }
        }
    }
}
