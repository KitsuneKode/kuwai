// Live wallpaper: the shell plays the video on the background layer itself
// (Omarchy's way; no mpvpaper). ~/Scripts/live-wallpaper.sh picks it:
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

Scope {
    id: root

    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state")
    property string video: ""
    property bool locked: false

    FileView {
        path: root.stateDir + "/live-wallpaper/last"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.video = text().trim()
        onLoadFailed: root.video = ""
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
                WlrLayershell.namespace: "rice-wallpaper"
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                mask: Region {}
                color: "transparent"

                readonly property var mon: Hyprland.monitorFor(slot.modelData)
                readonly property var ws: mon ? mon.activeWorkspace : null
                readonly property bool fullscreen: !!ws && !!ws.lastIpcObject && ws.lastIpcObject.hasfullscreen === true
                // Mostly behind windows: decoding a video for the gaps between
                // them costs a core for nothing. Plays on an empty or sparse
                // desktop; pauses (the frame stays) once windows cover ~85%.
                readonly property real coverage: {
                    if (!ws) return 0;
                    const W = bg.width, H = bg.height, mx = mon && mon.lastIpcObject ? mon.lastIpcObject.x : 0, my = mon && mon.lastIpcObject ? mon.lastIpcObject.y : 0;
                    let area = 0;
                    for (const t of Hyprland.toplevels.values) {
                        if (!t.workspace || t.workspace !== ws || !t.lastIpcObject) continue;
                        const o = t.lastIpcObject;
                        if (!o.size || !o.at || o.hidden) continue;
                        const x0 = Math.max(0, o.at[0] - mx), y0 = Math.max(0, o.at[1] - my);
                        const x1 = Math.min(W, o.at[0] - mx + o.size[0]), y1 = Math.min(H, o.at[1] - my + o.size[1]);
                        if (x1 > x0 && y1 > y0) area += (x1 - x0) * (y1 - y0);
                    }
                    return W > 0 && H > 0 ? Math.min(1, area / (W * H)) : 0;
                }
                readonly property bool covered: fullscreen || coverage >= 0.85
                readonly property bool shouldPlay: root.video !== "" && !covered && !root.locked && root.batteryOk

                VideoOutput {
                    id: out
                    anchors.fill: parent
                    fillMode: VideoOutput.PreserveAspectCrop
                    opacity: root.video !== "" && player.hasVideo && player.playbackState !== MediaPlayer.StoppedState ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
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
