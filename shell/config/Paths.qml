// Where kuwai lives, so nothing hardcodes ~/Projects/rice: $KUWAI_ROOT when
// set (the session exports it), else the folder above this shell.
pragma Singleton

import QtQuick
import Quickshell

Singleton {
    readonly property string root: (Quickshell.env("KUWAI_ROOT") || (Quickshell.shellDir + "/..")).replace(/\/+$/, "")
    readonly property string bin: root + "/bin"
    readonly property string stateHome: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")).replace(/\/+$/, "")
    readonly property string kittymuxState: Quickshell.env("KITTYMUX_STATE") || (stateHome + "/kittymux")
    // Present while this session is locked (modules/lock). Per Hyprland
    // instance and in the runtime dir: a lock left at a reboot, or held by
    // another session on another tty, must not lock this one.
    readonly property string runtime: (Quickshell.env("XDG_RUNTIME_DIR") || (Quickshell.env("HOME") + "/.cache/kuwai/runtime")).replace(/\/+$/, "")
    readonly property string lockFlag: runtime + "/kuwai/locked-" + (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || "session")
}
