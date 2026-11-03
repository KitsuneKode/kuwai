pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

Singleton {
    id: root

    property bool open: false
    property string targetScreen: ""
    property bool sniping: false

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
    }
}
