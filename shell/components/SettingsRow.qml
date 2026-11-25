// One setting: its name (and a line of detail) on the left, its control on
// the right; a hairline above every row but the first in its group.
//
//   SettingsRow { label: "24-hour time"; Toggle { … } }
import QtQuick
import QtQuick.Layouts
import qs.config

Item {
    id: row
    property string label
    property string detail
    // The setting this row changes (config/Settings): a ↺ beside the control
    // when it isn't the default, to put the default back.
    property string key: ""
    // For a screen reader only: sighted, the ↺ beside the control says it.
    readonly property string provenance: key && !Settings.isDefault(key) ? "Changed from the default" : ""
    Accessible.role: Accessible.Grouping
    Accessible.name: label
    Accessible.description: detail + (provenance ? ". " + provenance : "")
    default property alias control: slot.data
    width: parent ? parent.width : 480
    // Full help wraps. Constrained controls move below it without conflicting anchors.
    readonly property bool stacked: slot.implicitWidth > width * 0.48
    height: Math.max(Theme.sp(detail ? 60 : Theme.rowMin), stacked ? text.implicitHeight + slot.implicitHeight + 32 : Math.max(text.implicitHeight, slot.implicitHeight) + 24)

    // Found by the Settings search (SettingsPanel.markFound): a soft accent
    // wash while the search points here, and one pulse when you go to it
    // (it says "this one" where the page scrolled to). Inset 4 px in the
    // group's 12 px corners, so 8 px: concentric.
    property bool found: false
    property real pulseK: 0
    function pulse() { if (!Theme.reduceMotion) pulseIn.restart(); }
    NumberAnimation { id: pulseIn; target: row; property: "pulseK"; from: 1; to: 0; duration: Theme.breathOutMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
    Rectangle {
        anchors { fill: parent; margins: 4 }
        radius: Theme.r1
        color: Qt.alpha(Theme.accent, 0.14)
        opacity: row.found ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: Theme.colorMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
    }
    Rectangle {
        anchors { fill: parent; margins: 4 }
        radius: Theme.r1
        color: Qt.alpha(Theme.accent, 0.24)
        opacity: row.pulseK
        visible: opacity > 0.01
    }

    Rectangle {
        visible: !row.Positioner.isFirstItem
        x: 14; width: parent.width - 14; height: 1
        color: Theme.wash(1)
    }
    Column {
        id: text
        height: implicitHeight
        x: 14
        width: Math.max(0, row.stacked ? row.width - (resetMark.visible ? 54 : 28) : (resetMark.visible ? resetMark.x : slot.x) - x - 16)
        y: row.stacked ? 12 : (row.height - height) / 2
        spacing: 2
        Label { width: parent.width; elide: Text.ElideRight; text: row.label; size: Theme.tBody }
        Label { visible: row.detail !== ""; width: parent.width; wrapMode: Text.Wrap; text: row.detail; size: Theme.tFootnote; color: Theme.textTertiary }
    }
    Text {
        textFormat: Text.PlainText
        id: resetMark
        readonly property bool changed: row.key !== "" && !Settings.isDefault(row.key)
        visible: changed
        x: row.stacked ? row.width - width - 14 : slot.x - width - 10
        y: row.stacked ? text.y : (row.height - height) / 2
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
        activeFocusOnTab: changed
        Accessible.onPressAction: Settings.reset(row.key)
        Keys.onReturnPressed: Settings.reset(row.key)
        Keys.onSpacePressed: Settings.reset(row.key)
        FocusRing { cornerRadius: Theme.r1 }
    }
    RowLayout {
        id: slot
        x: row.width - width - 14
        y: row.stacked ? text.y + text.height + 8 : (row.height - height) / 2
        width: Math.min(implicitWidth, Math.max(0, row.width - 28))
        height: implicitHeight
    }
}
