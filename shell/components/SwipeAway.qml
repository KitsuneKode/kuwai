// Swipe a row away sideways (the notch's list, the center's rows): the
// gestures rule in one place. While the pointer is down the row is the
// pointer, 1:1. Let go and a spring finishes it at the pointer's speed (Fling):
// out past 40 % of its width or on a flick outward, home otherwise; a flick
// back home keeps it. Grab it mid-flight and it stays under the pointer. The
// fade is the distance travelled, so a caught row is never left half-faded.
//
//   SwipeAway { id: swipe; span: row.width; onLeaving: …remove it… }
//   transform: Translate { x: swipe.offset }
//   opacity: swipe.fade
//
// `leaving` fires the moment it's going (release past the line, the × or
// Delete): remove the row then, so the rows below close the gap while it
// slides, not after. `away(dir)` sends it out without a drag (no throw: no
// force was applied, so no bounce). Reduced motion: the springs land at once.
import QtQuick
import qs.config

DragHandler {
    id: h
    property real span: 300                  // the row's width: how far "out" is
    readonly property real offset: sx.value
    readonly property real fade: Math.max(0, 1 - Math.abs(sx.value) / Math.max(1, span))
    property bool gone: false
    signal leaving()

    target: null
    yAxis.enabled: false                     // the list scrolls; only sideways is ours

    readonly property Spring sx: Spring { tier: Theme.springModerate; epsilon: 0.5 }
    readonly property Fling fling: Fling {}
    property real grab: 0

    function away(dir) {
        if (gone) return;
        gone = true;
        sx.velocity = 0;
        sx.target = (dir < 0 ? -1 : 1) * span;
        leaving();
    }

    // Back in place, as new (a row reused for another notification).
    function reset() { gone = false; sx.snap(0); }

    onActiveChanged: {
        if (active) {
            if (gone) return;
            grab = sx.value;                     // caught on its way home: from here
            sx.snap(grab);
            fling.reset();
            return;
        }
        if (gone) return;
        const x = sx.value, dir = x < 0 ? -1 : 1;
        const flick = fling.vx() * dir;          // px/ms, + is outward
        if (Math.abs(x) > 2 && flick > -Theme.swipeFlick
                && (Math.abs(x) >= span * 0.4 || flick > Theme.swipeFlick)) {
            gone = true;
            sx.velocity = Math.max(0, flick) * dir * 1000;
            sx.target = dir * span;
            leaving();
        } else {
            sx.velocity = fling.vx() * 1000;
            sx.target = 0;
        }
    }
    onTranslationChanged: {
        if (gone) return;
        fling.add(translation.x, 0);
        sx.snap(grab + translation.x);
    }
}
