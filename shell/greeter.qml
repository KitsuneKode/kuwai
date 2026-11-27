// The login screen (GreeterView), before any session. greetd runs it as its
// own `greeter` user inside a bare Hyprland (greeter/hyprland.lua), from the
// copy greeter/sync keeps in /var/lib/kuwai-greeter (your home isn't
// readable by that user). The password goes to greetd, which runs PAM and,
// once it says yes, starts your session.
//
//   KUWAI_GREETER_USER     who logs in (one user; no picker)
//   KUWAI_GREETER_FACE     their picture (~/.face, copied by greeter/sync)
//   KUWAI_GREETER_WALL     the picture behind it (default: the astronaut
//                          SDDM theme's, which this replaces)
//   KUWAI_GREETER_ACCENT   its accent (default: that picture's pink)
//   KUWAI_SESSION          the session command (default: your login shell
//                          starting Hyprland, as SDDM did)
//
// Without greetd (run by hand) it opens as a window and logs nobody in.
// KUWAI_GREETER_SHOT=file.png renders it to that file and quits; a "%d" in
// the name films the intro instead (a frame every 50 ms).
// KUWAI_GREETER_DEMO=typing|checking|error|leave|suspend|reboot|poweroff
// shows that state.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Greetd
import Quickshell.Services.UPower
import qs.config
import qs.services
import qs.modules.lock
import "services/pamTurn.mjs" as PamTurn
import "services/faillock.mjs" as Faillock

