// A scrollbar that stays out of the way until you reach for it (Fluid
// Functionalism): a 4px, 8%-white thumb that widens to 6px and darkens on
// hover; it shows while scrolling (160ms in, 120ms out) and only when there
// is something to scroll. Drag it to scroll.
//
//   ScrollHint { flickable: list }   (anchor it to the flickable's right edge)
//   ScrollHint { flickable: list; inside: true }
//                                    it seats itself in the list's own right edge,
//                                    over the rows; for a list in a Column, where
//                                    a written-in hint would become a row
//
// It shows itself only while its list is shown and scrolls: don't bind its
// `visible` (an override kept its drag handle live over a list that didn't
// scroll).
import QtQuick
import qs.config

Item {
    id: bar

    required property Flickable flickable
    property bool inside: false
    Component.onCompleted: if (inside) {
        parent = flickable;                 // the Flickable itself, not its content: it doesn't scroll away
        anchors.top = flickable.top;
        anchors.bottom = flickable.bottom;
        anchors.right = flickable.right;
        z = 2;
    }
    readonly property bool needed: flickable.visible && flickable.contentHeight + flickable.topMargin + flickable.bottomMargin > flickable.height + 1
    property bool recently: false

    width: 10
    visible: needed
    opacity: needed && (recently || hover.hovered || drag.active) ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: bar.opacity > 0.5 ? Theme.quickMs : Theme.microMs } }

    Connections {
        target: bar.flickable
        function onContentYChanged() { bar.recently = true; idle.restart(); }
    }
    Timer { id: idle; interval: 900; onTriggered: bar.recently = false }

    HoverHandler { id: hover }

    Rectangle {
        id: thumb
        readonly property real ratio: Math.min(1, bar.flickable.visibleArea.heightRatio)
        anchors.right: parent.right
        anchors.rightMargin: 2
        width: hover.hovered || drag.active ? 6 : 4
        radius: width / 2
        height: Math.max(24, bar.height * ratio)
        y: (bar.height - height) * Math.max(0, Math.min(1, bar.flickable.visibleArea.yPosition / Math.max(0.0001, 1 - ratio)))
        color: Qt.rgba(1, 1, 1, drag.active ? 0.16 : hover.hovered ? 0.12 : 0.08)
        Behavior on width { NumberAnimation { duration: Theme.quickMs } }
        Behavior on color { ColorAnimation { duration: Theme.colorMs } }

        DragHandler {
            id: drag
            target: null
            xAxis.enabled: false
            property real startY: 0
            onActiveChanged: if (active) startY = bar.flickable.contentY
            onTranslationChanged: {
                const f = bar.flickable;
                const span = bar.height - thumb.height;
                if (span <= 0) return;
                const max = f.contentHeight - f.height;
                f.contentY = Math.max(0, Math.min(max, startY + translation.y / span * max));
            }
        }
    }
}
