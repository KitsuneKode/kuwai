import QtQuick
import qs.config
import qs.components
import qs.services
import "../../services/notifPrivacy.mjs" as Privacy

ClockFace {
    id: face

    property real areaW: 1920
    property real areaH: 1080
    property bool showing: true
    property bool dark: false
    property real level: 0

    readonly property real dim: 1 - level
    readonly property real margin: 0.06
    readonly property var next: Calendar.nextAfter(face.now.getTime(), 12 * 3600000)
    readonly property string named: next ? Privacy.eventTitle(next, Notifs.privacyFor("saver")) : ""
    readonly property real lineWidth: areaW * 0.4
    readonly property color soft: Qt.alpha(ink, 0.72)

    running: showing
    longDate: true
    unit: Theme.saverClockScale
    screenH: areaH
    opacity: 1 - level * (1 - Theme.saverLongDim)
    x: Math.round((areaW - width) / 2)
    y: Math.max(areaH * margin, Math.round(areaH * 0.42 - height / 2))
    Behavior on x { NumberAnimation { duration: Theme.saverMoveMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeSine } }
    Behavior on y { NumberAnimation { duration: Theme.saverMoveMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeSine } }

    Timer {
        interval: 45000 + Math.random() * 30000; repeat: true
        running: face.showing && !Theme.reduceMotion
        onTriggered: {
            const m = face.margin;
            const maxX = Math.max(face.areaW * m, face.areaW * (1 - m) - face.width);
            const maxY = Math.max(face.areaH * m, face.areaH * (1 - m) - face.height);
            face.x = face.areaW * m + Math.random() * (maxX - face.areaW * m);
            face.y = face.areaH * m + Math.random() * (maxY - face.areaH * m);
            interval = 45000 + Math.random() * 30000;
        }
    }

    ClockChip {
        visible: Weather.ok && !face.dark
        anchors.horizontalCenter: parent.horizontalCenter
        opacity: face.dim
        glyph: SystemStats.weatherGlyph
        text: Weather.temp + "°" + (Weather.desc ? " · " + Weather.desc : "")
        size: face.lineSize; color: face.soft
    }
    ClockChip {
        visible: !!face.next && !face.dark
        anchors.horizontalCenter: parent.horizontalCenter
        opacity: face.dim
        glyph: "\u{f00f0}"
        text: face.next ? (face.named ? Dates.time(face.next.start) + " · " + face.named : "Next event at " + Dates.time(face.next.start)) : ""
        size: face.lineSize; color: face.soft; maxWidth: face.lineWidth
    }
    ClockChip {
        visible: Media.playing && !!Media.active && !face.dark && !Settings.screensaverPulse
        anchors.horizontalCenter: parent.horizontalCenter
        opacity: face.dim
        glyph: "\u{f075a}"
        text: Media.active ? Media.title(Media.active) + (Media.active.trackArtist ? " · " + Media.active.trackArtist : "") : ""
        size: face.lineSize; color: face.soft; maxWidth: face.lineWidth
    }
    MediaPulse {
        visible: Settings.screensaverPulse && Media.playing && !!Media.active && !face.dark
        anchors.horizontalCenter: parent.horizontalCenter
        opacity: face.dim
        active: visible && face.showing
        title: Media.active ? Media.title(Media.active) + (Media.active.trackArtist ? " · " + Media.active.trackArtist : "") : ""
        size: face.lineSize
        maxWidth: face.lineWidth
        leftPadding: 0; topPadding: 0
    }
}
