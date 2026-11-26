// The lock screen (docs/ISLAND.md §9): Wayland's session lock, so nothing
// shows or takes input until PAM says yes. One surface per monitor, one
// password shared between them.
//
//   kuwai lock                     lock now (qs ipc call lock lock)
//
// The default: the shell's idle (services/Idle) and sleep guard lock here;
// hyprlock is only the fallback when the shell isn't up (bin/kuwai lock).
//
// Fail-safe: while locked, Paths.lockFlag exists (this session's, in the
// runtime dir, so it goes at a reboot or logout). If the shell
// dies while locked, Hyprland keeps the session locked (the protocol's
// promise: nothing is ever exposed) and, with misc:allow_session_lock_restore
// (hypr/kuwai/system.lua), lets a new locker take over: Quickshell's crash handler
// restarts the shell, which sees the file and locks again at once. From a
// TTY, `hyprlock` (or `kuwai restart`) does the same. Nothing you were doing
// is closed: the lock only covers the screen.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.Pam
import qs.config
import qs.services

Scope {
    id: root

    property bool locked: false
    onLockedChanged: Saver.locked = locked
    property string password: ""
    property bool checking: false
    property string error: ""
    property int failures: 0            // bumps on every miss: the field shakes
    // The right password: the views play their unlock, then the lock goes.
    property bool leaving: false
    property real lockedAt: Date.now()
    // A notification tapped on the lock screen: opened once you're in.
    property var openAfter: null
    Timer { id: release; interval: Theme.unlockReleaseMs; onTriggered: {
        root.leaving = false;
        root.unlocked();
        if (root.openAfter && !root.openAfter.discard) Notifs.activate(root.openAfter);
        else welcomeLater.restart();
        root.openAfter = null;
    } }
    Timer { id: welcomeLater; interval: 520; onTriggered: { Wellbeing.rested(); Moments.welcomeBack(root.lockedAt); } }

    readonly property string flag: Paths.lockFlag
    function lock() {
        password = ""; error = ""; checking = false;
        release.stop(); leaving = false;
        welcomeLater.stop();
        lockedAt = Date.now();
        openAfter = null;
        mark.command = ["sh", "-c", 'mkdir -p "$(dirname "$1")" && : > "$1"', "sh", flag];
        mark.running = true;
        locked = true;
        fading = false;
        // Type the password in your first layout, not whatever was last on.
        Quickshell.execDetached(["hyprctl", "switchxkblayout", "all", "0"]);
    }
    function unlocked() {
        mark.command = ["rm", "-f", flag];
        mark.running = true;
        locked = false;
    }
    Process { id: mark }
    // Started (or restarted after a crash) while the flag says locked: lock again.
    FileView {
        path: root.flag
        printErrors: false
        onLoaded: if (!root.locked) { console.warn("lock: the session was locked when the shell stopped; locking again"); root.lock(); }
    }
    property string challenge: ""
    property int answers: 0
    function submit() {
        if (leaving || password === "") return;
        if (challenge !== "") {
            const answer = password;
            password = ""; challenge = ""; checking = true;
            pam.respond(answer);
            return;
        }
        if (checking) return;
        error = "";
        checking = true;
        answers = 0;
        pam.start();
    }

    PamContext {
        id: pam
        // The system's login stack (/etc/pam.d/login): what hyprlock's own
        // file includes, without depending on the hyprlock package.
        config: "login"
        onResponseRequiredChanged: {
            if (!responseRequired) return;
            if (root.answers++ === 0) { respond(root.password); return; }
            root.checking = false;
            root.password = "";
            root.challenge = String(message || "Verification code").replace(/[:\s]+$/, "");
        }
        onCompleted: result => {
            root.checking = false;
            root.challenge = "";
            if (result === PamResult.Success) {
                root.password = "";
                root.leaving = true;
                release.restart();
            } else {
                root.password = "";
                root.error = result === PamResult.MaxTries ? "Too many attempts" : "Incorrect password";
                root.failures++;
            }
        }
        onError: err => {
            root.checking = false;
            root.challenge = "";
            root.password = "";
            root.error = "Couldn't check the password. Try again";
            root.failures++;
        }
    }

    // One lock surface per screen. Quickshell only builds those for the
    // screens it already has, and it will not build a new one for a screen
    // it already tracked. Turning the screens off (hypridle) drops the Acer
    // off the bus; it comes back as a new monitor, the old surface died with
    // the old output, and the laptop panel (which never disconnects) is the
    // only place the lock still shows. A new lock from this same process is
    // refused (Quickshell keeps the old one alive so the session can't fail
    // open: "Failed to acquire session lock", and Hyprland's crash screen),
    // so restart the shell instead: the process going away releases the
    // lock, allow_session_lock_restore lets the new one take it, and the
    // flag tells it to. Only once the lock is confirmed: a locker still
    // waiting for "locked" makes Hyprland ignore the next.
    //
    // Quickshell 0.3.2 does give a returning screen its lock surface (Hyprland's
    // log, 2026-11-20: a new lock surface on DP-3 as it came back), and the
    // restart was what you saw: the process holding the lock went away, so
    // Hyprland showed its "lock screen died" screen until the new shell locked
    // again, at every wake while locked. So it restarts only when a screen is
    // still without a lock surface once the screens have settled.
    readonly property bool secure: lockLoader.item ? lockLoader.item.secure : false
    property var lockSurfaces: []        // the live WlSessionLockSurfaces (they register below)
    function uncovered() {
        const have = lockSurfaces.filter(s => s && s.screen).map(s => s.screen.name);
        return Quickshell.screens.map(s => s.name).filter(n => have.indexOf(n) < 0);
    }
    function resurface() {
        if (!locked || !secure) return;
        const missing = uncovered();
        if (!missing.length) {
            console.info("lock: a monitor came back while locked; its lock surface is there");
            return;
        }
        console.warn("lock: " + missing.join(", ") + " came back without a lock surface; restarting the shell to cover it");
        Quickshell.execDetached([Paths.bin + "/kuwai-shell"]);
    }
    Timer { id: relockWait; interval: 2000; onTriggered: root.resurface() }
    Connections {
        target: typeof Hyprland !== "undefined" ? Hyprland : null
        function onRawEvent(event) {
            if (!root.locked) return;
            if (event.name === "monitoradded" || event.name === "monitoraddedv2") relockWait.restart();
        }
    }
    Loader {
        id: lockLoader
        active: true
        sourceComponent: lockFace
    }
    Component {
        id: lockFace
        WlSessionLock {
            locked: root.locked
            WlSessionLockSurface {
                id: lockSurface
                color: Theme.desktop          // under the wallpaper; with none, the desktop's own ground
                Component.onCompleted: root.lockSurfaces = root.lockSurfaces.concat([lockSurface])
                Component.onDestruction: root.lockSurfaces = root.lockSurfaces.filter(x => x !== lockSurface)
                LockView { anchors.fill: parent; lock: root }
            }
        }
    }

    // ── Fade before the lock (hypridle, 15 s ahead): the screens darken
    // slowly; any input is activity, hypridle calls `fade stop`, and the lock
    // never comes. Click-through, so whatever you touch just works.
    property bool fading: false
    Variants {
        model: Quickshell.screens
        LazyLoader {
            id: fadeSlot
            required property ShellScreen modelData
            active: root.fading || fadeOut.running
            PanelWindow {
                screen: fadeSlot.modelData
                anchors { top: true; bottom: true; left: true; right: true }
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.namespace: "kuwai.fade"
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                mask: Region {}
                color: "transparent"
                Rectangle {
                    anchors.fill: parent
                    color: "black"
                    opacity: root.fadeLevel
                }
            }
        }
    }
    property real fadeLevel: 0
    NumberAnimation { id: fadeIn; target: root; property: "fadeLevel"; to: 0.85; duration: Theme.idleDimMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeIn }
    NumberAnimation { id: fadeOut; target: root; property: "fadeLevel"; to: 0; duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
    onFadingChanged: { if (fading) { fadeOut.stop(); fadeIn.restart(); } else { fadeIn.stop(); fadeOut.restart(); } }
    IpcHandler {
        target: "fade"
        function start(): void { if (!root.locked) root.fading = true; }
        function stop(): void { root.fading = false; }
    }

    IpcHandler {
        target: "lock"
        function lock(): void { root.lock(); }
        // "locked" only once the compositor confirms the lock (secure):
        // what `kuwai lock --wait` waits for before the machine may sleep.
        function state(): string { return root.secure ? "locked" : root.locked ? "locking" : "unlocked"; }
    }
}
