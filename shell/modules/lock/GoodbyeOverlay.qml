// The goodbye (Farewell), over every screen of the desktop while
// services/Goodbye has one to say; takes no input meanwhile.
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services

Variants {
    model: Quickshell.screens
    LazyLoader {
        id: slot
        required property ShellScreen modelData
        active: Goodbye.kind !== "" || (slot.item && slot.item.busy)
        PanelWindow {
            readonly property bool busy: bye.visible
            screen: slot.modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            // Not rice-*: that layer rule blurs past 30 % alpha, a pop mid-fade.
            WlrLayershell.namespace: "kuwai-goodbye"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            color: "transparent"
            Farewell {
                id: bye
                anchors.fill: parent
                kind: Goodbye.kind
                name: { const u = Quickshell.env("USER") || ""; return u.charAt(0).toUpperCase() + u.slice(1); }
                onDone: Goodbye.black()
            }
        }
    }
}
