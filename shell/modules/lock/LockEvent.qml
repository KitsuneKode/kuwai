import QtQuick
import qs.config
import qs.components
import qs.services
import "../../services/notifPrivacy.mjs" as Privacy

Item {
    id: line
    property real now: Date.now()
    property real plate: 0
    property real within: 4 * 3600000
    readonly property var event: Calendar.nextToday(now, within)
    readonly property string title: event ? Privacy.eventTitle(event, Notifs.privacyFor("lock")) : ""
    readonly property string at: event ? "at " + Dates.time(event.start) : ""
    visible: event !== null
    width: Math.min(Theme.sp(430), row.implicitWidth + Theme.s5)
    height: row.implicitHeight + Theme.s3

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Qt.alpha(Theme.glassBlack, line.plate)
        Rectangle { anchors.fill: parent; radius: parent.radius; color: Theme.platter; border.width: 1; border.color: Theme.edge(3) }
    }
    Row {
        id: row
        anchors.centerIn: parent
        spacing: Theme.sp(Theme.s1)
        Text {
            id: mark
            rightPadding: Theme.sp(Theme.s1)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "\u{f00f0}"
            font.family: Theme.fontGlyph; font.pixelSize: Theme.sp(Theme.glyphS)
            color: Qt.rgba(1, 1, 1, 0.72)
        }
        Label {
            id: titleLabel
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, Theme.sp(430) - Theme.s5 - mark.width - when.implicitWidth - 2 * row.spacing)
            elide: Text.ElideRight
            text: line.title || "Event"
            size: Theme.tCallout; weight: Theme.wSemibold
            color: "white"
        }
        Label {
            id: when
            anchors.verticalCenter: parent.verticalCenter
            text: line.at
            size: Theme.tCallout; weight: Theme.wMedium; tabular: true
            color: Qt.rgba(1, 1, 1, 0.72)
        }
    }
    Accessible.role: Accessible.StaticText
    Accessible.name: (line.title || "Event") + " " + line.at
}
