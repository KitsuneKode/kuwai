// The keyboard's ring: drawn around its parent while it has focus from Tab
// (never for the pointer — a click doesn't light it up). One look for every
// control: 2px soft white, 3px out (just inside, where a clipping parent would cut it), following the parent's corners.
import QtQuick

Rectangle {
    id: ring
    property real gap: 3
    property real cornerRadius: parent && parent.radius !== undefined ? parent.radius : 8
    readonly property bool shown: !!parent && parent.activeFocus && parent.focusReason !== Qt.MouseFocusReason
    readonly property real at: shown && cramped() ? -1 : gap
    function cramped() {
        for (let p = parent.parent; p; p = p.parent) {
            if (!p.clip) continue;
            const r = parent.mapToItem(p, 0, 0);
            return r.x < gap || r.y < gap || r.x + parent.width > p.width - gap || r.y + parent.height > p.height - gap;
        }
        return false;
    }
    anchors.fill: parent
    anchors.margins: -at
    radius: Math.max(0, cornerRadius + at)
    color: "transparent"
    border.width: 2
    border.color: Qt.rgba(1, 1, 1, 0.6)
    visible: shown
    z: 100
}
