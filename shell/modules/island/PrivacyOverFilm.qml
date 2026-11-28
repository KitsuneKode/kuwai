import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.config
import qs.services

Scope {
    id: root

    Variants {
        model: Quickshell.screens

        Scope {
            id: one
            required property ShellScreen modelData
            readonly property var monitor: Hyprland.monitorFor(modelData)
            readonly property bool film: !!monitor && !!monitor.activeWorkspace && monitor.activeWorkspace.hasFullscreen
            readonly property bool wanted: Meeting.active && film && !Saver.locked && !Saver.showing && !Saver.screensOff

            LazyLoader {
                active: one.wanted
                PanelWindow {
                    screen: one.modelData
                    anchors.top: true
                    anchors.right: true
                    margins.top: Theme.s2
                    margins.right: Theme.s2
                    implicitWidth: Theme.s4
                    implicitHeight: Theme.s4
                    exclusiveZone: 0
                    color: "transparent"
                    WlrLayershell.namespace: "kuwai.privacy"
                    WlrLayershell.layer: WlrLayer.Overlay
                    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                    mask: Region {}
                    Rectangle {
                        anchors.centerIn: parent
                        width: Theme.s2; height: width; radius: width / 2
                        color: Theme.orange
                        Accessible.role: Accessible.Indicator
                        Accessible.name: Meeting.paused ? "Microphone held by a paused meeting" : "Microphone in use by a meeting recording"
                    }
                }
            }
        }
    }
}
