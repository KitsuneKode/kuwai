// Live wallpaper. bin/kuwai-livewall picks it:
// Super+Ctrl+W on/off, Super+Ctrl+Shift+W the next one. It writes the path to
// ~/.local/state/live-wallpaper/last (empty: off) and keeps `enabled` there.
//
// Off: nothing exists (no decoder, no layer); the static wallpaper (awww)
// is all there is. On: one muted, looping player per screen over it, fading
// in once frames arrive and out to transparent when it stops.
//
// A covered screen or battery policy pauses playback and keeps the last frame.
// The lock screen, screensaver and powered-off displays release the players.
//
// Who plays: mpv, when mpvpaper is installed (`kuwai-livewall can-play`):
// one mpvpaper per screen, which this file starts, pauses and stops through
// `kuwai-livewall out-play|out-pause|out-stop`. The decisions stay here. The
// shell's own player (QtMultimedia, a PanelWindow per screen) is the fallback.
// Measured 2026-11-18, a 1440p loop on two screens: ~1 GB and 24 % CPU inside
// the shell, against ~280 MB and 7 % a screen for mpv with hardware decoding,
// outside it.
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

    readonly property string stateDir: Paths.stateHome
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

    readonly property bool obscured: root.locked || Saver.locked || Saver.screensOff || Saver.showing
    readonly property bool batteryOk: !UPower.onBattery || Settings.liveOnBattery

    // mpv plays when mpvpaper (with socat and jq) is there; asked once at start.
    property bool viaMpv: false
    Process {
        running: true
        command: [Paths.bin + "/kuwai-livewall", "can-play"]
        onExited: (code, status) => root.viaMpv = code === 0
    }

    // Union of the visible rectangles. Adding each window's area counted
    // overlaps twice, so two stacked windows could pause the video while most
    // of the desktop was still showing.
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

    Variants {
        model: Quickshell.screens
        Scope {
            id: slot
            required property ShellScreen modelData

            // ── What this screen should do: play, pause (keep the frame) or stop ──
            readonly property var mon: Hyprland.monitorFor(slot.modelData)
            readonly property var ws: mon ? mon.activeWorkspace : null
            readonly property bool fullscreen: !!ws && ws.hasFullscreen
            // Mostly behind windows: decoding a video for the gaps between
            // them costs a core for nothing. Plays on an empty or sparse
            // desktop; pauses (the frame stays) once windows cover ~85%.
            readonly property real coverage: {
                if (!ws) return 0;
                const W = Theme.screenSize(slot.modelData, "width", 0), H = Theme.screenSize(slot.modelData, "height", 0);
                const mx = mon && mon.lastIpcObject ? mon.lastIpcObject.x : 0, my = mon && mon.lastIpcObject ? mon.lastIpcObject.y : 0;
                const rects = [];
                for (const t of Hyprland.toplevels.values) {
                    if (!t.workspace || t.workspace !== ws || !t.lastIpcObject) continue;
                    const o = t.lastIpcObject;
                    if (!o.size || !o.at || o.hidden) continue;
                    const x0 = Math.max(0, o.at[0] - mx), y0 = Math.max(0, o.at[1] - my);
                    const x1 = Math.min(W, o.at[0] - mx + o.size[0]), y1 = Math.min(H, o.at[1] - my + o.size[1]);
                    if (x1 > x0 && y1 > y0) rects.push({ x0: x0, y0: y0, x1: x1, y1: y1 });
                }
                return W > 0 && H > 0 ? Math.min(1, root.unionArea(rects) / (W * H)) : 0;
            }
            readonly property bool covered: fullscreen || coverage >= 0.85
            readonly property bool shouldPlay: root.video !== "" && !covered && !root.obscured && root.batteryOk
            property bool released: !shouldPlay
            onShouldPlayChanged: if (shouldPlay) released = false
            Timer {
                id: coverRelease
                interval: 10000
                running: root.video !== "" && !root.obscured && !slot.shouldPlay && !slot.released
                onTriggered: slot.released = true
            }
            readonly property string want: root.video === "" || root.obscured || (slot.released && !shouldPlay) ? "stop" : shouldPlay ? "play" : "pause"

            // Window geometry (lastIpcObject) is a snapshot: refresh it a
            // moment after windows open, close or move.
            Timer { id: refresh; interval: 400; onTriggered: Hyprland.refreshToplevels() }
            // Workspace changes don't always refresh lastIpcObject: a cheap refresh.
            Connections {
                target: Hyprland
                enabled: root.video !== ""
                function onRawEvent(e) {
                    if (e.name === "fullscreen" || e.name === "workspace" || e.name === "workspacev2") Hyprland.refreshWorkspaces();
                    if (["openwindow", "closewindow", "movewindow", "movewindowv2", "changefloatingmode", "fullscreen", "workspacev2"].indexOf(e.name) >= 0) refresh.restart();
                }
            }

            // ── mpv plays it: the latest decision, one command at a time ──
            property string sent: ""                 // "play FILE", "pause FILE", "stop": what mpv was last told
            function drive() {
                if (!root.viaMpv) return;
                const next = slot.want === "stop" ? "stop" : slot.want + " " + root.video;
                if (next === slot.sent && !ctl.running) return;
                if (ctl.running) { ctl.again = true; return; }
                const name = slot.modelData.name, bin = Paths.bin + "/kuwai-livewall";
                ctl.command = slot.want === "stop" ? [bin, "out-stop", name]
                            : slot.want === "play" ? [bin, "out-play", name, root.video]
                            : [bin, "out-play", name, root.video, "paused"];
                ctl.wanted = next;
                ctl.running = true;
            }
            onWantChanged: drive()
            Connections { target: root; function onVideoChanged() { slot.drive(); } function onViaMpvChanged() { slot.drive(); } }
            Process {
                id: ctl
                property string wanted: ""
                property bool again: false
                onExited: (code, status) => {
                    slot.sent = code === 0 ? wanted : "";
                    if (again) { again = false; slot.drive(); }
                }
            }
            // A screen that goes away takes its player with it.
            Component.onDestruction: if (root.viaMpv && slot.sent !== "" && slot.sent !== "stop")
                Quickshell.execDetached([Paths.bin + "/kuwai-livewall", "out-stop", slot.modelData.name])

        LazyLoader {
            active: !root.viaMpv && root.video !== "" && !root.obscured

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

                readonly property bool shouldPlay: slot.shouldPlay

                VideoOutput {
                    id: out
                    anchors.fill: parent
                    fillMode: VideoOutput.PreserveAspectCrop
                    opacity: root.video !== "" && player.hasVideo && player.playbackState !== MediaPlayer.StoppedState ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.ambientFadeMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                }
                MediaPlayer {
                    id: player
                    source: root.video !== "" ? "file://" + encodeURI(root.video).replace(/#/g, "%23").replace(/\?/g, "%3F") : ""
                    videoOutput: out
                    activeAudioTrack: -1
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
                Connections { target: player; function onSourceChanged() { bg.apply(); } }
                Component.onCompleted: apply()
            }
        }
        }
    }
}
