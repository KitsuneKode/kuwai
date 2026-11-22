pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    readonly property bool panel: (Island.panel !== "" && !Island.previewing) || Notifs.centerOpen || Assistant.open || Clipboard.open
    function publish() { file.setText(panel ? "panel\n" : "\n"); }
    onPanelChanged: publish()
    Component.onCompleted: publish()
    FileView {
        id: file
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/kuwai/keys"
        printErrors: false
    }
}
