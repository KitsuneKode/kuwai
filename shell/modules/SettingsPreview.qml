// The Settings panel in a window that never takes the keyboard, on a given
// page: for screenshots (`qs ipc … call test settings N`, -1 to close).
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.config
import qs.modules.island

PanelWindow {
    id: w
    property int page: 0
    property string query: ""
    // The laptop's screen when there is one: a test picture, not over your work.
    screen: Quickshell.screens.find(s => s.name === "eDP-1") || null
    anchors { top: true; left: true }
    margins { top: 80; left: 80 }
    implicitWidth: 780
    implicitHeight: 620
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "rice-gallery"
    mask: Region {}                      // click-through: it is only a picture
    Rectangle { anchors.fill: parent; radius: Theme.r4; color: "#1c1c1f" }
    SettingsPanel { id: sp; anchors.fill: parent; current: w.page; searchText: w.query }
}
