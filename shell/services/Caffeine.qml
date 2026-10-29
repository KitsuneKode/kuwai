// Caffeine: keep the machine awake (no dim, lock or suspend) while on.
// Wayland's idle-inhibit protocol works through a surface, so while it's on
// a 1×1 transparent, click-through layer exists purely to carry the
// inhibitor; off, nothing exists.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Wayland

Singleton {
    id: root
    property bool on: false

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
