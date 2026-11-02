// The system tray (StatusNotifierItem: Discord, Steam, nm-applet…), as
// Waybar's tray showed it: click to open the app, right click for its own
// menu, middle click for its secondary action, scroll passes through.
// Icons are monochrome-quiet until hovered.
import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import qs.config
import qs.components

Row {
    id: tray
    required property var window          // the island's window, to anchor menus
    property int iconSize: 16
    spacing: 10

    Repeater {
        // Applets the island already does better (Wi-Fi, Bluetooth, drives)
        // are hidden here; they keep running for what only they provide
        // (nm-applet's password prompts, blueman's pairing agent).
        model: SystemTray.items.values.filter(i => !/nm-applet|network|blueman|bluetooth|udiskie/i.test((i.id || "") + " " + (i.title || "")))
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
            // Our own menu (the theme's glass and accent), not Qt's native one.
            TrayMenu {
                id: menu
                anchorItem: it
                handle: it.modelData.menu
                window: tray.window
                // Keep the island open while this menu is (see IslandBar.menus).
                property bool counted: false
                onOpenChanged: {
                    if (open && !counted) { counted = true; tray.window.menus++; }
                    else if (!open && counted) { counted = false; tray.window.menus = Math.max(0, tray.window.menus - 1); }
                }
                Component.onDestruction: if (counted) tray.window.menus = Math.max(0, tray.window.menus - 1)
            }
            MouseArea {
                id: area
                anchors.fill: parent
                anchors.margins: -4
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                cursorShape: Qt.PointingHandCursor
                onClicked: mouse => {
                    if (mouse.button === Qt.RightButton || (mouse.button === Qt.LeftButton && it.modelData.onlyMenu)) { if (it.modelData.hasMenu) menu.open = !menu.open; }
                    else if (mouse.button === Qt.MiddleButton) it.modelData.secondaryActivate();
                    else it.modelData.activate();
                }
                onWheel: wheel => it.modelData.scroll(wheel.angleDelta.y / 120, false)
            }
        }
    }
}
