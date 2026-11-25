// Caffeine: keep the machine awake (no dim, lock, screen-off or suspend) while on.
//
// Hyprland 0.57 only counts a Wayland idle inhibitor after the surface is
// mapped, accepts input, and its alpha is above zero, and it does not look
// again when a layer maps or when that layer's fade (alpha 0 → 1) ends.
// The carrier below is created before it maps, so the cup can read On while
// hypridle still dims, locks and blanks. hypridle does watch logind's idle
// inhibit, so while On we hold one with systemd-inhibit. The process dies
// with the switch or the shell. A leftover user unit used to stay on for
// days, which is why this is not caffeine-mode.service.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Services.UPower
import qs.config

Singleton {
    id: root
    // Survives a shell restart (a file in $XDG_RUNTIME_DIR), not a logout or
    // a reboot: Caffeine left on by mistake ends with the session. (An
    // always-on systemd-inhibit unit did exactly that: no dim, lock or sleep
    // for days.) Toggle: Controls, the System panel, Super+Shift+C.
    property bool on: false
    property bool loaded: false
    function toggle() { on = !on; }

    // Settings → Idle → Keep awake (caffeineMode):
    //   manual   the cup only (default)
    //   login    the cup comes on with each session (still ends with it: the
    //            state is in the runtime dir, so a reboot starts from the setting)
    //   work     while something you started is working — a kittymux agent,
    //            a T3 Code thread, a software update — on AC power, the laptop
    //            doesn't fall asleep from idle. Screens still dim and lock
    //            (you're away; your work isn't), and the lid and the power
    //            menu still sleep: only the idle timer waits.
    // Work running on power, whatever Keep awake says: Idle holds the screens
    // on for it (Settings.idleScreensWhileWork). Turning them off disconnects
    // an external monitor here (it sleeps deeply), and Hyprland moves its
    // workspaces onto the laptop's screen and back: agents' windows jumped.
    readonly property var workNow: {
        if (UPower.onBattery) return [];
        const r = [];
        const k = (Kittymux.working ? Kittymux.working.length : 0) + Agents.desktop.filter(d => d.state === "working").length;
        if (k > 0) r.push(k === 1 ? "an agent is working" : k + " agents are working");
        if (T3Code.running > 0) r.push(T3Code.running === 1 ? "a T3 thread is running" : T3Code.running + " T3 threads are running");
        if (Updates.running) r.push("an update is running");
        return r;
    }
    readonly property var reasons: Settings.caffeineMode === "work" ? workNow : []
    readonly property bool working: reasons.length > 0
    readonly property string why: working ? "Staying up: " + reasons.join(", ") : ""
    property bool fresh: false            // no state file: a new session
    function startOn() { if (fresh && Settings.caffeineMode === "login") on = true; fresh = false; }
    Connections {
        target: Settings
        function onLoadedChanged() { if (Settings.loaded) root.startOn(); }
    }
    onOnChanged: if (loaded) state.setText(on ? "on\n" : "off\n")
    FileView {
        id: state
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/kuwai/caffeine"
        printErrors: false
        onLoaded: { root.on = text().trim() === "on"; root.loaded = true; adopt.running = true; }
        onLoadFailed: { root.loaded = true; adopt.running = true; root.fresh = true; if (Settings.loaded) root.startOn(); }
    }

    // The old Caffeine (idle-inhibitor-toggle.sh → caffeine-mode.service, a
    // systemd-inhibit the island couldn't see). If it's running, this one
    // takes over: on here, the service stopped, so there's one switch and
    // the cup always tells the truth.
    Process {
        id: adopt
        command: ["sh", "-c", "systemctl --user is-active --quiet caffeine-mode.service && systemctl --user stop caffeine-mode.service && echo adopted"]
        stdout: StdioCollector {
            onStreamFinished: if (text.trim() === "adopted") root.on = true
        }
    }

    // What hypridle actually obeys. Released when On goes false or the shell
    // exits, including a kill -9 (kuwai-shell restarts that way): both the
    // inhibitor and the `sleep` holding its lock die with their parent
    // (setpriv --pdeathsig). Without that every restart left one behind,
    // still blocking idle: eight of them had piled up.
    Process {
        id: hold
        running: root.loaded && root.on && root.swept
        command: ["setpriv", "--pdeathsig", "KILL", "--", "systemd-inhibit", "--what=idle", "--who=kuwai", "--why=Caffeine", "--mode=block",
                  "setpriv", "--pdeathsig", "KILL", "--", "sleep", "infinity"]
    }
    // Leftovers from an older shell (before the above), swept once at start.
    property bool swept: false
    Process {
        running: true
        command: ["sh", "-c", "for p in $(pgrep -f '^systemd-inhibit --what=idle --who=kuwai --why=Caffeine'); do pkill -KILL -P \"$p\"; kill -KILL \"$p\"; done 2>/dev/null; true"]
        onExited: root.swept = true
    }

    LazyLoader {
        active: root.on
        PanelWindow {
            id: carrier
            anchors.top: true
            anchors.left: true
            implicitWidth: 1
            implicitHeight: 1
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            mask: Region {}
            WlrLayershell.namespace: "kuwai-caffeine"
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            IdleInhibitor {
                window: carrier
                enabled: true
            }
        }
    }
}
