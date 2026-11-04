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

Singleton {
    id: root
    // Survives a shell restart (a file in $XDG_RUNTIME_DIR), not a logout or
    // a reboot: Caffeine left on by mistake ends with the session. (An
    // always-on systemd-inhibit unit did exactly that: no dim, lock or sleep
    // for days.) Toggle: Controls, the System panel, Super+Shift+C.
    property bool on: false
    property bool loaded: false
    function toggle() { on = !on; }
    onOnChanged: if (loaded) state.setText(on ? "on\n" : "off\n")
    FileView {
        id: state
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/rice/caffeine"
        printErrors: false
        onLoaded: { root.on = text().trim() === "on"; root.loaded = true; adopt.running = true; }
        onLoadFailed: { root.loaded = true; adopt.running = true; }
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
    // exits, including a kill -9 (rice-shell restarts that way): both the
    // inhibitor and the `sleep` holding its lock die with their parent
    // (setpriv --pdeathsig). Without that every restart left one behind,
    // still blocking idle: eight of them had piled up.
    Process {
        id: hold
        running: root.loaded && root.on && root.swept
        command: ["setpriv", "--pdeathsig", "KILL", "--", "systemd-inhibit", "--what=idle", "--who=rice", "--why=Caffeine", "--mode=block",
                  "setpriv", "--pdeathsig", "KILL", "--", "sleep", "infinity"]
    }
    // Leftovers from an older shell (before the above), swept once at start.
    property bool swept: false
    Process {
        running: true
        command: ["sh", "-c", "for p in $(pgrep -f '^systemd-inhibit --what=idle --who=rice --why=Caffeine'); do pkill -KILL -P \"$p\"; kill -KILL \"$p\"; done 2>/dev/null; true"]
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
            WlrLayershell.namespace: "rice-caffeine"
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            IdleInhibitor {
                window: carrier
                enabled: true
            }
        }
    }
}
