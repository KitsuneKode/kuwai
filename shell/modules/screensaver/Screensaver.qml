// The screensaver: a step of the idle ladder (services/Idle: saver → fade →
// lock, the lock at its usual time), and while Caffeine keeps the machine
// awake it comes after Settings.screensaverMins alone. It fades in your
// wallpaper, still (the default) or live, a scene or a film, with a large
// clock that moves a little every minute (no burn-in), the date and what's
// playing. Any key, click, scroll or move dismisses it, swallowed.
//
//   Settings.screensaverWhen: "always"   (default: before the fade and lock)
//                             "caffeine" (only while Caffeine is on)
//                             "off"
// Never over a fullscreen window (a film with Caffeine on stays a film).
// `kuwai screensaver` shows it now.
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.UPower
import Quickshell.Services.Pipewire
import qs.config
import qs.components
import qs.services
import "saverPhotos.mjs" as Photos

Scope {
    id: root

    readonly property bool allowed: Idle.saverAllowed
    property bool forced: false
    onFullscreenAnywhereChanged: if (fullscreenAnywhere) { forced = false; wakeGrace = false; }
    // hasFullscreen is live (Hyprland events). lastIpcObject was a snapshot
    // that only refreshed on request: one fullscreen video earlier kept it
    // "true", and the screensaver never came again (nor `kuwai screensaver`).
    readonly property bool fullscreenAnywhere: Hyprland.workspaces.values.some(w => w.hasFullscreen
        && Hyprland.monitors.values.some(m => m.activeWorkspace === w))
    // Put away by hand (`kuwai screensaver stop`, a key or the pointer on it)
    // while the session is still idle: it stays away until you have been back.
    // Without this, stop only ended a saver that start had forced; one that
    // idleness brought up came straight back, because nothing had been typed.
    property bool dismissed: false
    readonly property bool showing: (forced || wakeGrace || (allowed && idleShown && !dismissed))
        && !fullscreenAnywhere && !Saver.locked && !Saver.screensOff && (forced || !Idle.appHeld)

    IdleMonitor {
        id: idle
        // Not while you're dictating: speaking is no input, and the saver
        // came up mid-sentence.
        enabled: root.allowed && !Activities.voxBusy
        timeout: Idle.saverAfter
        // Caffeine is an inhibitor of our own: idle still counts here.
        respectInhibitors: false
        onIsIdleChanged: {
            if (isIdle) { root.idleShown = true; return; }
            const up = (root.forced || (root.idleShown && !root.dismissed)) && !root.fullscreenAnywhere && !Saver.locked && !Saver.screensOff;
            root.forced = false; root.dismissed = false; root.idleShown = false;
            if (up) { root.wakeGrace = true; graceEnd.restart(); }
        }
    }
    property bool idleShown: false
    property bool wakeGrace: false
    Timer { id: graceEnd; interval: 250; onTriggered: root.wakeGrace = false }
    function mediaTouched() { if (!wakeGrace) return; graceEnd.stop(); wakeGrace = false; forced = true; }
    Connections { target: Media; function onPlayingChanged() { root.mediaTouched(); } function onActiveChanged() { root.mediaTouched(); } }
    Connections { target: Media.active; ignoreUnknownSignals: true; function onTrackTitleChanged() { root.mediaTouched(); } }
    PwObjectTracker { objects: root.showing ? [Pipewire.defaultAudioSink] : [] }
    Connections {
        target: Pipewire.defaultAudioSink ? Pipewire.defaultAudioSink.audio : null
        ignoreUnknownSignals: true
        function onVolumeChanged() { root.mediaTouched(); }
        function onMutedChanged() { root.mediaTouched(); }
    }

    // What to play: the live wallpaper's pick, else the still wallpaper.
    readonly property string stateDir: Paths.stateHome
    property string video: ""
    FileView {
        path: root.stateDir + "/live-wallpaper/last"
        watchChanges: true; printErrors: false
        onFileChanged: reload()
        onLoaded: root.video = text().trim()
        onLoadFailed: root.video = ""
    }
    readonly property bool useVideo: video !== "" && (!UPower.onBattery || Settings.liveOnBattery)
    readonly property string style: Settings.screensaverStyle || "still"   // "still" · "live" · "dusk" · "borealis" · "night" · "photos"
    // Night: a dark film from ~/.local/share/kuwai-data/screensavers (seamless
    // half-speed loops, ~3–7 Mbit/s: cheap to decode, made by kuwai's setup).
    readonly property string clipDir: Quickshell.env("HOME") + "/.local/share/kuwai-data/screensavers"
    readonly property string clip: clipDir + "/" + (Settings.screensaverClip || "smoke-soft") + ".mp4"
    // The film didn't start (the file is missing, or the player died): Dusk instead, for this
    // showing only. It was for the whole session: one failure (a film folder that wasn't
    // there yet) kept Dusk on screen after the film was back and the setting had been
    // changed to it again, which looked like the setting doing nothing.
    property bool clipFailed: false
    // Before that, one more try decoded on the CPU, and the CPU from then on (until the shell
    // restarts). The GPU's decoder takes ~226 MB per player (one per screen) and asks for more
    // when the film first loops: with a dictation model or a game holding most of a 6 GB card
    // that ask failed ("Cannot allocate memory") at exactly the film's length, 7 of 9 failures
    // here, so the film stopped mid-show and Dusk came instead. Learnt once, not per showing:
    // retrying the GPU each time cut every showing at its first loop. On the CPU: no video
    // memory, about twice the CPU (measured, a 1440p film: 9 % → 18 % of a core).
    property bool filmOnCpu: false
    function filmFresh() { clipFailed = false; }
    onClipChanged: filmFresh()
    onStyleChanged: filmFresh()
    onVideoChanged: filmFresh()
    // The screen you were on when it came up: the one Live plays on.
    property string mainScreen: ""
    property bool dimmedHere: false
    onShowingChanged: {
        if (showing) { mainScreen = Screens.focusedName; filmFresh(); longFade.stop(); longLevel = 0; }
        else longBlack = false;
        Saver.showing = showing;
        if (!showing && dimmedHere) { dimmedHere = false; if (Dim.wanted) Dim.up(); }
    }
    readonly property string still: Hyde.wallpaper ? "file://" + Hyde.wallpaper : ""   // none: black
    property var photoPaths: []
    property bool photosListed: false
    readonly property var photoSet: photoPaths.length ? photoPaths : (Hyde.wallpaper ? [Hyde.wallpaper] : [])
    Process {
        running: root.showing && root.style === "photos"
        command: [Paths.bin + "/kuwai-saver-photos", Settings.screensaverFolder]
        stdout: StdioCollector {
            onStreamFinished: {
                let got = [];
                try { got = JSON.parse(text); } catch (e) {}
                if (!Array.isArray(got)) got = [];
                if (got.join("\n") !== root.photoPaths.join("\n")) root.photoPaths = got;
                root.photosListed = true;
            }
        }
    }

    // ── The film (Night, Live) plays in its own process ──────────────────
    // A player inside the shell kept ~110 MB for good after it stopped
    // (measured); a separate process gives all of it back when killed.
    // mpv plays it when mpvpaper is installed: ONE player and one decoder for
    // every screen (mpvpaper '*' draws one decode on each output), decoding on
    // the GPU and copying frames back. shell-saver/ (Qt's player) had one
    // decoder per screen: 888 MiB of video memory for two screens (nvidia-smi,
    // 2026-11-20), the card's last free gigabyte beside a dictation model;
    // one copy-back decoder measured 284 MiB at 3 % of a core (decoding on the
    // CPU instead: none, 17 %). mpv falls back to the CPU by itself when the
    // GPU's decoder fails mid-film. Without mpvpaper, shell-saver/ still plays.
    property bool mpvSaver: false
    Process {
        command: ["sh", "-c", "command -v mpvpaper"]
        running: true
        onExited: code => root.mpvSaver = code === 0
    }
    readonly property string film: style === "night" && !clipFailed ? clip
        : style === "live" && useVideo && !clipFailed ? video : ""
    // The film starts once the screen has gone dark (the black over it fades
    // out once it plays, below), so it never cuts in over the desktop.
    readonly property bool darkened: level >= 0.999
    readonly property string wantedFilm: showing && darkened && !longDark ? film : ""
    property real filmCover: 1
    property bool filmShown: false
    onActiveFilmChanged: if (activeFilm === "") { coverOut.stop(); filmCover = 1; filmShown = false; firstFrame.stop(); mpvIpc.connected = false; }
    readonly property string ipcPath: Paths.runtime + "/kuwai/saver-mpv/ipc"
    function reveal() {
        if (filmShown || activeFilm === "") return;
        filmShown = true;
        firstFrame.stop();
        coverOut.restart();
    }
    Socket {
        id: mpvIpc
        path: root.ipcPath
        onConnectedChanged: if (connected) { write('{"command":["observe_property",1,"playback-time"]}\n'); flush(); }
        parser: SplitParser {
            onRead: data => {
                let m = null;
                try { m = JSON.parse(data); } catch (e) { return; }
                if (m && m.event === "property-change" && m.name === "playback-time" && typeof m.data === "number" && m.data > 0) {
                    root.reveal();
                    mpvIpc.connected = false;
                }
            }
        }
    }
    Timer {
        id: firstFrame
        property int waited: 0
        interval: 250; repeat: true
        onTriggered: {
            waited += interval;
            if (!mpvIpc.connected) mpvIpc.connected = true;
            if (waited >= 8000) {
                stop();
                console.warn("screensaver: the film drew nothing in 8 s; trying again without it");
                filmProc.signal(9);
            }
        }
    }
    SequentialAnimation {
        id: coverOut
        PauseAnimation { duration: Theme.ambientFadeMs }   // a beat for the first frames
        NumberAnimation { target: root; property: "filmCover"; to: 0; duration: Theme.ambientFadeMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
    }
    property string activeFilm: ""
    property bool filmStopping: false
    onWantedFilmChanged: syncFilm()
    function syncFilm() {
        if (filmStopping || activeFilm === wantedFilm) return;
        if (filmProc.running || activeFilm !== "") {
            filmStopping = true;
            filmProc.signal(9);
        } else if (wantedFilm !== "") {
            activeFilm = wantedFilm;
            filmProc.running = true;
        }
    }
    function filmExited(code) {
        const failed = !filmStopping && activeFilm !== "" && wantedFilm === activeFilm;
        const missing = code === 66 || code === 65;   // no such file, or no picture in it: the CPU won't do better
        filmStopping = true;
        activeFilm = "";
        if (failed && !filmOnCpu && !missing) {
            console.warn("screensaver: the film stopped on the GPU's decoder; the CPU decodes films from now on");
            filmOnCpu = true;
        } else if (failed) {
            console.warn("screensaver: the selected film didn't start or stopped; showing Dusk");
            clipFailed = true;
        }
        filmStopping = false;
        Qt.callLater(root.syncFilm);
    }
    // mpv's options: no config of yours (its own empty MPV_HOME), the plainest
    // picture (profile=fast), and the GPU's decoder copying back unless the
    // CPU was learnt (filmOnCpu: no video memory at all).
    readonly property string mpvOptions: "really-quiet no-audio loop-file=inf panscan=1.0 profile=fast load-scripts=no osc=no cache=no"
        + " demuxer-max-bytes=16MiB demuxer-max-back-bytes=0 hwdec=" + (filmOnCpu ? "no" : "auto-copy-safe")
        + " input-ipc-server=" + ipcPath
    Process {
        id: filmProc
        // A missing file never starts it (test -r; exit 66 goes straight to Dusk).
        // mpvpaper never exits on a file mpv can't open (it waits for it), so a
        // file with no picture in it is refused first (ffprobe; exit 65, Dusk).
        // pdeathsig: the film dies with the shell. Without it, a shell killed
        // while the screensaver showed (a restart, `kuwai promote`) left the
        // film orphaned, covering a monitor for hours; input couldn't reach it.
        // mpvpaper's surfaces take no input (an empty region) and no keyboard.
        command: root.mpvSaver
            ? ["sh", "-c", 'test -r "$KUWAI_SAVER_FILE" || exit 66; '
                + 'if command -v ffprobe >/dev/null; then ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$KUWAI_SAVER_FILE" 2>/dev/null | grep -q . || exit 65; fi; '
                + 'home="${XDG_RUNTIME_DIR:?}/kuwai/saver-mpv"; (umask 077; mkdir -p "$home") || exit 1; '
                + 'MPV_HOME="$home" exec setpriv --pdeathsig KILL mpvpaper -l top -o "$1" "*" "$KUWAI_SAVER_FILE" </dev/null >/dev/null 2>&1', "kuwai-saver", root.mpvOptions]
            : ["sh", "-c", 'test -r "$KUWAI_SAVER_FILE" || exit 66; exec setpriv --pdeathsig KILL qs -p "$1"', "kuwai-saver", Quickshell.shellDir + "/../shell-saver"]
        onStarted: {
            if (!root.mpvSaver) { root.reveal(); return; }
            firstFrame.waited = 0;
            firstFrame.restart();
        }
        // Every screen: one screen with the film and the other black read as
        // "the screensaver only came up on one monitor". It's a separate
        // process, killed on wake, so the second decoder costs nothing after.
        // Basic render loop: the threaded one leaks per frame on NVIDIA (bin/kuwai-shell).
        // On the CPU: Qt's FFmpeg backend tries no hardware decoder for an unknown device type.
        environment: root.filmOnCpu
            ? ({ KUWAI_SAVER_FILE: root.activeFilm, KUWAI_SAVER_SCREEN: "*", QSG_RENDER_LOOP: "basic", QT_FFMPEG_DECODING_HW_DEVICE_TYPES: "none" })
            : ({ KUWAI_SAVER_FILE: root.activeFilm, KUWAI_SAVER_SCREEN: "*", QSG_RENDER_LOOP: "basic" })
        onExited: (exitCode, exitStatus) => root.filmExited(exitCode)
    }
    property bool longBlack: false
    property real longLevel: 0
    readonly property bool longDark: longLevel >= 0.999
    Timer {
        interval: Idle.saverLongAfter * 1000
        running: root.showing && Idle.saverLongAfter > 0 && !root.longBlack
        onTriggered: root.longBlack = true
    }
    onLongBlackChanged: if (longBlack) longFade.restart()
    NumberAnimation { id: longFade; target: root; property: "longLevel"; to: 1; duration: Theme.saverLongFadeMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeInOut }
    // ── Dim after a while: "Dim the screen" in, every screen down (services/Dim),
    // back where it was on wake.
    Timer {
        interval: Math.max(60, Idle.dimAfter) * 1000
        running: root.showing && !Dim.wanted && Idle.dimAfter > 0
        onTriggered: { root.dimmedHere = true; Dim.down(); }
    }

    // SIGKILL, never SIGTERM: Quickshell can crash on a polite exit and its
    // crash handler would relaunch the film (bin/kuwai-shell has the story).
    Component.onDestruction: if (filmProc.running) filmProc.signal(9)
    function dismiss() { forced = false; wakeGrace = false; dismissed = true; }
    IpcHandler {
        target: "screensaver"
        // (Not show/hide: `qs ipc … show` is the CLI's own "list functions".)
        function start(): void { root.forced = true; }
        function stop(): void { root.dismiss(); }
    }

    property real level: showing ? 1 : 0
    Behavior on level { NumberAnimation { duration: root.showing ? 900 : 220; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
    readonly property bool veiling: !Theme.reduceMotion && level > 0.02 && level < 0.999

    Variants {
        model: Quickshell.screens
        LazyLoader {
            id: slot
            required property ShellScreen modelData
            active: root.showing || root.level > 0
            PanelWindow {
                id: win
                screen: slot.modelData
                anchors { top: true; bottom: true; left: true; right: true }
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.namespace: "kuwai.screensaver"   // not kuwai-*: those blur what's behind past 0.3 alpha, and the vignette crossed it (a blurred lower third)
                WlrLayershell.keyboardFocus: root.showing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
                color: "transparent"

                Item {
                    id: stage
                    anchors.fill: parent
                    opacity: Theme.reduceMotion ? root.level : root.veiling || root.level >= 0.999 ? 1 : 0
                    focus: true
                    layer.enabled: root.veiling
                    layer.effect: ShaderEffect {
                        property color accent: Theme.accent
                        property vector2d size: Qt.vector2d(stage.width, stage.height)
                        property vector2d center: Qt.vector2d(stage.width / 2, stage.height / 2)
                        property real mode: 3
                        property real t: root.level
                        property real radius: 0
                        fragmentShader: Qt.resolvedUrl("../../shaders/portal.frag.qsb")
                    }
                    Keys.onPressed: e => { root.dismiss(); e.accepted = true; }

                    // The film's screen stays clear: the film is under this
                    // surface (its own process, Top layer).
                    // (The film wanted, not yet started: the screen darkens first.)
                    readonly property bool filmHere: root.film !== ""
                    Rectangle { anchors.fill: parent; color: "black"; opacity: stage.filmHere ? root.filmCover : 1; visible: opacity > 0.001 }

                    // What fills the screen: the Dusk scene (default, drawn live,
                    // nothing to decode), your live wallpaper, or the still one.
                    readonly property bool stillHere: root.style === "still"
                    readonly property bool photosHere: root.style === "photos"
                    // Night and Live: the film on every screen (the saver process).
                    // The drawn scenes are ambient: clouds that cross the sky in
                    // minutes, stars, petals. Drawn at the screen's own rate they
                    // cost a third of a core for as long as you were away (33–36 %
                    // measured on a 200 Hz and a 165 Hz screen, all night under
                    // Caffeine). So the scene itself is never put on screen: a
                    // picture of it is, taken fifteen times a second. Its
                    // animations run as before; only how often they are drawn
                    // changes. Reduced motion: one picture, then nothing.
                    Loader {
                        id: sceneLoader
                        anchors.fill: parent
                        active: !stage.filmHere && !stage.stillHere && !stage.photosHere && !root.longDark
                        sourceComponent: root.style === "borealis" ? borealisC : duskC
                        onLoaded: sceneFrame.scheduleUpdate()
                        onWidthChanged: sceneFrame.scheduleUpdate()
                        onHeightChanged: sceneFrame.scheduleUpdate()
                    }
                    ShaderEffectSource {
                        id: sceneFrame
                        anchors.fill: parent
                        visible: sceneLoader.active
                        sourceItem: sceneLoader
                        hideSource: true
                        live: false
                        readonly property int frameMs: 66
                        Timer {
                            interval: sceneFrame.frameMs; repeat: true
                            running: root.showing && sceneLoader.active && !Theme.reduceMotion
                            onTriggered: sceneFrame.scheduleUpdate()
                        }
                    }
                    Component { id: duskC; DuskScene { running: root.showing } }
                    Component { id: borealisC; BorealisScene { running: root.showing } }
                    Loader {
                        anchors.fill: parent
                        active: stage.photosHere && root.photosListed && !root.longDark
                        sourceComponent: PhotoShuffle {
                            paths: root.photoSet
                            running: root.showing && !root.longBlack
                            holdMs: Photos.holdMs(Settings.screensaverPhotoMins)
                        }
                    }
                    Image {
                        visible: stage.stillHere
                        anchors.fill: parent
                        source: stage.stillHere && !root.longDark ? root.still : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        // Decoded once at a sensible size (and cached): it was
                        // full size, uncached, on every appearance.
                        sourceSize: Qt.size(Math.min(win.width, 1920), Math.min(win.height, 1080))
                        scale: 1.06
                        NumberAnimation on scale {
                            running: stage.stillHere && root.showing && !root.longBlack && !Theme.reduceMotion
                            from: 1.06; to: 1.12; duration: Theme.saverZoomMs
                            easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeSine
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

                    Rectangle { anchors.fill: parent; color: "black"; opacity: root.longLevel; visible: opacity > 0.001 }

                    // The clock: large, light, and somewhere new each minute.
                    Column {
                        id: face
                        spacing: 2
                        opacity: 1 - root.longLevel * (1 - Theme.saverLongDim)
                        property date now: new Date()
                        onVisibleChanged: if (visible) now = new Date()
                        Connections {
                            target: root
                            function onShowingChanged() {
                                if (root.showing) {
                                    face.now = new Date();
                                    saverClock.interval = 60000 - (Date.now() % 60000) + 50;
                                    saverClock.restart();
                                }
                            }
                        }
                        Timer {
                            id: saverClock
                            interval: 60000 - (Date.now() % 60000) + 50
                            running: root.showing
                            onTriggered: { face.now = new Date(); interval = 60000 - (Date.now() % 60000) + 50; restart(); }
                        }
                        Text {
                            textFormat: Text.PlainText
                            text: Dates.clock(face.now)
                            font.family: Theme.fontRounded
                            font.pixelSize: Math.round(win.height * 0.13)
                            font.weight: Font.Light
                            font.features: Theme.numeralFeatures(true, true)
                            color: Qt.rgba(1, 1, 1, 0.92)
                        }
                        Text {
                            textFormat: Text.PlainText
                            text: Dates.longDate(face.now)
                            font.family: Theme.fontText
                            font.pixelSize: Math.round(win.height * 0.022)
                            color: Qt.rgba(1, 1, 1, 0.7)
                            leftPadding: 6
                        }
                        Text {
                            textFormat: Text.PlainText
                            visible: Weather.ok && !root.longDark
                            opacity: 1 - root.longLevel
                            text: Weather.glyph + "  " + Weather.temp + "°" + (Weather.desc ? " · " + Weather.desc : "")
                            font.family: Theme.fontText
                            font.pixelSize: Math.round(win.height * 0.017)
                            color: Qt.rgba(1, 1, 1, 0.6)
                            leftPadding: 6; topPadding: 10
                        }
                        Text {
                            readonly property var next: Calendar.nextAfter(face.now.getTime(), 12 * 3600000)
                            readonly property bool named: Settings.notifPrivacy === "never" && !Notifs.sharing
                            textFormat: Text.PlainText
                            visible: !!next && !root.longDark
                            opacity: 1 - root.longLevel
                            text: next ? "\u{f00f0}  " + (named ? Dates.time(next.start) + " · " + next.title : "Next event at " + Dates.time(next.start)) : ""
                            elide: Text.ElideRight
                            width: Math.min(implicitWidth, win.width * 0.4)
                            font.family: Theme.fontText
                            font.pixelSize: Math.round(win.height * 0.017)
                            color: Qt.rgba(1, 1, 1, 0.6)
                            leftPadding: 6; topPadding: 10
                        }
                        Text {
                            textFormat: Text.PlainText
                            visible: Media.playing && !!Media.active && !root.longDark
                            opacity: 1 - root.longLevel
                            text: Media.active ? "\u{f075a}  " + (Media.title(Media.active)) + (Media.active.trackArtist ? " · " + Media.active.trackArtist : "") : ""
                            elide: Text.ElideRight
                            width: Math.min(implicitWidth, win.width * 0.4)
                            font.family: Theme.fontText
                            font.pixelSize: Math.round(win.height * 0.017)
                            color: Qt.rgba(1, 1, 1, 0.6)
                            leftPadding: 6; topPadding: 10
                        }
                        // Bottom-left third at first, then a new place each minute.
                        x: win.width * 0.07; y: win.height * 0.62
                        Behavior on x { NumberAnimation { duration: Theme.saverMoveMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeSine } }
                        Behavior on y { NumberAnimation { duration: Theme.saverMoveMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeSine } }
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
                    // Any key dismisses it too; for a screen reader it is one button.
                    Accessible.role: Accessible.Button
                    Accessible.name: "Screen saver"
                    Accessible.description: "Press to wake"
                    Accessible.onPressAction: root.dismiss()
                }
            }
        }
    }
}
