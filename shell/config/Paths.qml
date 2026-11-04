// Where kuwai lives, so nothing hardcodes ~/Projects/rice: $KUWAI_ROOT when
// set (the session exports it), else the folder above this shell.
pragma Singleton

import QtQuick
import Quickshell

Singleton {
    readonly property string root: (Quickshell.env("KUWAI_ROOT") || (Quickshell.shellDir + "/..")).replace(/\/+$/, "")
    readonly property string bin: root + "/bin"
    // Present while this session is locked (modules/lock). Per Hyprland
    // instance and in the runtime dir: a lock left at a reboot, or held by
    // another session on another tty, must not lock this one.
    readonly property string lockFlag: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/rice/locked-" + (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || "session")
}
