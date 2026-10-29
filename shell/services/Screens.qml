// Which monitor is focused, reliably. Quickshell's Hyprland.focusedMonitor
// stays null after a (re)start until focus next changes, so surfaces that
// asked it fell back to the first screen (toasts showed up on the laptop
// while you were on the external monitor). Ask Hyprland once at startup,
// then follow its focus events.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Singleton {
    id: root

    property string probed: ""
    // (Guarded: while a hot reload tears the old copy down, Hyprland can be
    // briefly unavailable.)
    readonly property string focusedName: {
        const m = typeof Hyprland !== "undefined" && Hyprland ? Hyprland.focusedMonitor : null;
        if (m && m.name) return m.name;
        if (probed) return probed;
        const first = Quickshell.screens.length ? Quickshell.screens[0] : null;
        return first && first.name ? first.name : "";
    }
    readonly property var focused: Quickshell.screens.find(s => s.name === focusedName) || Quickshell.screens[0]

    function screenNamed(name) {
        return Quickshell.screens.find(s => s.name === name) || focused;
    }

    Component.onCompleted: probe.running = true
    Process {
        id: probe
        command: ["hyprctl", "monitors", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const m = JSON.parse(text).find(x => x.focused);
                    if (m) root.probed = m.name;
                } catch (e) {}
            }
        }
    }
}
