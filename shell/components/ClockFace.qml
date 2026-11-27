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
    readonly property alias digits: morph
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
    TextMorph {
        id: morph
        anchors.horizontalCenter: face.centered ? parent.horizontalCenter : undefined
        text: Dates.clock(face.now)
        size: face.clockSize; weight: Theme.wBold; rounded: true
        color: face.ink
        duration: Theme.breatheMs; stagger: 60
    }
    Column {
        id: slot
        leftPadding: face.lead
        topPadding: visibleChildren.length > 0 ? Theme.lockLineTop : 0
        spacing: Theme.s3
        anchors.horizontalCenter: face.centered ? parent.horizontalCenter : undefined
    }
}
