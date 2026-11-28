import QtQuick
import qs.config

Column {
    id: face

    property color ink: Theme.lockTint(Theme.accent)
    property real screenH: 1080
    property real unit: 1
    property bool centered: true
    property bool longDate: false
    property bool running: true
    property date now: new Date()
    readonly property int dateSize: Math.round(Theme.tLockDate * unit)
    readonly property int clockSize: Math.round(Theme.lockClockSize(screenH) * unit)
    readonly property int lineSize: Math.round(Theme.tLockLine * unit)
    readonly property int lead: centered ? 0 : Math.round(clockSize * Theme.textScale * Theme.clockLead)
    readonly property alias digits: clockRow
    default property alias lines: slot.data

    spacing: Theme.lockClockGap

    onRunningChanged: if (running) {
        now = new Date();
        minute.interval = 60000 - (Date.now() % 60000) + 50;
        minute.restart();
    }
    Timer {
        id: minute
        running: face.running
        interval: 60000 - (Date.now() % 60000) + 50
        onTriggered: { face.now = new Date(); interval = 60000 - (Date.now() % 60000) + 50; restart(); }
    }

    Label {
        anchors.horizontalCenter: face.centered ? parent.horizontalCenter : undefined
        leftPadding: face.lead
        text: face.longDate ? Dates.longDate(face.now) : Dates.shortDate(face.now)
        size: face.dateSize; weight: Theme.wSemibold
        color: face.ink
    }
    Item {
        id: clockRow
        anchors.horizontalCenter: face.centered ? parent.horizontalCenter : undefined
        readonly property int clockPx: Math.round(face.clockSize * Theme.textScale)
        readonly property string timeText: Dates.clock(face.now)
        readonly property var timeParts: {
            const split = timeText.match(/^([0-9]+)[^0-9]+([0-9]{2})$/);
            if (split) return { hour: split[1], minute: split[2] };
            const at = face.now;
            const h = Settings.clock24 ? at.getHours() : (at.getHours() + 11) % 12 + 1;
            return { hour: Settings.clock24 && h < 10 ? "0" + h : String(h), minute: (at.getMinutes() < 10 ? "0" : "") + at.getMinutes() };
        }
        readonly property real digitCapH: zero.tightBoundingRect.height || clockMetrics.ascent
        readonly property real lift: -Math.round(clockMetrics.ascent - digitCapH)
        readonly property real pairW: Math.ceil(zero.advanceWidth * 2)
        width: implicitWidth
        height: implicitHeight
        implicitWidth: pairW + colon.implicitWidth + pairW
        implicitHeight: Math.ceil(digitCapH)

        TextMetrics {
            id: zero
            text: "0"
            font.family: Fonts.clockFace
            font.pixelSize: clockRow.clockPx
            font.weight: Fonts.clockIsGeist ? Theme.wSemibold : Theme.wBold
            font.features: Theme.numeralFeatures(true, true)
            font.letterSpacing: Fonts.clockTracking(clockRow.clockPx)
            font.variableAxes: Theme.axesWeight(face.clockSize, Fonts.clockIsGeist ? Theme.wSemibold : Theme.wBold)
        }
        FontMetrics {
            id: clockMetrics
            font.family: Fonts.clockFace
            font.pixelSize: clockRow.clockPx
            font.weight: Fonts.clockIsGeist ? Theme.wSemibold : Theme.wBold
            font.variableAxes: Theme.axesWeight(face.clockSize, Fonts.clockIsGeist ? Theme.wSemibold : Theme.wBold)
        }
        Item {
            id: hourCell
            readonly property real capH: clockRow.digitCapH
            x: 0
            width: clockRow.pairW
            height: clockRow.digitCapH
            clip: true
            Label {
                id: hours
                anchors.right: parent.right
                y: clockRow.lift
                width: parent.width
                horizontalAlignment: Text.AlignRight
                text: clockRow.timeParts.hour
                size: face.clockSize; weight: Fonts.clockIsGeist ? Theme.wSemibold : Theme.wBold; rounded: true; tabular: true
                color: face.ink
                font.family: Fonts.clockFace
                font.letterSpacing: Fonts.clockTracking(clockRow.clockPx)
            }
        }
        Item {
            id: colonCell
            readonly property real capH: clockRow.digitCapH
            x: hourCell.width
            width: colon.implicitWidth
            height: clockRow.digitCapH
            clip: true
            Label {
                id: colon
                x: 0
                y: clockRow.lift - clockRow.clockPx * 0.04
                text: ":"
                size: face.clockSize; weight: hours.weight; rounded: true; tabular: true
                color: face.ink
                font.family: Fonts.clockFace
                font.letterSpacing: 0
            }
        }
        Item {
            id: minuteCell
            readonly property real capH: clockRow.digitCapH
            x: colonCell.x + colonCell.width
            width: clockRow.pairW
            height: clockRow.digitCapH
            clip: true
            Label {
                id: minutes
                anchors.left: parent.left
                y: clockRow.lift
                width: parent.width
                text: clockRow.timeParts.minute
                size: face.clockSize; weight: hours.weight; rounded: true; tabular: true
                color: face.ink
                font.family: Fonts.clockFace
                font.letterSpacing: Fonts.clockTracking(clockRow.clockPx)
            }
        }
    }
    Column {
        id: slot
        leftPadding: face.lead
        topPadding: visibleChildren.length > 0 ? Theme.lockLineTop : 0
        spacing: Theme.s3
        anchors.horizontalCenter: face.centered ? parent.horizontalCenter : undefined
    }
}
