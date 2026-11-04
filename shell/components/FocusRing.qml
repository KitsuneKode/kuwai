// The keyboard's ring: drawn around its parent while it has focus from Tab
// (never for the pointer — a click doesn't light it up). One look for every
// control: 2px soft white, 3px out, following the parent's corners.
import QtQuick

Rectangle {
    property real gap: 3
    property real cornerRadius: parent && parent.radius !== undefined ? parent.radius : 8
    anchors.fill: parent
    anchors.margins: -gap
    radius: cornerRadius + gap
    color: "transparent"
    border.width: 2
    border.color: Qt.rgba(1, 1, 1, 0.6)
    visible: !!parent && parent.activeFocus && parent.focusReason !== Qt.MouseFocusReason
    z: 100
}
