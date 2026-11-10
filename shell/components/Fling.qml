// The pointer's speed when a drag ends, for deciding a swipe and seeding its
// release (the gestures rule: dismiss on distance OR the flick, and the
// element leaves at the speed it was moving). Measured over the last ~100 ms
// of movement, not averaged over the whole drag: a slow drag that ends in a
// flick counts, a fast start that then stopped doesn't.
//
//   Fling { id: fling }
//   onActiveChanged:      active ? fling.reset() : fling.vx()   // px/ms
//   onTranslationChanged: fling.add(translation.x, translation.y)
import QtQuick

QtObject {
    property var samples: []
    readonly property int windowMs: 100

    function reset() { samples = []; }
    function add(x, y) {
        const t = Date.now();
        samples.push({ t: t, x: x, y: y });
        while (samples.length > 2 && t - samples[0].t > windowMs) samples.shift();
    }
    // px/ms on each axis; 0 when the pointer had stopped before letting go.
    function v(axis) {
        if (samples.length < 2) return 0;
        const a = samples[0], b = samples[samples.length - 1];
        if (Date.now() - b.t > windowMs) return 0;
        return (b[axis] - a[axis]) / Math.max(1, b.t - a.t);
    }
    function vx() { return v("x"); }
    function vy() { return v("y"); }
}
