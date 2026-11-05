// The lock and login screens' status, loose in the top-right corner as on a
// Mac's lock screen: Bluetooth when it's on, Wi-Fi or a cable, the charge
// and the battery (IslandStatus, the island's own). It arrives from the
// right a beat after the screen does; `shown` (0–1) drives it.
//
// Plugging in is a moment, as on an iPhone: the battery fills from empty to
// its charge in green, the number counting with it, and a ring pings out of
// it twice.
import QtQuick
import QtQuick.Effects
import qs.config
import qs.modules.island

Item {
    id: corner
    property real shown: 1
    anchors { top: parent.top; right: parent.right; topMargin: 18; rightMargin: 26 }
    width: status.implicitWidth; height: status.implicitHeight
    opacity: shown
    transform: Translate { x: (1 - corner.shown) * 16 * (Theme.reduceMotion ? 0 : 1) }

    IslandStatus {
        id: status
        tint: Qt.rgba(1, 1, 1, 0.92)
        bluetoothWhenOn: true
        // The picture behind is anything; a soft shadow keeps white legible.
        layer.enabled: true
        layer.effect: MultiEffect { shadowEnabled: true; shadowBlur: 0.5; shadowOpacity: 0.45; shadowVerticalOffset: 1; shadowHorizontalOffset: 0 }
        onOnACChanged: if (onAC) corner.plugged()
    }

    function plugged() {
        if (!status.hasBattery || Theme.reduceMotion) return;
        sweep.restart();
    }
    SequentialAnimation {
        id: sweep
        NumberAnimation { target: status; property: "shownPct"; from: 0; to: status.pct; duration: 900; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
        PauseAnimation { duration: 500 }
        PropertyAction { target: status; property: "shownPct"; value: -1 }
    }
    Repeater {
        model: 2
        Rectangle {
            id: ping
            required property int index
            readonly property Item bat: status.batteryItem
            x: bat.x - 3; y: bat.y - 3
            width: bat.width + 6; height: bat.height + 6
            radius: 7
            color: "transparent"
            border.width: 1.5
            border.color: Theme.positive
            opacity: 0
            SequentialAnimation {
                running: sweep.running
                PauseAnimation { duration: 120 + ping.index * 220 }
                ParallelAnimation {
                    NumberAnimation { target: ping; property: "scale"; from: 1; to: 1.9; duration: 700; easing.type: Easing.OutCubic }
                    NumberAnimation { target: ping; property: "opacity"; from: 0.9; to: 0; duration: 700; easing.type: Easing.OutCubic }
                }
            }
        }
    }
}
