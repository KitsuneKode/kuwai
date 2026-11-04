// Caffeine: keep the machine awake (no dim, lock or suspend) while on.
// Wayland's idle-inhibit protocol works through a surface, so while it's on
// a 1×1 transparent, click-through layer exists purely to carry the
// inhibitor; off, nothing exists.
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
