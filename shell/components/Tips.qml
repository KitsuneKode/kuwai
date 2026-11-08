// Tooltips for a surface: one layer over everything (so a list's clip never
// cuts one off), one bubble that any control can call up.
//
//   Tips { id: tips }                                   // once, on top
//   HoverHandler { onHoveredChanged: hovered ? tips.show(parent, "Pin", ["⌃", "P"]) : tips.hide(parent) }
//
// Timing, Emil Kowalski's rule: the first tip waits 450ms (so passing over a
// toolbar doesn't spray tips), then any tip asked for within 300ms of one
// closing shows at once, with no animation: moving along a row of buttons
// reads instantly. The bubble scales from the edge facing its control
// (0.97 → 1, 125ms ease-out) and sits above it, or below if there's no room.
import QtQuick
import qs.config

Item {
    id: tips
    anchors.fill: parent
    z: 1000

    property Item target: null
    property string text
    property var keys: []
    property bool shown: false
    property bool instant: false
    property real hiddenAt: 0

    property var pending: null
    function show(item, text, keys) {
        pending = { item: item, text: text, keys: keys || [] };
        if (shown || Date.now() - hiddenAt < 300) apply(true);
        else wait.restart();
    }
    function hide(item) {
        if (pending && pending.item === item) { wait.stop(); pending = null; }
        if (target === item && shown) { shown = false; hiddenAt = Date.now(); }
    }
    function apply(now) {
        if (!pending) return;
        target = pending.item;
        text = pending.text;
        keys = pending.keys;
        instant = now;
        shown = true;
    }
    Timer { id: wait; interval: Theme.tipMs; onTriggered: tips.apply(false) }

    readonly property rect at: target && shown ? target.mapToItem(tips, 0, 0, target.width, target.height) : Qt.rect(0, 0, 0, 0)
    readonly property bool flip: at.y - bubble.height - 8 < 0

    Rectangle {
        id: bubble
        x: Math.round(Math.max(6, Math.min(tips.width - width - 6, tips.at.x + tips.at.width / 2 - width / 2)))
        y: Math.round(tips.flip ? tips.at.y + tips.at.height + 8 : tips.at.y - height - 8)
        width: row.implicitWidth + 18
        height: 26
        radius: 8
        color: Qt.rgba(0.20, 0.20, 0.23, 0.98)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.12)
        transformOrigin: tips.flip ? Item.Top : Item.Bottom
        opacity: tips.shown ? 1 : 0
        scale: tips.shown || Theme.reduceMotion ? 1 : 0.97
        visible: opacity > 0.01
        Behavior on opacity { enabled: !tips.instant; NumberAnimation { duration: tips.shown ? 125 : 90; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
        Behavior on scale { enabled: !tips.instant; NumberAnimation { duration: Theme.quickMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }

        Row {
            id: row
            anchors.centerIn: parent
            spacing: 6
            Label { anchors.verticalCenter: parent.verticalCenter; text: tips.text; size: 12; weight: Theme.wMedium }
            Row {
                visible: tips.keys.length > 0
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Repeater { model: tips.keys; KeyCap { required property string modelData; text: modelData } }
            }
        }
    }
}
