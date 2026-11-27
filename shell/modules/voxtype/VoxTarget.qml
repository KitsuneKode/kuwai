// Where a dictation will land: a ring just outside that window while you
// speak (red, as the island's mic) and while it's written out (the accent),
// gone when the text lands. It is drawn over the screen, click-through, and
// never touches the window. voxtype-outline.sh used to make the window's
// border 3 px thicker instead, which shrank the window: kitty re-laid its
// grid, a TUI redrew, and the terminal jumped at the start and end of every
// take.
//
// The window comes from voxtype's target_window (voxtype-toggle.sh writes it
// when a take starts); its place from `hyprctl clients`, read again only
// when a window moves while a take is on.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import qs.config
import qs.components
import qs.services

Scope {
    id: root

    readonly property bool on: Activities.voxBusy && !Saver.away
    readonly property string runtime: Paths.runtime
    property string address: ""
    // { monitor, x, y, w, h } in that monitor's logical pixels, or null
    property var box: null
    property int border: 3
    property int rounding: 25

    FileView {
        path: root.runtime + "/voxtype/target_window"
        watchChanges: true; printErrors: false
        onFileChanged: reload()
        onLoaded: { try { root.address = JSON.parse(text() || "{}").address || ""; } catch (e) { root.address = ""; } if (root.on) look.restart(); }
    }
    onOnChanged: { if (on) look.restart(); }

    // Where it is now (and the border it has, so the ring sits outside it).
    Timer { id: look; interval: 60; onTriggered: if (root.on && root.address && !where.running) where.running = true }
    Process {
        id: where
        command: ["sh", "-c", 'hyprctl clients -j; printf "\\036"; hyprctl monitors -j; printf "\\036"; hyprctl getoption decoration:rounding -j; printf "\\036"; hyprctl getoption general:border_size -j']
        stdout: StdioCollector {
            onStreamFinished: {
                let parts = [];
                try { parts = text.split("\x1e").map(p => JSON.parse(p)); } catch (e) { root.box = null; return; }
                const [clients, monitors, rnd, bsz] = parts;
                if (rnd && rnd.int !== undefined) root.rounding = rnd.int;
                if (bsz && bsz.int !== undefined) root.border = bsz.int;
                const c = (clients || []).find(x => x.address === root.address);
                const m = c && (monitors || []).find(x => x.id === c.monitor);
                // On a workspace nobody sees, or fullscreen (no room outside it): no ring.
                if (!c || !m || c.fullscreen || !c.mapped || c.hidden || (m.activeWorkspace.id !== c.workspace.id && m.specialWorkspace.id !== c.workspace.id)) { root.box = null; return; }
                root.box = { monitor: m.name, x: c.at[0] - m.x, y: c.at[1] - m.y, w: c.size[0], h: c.size[1] };
            }
        }
    }
    // A window moving or the workspace changing while a take is on.
    Connections {
        target: Hyprland
        enabled: root.on
        function onRawEvent(event) {
            if (/^(movewindow|changefloatingmode|fullscreen|workspace|focusedmon|resizewindow|openwindow|closewindow|activelayout)/.test(event.name)) look.restart();
        }
    }

    // The screen the ring is on; kept a moment after it goes, so it fades.
    PwObjectTracker { objects: root.on ? [Pipewire.defaultAudioSource] : [] }
    PwNodePeakMonitor {
        id: voice
        node: Pipewire.defaultAudioSource
        enabled: root.on && Activities.voxListening && !Theme.reduceMotion
    }
    property real glow: 0
    property vector4d hist0: Qt.vector4d(0, 0, 0, 0)
    property vector4d hist1: Qt.vector4d(0, 0, 0, 0)
    Timer {
        interval: 45; repeat: true
        running: voice.enabled
        onTriggered: {
            const p = voice.peaks && voice.peaks.length ? Math.max(...voice.peaks) : (voice.peak || 0);
            const v = Math.min(1, Math.sqrt(Math.max(0, p)) * 1.4);
            root.glow = v > root.glow ? root.glow + (v - root.glow) * 0.6 : root.glow * 0.82 + v * 0.18;
            root.hist1 = Qt.vector4d(root.hist0.w, root.hist1.x, root.hist1.y, root.hist1.z);
            root.hist0 = Qt.vector4d(root.glow, root.hist0.x, root.hist0.y, root.hist0.z);
        }
        onRunningChanged: if (running) { root.glow = 0; root.hist0 = Qt.vector4d(0, 0, 0, 0); root.hist1 = Qt.vector4d(0, 0, 0, 0); }
    }
    readonly property bool writing: Activities.voxState === "transcribing" && !Theme.reduceMotion
    readonly property string target: on && box ? box.monitor : ""
    property string shownOn: ""
    onTargetChanged: { if (target) { linger.stop(); shownOn = target; } else linger.restart(); }
    Timer { id: linger; interval: Theme.exitMs + 60; onTriggered: root.shownOn = root.target }

    Variants {
        model: Quickshell.screens
        LazyLoader {
            id: slot
            required property ShellScreen modelData
            readonly property bool here: root.on && !!root.box && root.box.monitor === modelData.name
                && !(Island.panel !== "" && Island.screen === modelData.name)
            active: root.shownOn === modelData.name
            PanelWindow {
                screen: slot.modelData
                anchors { top: true; bottom: true; left: true; right: true }
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Top
                WlrLayershell.namespace: "kuwai.voxtarget"
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                mask: Region {}
                color: "transparent"

                Rectangle {
                    id: caption
                    readonly property bool want: slot.here && Activities.voxListening && !Activities.voxInField && Activities.voxText !== "" && !!root.box
                    width: Math.min(words.implicitWidth + Theme.s4 * 2, root.box ? root.box.w * 0.7 : 0)
                    height: words.implicitHeight + Theme.s2 * 2
                    x: root.box ? root.box.x + (root.box.w - width) / 2 : 0
                    y: root.box ? root.box.y + root.box.h - height - Theme.s5 : 0
                    radius: height / 2
                    color: Qt.rgba(0.07, 0.07, 0.09, 0.88)
                    border.width: 1; border.color: Theme.edge(1)
                    opacity: want ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: want ? Theme.enterMs : Theme.exitMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                    Label {
                        id: words
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, caption.width - Theme.s4 * 2)
                        elide: Text.ElideLeft
                        text: Activities.voxText
                        size: Theme.tCallout
                        color: Theme.textPrimary
                    }
                }
                Rectangle {
                    id: ring
                    // Outside the window's own border, concentric with it.
                    readonly property int gap: 3
                    readonly property int stroke: 3
                    readonly property int out: root.border + gap + stroke
                    x: root.box ? root.box.x - out : 0
                    y: root.box ? root.box.y - out : 0
                    width: root.box ? root.box.w + out * 2 : 0
                    height: root.box ? root.box.h + out * 2 : 0
                    radius: root.rounding + out
                    color: "transparent"
                    border.width: stroke
                    border.color: Theme.reduceMotion ? Qt.alpha(Activities.voxListening ? Theme.red : Theme.accent, 0.6) : "transparent"
                    Behavior on border.color { ColorAnimation { duration: Theme.colorMs } }
                    opacity: slot.here ? 1 : 0
                    ShaderEffect {
                        id: wave
                        readonly property real pad: 24
                        x: -pad; y: -pad
                        width: ring.width + pad * 2
                        height: ring.height + pad * 2
                        visible: !Theme.reduceMotion
                        property vector2d size: Qt.vector2d(width, height)
                        property real radius: ring.radius
                        property real stroke: ring.stroke
                        property real mode: root.writing ? 1 : 0
                        Behavior on mode { NumberAnimation { duration: Theme.colorMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                        property real phase: 0
                        NumberAnimation on phase {
                            running: root.writing && slot.here
                            from: 0; to: 1
                            duration: Theme.shimmerMs * 3 / 2
                            loops: Animation.Infinite
                        }
                        property vector4d hist0: root.hist0
                        property vector4d hist1: root.hist1
                        property color listenColor: Theme.red
                        property color writeColor: Qt.lighter(Theme.accent, 1.25)
                        property color writeColor2: Theme.accent.hslHue < 0 ? Theme.purple
                            : Qt.hsla((Theme.accent.hslHue + 0.14) % 1, Theme.accent.hslSaturation, Math.min(0.72, Theme.accent.hslLightness + 0.08), 1)
                        fragmentShader: Qt.resolvedUrl("../../shaders/voxring.frag.qsb")
                    }
                    Behavior on opacity { NumberAnimation { duration: slot.here ? Theme.enterMs : Theme.exitMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                }
            }
        }
    }
}
