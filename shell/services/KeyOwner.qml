pragma Singleton

import QtQuick
import Quickshell
import qs.config
import Quickshell.Io

Singleton {
    id: root
    readonly property bool panel: (Island.panel !== "" && !Island.keyless) || Notifs.centerOpen || Assistant.open || Clipboard.open
    function publish() { file.setText(panel ? "panel\n" : "\n"); }
    onPanelChanged: publish()
    Component.onCompleted: publish()
    FileView {
        id: file
        path: Paths.runtime + "/kuwai/keys"
        printErrors: false
    }
}
