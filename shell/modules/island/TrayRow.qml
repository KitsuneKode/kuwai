// The system tray (StatusNotifierItem: Discord, Steam, nm-applet…), as
// Waybar's tray showed it: click to open the app, right click for its own
// menu, middle click for its secondary action, scroll passes through.
// Icons are monochrome-quiet until hovered.
import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import qs.config

Row {
    id: tray
    required property var window          // the island's window, to anchor menus
    property int iconSize: 16
    spacing: 10

    Repeater {
        model: SystemTray.items
        Item {
            id: it
            required property var modelData
            width: tray.iconSize; height: tray.iconSize
            IconImage {
                anchors.fill: parent
                source: it.modelData.icon
                asynchronous: true
                opacity: area.containsMouse ? 1 : 0.8
                Behavior on opacity { NumberAnimation { duration: Theme.colorMs } }
            }
            QsMenuAnchor {
                id: menu
                menu: it.modelData.menu
                anchor.window: tray.window
                anchor.item: it
                anchor.edges: Edges.Bottom
            }
            MouseArea {
                id: area
                anchors.fill: parent
                anchors.margins: -4
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                cursorShape: Qt.PointingHandCursor
                onClicked: mouse => {
                    if (mouse.button === Qt.RightButton || (mouse.button === Qt.LeftButton && it.modelData.onlyMenu)) { if (it.modelData.hasMenu) menu.open(); }
                    else if (mouse.button === Qt.MiddleButton) it.modelData.secondaryActivate();
                    else it.modelData.activate();
                }
                onWheel: wheel => it.modelData.scroll(wheel.angleDelta.y / 120, false)
            }
        }
    }
}
