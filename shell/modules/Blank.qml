// Blank a screen (Super+Ctrl+N, `rice blank`): again to bring it back.
//
// Two screens or more: the ones you're NOT on go black (working on the
// monitor, the laptop panel goes dark; on the laptop, the monitor does).
// One screen: that one (press again, blind, to get it back).
//
// Black is a curtain of our own (an Overlay layer, pure black) with the
// screen's backlight at 0 under it: DPMS off would have been undone by the
// first key press (misc:key_press_enables_dpms, which the idle screens-off
// needs). The levels are restored exactly. A click on a curtain, or the
// screen going away, brings it back too.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.config
import qs.services

Scope {
    id: root

    property var blanked: []          // screen names under a curtain
    property var levels: ({})         // name → brightness before
    readonly property string ctl: Quickshell.env("HOME") + "/Scripts/brightness.sh"

    function toggle() {
        if (blanked.length) { restore(); return; }
        const all = Quickshell.screens.map(s => s.name);
        const here = Screens.focusedName;
        const pick = all.length > 1 ? all.filter(n => n !== here) : all;
        if (!pick.length) return;
        blanked = pick;
        reading.running = true;
    }
    function restore() {
        const was = levels;
        blanked = [];
        levels = ({});
        for (const name in was) Quickshell.execDetached([ctl, "--output", name, "set", String(was[name])]);
    }
    // Remember each level, then take it to 0 (the curtain is already black).
    Process {
        id: reading
        command: [root.ctl, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                let st = null;
                try { st = JSON.parse(text); } catch (e) { return; }
                if (!st || !st.outputs || !root.blanked.length) return;
                const was = {};
                for (const name of root.blanked) {
                    const o = st.outputs[name];
                    if (o && typeof o.value === "number" && o.value > 0) was[name] = o.value;
                }
                root.levels = was;
                for (const name in was) Quickshell.execDetached([root.ctl, "--output", name, "set", "0"]);
            }
        }
    }
    // A screen unplugged while dark: forget it.
    Connections {
        target: Quickshell
        function onScreensChanged() {
            const live = Quickshell.screens.map(s => s.name);
            if (root.blanked.some(n => live.indexOf(n) < 0)) root.blanked = root.blanked.filter(n => live.indexOf(n) >= 0);
        }
    }

    Variants {
        model: Quickshell.screens
        LazyLoader {
            id: slot
            required property ShellScreen modelData
            active: root.blanked.indexOf(modelData.name) >= 0
            PanelWindow {
                screen: slot.modelData
                anchors { top: true; bottom: true; left: true; right: true }
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.namespace: "kuwai-blank"
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                color: "black"
                // The pointer wandered over and clicked: you want it back.
                MouseArea { anchors.fill: parent; cursorShape: Qt.BlankCursor; onClicked: root.restore() }
            }
        }
    }

    GlobalShortcut {
        appid: "rice"
        name: "blank"
        description: "Blank the other screen (again to bring it back)"
        onPressed: root.toggle()
    }
    IpcHandler {
        target: "blank"
        function toggle(): void { root.toggle(); }
        function restore(): void { root.restore(); }
    }
}
