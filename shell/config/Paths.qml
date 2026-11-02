// Where kuwai lives, so nothing hardcodes ~/Projects/rice: $KUWAI_ROOT when
// set (the session exports it), else the folder above this shell.
pragma Singleton

import QtQuick
import Quickshell

Singleton {
    readonly property string root: (Quickshell.env("KUWAI_ROOT") || (Quickshell.shellDir + "/..")).replace(/\/+$/, "")
    readonly property string bin: root + "/bin"
}
