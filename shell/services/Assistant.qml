pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.services

Singleton {
    id: root

    property bool open: false
    property string targetScreen: ""
    property bool sniping: false
    // A window opened while the assistant was up (Satty, a link from a
    // reply, an app): it gets the keyboard, the assistant stays on screen
    // and takes the keyboard back when you click in it.
    property bool yielded: false
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "openwindow" || !root.open || root.sniping) return;
            root.yielded = true;
            Island.giveFocus(String(event.data || "").split(",")[0]);
        }
    }

    function toggle() {
        if (open) {
            hide();
        } else {
            show();
        }
    }

    function show() {
        if (typeof Screens !== "undefined" && Screens.focusedName) {
            targetScreen = Screens.focusedName;
        }
        open = true;
        yielded = false;
        OllamaService.probe();
    }

    function hide() {
        open = false;
        OllamaService.onPanelClosed();
    }

    IpcHandler {
        target: "assistant"
        function toggle() { root.toggle(); }
        function open() { root.show(); }
        function close() { root.hide(); }
        function state(): string { return root.open ? "open" : "closed"; }
        // Ask about what you're looking at: the focused window's screenshot, its app,
        // folder and git, your selection and clipboard come attached (bind it to a key).
        function here() { OllamaService.snapshotActiveWindow(); }
    }
}
