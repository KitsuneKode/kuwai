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
import Quickshell.Wayland
import Quickshell.Services.Greetd
import qs.modules.lock

ShellRoot {
    id: root

    readonly property string user: Quickshell.env("KUWAI_GREETER_USER") || "kitsunekode"
    readonly property string name: user
    readonly property string face: Quickshell.env("KUWAI_GREETER_FACE") || ""
    readonly property string wallpaper: Quickshell.env("KUWAI_GREETER_WALL") || "/usr/share/sddm/themes/sddm-astronaut-theme/Backgrounds/post-apocalyptic_hacker.png"
    readonly property color accent: Quickshell.env("KUWAI_GREETER_ACCENT") || "#fc2e64"
    // What your session will show first: its wallpaper (greeter/sync copies it).
    readonly property string desktopWall: Quickshell.env("HOME") + "/.cache/hyde/wall.set"
    readonly property string session: Quickshell.env("KUWAI_SESSION") || "exec start-hyprland"
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

    function submit() {
        if (checking || leaving || password === "") return;
        if (!Greetd.available) { fail("greetd isn't running"); return; }
        error = "";
        checking = true;
        Greetd.createSession(user);
    }
    function fail(message) {
        checking = false;
        password = "";
        error = message;
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
            if (responseRequired) Greetd.respond(echoResponse ? root.user : root.password);
            else if (error) root.error = message;
        }
        function onAuthFailure(message) { root.fail("Incorrect password"); }
        function onError(error) { root.fail("Couldn't log in (" + error + ")"); }
        function onReadyToLaunch() {
            root.password = "";
            root.leaving = true;      // the views play their outro, into your wallpaper
            handoff.start();
        }
    }
    // After the outro: unlock (quitting while locked would flash Hyprland's
    // "lockscreen died" screen) and hand over to the session.
    Timer {
        id: handoff
        interval: 1100
        onTriggered: {
            root.locked = false;
            // greetd joins these with spaces into `sh -c "…profile…; exec <them>"`,
            // so they're one shell line, quoted for that: separate argv words
            // (sh -c 'script' sh arg) fall apart into `sh -c exec`, which
            // ends the session at once, and greetd shows the login again.
            Greetd.launch(['"${SHELL:-/bin/sh}"', "-l", "-c", "'" + root.session.replace(/'/g, "'\\''") + "'"], [], true);
        }
    }

    // The session lock: one surface per screen, keyboard on whichever has
    // the pointer, and nothing else drawn or reachable meanwhile.
    WlSessionLock {
        locked: Greetd.available && root.locked
        WlSessionLockSurface {
            color: "black"
            GreeterView { anchors.fill: parent; lock: root }
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
