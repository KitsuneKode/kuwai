// Where a dictation will land: a ring around that window while you speak
// (red, as the island's mic, glowing with your voice) and while it's written
// out (a calm light in the accent), gone when the text lands. Drawn over the
// screen on the overlay layer, click-through, never touching the window: the
// border used to grow 3 px instead, which re-laid kitty's grid every take.
// Outside the window when there's room, inside its edge when there isn't
// (maximised, fullscreen, against the screen's edge); voxRing.mjs places it.
// The voice is the source linked into voxtype's capture stream (the default
// source until that stream appears), on a dB scale that follows the session.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import qs.config
import qs.components
import qs.services
import "voxRing.mjs" as VoxRing

Scope {
    id: root

    readonly property bool on: Activities.voxBusy && !Saver.away
    readonly property string runtime: Paths.runtime
    property string address: ""
    property var box: null
    property int border: 3
    property int rounding: 25
    readonly property int gap: 3
    readonly property int stroke: 3

    FileView {
        path: root.runtime + "/voxtype/target_window"
        watchChanges: true; printErrors: false
        onFileChanged: reload()
        onLoaded: { try { root.address = JSON.parse(text() || "{}").address || ""; } catch (e) { root.address = ""; } if (root.on) look.restart(); }
    }
    onOnChanged: { if (on) look.restart(); }

    function read(address, clients, monitors, rnd, bsz) {
        if (rnd && rnd.int !== undefined) rounding = rnd.int;
        if (bsz && bsz.int !== undefined) border = bsz.int;
        box = VoxRing.place(address, clients, monitors, { border: border, rounding: rounding, gap: gap, stroke: stroke });
    }
    Timer { id: look; interval: 60; onTriggered: if (root.on && root.address && !where.running) where.running = true }
    Process {
        id: where
        command: ["sh", "-c", 'hyprctl clients -j; printf "\\036"; hyprctl monitors -j; printf "\\036"; hyprctl getoption decoration:rounding -j; printf "\\036"; hyprctl getoption general:border_size -j']
        stdout: StdioCollector {
            onStreamFinished: {
                let parts = [];
                try { parts = text.split("\x1e").map(p => JSON.parse(p)); } catch (e) { root.box = null; return; }
                root.read(root.address, parts[0], parts[1], parts[2], parts[3]);
            }
        }
    }
    // A window moving or the workspace changing while a take is on.
    Connections {
        target: Hyprland
        enabled: root.on
        function onRawEvent(event) {
            if (/^(movewindow|changefloatingmode|fullscreen|workspace|focusedmon|openwindow|closewindow|activelayout|activespecial|moveworkspace|monitorremoved)/.test(event.name)) look.restart();
        }
    }

    readonly property var heard: {
        if (!on) return null;
        const s = Activities.voxStreams[0];
        const g = s ? Pipewire.linkGroups.values.find(l => l.target === s && l.source && !l.source.isStream) : null;
        return g ? g.source : Pipewire.defaultAudioSource;
    }
    PwObjectTracker { objects: root.heard ? [root.heard] : [] }
    PwNodePeakMonitor {
        id: voice
        node: root.heard
        enabled: root.on && !!root.box && Activities.voxListening
    }
    property real peak: voice.peak
    property var level: VoxRing.quiet()
    property vector4d hist0: Qt.vector4d(0, 0, 0, 0)
    property vector4d hist1: Qt.vector4d(0, 0, 0, 0)
    Timer {
        id: sample
        interval: 45; repeat: true
        running: voice.enabled
        onTriggered: {
            root.level = VoxRing.listen(root.level, root.peak, interval);
            const g = root.level.glow;
            root.hist1 = Qt.vector4d(root.hist0.w, root.hist1.x, root.hist1.y, root.hist1.z);
            root.hist0 = Qt.vector4d(g, root.hist0.x, root.hist0.y, root.hist0.z);
        }
        onRunningChanged: if (running) { root.level = VoxRing.quiet(); root.hist0 = Qt.vector4d(0, 0, 0, 0); root.hist1 = Qt.vector4d(0, 0, 0, 0); }
    }
    readonly property bool writing: Activities.voxState === "transcribing"
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
                id: ringWindow
                screen: slot.modelData
                anchors { top: true; bottom: true; left: true; right: true }
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.namespace: "kuwai.voxtarget"
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                mask: Region {}
                color: "transparent"

                Item {
                    id: ring
                    readonly property bool wordless: true
                    readonly property real pad: 24
                    property bool born: false
                    Component.onCompleted: born = true
                    x: root.box ? root.box.x - pad : 0
                    y: root.box ? root.box.y - pad : 0
                    width: root.box ? root.box.w + pad * 2 : 0
                    height: root.box ? root.box.h + pad * 2 : 0
                    opacity: slot.here && born ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: slot.here ? Theme.enterMs : Theme.exitMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                    ShaderEffect {
                        anchors.fill: parent
                        property vector2d size: Qt.vector2d(width, height)
                        property real pad: ring.pad
                        property real radius: root.box ? root.box.radius : 0
                        property real stroke: root.stroke
                        property real inward: root.box && root.box.inside ? 1 : 0
                        property real still: Theme.reduceMotion ? 1 : 0
                        property real mode: root.writing ? 1 : 0
                        Behavior on mode { NumberAnimation { duration: Theme.colorMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                        property real phase: 0
                        NumberAnimation on phase {
                            running: root.writing && slot.here && !Theme.reduceMotion
                            from: 0; to: 1
                            duration: Theme.shimmerMs * 2
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
                }
                Rectangle {
                    id: caption
                    readonly property var win: root.box ? root.box.win : null
                    readonly property bool wanted: slot.here && Activities.voxListening && !Activities.voxInField && Activities.voxText !== "" && !!win && !Notifs.sharing
                    property bool want: false
                    onWantedChanged: { if (wanted) settle.restart(); else { settle.stop(); want = false; } }
                    Component.onCompleted: if (wanted) settle.restart()
                    Timer { id: settle; interval: Theme.enterMs * 2; onTriggered: { Activities.voxRecheckField(); caption.want = caption.wanted; } }
                    width: Math.min(words.implicitWidth + Theme.s4 * 2, win ? win.w * 0.7 : 0)
                    height: words.implicitHeight + Theme.s2 * 2
                    x: win ? win.x + (win.w - width) / 2 : 0
                    y: win ? Math.min(win.y + win.h - height - Theme.s5, parent.height - Theme.s5 * 4 - height) : 0
                    radius: height / 2
                    color: Qt.rgba(0.07, 0.07, 0.09, 0.88)
                    border.width: 1; border.color: Theme.edge(1)
                    opacity: want ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: caption.want ? Theme.enterMs : Theme.exitMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                    Label {
                        id: words
                        anchors.centerIn: parent
                        width: Math.max(0, Math.min(implicitWidth, caption.width - Theme.s4 * 2))
                        elide: Text.ElideLeft
                        text: Activities.voxText
                        size: Theme.tCallout
                        color: Theme.textPrimary
                    }
                }
            }
        }
    }
}
