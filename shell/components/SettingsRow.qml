// One setting: its name (and a line of detail) on the left, its control on
// the right; a hairline above every row but the first in its group.
//
//   SettingsRow { label: "24-hour time"; Toggle { … } }
import QtQuick
import qs.config

Item {
    id: row
    property string label
    property string detail
    // The setting this row changes (config/Settings): a ↺ beside the control
    // when it isn't the default, to put the default back.
    property string key: ""
    default property alias control: slot.data
    width: parent ? parent.width : 480
    // The detail wraps (up to three lines) and the row grows with it.
    height: Math.max(detail ? 60 : 46, text.implicitHeight + 24)

    // Found by the Settings search (SettingsPanel.markFound): a soft accent
    // wash while the search points here, and one pulse when you go to it
    // (it says "this one" where the page scrolled to). Inset 4 px in the
    // group's 12 px corners, so 8 px: concentric.
    property bool found: false
    property real pulseK: 0
    function pulse() { if (!Theme.reduceMotion) pulseIn.restart(); }
    NumberAnimation { id: pulseIn; target: row; property: "pulseK"; from: 1; to: 0; duration: Theme.breathOutMs; easing.type: Easing.OutCubic }
    Rectangle {
        anchors { fill: parent; margins: 4 }
        radius: 8
        color: Qt.alpha(Theme.accent, 0.14)
        opacity: row.found ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: Theme.colorMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
    }
    Rectangle {
        anchors { fill: parent; margins: 4 }
        radius: 8
        color: Qt.alpha(Theme.accent, 0.24)
        opacity: row.pulseK
        visible: opacity > 0.01
    }

    Rectangle {
        visible: !row.Positioner.isFirstItem
        x: 14; width: parent.width - 14; height: 1
        color: Qt.rgba(1, 1, 1, 0.07)
    }
    Column {
        id: text
        anchors { left: parent.left; leftMargin: 14; right: resetMark.visible ? resetMark.left : slot.left; rightMargin: 16; verticalCenter: parent.verticalCenter }
        spacing: 2
        Label { width: parent.width; elide: Text.ElideRight; text: row.label; size: 13 }
        Label { visible: row.detail !== ""; width: parent.width; wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight; text: row.detail; size: 11; color: Theme.textTertiary }
    }
    Text {
        id: resetMark
        readonly property bool changed: row.key !== "" && !Settings.isDefault(row.key)
        visible: changed
        anchors { right: slot.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
        text: "\u{f0453}"                                   // restore
        font.family: Theme.fontGlyph; font.pixelSize: 15
        color: resetArea.containsMouse ? Theme.textPrimary : Theme.textTertiary
        Behavior on color { ColorAnimation { duration: Theme.colorMs } }
        MouseArea {
            id: resetArea
            anchors.fill: parent; anchors.margins: -6
            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: Settings.reset(row.key)
        }
        Tip { text: "Back to the default (" + JSON.stringify(Settings.defaultOf(row.key)) + ")"; shown: resetArea.containsMouse; below: true }
        Accessible.role: Accessible.Button
        Accessible.name: "Reset " + row.label + " to the default"
    }
    Item {
        id: slot
        anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
        width: childrenRect.width
        height: childrenRect.height
    }
}
