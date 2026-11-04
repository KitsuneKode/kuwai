pragma Singleton

// The goodbye before sleep, restart, shut down or log out (modules/lock/
// GoodbyeOverlay draws it on every screen, the login screen has its own):
// `run(kind, cmd)` shows it, and the command runs once it has gone to
// black. Sleep comes back: the overlay clears just after the wake.
// RICE_DRYRUN=1 shows it and logs the command instead.
// (No braces before the pragma: Quickshell's scanner stops at the first.)

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property string kind: ""          // suspend | reboot | poweroff | logout
    property var cmd: []
    function run(k, c) {
        if (kind) return;
        cmd = c;
        kind = k;
    }
    // Every screen's overlay calls this when it's black; the first one counts.
    function black() {
        if (!kind || after.running) return;
        if (Quickshell.env("RICE_DRYRUN") === "1") console.warn("goodbye (dry run): " + cmd.join(" "));
        else { launch.command = cmd; launch.running = true; }
        after.restart();
    }
    Process { id: launch }
    // Timers stand still while suspended, so after sleep this fires just
    // after the wake; if a restart or shut down was refused, the screen
    // comes back after a while instead of staying black.
    Timer { id: after; interval: root.kind === "suspend" || Quickshell.env("RICE_DRYRUN") === "1" ? 1500 : 20000; onTriggered: root.kind = "" }
}
