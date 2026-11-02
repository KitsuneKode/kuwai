// Notification toasts, stacked Sonner-style in the top-right corner under
// the bar.
//
//   collapsed   the newest toast in front; up to two more peek out below it,
//               each 14px lower and 5% smaller, cut to the front one's height
//               with their content hidden; any beyond three wait invisibly
//   expanded    hovering (or touching) the stack fans every toast out to its
//               own height, 14px apart, and pauses all their clocks
//
// Which monitor: the one focused when a toast arrives. There's a surface per
// screen; a new toast brings the stack to the focused monitor, and then it
// stays put (focus follows the mouse here, and a stack hopping screens as
// the pointer crosses them reads as broken). Not while you're on it.
//
// When the center opens, the toasts fade out fast (Fluid Functionalism's
// fast exit) while the center morphs out of the front one's rectangle.
//
// Positions are worked out here and handed to each card; cards animate to
// them (400ms CSS `ease`, from wherever they are, so it's interruptible).
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.config
import qs.services

Scope {
    id: root

    // Island bar: toasts pour out of the island (top centre) and go back into
    // it; with Waybar they keep the top-right corner under the bar.
    // Toasts keep the top-right corner (the island extends only for the
    // volume / brightness HUD). Flip to `Settings.bar === "island"` to have
    // them pour out of the island instead — the code path is kept.
    readonly property bool fromIsland: false
    readonly property real islandH: 34
    readonly property real islandTop: Settings.islandStyle === "floating" ? 6 : 0
    readonly property real islandGap: 10
    function islandWidth(screenName) { return Island.restWidths[screenName] || 260; }

    readonly property var stack: Notifs.popups                 // includes leaving ones
    readonly property var live: stack.filter(i => !i.leaving)  // laid out

    property bool hovered: false
    property bool interacting: false
    property bool pinnedOpen: false
    // A single toast has nothing to fan out.
    readonly property bool expanded: (hovered || interacting || pinnedOpen) && live.length > 1

    readonly property real frontHeight: live.length ? live[0].cardHeight : 0
    function offsetOf(index) {
        let o = 0;
        for (let k = 0; k < index; k++) o += live[k].cardHeight + Theme.stackGap;
        return o;
    }
    // Only the first three are ever shown (Sonner hides the rest even when
    // fanned out), so only they take room and input.
    readonly property int shownCount: Math.min(live.length, Theme.stackVisible)
    readonly property real expandedHeight: shownCount ? offsetOf(shownCount - 1) + live[shownCount - 1].cardHeight : 0
    readonly property real collapsedHeight: frontHeight + Theme.stackGap * Math.max(0, shownCount - 1)

    Binding { target: Notifs; property: "held"; value: root.expanded || root.interacting }
    // Where the center morphs out of; frozen while it's open.
    Binding {
        target: Notifs
        property: "frontToast"
        when: !Notifs.centerOpen
        value: root.live.length ? { screen: root.targetName, height: root.frontHeight } : null
        restoreMode: Binding.RestoreNone
    }

    // ── Which screen ─────────────────────────────────────────────────────
    property string targetName: ""
    function focusedName() { return Screens.focusedName; }
    function follow() {
        if (!hovered && !interacting) targetName = focusedName();
    }
    Component.onCompleted: targetName = focusedName()
    Connections {
        target: Notifs
        function onArrived() { root.follow(); }
        // The center takes over: fade the stack (fast exit), then quietly
        // retire what was on screen; it's all in the center's list anyway.
        function onCenterOpenChanged() {
            if (Notifs.centerOpen && root.stack.length) fadeOut.restart();
        }
    }

    property real handoff: 1
    NumberAnimation {
        id: fadeOut; target: root; property: "handoff"; to: 0
        duration: Theme.springFast.exitMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut
        onFinished: {
            for (const i of root.stack.slice()) Notifs.left(i);
            root.handoff = 1;
        }
    }
    readonly property bool active: stack.length > 0 && (!Notifs.centerOpen || fadeOut.running)

    IpcHandler {
        target: "toasts"
        // Fan the stack out from the keyboard (or a script) as if hovered.
        function expand(on: bool): void { root.pinnedOpen = on; }
        // Diagnostics: where the stack is and what Hyprland says is focused.
        function where(): string {
            const m = Hyprland.focusedMonitor;
            return JSON.stringify({ target: root.targetName, focused: Screens.focusedName, quickshell: m ? m.name : null,
                                    ipc: Hyprland.monitors.values.filter(x => x.lastIpcObject && x.lastIpcObject.focused).map(x => x.name) });
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property ShellScreen modelData
            readonly property bool here: !!modelData && modelData.name === root.targetName

            screen: modelData
            visible: root.active && here

            anchors.top: true
            anchors.right: !root.fromIsland
            margins.top: root.fromIsland ? 0 : Theme.barGap
            margins.right: root.fromIsland ? 0 : 4
            // Room for the cards, the close button's overhang and swipes,
            // which all happen inside the surface.
            implicitWidth: Theme.toastWidth + 72
            implicitHeight: modelData ? Math.min(modelData.height - 80, 900) : 900
            exclusionMode: root.fromIsland ? ExclusionMode.Ignore : ExclusionMode.Normal
            color: "transparent"
            readonly property real islandW: root.islandWidth(modelData ? modelData.name : "")

            WlrLayershell.namespace: "rice-notifs"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            mask: Region { item: hitArea }

            Item {
                id: area
                anchors.right: root.fromIsland ? undefined : parent.right
                anchors.rightMargin: 12
                anchors.horizontalCenter: root.fromIsland ? parent.horizontalCenter : undefined
                y: root.fromIsland ? root.islandTop + root.islandH + root.islandGap : 12
                width: Theme.toastWidth
                height: root.expanded ? root.expandedHeight : root.collapsedHeight
                opacity: root.handoff

                // Input region: the stack plus a little slack for the close
                // button and for the pointer crossing the gaps while expanded.
                Item {
                    id: hitArea
                    anchors.fill: parent
                    anchors.margins: -10
                }

                HoverHandler {
                    onHoveredChanged: root.hovered = hovered
                }

                // Cards exist only on the screen the stack is on.
                Repeater {
                    model: ScriptModel { values: win.here ? root.stack : [] }
                    NotifCard { stack: root; islandW: win.islandW }
                }
            }
        }
    }
}
