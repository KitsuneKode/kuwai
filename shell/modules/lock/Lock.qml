// The lock screen (docs/ISLAND.md §9): Wayland's session lock, so nothing
// shows or takes input until PAM says yes. One surface per monitor, one
// password shared between them.
//
//   rice lock                     lock now (qs ipc call lock lock)
//
// Not the default yet: hypridle still runs hyprlock. If this ever crashes
// while locked, Hyprland keeps the session locked (that is the protocol's
// promise); unlock from a TTY with `hyprctl --instance 0 keyword
// misc:allow_session_lock_restore 1` and `hyprlock`, or run `rice lock` again.
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

    function lock() {
        password = ""; error = ""; checking = false;
        locked = true;
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
                root.locked = false;
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
        function state(): string { return root.locked ? "locked" : "unlocked"; }
    }
}
