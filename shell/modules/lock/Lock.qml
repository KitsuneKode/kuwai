// The lock screen (docs/ISLAND.md §9): Wayland's session lock, so nothing
// shows or takes input until PAM says yes. One surface per monitor, one
// password shared between them.
//
//   rice lock                     lock now (qs ipc call lock lock)
//
// Not the default yet: hypridle still runs hyprlock.
//
// Fail-safe: while locked, ~/.local/state/rice/locked exists. If the shell
// dies while locked, Hyprland keeps the session locked (the protocol's
// promise: nothing is ever exposed) and, with misc:allow_session_lock_restore
// (hypr/kuwai/system.lua), lets a new locker take over: Quickshell's crash handler
// restarts the shell, which sees the file and locks again at once. From a
// TTY, `hyprlock` (or `rice restart`) does the same. Nothing you were doing
// is closed: the lock only covers the screen.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.Pam
import qs.config

Scope {
    id: root

    property bool locked: false
    property string password: ""
    property bool checking: false
    property string error: ""
    property int failures: 0            // bumps on every miss: the field shakes

    readonly property string flag: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/rice/locked"
    function lock() {
        password = ""; error = ""; checking = false;
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
    function submit() {
        if (checking || password === "") return;
        error = "";
        checking = true;
        pam.start();
    }

    PamContext {
        id: pam
        // The system's login stack (/etc/pam.d/login): what hyprlock's own
        // file includes, without depending on the hyprlock package.
        config: "login"
        onResponseRequiredChanged: {
            if (!responseRequired) return;
            respond(root.password);
        }
        onCompleted: result => {
            root.checking = false;
            if (result === PamResult.Success) {
                root.password = "";
                root.unlocked();
            } else {
                root.password = "";
                root.error = result === PamResult.MaxTries ? "Too many attempts" : "Incorrect password";
                root.failures++;
            }
        }
        onError: err => {
            root.checking = false;
            root.password = "";
            root.error = "Couldn't check the password (" + PamError.toString(err) + ")";
            root.failures++;
        }
    }

    // One lock surface per screen. Quickshell only builds those for the
    // screens it already has, and it will not build a new one for a screen
    // it already tracked. Turning the screens off (hypridle) drops the Acer
    // off the bus; it comes back as a new monitor, the old surface died with
    // the old output, and the laptop panel (which never disconnects) is the
    // only place the lock still shows. Drop the locker and take the session
    // back — allow_session_lock_restore is on — once the new output is up.
    readonly property bool secure: lockLoader.item ? lockLoader.item.secure : false
    function resurface() {
        if (!locked) return;
        console.warn("lock: a monitor came back while locked; covering every screen again");
        lockLoader.active = false;
        relockCreate.restart();
    }
    Timer { id: relockWait; interval: 500; onTriggered: root.resurface() }
    Timer { id: relockCreate; interval: 50; onTriggered: if (root.locked) lockLoader.active = true }
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
                color: "black"
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
                WlrLayershell.namespace: "rice-fade"
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
    NumberAnimation { id: fadeIn; target: root; property: "fadeLevel"; to: 0.85; duration: 14000; easing.type: Easing.InQuad }
    NumberAnimation { id: fadeOut; target: root; property: "fadeLevel"; to: 0; duration: 220; easing.type: Easing.OutQuad }
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
        // what `rice lock --wait` waits for before the machine may sleep.
        function state(): string { return root.secure ? "locked" : root.locked ? "locking" : "unlocked"; }
    }
}
