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

// Leaving: a fast exit folds it almost at once; a drift away gets the grace.
function foldDelay(p) {
    return (+p.speed || 0) > FAST ? 150 : 450;
}
