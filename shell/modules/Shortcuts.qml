// Global shortcuts, registered with Hyprland by the shell itself
// (hyprland-global-shortcuts). A bind like
//   bind = SUPER, N, global, rice:center
// calls straight into this process: nothing is spawned per keypress, so the
// center answers on the same frame instead of after a shell + IPC round trip.
// The binds live in hypr/kuwai/binds.lua; `hyprctl globalshortcuts` lists these.
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
        name: "settings"
        description: "Settings"
        onPressed: Island.toggle("settings", "", "key")
    }
    GlobalShortcut {
        appid: "rice"
        name: "themes"
        description: "Themes"
        onPressed: Island.themes("themes")
    }
    GlobalShortcut {
        appid: "rice"
        name: "wallpapers"
        description: "Wallpapers"
        onPressed: Island.themes("wallpapers")
    }
    GlobalShortcut {
        appid: "rice"
        name: "system"
        description: "System: CPU, memory, GPU, updates"
        onPressed: Island.toggle("system", "", "key")
    }
    GlobalShortcut {
        appid: "rice"
        name: "updates"
        description: "Software Update: review and install"
        onPressed: Island.toggle("updates", "", "key")
    }
    GlobalShortcut {
        appid: "rice"
        name: "keys"
        description: "Keyboard shortcuts"
        onPressed: Island.toggle("keys", "", "key")
    }
    // Hold Super (kuwai.automation): open — never toggle — and close only if
    // it was this hold that opened it and a real shortcut followed.
    // The switcher (services/Switcher): kuwai sends these from Alt+Tab,
    // Alt+Shift+Tab, Alt+` and the moment Alt comes back up.
    GlobalShortcut { appid: "rice"; name: "emoji"; description: "Emoji (the launcher's : mode)"; onPressed: Island.openWith(":") }
    GlobalShortcut { appid: "rice"; name: "glyphs"; description: "Nerd Font glyphs (the launcher's ; mode)"; onPressed: Island.openWith(";") }
    GlobalShortcut { appid: "rice"; name: "switch-next"; description: "Windows: next (hold Alt)"; onPressed: Switcher.begin(1, false) }
    GlobalShortcut { appid: "rice"; name: "switch-prev"; description: "Windows: previous"; onPressed: Switcher.begin(-1, false) }
    GlobalShortcut { appid: "rice"; name: "switch-app"; description: "Windows of this app"; onPressed: Switcher.begin(1, true) }
    GlobalShortcut { appid: "rice"; name: "switch-ws"; description: "Windows on this workspace"; onPressed: Switcher.begin(1, false, true) }
    GlobalShortcut { appid: "rice"; name: "switch-commit"; description: "Windows: switch (Alt released)"; onPressed: Switcher.commit() }
    GlobalShortcut { appid: "rice"; name: "switch-cancel"; description: "Windows: cancel"; onPressed: Switcher.cancel() }
    GlobalShortcut {
        appid: "rice"
        name: "keys-open"
        description: "Shortcuts palette: open (hold Super)"
        onPressed: Island.open("keys", "", "key")
    }
    GlobalShortcut {
        appid: "rice"
        name: "keys-close"
        description: "Shortcuts palette: close"
        onPressed: if (Island.panel === "keys") Island.close()
    }
    GlobalShortcut {
        appid: "rice"
        name: "calendar"
        description: "Calendar"
        onPressed: Island.toggle("calendar", "", "key")
    }
}
