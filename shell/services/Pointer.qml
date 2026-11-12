pragma Singleton

// Where the pointer is, without owning any screen area: the island's
// "nearing" needs to know the pointer is 30–60 px away, and a surface that
// big would swallow the clicks meant for the windows under it (a browser's
// tabs). So we ask Hyprland over its request socket (j/cursorpos): no
// process, a few hundred bytes, ~0.1 ms.
//
// Only while someone wants it (`want()` / `unwant()`), and adaptively:
// ~12 Hz while the pointer is in the top band of a screen, 4 Hz elsewhere.
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
    readonly property bool hot: !!(Hyprland.monitors && Hyprland.monitors.values || []).some(m => {
        const o = m.lastIpcObject || {};
        const w = (o.width || 0) / (o.scale || 1);
        return x >= (o.x || 0) && x < (o.x || 0) + w && y >= (o.y || 0) && y < (o.y || 0) + hotBand;
    })

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
                    const now = Date.now();
                    const dt = Math.max(1, now - root.t);
                    // After a pause (nobody wanted it) the last sample is old:
                    // that's not movement, so it reads as still.
                    const fresh = dt < 600;
                    root.vx = fresh ? (p.x - root.x) / dt * 1000 : 0;
                    root.vy = fresh ? (p.y - root.y) / dt * 1000 : 0;
                    root.speed = Math.hypot(root.vx, root.vy);
                    root.x = p.x; root.y = p.y; root.t = now;
                } catch (e) {}
                sock.connected = false;
            }
        }
    }
    Timer {
        interval: root.hot ? 80 : 250
        repeat: true
        running: root.wanted > 0
        onTriggered: { if (sock.connected) sock.connected = false; sock.connected = true; }
    }
}
