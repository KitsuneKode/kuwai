// The volume / brightness HUD on the lock screen and the login screen: the
// session's own HUD (modules/osd) is a layer the session lock covers, so
// the keys worked there but showed nothing. A pill near the bottom: the
// glyph, a bar and the value; only when something changes (not on lock),
// gone 1.4 s after the last change.
//
// Volume: PipeWire's default output, when there is one (the login screen's
// greeter user has no sound server: brightness only there). Brightness:
// the laptop panel's backlight in /sys, read every 0.3 s while shown on
// screen (sysfs doesn't notify).
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.config

Item {
    id: hud
    property bool active: true              // the lock / login screen is up
    width: 300; height: 46

    // ── What changed last ────────────────────────────────────────────────
    property string kind: ""                 // "volume" | "brightness"
    property real value: 0
    property bool muted: false
    property bool shown: false
    function show(k, v, m) { kind = k; value = v; muted = !!m; shown = true; hideLater.restart(); }
    Timer { id: hideLater; interval: 1400; onTriggered: hud.shown = false }
    // Nothing on arrival: values settling aren't news.
    property bool armed: false
    Timer { interval: 600; running: hud.active; onTriggered: hud.armed = true }
    onActiveChanged: if (!active) { armed = false; shown = false; }

    // Volume (reactive).
    readonly property var sink: Pipewire.defaultAudioSink
    PwObjectTracker { objects: hud.sink ? [hud.sink] : [] }
    readonly property real vol: sink && sink.audio ? sink.audio.volume : -1
    readonly property bool mute: !!sink && !!sink.audio && sink.audio.muted
    onVolChanged: if (armed && vol >= 0) show("volume", vol, mute)
    onMuteChanged: if (armed && vol >= 0) show("volume", vol, mute)

    // Brightness (polled while active).
    property string backlight: ""
    property real maxB: 0
    property real curB: -1
    Process {
        running: hud.active && hud.backlight === ""
        command: ["sh", "-c", "for d in /sys/class/backlight/*; do [ -r \"$d/brightness\" ] && { echo \"$d\"; cat \"$d/max_brightness\"; exit 0; }; done"]
        stdout: StdioCollector { onStreamFinished: { const l = text.trim().split("\n"); if (l.length >= 2) { hud.backlight = l[0]; hud.maxB = Number(l[1]) || 0; } } }
    }
    FileView { id: bl; path: hud.backlight ? hud.backlight + "/brightness" : ""; printErrors: false
        onLoaded: { const v = Number(text().trim()); if (hud.maxB > 0 && v !== hud.curB) { const first = hud.curB < 0; hud.curB = v; if (!first && hud.armed) hud.show("brightness", v / hud.maxB, false); } } }
    Timer { interval: 300; repeat: true; running: hud.active && hud.backlight !== ""; onTriggered: bl.reload() }

    // The session's lock screen: the brightness controller's own events
    // (bin/rice-brightness, the same feed as the session HUD), so a change on
    // any screen shows, the Acer over DDC included. The keys follow the
    // focused screen, usually the external one, whose change sysfs above
    // never sees: brightness worked there but showed nothing. The login
    // screen has no controller (greeter/keys and ddcFile instead).
    property bool brightnessFeed: false
    Process {
        running: hud.active && hud.brightnessFeed
        command: ["setpriv", "--pdeathsig", "KILL", "--", Paths.bin + "/rice-brightness", "watch", "--part", "osd"]
        stdout: SplitParser {
            onRead: line => {
                let ev;
                try { ev = JSON.parse(line); } catch (e) { return; }
                if (ev.kind === "brightness" && typeof ev.value === "number" && hud.armed) hud.show("brightness", ev.value / 100, false);
            }
        }
    }
    // The login screen's external monitors: greeter/keys writes the value DDC
    // set (sysfs has nothing to watch for them). Empty elsewhere.
    property string ddcFile: ""
    FileView { path: hud.ddcFile; watchChanges: true; printErrors: false
        onFileChanged: reload()
        onLoaded: { const v = parseInt(text()); if (hud.armed && v >= 0) hud.show("brightness", v / 100, false); } }

    // ── The pill ─────────────────────────────────────────────────────────
    opacity: shown ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: hud.shown ? Theme.hudInMs : Theme.hudOutMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
    transform: Translate { y: hud.shown || Theme.reduceMotion ? 0 : 6; Behavior on y { NumberAnimation { duration: Theme.hudInMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } } }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Qt.rgba(0.08, 0.08, 0.09, 0.82)
        border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.1)
    }
    Text {
        id: glyph
        x: 18; anchors.verticalCenter: parent.verticalCenter
        font.family: Theme.fontGlyph; font.pixelSize: 18
        color: hud.muted ? Theme.textTertiary : Theme.textPrimary
        text: hud.kind === "brightness" ? "\u{f00e0}"
            : hud.muted || hud.value <= 0.001 ? "\u{f075f}" : hud.value < 0.34 ? "\u{f057f}" : hud.value < 0.67 ? "\u{f0580}" : "\u{f057e}"
    }
    Rectangle {
        id: track
        anchors { left: glyph.right; leftMargin: 14; right: pct.left; rightMargin: 14; verticalCenter: parent.verticalCenter }
        height: 6; radius: 3
        color: Qt.rgba(1, 1, 1, 0.14)
        Rectangle {
            width: parent.width * Math.max(0, Math.min(1, hud.value)); height: parent.height; radius: 3
            color: hud.muted ? Theme.textTertiary : Theme.textPrimary
            Behavior on width { NumberAnimation { duration: Theme.glideMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
        }
    }
    Text {
        id: pct
        anchors { right: parent.right; rightMargin: 18; verticalCenter: parent.verticalCenter }
        width: 40; horizontalAlignment: Text.AlignRight
        text: hud.muted ? "Muted" : Math.round(hud.value * 100) + "%"
        font.family: Theme.fontText; font.pixelSize: 13; font.weight: Font.DemiBold
        font.features: ({ "tnum": 1 })
        color: Theme.textSecondary
    }
}
