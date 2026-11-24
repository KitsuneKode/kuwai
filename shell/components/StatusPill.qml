import QtQuick
import qs.config

Rectangle {
    id: pill
    property string text
    property color dot: Theme.textTertiary
    implicitWidth: row.implicitWidth + Theme.s3 * 2
    implicitHeight: Math.max(Theme.sp(24), label.implicitHeight + 6)
    radius: height / 2
    color: Theme.wash(1)
    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6
        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 6; height: 6; radius: 3; color: pill.dot }
        Label {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            text: pill.text
            size: Theme.tFootnote; weight: Theme.wMedium
            color: Theme.textSecondary
            font.features: ({ "tnum": 1 })
        }
    }
    Accessible.role: Accessible.StaticText
    Accessible.name: pill.text
}
