import QtQuick
import Quickshell
import qs.config

Item {
    id: root
    visible: false
    property var targetWindow: null
    property Item targetItem: null
    property real radius: Theme.r4
    property real inset: 1
    property bool active: true

    readonly property bool _enabled: active && !!targetWindow && !!targetItem && targetItem.visible && targetItem.width > inset * 2 && targetItem.height > inset * 2
    readonly property point _mapped: (_enabled && targetWindow.contentItem) ? targetItem.mapToItem(targetWindow.contentItem, 0, 0) : Qt.point(0, 0)
    readonly property real _bx: _mapped.x + inset
    readonly property real _by: _mapped.y + inset
    readonly property real _bw: Math.max(0, (targetItem ? targetItem.width : 0) - inset * 2)
    readonly property real _bh: Math.max(0, (targetItem ? targetItem.height : 0) - inset * 2)

    Region {
        id: blurRegion
        x: root._bx
        y: root._by
        width: root._bw
        height: root._bh
        radius: Math.max(0, root.radius - root.inset)

        Region {
            intersection: Intersection.Intersect
            width: root.targetWindow ? root.targetWindow.width : 0
            height: root.targetWindow ? root.targetWindow.height : 0
        }
    }

    function apply() {
        if (!targetWindow || !targetWindow.BackgroundEffect) return;
        targetWindow.BackgroundEffect.blurRegion = _enabled ? blurRegion : null;
    }

    function kick() {
        if (!targetWindow || !targetWindow.BackgroundEffect) return;
        targetWindow.BackgroundEffect.blurRegion = null;
        if (_enabled) targetWindow.BackgroundEffect.blurRegion = blurRegion;
    }

    on_EnabledChanged: apply()
    on_BxChanged: apply()
    on_ByChanged: apply()
    on_BwChanged: apply()
    on_BhChanged: apply()
    onRadiusChanged: apply()
    Component.onCompleted: apply()
    Component.onDestruction: {
        if (targetWindow && targetWindow.BackgroundEffect) targetWindow.BackgroundEffect.blurRegion = null;
    }
}
