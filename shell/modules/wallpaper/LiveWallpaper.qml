// Live wallpaper: the shell plays the video on the background layer itself
// (Omarchy's way; no mpvpaper). bin/kuwai-livewall picks it:
// Super+Ctrl+W on/off, Super+Ctrl+Shift+W the next one. It writes the path to
// ~/.local/state/live-wallpaper/last (empty: off) and keeps `enabled` there.
//
// Off: nothing exists (no decoder, no layer); the static wallpaper (awww)
// is all there is. On: one muted, looping player per screen over it, fading
// in once frames arrive and out to transparent when it stops.
//
// Paused, not decoding, whenever nobody can see it or it costs too much:
//   a fullscreen window on that screen · the screen locked · on battery
//   (Settings.liveOnBattery to allow it)
import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.UPower
import qs.config
import qs.services

Scope {
    id: root

    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state")
    property string video: ""
    property bool locked: false

    // `last` names the loop you picked; what plays is what kuwai-livewall
    // says is playable: the loop itself, or its 4:2:0 copy once one exists (a
    // 4:4:4 loop can't be decoded by the GPU: two players decoding it in
    // software held 739–1111 MB inside the shell). The script writes `last`
    // again when a copy is ready, so this asks once more and switches to it.
    property string picked: ""
    onPickedChanged: resolve()
    function resolve() {
        if (picked === "") { video = ""; return; }
        if (playable.running) { playable.again = true; return; }
        playable.asked = picked;
        playable.command = [Paths.bin + "/kuwai-livewall", "playable", picked];
        playable.running = true;
    }
    Process {
        id: playable
        property string asked: ""
        property bool again: false
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim();
                // Only for the pick it was asked about (a newer pick asks again below).
                if (playable.asked === root.picked) root.video = p !== "" ? p : root.picked;
            }
        }
        onExited: (code, status) => {
            if (code !== 0 && asked === root.picked) root.video = root.picked;   // the script failed: play the loop as it is
            if (again || asked !== root.picked) { again = false; root.resolve(); }
        }
    }
    FileView {
        path: root.stateDir + "/live-wallpaper/last"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        // The same pick written again (a copy became ready) asks again too.
        onLoaded: { const f = text().trim(); if (f === root.picked) root.resolve(); else root.picked = f; }
        onLoadFailed: root.picked = ""
    }
    // The lock screen's flag (modules/lock): present while locked.
    FileView {
        path: Paths.lockFlag
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.locked = true
        onLoadFailed: root.locked = false
    }

    readonly property bool batteryOk: !UPower.onBattery || Settings.liveOnBattery

    Variants {
        model: Quickshell.screens
        LazyLoader {
            id: slot
            required property ShellScreen modelData
            active: root.video !== "" || fadeOut
            property bool fadeOut: false

            PanelWindow {
                id: bg
                screen: slot.modelData
                anchors { top: true; bottom: true; left: true; right: true }
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Background
                // Outside kuwai-*: that rule blurs every kuwai-* surface, and a later
                // blur=false does not undo it. A full-screen video would pay
                // for a blur nobody can see. Same split as the screensaver.
                WlrLayershell.namespace: "kuwai.wallpaper"
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                mask: Region {}
                color: "transparent"

                readonly property var mon: Hyprland.monitorFor(slot.modelData)
                readonly property var ws: mon ? mon.activeWorkspace : null
                readonly property bool fullscreen: !!ws && ws.hasFullscreen
                // Mostly behind windows: decoding a video for the gaps between
                // them costs a core for nothing. Plays on an empty or sparse
                // desktop; pauses (the frame stays) once windows cover ~85%.
                // Union of the visible rectangles. Adding each window's area
                // counted overlaps twice, so two stacked windows could pause
                // the video while most of the desktop was still showing.
                function unionArea(rects) {
                    if (!rects.length) return 0;
                    const xs = [];
                    for (let i = 0; i < rects.length; i++) xs.push(rects[i].x0, rects[i].x1);
                    xs.sort((a, b) => a - b);
                    let area = 0;
                    for (let i = 0; i < xs.length - 1; i++) {
                        const xL = xs[i], xR = xs[i + 1];
                        if (xR <= xL) continue;
                        const spans = [];
                        for (let j = 0; j < rects.length; j++) {
                            const r = rects[j];
                            if (r.x0 < xR && r.x1 > xL) spans.push(r);
                        }
                        spans.sort((a, b) => a.y0 - b.y0 || a.y1 - b.y1);
                        let yCursor = -Infinity;
                        for (let j = 0; j < spans.length; j++) {
                            const y0 = Math.max(spans[j].y0, yCursor);
                            if (spans[j].y1 > y0) {
                                area += (xR - xL) * (spans[j].y1 - y0);
                                yCursor = spans[j].y1;
                            }
                        }
                    }
                    return area;
                }
                readonly property real coverage: {
                    if (!ws) return 0;
                    const W = bg.width, H = bg.height, mx = mon && mon.lastIpcObject ? mon.lastIpcObject.x : 0, my = mon && mon.lastIpcObject ? mon.lastIpcObject.y : 0;
                    const rects = [];
                    for (const t of Hyprland.toplevels.values) {
                        if (!t.workspace || t.workspace !== ws || !t.lastIpcObject) continue;
                        const o = t.lastIpcObject;
                        if (!o.size || !o.at || o.hidden) continue;
                        const x0 = Math.max(0, o.at[0] - mx), y0 = Math.max(0, o.at[1] - my);
                        const x1 = Math.min(W, o.at[0] - mx + o.size[0]), y1 = Math.min(H, o.at[1] - my + o.size[1]);
                        if (x1 > x0 && y1 > y0) rects.push({ x0: x0, y0: y0, x1: x1, y1: y1 });
                    }
                    return W > 0 && H > 0 ? Math.min(1, bg.unionArea(rects) / (W * H)) : 0;
                }
                readonly property bool covered: fullscreen || coverage >= 0.85
                readonly property bool shouldPlay: root.video !== "" && !covered && !root.locked && root.batteryOk && !Saver.showing   // under the screensaver: nobody sees it

                VideoOutput {
                    id: out
                    anchors.fill: parent
                    fillMode: VideoOutput.PreserveAspectCrop
                    opacity: root.video !== "" && player.hasVideo && player.playbackState !== MediaPlayer.StoppedState ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.ambientFadeMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                }
                MediaPlayer {
                    id: player
                    source: root.video !== "" ? "file://" + root.video : ""
                    videoOutput: out
                    audioOutput: AudioOutput { muted: true; volume: 0 }
                    loops: MediaPlayer.Infinite
                }
                // Play, pause or stop as conditions change (a fullscreen game,
                // the lock, unplugging); a pause keeps the frame on screen.
                function apply() {
                    if (root.video === "") player.stop();
                    else if (shouldPlay) player.play();
                    else if (player.playbackState === MediaPlayer.PlayingState) player.pause();
                }
                onShouldPlayChanged: apply()
                // Window geometry (lastIpcObject) is a snapshot: refresh it a
                // moment after windows open, close or move.
                Timer { id: refresh; interval: 400; onTriggered: Hyprland.refreshToplevels() }
                Connections { target: player; function onSourceChanged() { bg.apply(); } }
                Component.onCompleted: apply()
                // Workspace changes don't always refresh lastIpcObject: a cheap refresh.
                Connections {
                    target: Hyprland
                    function onRawEvent(e) {
                        if (e.name === "fullscreen" || e.name === "workspace" || e.name === "workspacev2") Hyprland.refreshWorkspaces();
                        if (["openwindow", "closewindow", "movewindow", "movewindowv2", "changefloatingmode", "fullscreen", "workspacev2"].indexOf(e.name) >= 0) refresh.restart();
                    }
                }
            }
        }
    }
}
