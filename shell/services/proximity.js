.pragma library
// Is the pointer reaching for the hidden or minimal island, or passing by?
// (modules/island/IslandBar; tested in tests/shell/proximity.test.mjs.)
// The same reading as the PiP's (hypr/kuwai/extras.lua): faster than
// 1100 px/s is passing by. Reaching is resting near it, or heading up at it:
// the top edge is where a notch is, so moving up is reaching, while moving
// sideways along the top is on the way to a tab or a menu.
//
// p: { speed, vx, vy } in px/s from services/Pointer (y grows downward).

var FAST = 1100;     // px/s: faster is passing by (PiP's PIP_FAST)
var REST = 350;      // px/s: slower is resting, wherever it's heading
var EDGE_FAST = 800; // px/s: along the top edge itself, faster is passing

function reaching(p) {
    var s = +p.speed || 0, vx = +p.vx || 0, vy = +p.vy || 0;
    if (s < REST) return true;
    return s < FAST && vy < 0 && -vy > Math.abs(vx);
}

// On the edge strip, after its 90 ms rest: still moving along it fast means
// passing by (wait and look again). A sample older than 250 ms says nothing.
function edgeSettled(p, now) {
    var age = now - (+p.t || 0);
    return age > 250 || (+p.speed || 0) < EDGE_FAST;
}

// The reach: `side` px either side of the island and `below` px under it,
// measured from the island as it rests (dx: the pointer's distance from the
// screen's middle; restW: the resting island's width; bottom: its lower edge).
// Never from the width nearing itself has grown it to: that fed the zone its
// own result, so the zone followed the pointer outward and the capsules
// beside the island moved away from a hand going for them.
var SIDE = 56, BELOW = 48;
function inZone(dx, y, restW, bottom, slack) {
    var s = +slack || 0;
    return Math.abs(dx) <= restW / 2 + SIDE + s && y <= bottom + BELOW + s;
}

// Over the island, on the way somewhere else: moving sideways, not resting
// (vx, vy in px/s; 0, 0 once the pointer has stopped). The island does not
// grow under a pointer that is crossing it to the capsule on the other side;
// it grows when the pointer rests or comes down onto it.
function crossing(vx, vy) {
    var ax = Math.abs(+vx || 0), ay = Math.abs(+vy || 0);
    return ax > REST && ax > 1.5 * ay;
}

// Leaving: a fast exit folds it almost at once; a drift away gets the grace.
function foldDelay(p) {
    return (+p.speed || 0) > FAST ? 150 : 450;
}
