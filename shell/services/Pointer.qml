pragma Singleton

// Where the pointer is, without owning any screen area: the island's
// "nearing" needs to know the pointer is 30–60 px away, and a surface that
// big would swallow the clicks meant for the windows under it (a browser's
// tabs). So we ask Hyprland over its request socket (j/cursorpos): no
// process, a few hundred bytes, ~0.1 ms.
//
// Only while someone wants it (`want()` / `unwant()`), and adaptively:
// ~12 Hz while the pointer is in the top band of a screen, 1 Hz elsewhere.
// (No braces before the pragma: Quickshell's scanner stops at the first.)

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Singleton {
    id: root

    property real x: -1e6              // global, logical px
    property real y: -1e6
    property real t: 0                 // when sampled (ms)
    property real speed: 0             // px/s between the last two samples
    property real vx: 0                // its direction, px/s (y grows downward)
    property real vy: 0
    property int wanted: 0
    function want() { wanted++; }
    function unwant() { wanted = Math.max(0, wanted - 1); }
    // Near the top edge of any screen (where the island is): look more often.
    property real hotBand: 140
    // Set where the position is read, not bound: a binding over Hyprland's
    // monitor list was re-evaluated while a reload tore the old shell down,
    // got undefined (the function never ran, so its try/catch couldn't help)
    // and Qt warned "Unable to assign [undefined] to bool" at every reload.
    property bool hot: false
    function inHotBand(px, py) {
        const ms = Hyprland.monitors.values;
        for (let i = 0; i < ms.length; i++) {
            const o = ms[i].lastIpcObject || {};
            const rotated = [1, 3, 5, 7].indexOf(Number(o.transform) || 0) >= 0;
            const w = ((rotated ? o.height : o.width) || 0) / (o.scale || 1);
            if (px >= (o.x || 0) && px < (o.x || 0) + w && py >= (o.y || 0) && py < (o.y || 0) + hotBand) return true;
        }
        return false;
    }

    readonly property string sockPath: (Quickshell.env("XDG_RUNTIME_DIR") || "") + "/hypr/" + (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || "") + "/.socket.sock"

    Socket {
        id: sock
        path: root.sockPath
        onConnectedChanged: if (connected) { write("j/cursorpos"); flush(); }
        parser: SplitParser {
            splitMarker: "}"
            onRead: data => {
                try {
                    const p = JSON.parse(data.trim() + "}");
                    if (typeof p.x !== "number" || typeof p.y !== "number" || !Number.isFinite(p.x) || !Number.isFinite(p.y)) throw new Error("Invalid cursor position");
                    const now = Date.now();
                    const dt = now - root.t;
                    // After a pause (nobody wanted it) the last sample is old:
                    // that's not movement, so it reads as still.
                    const fresh = dt > 0 && dt < 600;
                    root.vx = fresh ? (p.x - root.x) / dt * 1000 : 0;
                    root.vy = fresh ? (p.y - root.y) / dt * 1000 : 0;
                    root.speed = Math.hypot(root.vx, root.vy);
                    root.x = p.x; root.y = p.y;
                    root.hot = root.inHotBand(p.x, p.y);
                    // t notifies consumers: publish only after the complete sample.
                    root.t = now;
                } catch (e) {}
                sock.connected = false;
            }
        }
    }
    Timer {
        interval: root.hot ? 80 : 1000
        repeat: true
        running: root.wanted > 0
        onTriggered: { if (sock.connected) sock.connected = false; sock.connected = true; }
    }
}
