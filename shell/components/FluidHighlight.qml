// Fluid Functionalism's fluid hover: ONE highlight per list that glides from
// item to item on the fast spring instead of every row blinking its own.
// Leaving into empty space puts it out; the next item lit fades it in fresh
// where it lands (it doesn't slide over from wherever it last was). With
// `ring`, it doubles as the keyboard focus ring (FocusRing's one look: 2px
// soft white; +10% fill).
// Keys don't glide: a ring driven by arrow keys jumps to the next row (a key
// repeats too often to animate, and the eye is already there); only the
// pointer gets the spring. It also takes the lit item's opacity, so a row
// swiped away fades with its light instead of leaving it behind.
//
// Put it inside the coordinate space the items live in (a list's
// contentItem) and point `target` at the item to light.
import QtQuick
import qs.config

Item {
    id: h

    property Item target: null
    property bool ring: false
    property bool glideKeys: false      // true only for a list that wants the ring to travel
    property bool instant: false
    property real radius: Theme.r2
    property real inset: 0
    property color fill: h.ring ? Theme.wash(2) : Theme.rowHover
    property color edge: "transparent"
    property bool lit: false
    property real keptOp: 1
    readonly property real targetOp: target ? target.opacity : keptOp
    onTargetOpChanged: if (target) keptOp = targetOp

    z: 50
    visible: opacity > 0.001
    opacity: lit ? 1 : 0
    Behavior on opacity {
        NumberAnimation { duration: h.lit ? Theme.hoverMs : Theme.springFast.exitMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
    }

    x: sx.value; y: sy.value; width: sw.value; height: sh.value

    Spring { id: sx; tier: Theme.springFast; epsilon: 0.25 }
    Spring { id: sy; tier: Theme.springFast; epsilon: 0.25 }
    Spring { id: sw; tier: Theme.springFast; epsilon: 0.25 }
    Spring { id: sh; tier: Theme.springFast; epsilon: 0.25 }

    property bool fresh: true
    property bool pendingFollow: false
    property bool gone: false
    property var _unsubs: []
    function scheduleFollow() {
        if (pendingFollow) return;
        pendingFollow = true;
        Qt.callLater(() => {
            if (gone) return;
            pendingFollow = false;
            follow();
        });
    }
    function clearWatches() {
        for (let i = 0; i < _unsubs.length; i++) {
            try { _unsubs[i](); } catch (e) {}
        }
        _unsubs = [];
    }
    function bindWatch(sig, fn) {
        if (!sig || typeof sig.connect !== "function") return;
        sig.connect(fn);
        _unsubs.push(() => { try { sig.disconnect(fn); } catch (e) {} });
    }
    function watchChain() {
        clearWatches();
        if (!target || !parent) return;
        const onMove = () => h.scheduleFollow();
        const onReparent = () => { h.watchChain(); h.scheduleFollow(); };
        bindWatch(parent.xChanged, onMove);
        bindWatch(parent.yChanged, onMove);
        let p = target;
        let depth = 0;
        while (p && depth < 32) {
            bindWatch(p.xChanged, onMove);
            bindWatch(p.yChanged, onMove);
            bindWatch(p.widthChanged, onMove);
            bindWatch(p.heightChanged, onMove);
            if ("contentY" in p && p.contentYChanged) bindWatch(p.contentYChanged, onMove);
            if ("contentX" in p && p.contentXChanged) bindWatch(p.contentXChanged, onMove);
            if (p.transform && p.transform.length) {
                for (let i = 0; i < p.transform.length; i++) {
                    const tr = p.transform[i];
                    if (tr && tr.xChanged) bindWatch(tr.xChanged, onMove);
                    if (tr && tr.yChanged) bindWatch(tr.yChanged, onMove);
                }
            }
            if (p === h.parent) break;
            bindWatch(p.parentChanged, onReparent);
            p = p.parent;
            depth++;
        }
    }

    onTargetChanged: {
        watchChain();
        if (!target) outTimer.restart();
        else { outTimer.stop(); freshTimer.stop(); follow(); lit = true; }
    }
    onParentChanged: watchChain()
    Component.onCompleted: if (target) { watchChain(); follow(); lit = true; }
    Component.onDestruction: { gone = true; clearWatches(); }
    // Once it has faded out, the next entry starts fresh.
    Timer { id: freshTimer; interval: Theme.springFast.exitMs; onTriggered: h.fresh = true }
    Timer { id: outTimer; interval: Theme.handoffMs; onTriggered: if (!h.target) { h.lit = false; freshTimer.restart(); } }

    function follow() {
        if (!target || !parent) return;
        const p = target.mapToItem(parent, 0, 0);
        // Reduced motion: no glide, just the fade at the new item. Keys: no glide.
        const x = p.x + inset, w = Math.max(0, target.width - inset * 2);
        if (fresh || instant || Theme.reduceMotion || (ring && !glideKeys)) {
            sx.snap(x); sy.snap(p.y); sw.snap(w); sh.snap(target.height);
            fresh = false;
        } else {
            sx.target = x; sy.target = p.y; sw.target = w; sh.target = target.height;
        }
    }

    Rectangle {
        anchors.fill: parent
        opacity: h.targetOp
        radius: h.radius
        // Surface-relative overlays: hover +6% white, selected +10%.
        color: h.fill
        border.width: h.ring ? 2 : h.edge.a > 0 ? 1 : 0
        border.color: h.ring ? Qt.rgba(1, 1, 1, 0.6) : h.edge          // = components/FocusRing
        Behavior on color { ColorAnimation { duration: Theme.hoverMs } }
    }
}
