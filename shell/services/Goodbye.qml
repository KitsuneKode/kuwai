pragma Singleton

// The goodbye before sleep, restart, shut down or log out (modules/lock/
// GoodbyeOverlay draws it on every screen, the login screen has its own):
// `run(kind, cmd)` shows it, and the command runs once it has gone to
// black. Sleep comes back: the overlay clears just after the wake.
// KUWAI_DRYRUN=1 shows it and logs the command instead.
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
        backstop.restart();
    }
    // The command runs when an overlay has faded to black. A screen that is
    // off (or not drawing) never says so, and Sleep did nothing: after 4 s
    // it runs anyway.
    Timer { id: backstop; interval: 4000; onTriggered: root.black() }
    // Every screen's overlay calls this when it's black; the first one counts.
    function black() {
        if (!kind || after.running) return;
        backstop.stop();
        if (Quickshell.env("KUWAI_DRYRUN") === "1") console.warn("goodbye (dry run): " + cmd.join(" "));
        else { launch.command = cmd; launch.running = true; }
        after.restart();
    }
    // Refused (an inhibitor that blocks, polkit said no): say why, and the
    // screen comes back now instead of staying black for 20 s.
    Process {
        id: launch
        stderr: StdioCollector { id: launchErr }
        onExited: (code) => {
            if (code === 0) return;
            const why = (launchErr.text || "").trim().split("\n").pop() || ("exit " + code);
            Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "kuwai", "Couldn't " + ({ suspend: "sleep", reboot: "restart", poweroff: "shut down", logout: "log out" }[root.kind] || "do that"), why]);
            after.stop();
            root.kind = "";
        }
    }
    // Timers stand still while suspended, so after sleep this fires just
    // after the wake; if a restart or shut down was refused, the screen
    // comes back after a while instead of staying black.
    Timer { id: after; interval: root.kind === "suspend" || Quickshell.env("KUWAI_DRYRUN") === "1" ? 1500 : 20000; onTriggered: root.kind = "" }
}
