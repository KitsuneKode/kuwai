// The screensaver. While Caffeine keeps the machine awake nothing dims or
// locks, so after Settings.screensaverMins idle minutes this fades in: your
// live wallpaper full screen (or the still wallpaper, slowly drifting), a
// large clock that moves a little every minute (no burn-in), the date and
// what's playing. Any key, click, scroll or move dismisses it; that first
// input is swallowed, so it never lands on a window.
//
//   Settings.screensaverWhen: "caffeine" (default: only while Caffeine is on)
//                             "always"   (also before the idle lock)
//                             "off"
// Never over a fullscreen window (a film with Caffeine on stays a film).
// `rice screensaver` shows it now.
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.UPower
import qs.config
import qs.components
import qs.services

Scope {
    id: root

    readonly property string when: Settings.screensaverWhen || "caffeine"
    readonly property bool allowed: when === "always" || (when === "caffeine" && Caffeine.on)
    property bool forced: false
    // hasFullscreen is live (Hyprland events). lastIpcObject was a snapshot
    // that only refreshed on request: one fullscreen video earlier kept it
    // "true", and the screensaver never came again (nor `rice screensaver`).
    readonly property bool fullscreenAnywhere: Hyprland.workspaces.values.some(w => w.hasFullscreen
        && Hyprland.monitors.values.some(m => m.activeWorkspace === w))
    readonly property bool showing: (forced || (allowed && idle.isIdle)) && !fullscreenAnywhere

    IdleMonitor {
        id: idle
        enabled: root.allowed
        timeout: Math.max(1, Settings.screensaverMins || 3) * 60
        // Caffeine is an inhibitor of our own: idle still counts here.
        respectInhibitors: false
        onIsIdleChanged: if (!isIdle) root.forced = false
    }

    // What to play: the live wallpaper's pick, else the still wallpaper.
    readonly property string stateDir: Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state"
    property string video: ""
    FileView {
        path: root.stateDir + "/live-wallpaper/last"
        watchChanges: true; printErrors: false
        onFileChanged: reload()
        onLoaded: root.video = text().trim()
    }
    readonly property bool useVideo: video !== "" && (!UPower.onBattery || Settings.liveOnBattery)
    readonly property string style: Settings.screensaverStyle || "dusk"   // dusk · night · live · still
    // Night: a dark film from ~/.local/share/rice/screensavers (seamless
    // half-speed loops, ~3–7 Mbit/s: cheap to decode, made by kuwai's setup).
    readonly property string clipDir: Quickshell.env("HOME") + "/.local/share/rice/screensavers"
    readonly property string clip: clipDir + "/" + (Settings.screensaverClip || "smoke-soft") + ".mp4"
    property bool clipFailed: false      // this session only: Dusk instead
    onClipChanged: clipFailed = false
    // The screen you were on when it came up: the one Live plays on.
    property string mainScreen: ""
    onShowingChanged: {
        if (showing) mainScreen = Screens.focusedName;
        Saver.showing = showing;
        if (!showing && Dim.wanted) Dim.up();
    }
    readonly property string still: "file://" + Quickshell.env("HOME") + "/.cache/hyde/wall.set"

    // ── The film (Night, Live) plays in its own process: shell-saver/ ─────
    // A player inside the shell kept ~110 MB for good after it stopped
    // (measured); a separate process gives all of it back when killed.
    readonly property string film: style === "night" && !clipFailed ? clip
        : style === "live" && useVideo ? video : ""
    readonly property bool filmUp: showing && film !== ""
    Process {
        id: filmProc
        // A missing file never starts it (test -r).
        // pdeathsig: the film dies with the shell. Without it, a shell killed
        // while the screensaver showed (a restart, `rice promote`) left the
        // film orphaned, covering a monitor for hours; input couldn't reach it.
        command: ["sh", "-c", 'test -r "$KUWAI_SAVER_FILE" && exec setpriv --pdeathsig KILL qs -p "$1"', "rice-saver", Quickshell.shellDir + "/../shell-saver"]
        // Every screen: one screen with the film and the other black read as
        // "the screensaver only came up on one monitor". It's a separate
        // process, killed on wake, so the second decoder costs nothing after.
        // Basic render loop: the threaded one leaks per frame on NVIDIA (bin/rice-shell).
        environment: ({ KUWAI_SAVER_FILE: root.film, KUWAI_SAVER_SCREEN: "*", QSG_RENDER_LOOP: "basic" })
        // The shell is the only one that ends it (SIGKILL, filmUp false), so
        // any exit while the film should be up is a failure: Dusk instead.
        // Our own SIGKILL (the screensaver going, a restart) isn't a failure:
        // counting it latched Night off to Dusk for the rest of the session.
        onExited: { if (!root.killing && root.filmUp && root.style === "night") root.clipFailed = true; root.killing = false; }
    }
    // ── Dim after a while: ten minutes in, every screen down (services/Dim),
    // back where it was on wake.
    Timer {
        interval: 10 * 60 * 1000
        running: root.showing && !Dim.wanted
        onTriggered: Dim.down()
    }

    // SIGKILL, never SIGTERM: Quickshell can crash on a polite exit and its
    // crash handler would relaunch the film (bin/rice-shell has the story).
    onFilmUpChanged: {
        if (filmUp) { if (!filmProc.running) filmProc.running = true; }
        else if (filmProc.running) { killing = true; filmProc.signal(9); }
    }
    property bool killing: false
    Component.onDestruction: if (filmProc.running) filmProc.signal(9)
    // Backstop: a film left over from an earlier shell (before pdeathsig, or
    // however it happened) goes when this one starts.
    Component.onCompleted: {
        Quickshell.execDetached(["pkill", "-9", "-f", "^qs -p .*/shell-saver$"]);
    }

    function dismiss() { forced = false; }
    IpcHandler {
        target: "screensaver"
        // (Not show/hide: `qs ipc … show` is the CLI's own "list functions".)
        function start(): void { root.forced = true; }
        function stop(): void { root.forced = false; }
    }

    property real level: showing ? 1 : 0
    Behavior on level { NumberAnimation { duration: root.showing ? 1200 : 220; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }

    Variants {
        model: Quickshell.screens
        LazyLoader {
            id: slot
            required property ShellScreen modelData
            active: root.showing || root.level > 0.01
            PanelWindow {
                id: win
                screen: slot.modelData
                anchors { top: true; bottom: true; left: true; right: true }
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.namespace: "kuwai-screensaver"   // not rice-*: those blur what's behind past 0.3 alpha, and the vignette crossed it (a blurred lower third)
                WlrLayershell.keyboardFocus: root.showing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
                color: "transparent"

                Item {
                    id: stage
                    anchors.fill: parent
                    opacity: root.level
                    focus: true
                    Keys.onPressed: e => { root.dismiss(); e.accepted = true; }

                    // The film's screen stays clear: the film is under this
                    // surface (its own process, Top layer).
                    readonly property bool filmHere: root.film !== ""
                    Rectangle { anchors.fill: parent; color: "black"; visible: !stage.filmHere }

                    // What fills the screen: the Dusk scene (default, drawn live,
                    // nothing to decode), your live wallpaper, or the still one.
                    readonly property bool stillHere: root.style === "still"
                    // Night and Live: the film on every screen (the saver process).
                    readonly property bool night: root.style === "night" && !root.clipFailed
                    Loader {
                        anchors.fill: parent
                        active: !stage.filmHere && !stage.stillHere && !stage.night
                        sourceComponent: DuskScene { running: root.showing }
                    }
                    Image {
                        visible: stage.stillHere
                        anchors.fill: parent
                        source: stage.stillHere ? root.still : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        // Decoded once at a sensible size (and cached): it was
                        // full size, uncached, on every appearance.
                        sourceSize: Qt.size(Math.min(win.width, 1920), Math.min(win.height, 1080))
                        scale: 1.06
                        SequentialAnimation on scale {
                            running: stage.stillHere && root.showing && !Theme.reduceMotion
                            loops: Animation.Infinite
                            NumberAnimation { to: 1.12; duration: 40000; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1.06; duration: 40000; easing.type: Easing.InOutSine }
                        }
                    }
                    // A soft vignette so the clock reads on any wallpaper.
                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.15) }
                            GradientStop { position: 0.6; color: Qt.rgba(0, 0, 0, 0.25) }
                            GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.55) }
                        }
                    }

                    // The clock: large, light, and somewhere new each minute.
                    Column {
                        id: face
                        spacing: 2
                        property date now: new Date()
                        Timer { interval: 1000; repeat: true; running: root.showing; onTriggered: face.now = new Date() }
                        Text {
                            text: Qt.formatTime(face.now, Settings.clock24 ? "HH:mm" : "h:mm")
                            font.family: Theme.fontRounded || Theme.fontText
                            font.pixelSize: Math.round(win.height * 0.13)
                            font.weight: Font.Light
                            font.features: ({ "tnum": 1 })
                            color: Qt.rgba(1, 1, 1, 0.92)
                        }
                        Text {
                            text: Qt.formatDate(face.now, "dddd, d MMMM")
                            font.family: Theme.fontText
                            font.pixelSize: Math.round(win.height * 0.022)
                            color: Qt.rgba(1, 1, 1, 0.7)
                            leftPadding: 6
                        }
                        Text {
                            visible: Media.playing && !!Media.active
                            text: Media.active ? "\u{f075a}  " + (Media.active.trackTitle || "") + (Media.active.trackArtist ? " · " + Media.active.trackArtist : "") : ""
                            font.family: Theme.fontText
                            font.pixelSize: Math.round(win.height * 0.017)
                            color: Qt.rgba(1, 1, 1, 0.6)
                            leftPadding: 6; topPadding: 10
                        }
                        // Bottom-left third at first, then a new place each minute.
                        x: win.width * 0.07; y: win.height * 0.62
                        Behavior on x { NumberAnimation { duration: 6000; easing.type: Easing.InOutSine } }
                        Behavior on y { NumberAnimation { duration: 6000; easing.type: Easing.InOutSine } }
                        // Each screen on its own rhythm (45–75 s, new each time), so
                        // two monitors don't move in lockstep; always fully inside a
                        // 6 % margin (it could be placed with its date past the edge).
                        Timer {
                            interval: 45000 + Math.random() * 30000; repeat: true
                            running: root.showing && !Theme.reduceMotion
                            onTriggered: {
                                const m = 0.06;
                                const maxX = Math.max(win.width * m, win.width * (1 - m) - face.width);
                                const maxY = Math.max(win.height * m, win.height * (1 - m) - face.height);
                                face.x = win.width * m + Math.random() * (maxX - win.width * m);
                                face.y = win.height * m + Math.random() * (maxY - win.height * m);
                                interval = 45000 + Math.random() * 30000;
                            }
                        }
                    }

                    // Any pointer input: dismiss (and keep it from reaching a window).
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.AllButtons
                        property point last: Qt.point(-1, -1)
                        onPositionChanged: m => {
                            if (last.x >= 0 && (Math.abs(m.x - last.x) > 3 || Math.abs(m.y - last.y) > 3)) root.dismiss();
                            last = Qt.point(m.x, m.y);
                        }
                        onPressed: root.dismiss()
                        onWheel: root.dismiss()
                        cursorShape: Qt.BlankCursor
                    }
                }
            }
        }
    }
}
