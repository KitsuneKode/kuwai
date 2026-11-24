pragma Singleton
import QtQuick
import Quickshell
import qs.config

Singleton {
    id: root

    readonly property var cues: ({
        connect: "/usr/share/sounds/freedesktop/stereo/device-added.oga",
        disconnect: "/usr/share/sounds/freedesktop/stereo/device-removed.oga",
        charge: "/usr/share/sounds/freedesktop/stereo/power-plug.oga",
        screenshot: "/usr/share/sounds/freedesktop/stereo/camera-shutter.oga",
        voiceStart: "/usr/share/sounds/freedesktop/stereo/message-new-instant.oga",
        voiceDone: "/usr/share/sounds/freedesktop/stereo/complete.oga",
        alert: "/usr/share/sounds/freedesktop/stereo/dialog-warning.oga",
        timer: "/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga"
    })

    function play(cue, force) {
        if (!force && (Saver.away || Notifs.muted)) return false;
        const path = cues[cue] || "";
        if (!path) return false;
        Quickshell.execDetached([
            "sh", "-c",
            '[ -r "$1" ] || exit 0; command -v pw-play >/dev/null && exec pw-play "$1"; command -v paplay >/dev/null && exec paplay "$1"',
            "sound", path
        ]);
        return true;
    }
}