ShellRoot {
    id: root

    readonly property string user: Quickshell.env("KUWAI_GREETER_USER") || Quickshell.env("USER") || ""
    readonly property string name: user
    readonly property string face: Quickshell.env("KUWAI_GREETER_FACE") || ""
    readonly property string wallpaper: Quickshell.env("KUWAI_GREETER_WALL") || ""
    readonly property color accent: Quickshell.env("KUWAI_GREETER_ACCENT") || Theme.loginAccent
    // What your session will show first: its wallpaper (greeter/sync copies it).
    readonly property string desktopWall: Hyde.wallpaper     // "" without one: GreeterView shows the desktop's ground (Theme.desktop)
    // The session, without the terminal in between: clear tty1 and hide its
    // cursor, and preserve startup diagnostics in the journal without
    // flashing compositor output between the login screen and desktop.
    readonly property string session: Quickshell.env("KUWAI_SESSION") || "exec '" + (Quickshell.shellDir + "/../session-start").replace(/'/g, "'\\''") + "'"
    readonly property string handoffId: Date.now().toString(36) + "-" + Math.random().toString(36).slice(2)
    function trace(phase) { console.info("kuwai-handoff", root.handoffId, phase); }
    readonly property string shot: Quickshell.env("KUWAI_GREETER_SHOT") || ""
    readonly property bool film: shot.indexOf("%d") >= 0
    readonly property string demo: Quickshell.env("KUWAI_GREETER_DEMO") || ""

    // What the view reads.
    property bool locked: true
    property bool leaving: false
    property string password: ""
    property bool checking: false
    property string error: ""
    property int failures: 0
    property string farewell: ""      // suspend | reboot | poweroff: the goodbye showing

    property real lockedUntil: 0
    property real now: Date.now()
    readonly property int lockLeft: Math.max(0, Math.ceil((lockedUntil - now) / 1000))
    Timer {
        interval: 1000; repeat: true
        running: root.lockedUntil > root.now
        onTriggered: {
            root.now = Date.now();
            if (root.lockLeft > 0) root.error = Faillock.lockedWords(root.lockLeft);
            else { root.lockedUntil = 0; root.error = ""; }
        }
    }
    property string challenge: ""
    property string note: ""
    property string held: ""
    property bool named: false
    function submit() {
        if (leaving || password === "") return;
        if (lockLeft > 0) { password = ""; failures++; return; }
        if (challenge !== "") {
            const answer = password;
            password = ""; challenge = ""; checking = true;
            Greetd.respond(answer);
            return;
        }
        if (checking) return;
        if (!Greetd.available) { fail("greetd isn't running"); return; }
        error = "";
        note = "";
        held = password;
        named = false;
        checking = true;
        trace("auth-request");
        Greetd.createSession(user);
    }
    function fail(message) {
        trace("failure");
        challenge = "";
        held = "";
        note = "";
        handoff.stop();
        launchAck.stop();
        quitAnyway.stop();
        locked = true;
        leaving = false;
        checking = false;
        password = "";
        error = lockLeft > 0 ? Faillock.lockedWords(lockLeft) : message;
        failures++;
        if (Greetd.state !== GreetdState.Inactive) Greetd.cancelSession();
    }
    // A held power button: the views say goodbye, then (powered) it happens.
    function power(action) {
        if (farewell || leaving) return;
        farewell = action;
    }
    function powered() {
        if (!farewell || poweredOff.running) return;
        if (Greetd.available) Quickshell.execDetached(["systemctl", farewell]);
        poweredOff.restart();
    }
    // Sleep comes back: timers stand still while suspended, so this fires
    // just after the wake and the login screen returns. (Restart and shut
    // down never get here.)
    Timer { id: poweredOff; interval: root.farewell === "suspend" ? 1500 : 30000; onTriggered: root.farewell = "" }

    Connections {
        target: Greetd
        function onAuthMessage(message, error, responseRequired, echoResponse) {
            if (!responseRequired) {
                const mins = PamTurn.lockedMinutes(message);
                if (mins >= 0) { root.now = Date.now(); root.lockedUntil = root.now + mins * 60000; }
                if (error) root.error = message; else root.note = PamTurn.note(message);
                return;
            }
            root.note = "";
            const k = PamTurn.kind(message, echoResponse);
            if (k === "user" && !root.named) { root.named = true; Greetd.respond(root.user); return; }
            if (k === "password" && root.held !== "") { const p = root.held; root.held = ""; Greetd.respond(p); return; }
            root.checking = false;
            root.password = "";
            root.challenge = PamTurn.label(message);
        }
        function onAuthFailure(message) { root.fail("Incorrect password"); }
        function onError(error) { root.trace("error"); root.fail("Couldn't log in. Try again"); }
        function onReadyToLaunch() {
            root.password = "";
            root.held = "";
            root.note = "";
            root.trace("authenticated");
            root.leaving = true;      // the views play their outro, into your wallpaper
            handoff.start();
        }
        function onLaunched() {
            launchAck.stop();
            root.trace("launched");
            endCompositor.running = true;
            quitAnyway.start();
        }
    }
    // After the outro: unlock (quitting while locked would flash Hyprland's
    // "lockscreen died" screen) and hand over to the session. The cover below
    // already shows the outro's last frame, so the unlock changes nothing seen.
    Timer {
        id: handoff
        interval: 1100
        onTriggered: {
            root.trace("launch-request");
            root.locked = false;
            // greetd joins these with spaces into `sh -c "…profile…; exec <them>"`,
            // so they're one shell line, quoted for that: separate argv words
            // (sh -c 'script' sh arg) fall apart into `sh -c exec`, which
            // ends the session at once, and greetd shows the login again.
            Greetd.launch(['"${SHELL:-/bin/sh}"', "-l", "-c", "'" + root.session.replace(/'/g, "'\\''") + "'"], ["KUWAI_HANDOFF_ID=" + root.handoffId], false);
            launchAck.start();
        }
    }
    Timer { id: launchAck; interval: 8000; onTriggered: { root.trace("launch-timeout"); root.fail("Couldn't start your session. Try again"); } }
    // Hyprland is told to end while the cover is still up: it stops drawing
    // at once, so its last frame (your wallpaper) stays on the screens through
    // its ~1 s teardown, where quitting first left its black background.
    Process {
        id: endCompositor
        command: ["hyprctl", "dispatch", "hl.dsp.exit()"]
        onExited: Qt.quit()
    }
    // hyprctl didn't answer: quit the old way (greeter/start ends Hyprland).
    Timer { id: quitAnyway; interval: 3000; onTriggered: Qt.quit() }

    // The outro's last frame (your wallpaper, the welcome) on the overlay
    // layer, made as the outro starts: hidden under the lock until it lifts.
    LazyLoader {
        active: Greetd.available && root.leaving
        Variants {
            model: Quickshell.screens
            PanelWindow {
                required property var modelData
                screen: modelData
                anchors { top: true; bottom: true; left: true; right: true }
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.namespace: "kuwai-greeter-cover"
                color: Theme.desktop          // the desktop's ground under the wallpaper (none: that's what shows)
                Image {
                    id: coverWall
                    anchors.fill: parent
                    source: root.desktopWall ? "file://" + root.desktopWall : ""
                    sourceSize: Qt.size(width, height)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
                LoginWelcome {
                    anchors.centerIn: parent
                    name: root.name
                    visible: coverWall.status === Image.Ready
                }
            }
        }
    }

    // ── Nobody logs in: dim, then screens off, then sleep ────────────────
    // Any key or the pointer brings it back; a password half typed is
    // dropped when the screens go off.
    readonly property bool watchIdle: Greetd.available && locked && !leaving && !checking && !farewell
    property bool dimmed: false
    IdleMonitor {
        enabled: root.watchIdle
        timeout: 30
        onIsIdleChanged: root.dimmed = isIdle
    }
    IdleMonitor {
        enabled: root.watchIdle
        timeout: 60
        onIsIdleChanged: {
            if (isIdle) root.password = "";
            Quickshell.execDetached(["hyprctl", "dispatch", `hl.dsp.dpms({ action = "${isIdle ? "disable" : "enable"}" })`]);
        }
    }
    IdleMonitor {
        enabled: root.watchIdle
        timeout: UPower.onBattery ? 600 : 1200
        onIsIdleChanged: if (isIdle) Quickshell.execDetached(["systemctl", "suspend"])
    }

    // The session lock: one surface per screen, keyboard on whichever has
    // the pointer, and nothing else drawn or reachable meanwhile.
    WlSessionLock {
        locked: Greetd.available && root.locked
        WlSessionLockSurface {
            color: "black"
            GreeterView { anchors.fill: parent; lock: root }
            Rectangle {
                anchors.fill: parent
                color: "black"
                opacity: root.dimmed && root.watchIdle ? 0.6 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: root.dimmed ? Theme.ambientFadeMs : Theme.exitMs } }
            }
        }
    }

    LazyLoader {
        active: !Greetd.available
        FloatingWindow {
            implicitWidth: 1920
            implicitHeight: 1080
            color: "black"
            // A shot is always 1920×1080 (the panel's logical size), whatever
            // size the window was given.
            GreeterView {
                id: look
                width: root.shot ? 1920 : parent.width
                height: root.shot ? 1080 : parent.height
                lock: root
                preview: root.shot !== "" && !root.film
            }
            Timer {
                running: root.shot !== "" && !root.film
                interval: 3500
                onTriggered: look.grabToImage(r => { r.saveToFile(root.shot); Qt.quit(); })
            }
            Timer {
                property int frame: 0
                running: root.film
                interval: 50; repeat: true
                onTriggered: {
                    const n = frame++;
                    look.grabToImage(r => r.saveToFile(root.shot.replace("%d", String(n).padStart(3, "0"))));
                    if (n >= 44) { stop(); Qt.callLater(Qt.quit); }
                }
            }
        }
    }
    Timer { running: root.demo === "leave"; interval: root.film ? 300 : 2000; onTriggered: root.leaving = true }
    Component.onCompleted: {
        if (demo === "typing" || demo === "checking") password = "hunter22";
        if (demo === "checking") checking = true;
        if (demo === "error") { error = "Incorrect password"; failures = 1; }
        if (["suspend", "reboot", "poweroff"].indexOf(demo) >= 0) farewell = demo;
    }
}
