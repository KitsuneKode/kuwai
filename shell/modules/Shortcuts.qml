// Global shortcuts, registered with Hyprland by the shell itself
// (hyprland-global-shortcuts). A bind like
//   bind = SUPER, N, global, kuwai:center
// calls straight into this process: nothing is spawned per keypress, so the
// center answers on the same frame instead of after a shell + IPC round trip.
// The binds live in hypr/kuwai/binds.lua; `hyprctl globalshortcuts` lists these.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.config
import qs.services

Scope {
    readonly property string fKeys: Settings.loaded ? Settings.fKeys : ""
    onFKeysChanged: if (fKeys) Hyprland.dispatch(fKeys === "plain" ? "kuwai.fkeys(true)" : "kuwai.fkeys(false)")
    // The island's card from the keyboard (Island.cardKeys): only while one
    // shows; held (its timer paused) while the keyboard is on it.
    readonly property bool cardUp: Notifs.peek !== null || Moments.card !== null
    onCardUpChanged: if (!cardUp) Island.cardKeys = false
    Connections {
        target: Island
        function onCardKeysChanged() {
            Notifs.peekHeld = Island.cardKeys && Notifs.peek !== null;
            Moments.cardHeld = Island.cardKeys && Moments.card !== null;
        }
    }
    GlobalShortcut {
        appid: "kuwai"
        name: "island-card"
        description: "Island: answer the card it shows (a notification, an alarm) from the keyboard"
        onPressed: Island.cardKeys = !Island.cardKeys && (Notifs.peek !== null || Moments.card !== null)
    }
    GlobalShortcut {
        appid: "kuwai"
        name: "center"
        description: "Notifications: open or close the center"
        onPressed: Notifs.toggleCenter("notifications", "key")
    }
    GlobalShortcut {
        appid: "kuwai"
        name: "agents"
        description: "Agents: every kitty pane and T3 thread, grown out of the island (the one place agents live)"
        onPressed: Island.toggle("agents", "", "key")
    }
    GlobalShortcut {
        appid: "kuwai"
        name: "agents-go"
        description: "Agents: go to the one that needs you (its kitty pane, its T3 thread); none: the list"
        onPressed: Agents.goNeeds()
    }
    GlobalShortcut {
        appid: "kuwai"
        name: "assistant"
        description: "AI Assistant: local LLM chat and multimodal vision"
        onPressed: {
            if (!Settings.assistantOptIn) {
                Island.openSettings("assistant");
                return;
            }
            Assistant.toggle();
        }
    }
    GlobalShortcut {
        appid: "kuwai"
        name: "bluetooth"
        description: "Bluetooth: devices, connect, battery"
        onPressed: Island.open("bluetooth", "", "key")
    }
    GlobalShortcut {
        appid: "kuwai"
        name: "wifi"
        description: "Wi-Fi: the networks, in Controls"
        onPressed: Notifs.openControls("wifi", "key")
    }
    GlobalShortcut {
        appid: "kuwai"
        name: "controls"
        description: "Controls: Wi-Fi, Bluetooth, sound, Do Not Disturb"
        onPressed: Notifs.toggleCenter("controls", "key")
    }
    GlobalShortcut {
        appid: "kuwai"
        name: "dnd"
        description: "Do Not Disturb on/off"
        onPressed: Notifs.toggleUserDnd()
    }
    GlobalShortcut {
        appid: "kuwai"
        name: "open-latest"
        description: "Open the newest notification on screen"
        onPressed: Notifs.activateLatest()
    }
    GlobalShortcut {
        appid: "kuwai"
        name: "clipboard"
        description: "Clipboard history"
        onPressed: Clipboard.toggle("all")
    }
    GlobalShortcut {
        appid: "kuwai"
        name: "clipboard-pins"
        description: "Clipboard: pinned entries"
        onPressed: Clipboard.toggle("pinned")
    }
    GlobalShortcut {
        appid: "kuwai"
        name: "record"
        description: "Screen recording: set up, or stop"
        onPressed: Clipboard.recordKey()
    }
    GlobalShortcut {
        appid: "kuwai"
        name: "power"
        description: "Power menu: lock, sleep, log out, restart, shut down"
        onPressed: Island.toggle("power", "", "key")
    }
    GlobalShortcut {
        appid: "kuwai"
        name: "launcher"
        description: "Launcher: apps, windows, actions, a calculator"
        onPressed: Island.toggle("launcher", "", "key")
    }
    GlobalShortcut {
        appid: "kuwai"
        name: "settings"
        description: "Settings"
        onPressed: Island.toggle("settings", "", "key")
    }
    GlobalShortcut {
        appid: "kuwai"
        name: "themes"
        description: "Themes"
        onPressed: Island.themes("themes")
    }
    GlobalShortcut {
        appid: "kuwai"
        name: "wallpapers"
        description: "Wallpapers"
        onPressed: Island.themes("wallpapers")
    }
    GlobalShortcut {
        appid: "kuwai"
        name: "system"
        description: "System: CPU, memory, GPU, updates"
        onPressed: Island.toggle("system", "", "key")
    }
    GlobalShortcut { appid: "kuwai"; name: "island-peek"; description: "Show the island's details (minimal island)"; onPressed: Island.peekFor(2500) }
    // Ctrl+Alt+Shift+W: the mini notch ⇄ everything (workspaces, time, status).
    GlobalShortcut { appid: "kuwai"; name: "island-style"; description: "Island: minimal ⇄ everything"; onPressed: { Settings.set("islandTucked", false); Settings.set("islandRest", Settings.islandRest === "full" ? "minimal" : "full"); } }
    GlobalShortcut { appid: "kuwai"; name: "island-tuck"; description: "Tuck the island away / bring it back"
        onPressed: {
            if (Settings.bar === "island") Settings.set("islandTucked", !Settings.islandTucked);
            else Quickshell.execDetached(["sh", "-c", "pkill -x waybar || exec " + (Hyde.hasShell ? "hyde-shell waybar" : "waybar")]);   // Waybar users: on/off (HyDE's, else plain)
        }
    }
    GlobalShortcut { appid: "kuwai"; name: "caffeine"; description: "Caffeine: keep awake (no dim, lock or sleep)"; onPressed: Caffeine.toggle() }
    GlobalShortcut {
        appid: "kuwai"
        name: "updates"
        description: "Software Update: review and install"
        onPressed: Island.toggle("updates", "", "key")
    }
    GlobalShortcut {
        appid: "kuwai"
        name: "keys"
        description: "Keyboard shortcuts"
        onPressed: Island.toggle("keys", "", "key")
    }
    GlobalShortcut {
        appid: "kuwai"
        name: "modes"
        description: "Desktop modes, in the launcher"
        onPressed: Island.openWith("mode ")
    }
    // Hold Super (kuwai.automation): open — never toggle — and close only if
    // it was this hold that opened it and a real shortcut followed.
    // The switcher (services/Switcher): kuwai sends these from Alt+Tab,
    // Alt+Shift+Tab, Alt+` and the moment Alt comes back up.
    GlobalShortcut { appid: "kuwai"; name: "emoji"; description: "Emoji (the launcher's : mode)"; onPressed: Island.openWith(":") }
    GlobalShortcut { appid: "kuwai"; name: "glyphs"; description: "Nerd Font glyphs (the launcher's ; mode)"; onPressed: Island.openWith(";") }
    GlobalShortcut { appid: "kuwai"; name: "note"; description: "Quick note (a line in ~/Notes/inbox.md)"; onPressed: Island.openWith("note ") }
    GlobalShortcut { appid: "kuwai"; name: "remind"; description: "Remind me (\"in 20m tea\", \"at 5 call mum\")"; onPressed: Island.openWith("remind me ") }
    GlobalShortcut { appid: "kuwai"; name: "switch-next"; description: "Windows: next (hold Alt)"; onPressed: Switcher.begin(1, false) }
    GlobalShortcut { appid: "kuwai"; name: "switch-prev"; description: "Windows: previous"; onPressed: Switcher.begin(-1, false) }
    GlobalShortcut { appid: "kuwai"; name: "switch-app"; description: "Windows of this app"; onPressed: Switcher.begin(1, true) }
    GlobalShortcut { appid: "kuwai"; name: "switch-ws"; description: "Windows on this workspace"; onPressed: Switcher.begin(1, false, true) }
    GlobalShortcut { appid: "kuwai"; name: "switch-commit"; description: "Windows: switch (Alt released)"; onPressed: Switcher.commit() }
    GlobalShortcut { appid: "kuwai"; name: "switch-cancel"; description: "Windows: cancel"; onPressed: Switcher.cancel() }
    GlobalShortcut {
        appid: "kuwai"
        name: "keys-open"
        description: "Shortcuts palette: open (hold Super)"
        onPressed: Island.open("keys", "", "key")
    }
    GlobalShortcut {
        appid: "kuwai"
        name: "keys-close"
        description: "Shortcuts palette: close"
        onPressed: if (Island.panel === "keys") Island.close()
    }
    GlobalShortcut {
        appid: "kuwai"
        name: "calendar"
        description: "Calendar"
        onPressed: Island.toggle("calendar", "", "key")
    }
}
