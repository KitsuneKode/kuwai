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
        config: "hyprlock"               // the same PAM stack the current lock uses
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

    WlSessionLock {
        id: session
        locked: root.locked
        WlSessionLockSurface {
            color: "black"
            LockView { anchors.fill: parent; lock: root }
        }
    }

    IpcHandler {
        target: "lock"
        function lock(): void { root.lock(); }
        // "locked" only once the compositor confirms the lock (secure):
        // what `rice lock --wait` waits for before the machine may sleep.
        function state(): string { return session.secure ? "locked" : root.locked ? "locking" : "unlocked"; }
    }
}
