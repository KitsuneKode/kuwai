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
    property point _mapped: Qt.point(0, 0)
    property bool _pending: false
    property var _unsubs: []
    readonly property real _bx: _mapped.x + inset
    readonly property real _by: _mapped.y + inset
    readonly property real _bw: Math.max(0, (targetItem ? targetItem.width : 0) - inset * 2)
    readonly property real _bh: Math.max(0, (targetItem ? targetItem.height : 0) - inset * 2)

    function _clearWatches() {
        for (let i = 0; i < _unsubs.length; i++) {
            try { _unsubs[i](); } catch (e) {}
        }
        _unsubs = [];
    }
    function _bindWatch(sig, fn) {
        if (!sig || typeof sig.connect !== "function") return;
        sig.connect(fn);
        _unsubs.push(() => { try { sig.disconnect(fn); } catch (e) {} });
    }
    function _syncMapped() {
        _mapped = (_enabled && targetWindow && targetWindow.contentItem && targetItem)
            ? targetItem.mapToItem(targetWindow.contentItem, 0, 0)
            : Qt.point(0, 0);
        apply();
    }
    function _scheduleSync() {
        if (_pending) return;
        _pending = true;
        Qt.callLater(() => {
            _pending = false;
            _syncMapped();
        });
    }
    function _watchChain() {
        _clearWatches();
        if (!targetItem || !targetWindow || !targetWindow.contentItem) { _syncMapped(); return; }
        const onMove = () => root._scheduleSync();
        const onReparent = () => { root._watchChain(); root._scheduleSync(); };
        let p = targetItem;
        let depth = 0;
        while (p && depth < 32) {
            _bindWatch(p.xChanged, onMove);
            _bindWatch(p.yChanged, onMove);
            _bindWatch(p.widthChanged, onMove);
            _bindWatch(p.heightChanged, onMove);
            if ("contentY" in p && p.contentYChanged) _bindWatch(p.contentYChanged, onMove);
            if ("contentX" in p && p.contentXChanged) _bindWatch(p.contentXChanged, onMove);
            if (p === targetWindow.contentItem) break;
            _bindWatch(p.parentChanged, onReparent);
            p = p.parent;
            depth++;
        }
        _syncMapped();
    }

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

    onTargetItemChanged: _watchChain()
    onTargetWindowChanged: _watchChain()
    on_EnabledChanged: _syncMapped()
    onRadiusChanged: apply()
    Component.onCompleted: _watchChain()
    Component.onDestruction: {
        _clearWatches();
        if (targetWindow && targetWindow.BackgroundEffect) targetWindow.BackgroundEffect.blurRegion = null;
    }
}
