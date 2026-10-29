// Global shortcuts, registered with Hyprland by the shell itself
// (hyprland-global-shortcuts). A bind like
//   bind = SUPER, N, global, rice:center
// calls straight into this process: nothing is spawned per keypress, so the
// center answers on the same frame instead of after a shell + IPC round trip.
// The binds live in hypr/rice.conf; `hyprctl globalshortcuts` lists these.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.services

Scope {
    GlobalShortcut {
        appid: "rice"
        name: "center"
        description: "Notifications: open or close the center"
        onPressed: Notifs.toggleCenter("notifications", "key")
    }
    GlobalShortcut {
        appid: "rice"
        name: "agents"
        description: "Agents (kittymux): open the center on the Agents tab"
        onPressed: Notifs.toggleCenter("agents", "key")
    }
    GlobalShortcut {
        appid: "rice"
        name: "dnd"
        description: "Do Not Disturb on/off"
        onPressed: Notifs.dnd = !Notifs.dnd
    }
    GlobalShortcut {
        appid: "rice"
        name: "open-latest"
        description: "Open the newest notification on screen"
        onPressed: {
            const top = Notifs.popups.find(i => !i.leaving);
            if (top) Notifs.activate(top);
        }
    }
    GlobalShortcut {
        appid: "rice"
        name: "clipboard"
        description: "Clipboard history"
        onPressed: Clipboard.toggle("all")
    }
    GlobalShortcut {
        appid: "rice"
        name: "clipboard-pins"
        description: "Clipboard: pinned entries"
        onPressed: Clipboard.toggle("pinned")
    }
    GlobalShortcut {
        appid: "rice"
        name: "record"
        description: "Screen recording: set up, or stop"
        onPressed: Clipboard.recordKey()
    }
    GlobalShortcut {
        appid: "rice"
        name: "power"
        description: "Power menu: lock, sleep, log out, restart, shut down"
        onPressed: Island.toggle("power", "", "key")
    }
    GlobalShortcut {
        appid: "rice"
        name: "launcher"
        description: "Launcher: apps, windows, actions, a calculator"
        onPressed: Island.toggle("launcher", "", "key")
    }
    GlobalShortcut {
        appid: "rice"
        name: "calendar"
        description: "Calendar"
        onPressed: Island.toggle("calendar", "", "key")
    }
}
