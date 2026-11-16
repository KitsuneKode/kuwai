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
    property real radius: 18

    z: 50
    visible: opacity > 0.001
    opacity: target ? 1 : 0
    Behavior on opacity {
        NumberAnimation { duration: h.target ? 80 : Theme.springFast.exitMs; easing.type: Easing.OutCubic }
    }

    x: sx.value; y: sy.value; width: sw.value; height: sh.value

    Spring { id: sx; tier: Theme.springFast; epsilon: 0.25 }
    Spring { id: sy; tier: Theme.springFast; epsilon: 0.25 }
    Spring { id: sw; tier: Theme.springFast; epsilon: 0.25 }
    Spring { id: sh; tier: Theme.springFast; epsilon: 0.25 }

    property bool fresh: true
    onTargetChanged: if (!target) freshTimer.restart(); else { freshTimer.stop(); follow(); }
    // Once it has faded out, the next entry starts fresh.
    Timer { id: freshTimer; interval: Theme.springFast.exitMs; onTriggered: h.fresh = true }

    // Items move (rows grow, lists scroll), so track the target every frame.
    FrameAnimation {
        running: h.target !== null
        onTriggered: h.follow()
    }

    function follow() {
        if (!target || !parent) return;
        const p = target.mapToItem(parent, 0, 0);
        // Reduced motion: no glide, just the fade at the new item. Keys: no glide.
        if (fresh || Theme.reduceMotion || (ring && !glideKeys)) {
            sx.snap(p.x); sy.snap(p.y); sw.snap(target.width); sh.snap(target.height);
            fresh = false;
        } else {
            sx.target = p.x; sy.target = p.y; sw.target = target.width; sh.target = target.height;
        }
    }

    Rectangle {
        anchors.fill: parent
        opacity: h.target ? h.target.opacity : 1
        radius: h.radius
        // Surface-relative overlays: hover +6% white, selected +10%.
        color: Qt.rgba(1, 1, 1, h.ring ? 0.10 : 0.06)
        border.width: h.ring ? 2 : 0
        border.color: Qt.rgba(1, 1, 1, 0.6)          // = components/FocusRing
        Behavior on color { ColorAnimation { duration: Theme.hoverMs } }
    }
}
