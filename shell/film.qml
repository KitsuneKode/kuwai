// Films the login and lock screens for the README (greeter/preview runs it,
// in a throwaway HOME and runtime dir): a window draws one scene with a
// stand-in for the lock's state, plays its scripted beats, and saves a
// frame as often as it can, each named for the ms it was taken at, so the
// GIFs keep real timing. Nothing is locked and nobody is logged in.
//
//   SCENE=lock-unlock LENGTH=3000 OUT=/tmp/frames [FULL=1] qs -p shell/film.qml
//
// Scenes: login-intro, login-ask, login-error, login-handoff, login-reboot,
// login-poweroff, login-suspend, login-hold (Restart held, then its goodbye), lock-locking, lock-unlock,
// lock-charge, lock-timer, lock-notifs, island-device. Frames are 960×540 BMP (PNG is too
// slow to keep up), or 1920×1080 with FULL.
import QtQuick
import Quickshell
import qs.config
import qs.components
import qs.services
import qs.modules.lock
import qs.modules.island

ShellRoot {
    id: root
    readonly property string scene: Quickshell.env("SCENE")
    readonly property string out: Quickshell.env("OUT")
    readonly property int length: +(Quickshell.env("LENGTH") || 2000)
    readonly property bool isLock: scene.startsWith("lock")
    readonly property bool isIsland: scene.startsWith("island")

    property bool locked: true
    property bool leaving: false
    property string password: ""
    property bool checking: false
    property string error: ""
    property int failures: 0
    property string farewell: ""
    readonly property string name: "kitsunekode"
    readonly property string face: Quickshell.env("HOME") + "/.face"
    readonly property string wallpaper: "/usr/share/sddm/themes/sddm-astronaut-theme/Backgrounds/post-apocalyptic_hacker.png"
    readonly property string desktopWall: Quickshell.env("HOME") + "/.cache/hyde/wall.set"
    readonly property color accent: "#fc2e64"
    function submit() {}
    function power(a) { farewell = a; }
    function powered() {}

    function find(item, fn) {
        if (item[fn] !== undefined && typeof item[fn] === "function") return item;
        for (const c of item.children) { const r = find(c, fn); if (r) return r; }
        return null;
    }
    function findAll(item, fn, out) {
        out = out || [];
        if (item[fn] !== undefined && typeof item[fn] === "function") out.push(item);
        for (const c of item.children) findAll(c, fn, out);
        return out;
    }
    function at(ms, fn) { const t = Qt.createQmlObject("import QtQuick; Timer {}", root); t.interval = ms; t.triggered.connect(fn); t.start(); }

    FloatingWindow {
        id: win
        implicitWidth: 1920; implicitHeight: 1080
        color: "black"
        Loader {
            id: look
            width: 1920; height: 1080
            sourceComponent: root.isIsland ? islandC : root.isLock ? lockC : greetC
        }
        // The island alone, over your wallpaper: rest, and a device's card.
        Component {
            id: islandC
            Item {
                id: isl
                width: 1920; height: 1080
                Image { anchors.fill: parent; source: "file://" + root.desktopWall; sourceSize: Qt.size(1920, 1080); fillMode: Image.PreserveAspectCrop }
                readonly property bool open: Moments.card !== null
                property var keep: null
                Connections { target: Moments; function onCardChanged() { if (Moments.card) isl.keep = Moments.card; } }
                Spring { id: grow; tier: isl.open ? Theme.surfaceIn : Theme.surfaceOut; epsilon: 0.001; target: isl.open ? 1 : 0 }
                Item {
                    id: fr
                    readonly property real w: 190 + 230 * grow.value
                    width: w + 18; height: 34 + 50 * grow.value
                    x: Math.round((isl.width - width) / 2)
                    NotchShape { w: fr.w; h: fr.height; ear: 9; radius: fr.height <= 35 ? 14 : 30; fill: Qt.rgba(0, 0, 0, 0.94) }
                    Item {
                        x: 9; width: fr.w; height: fr.height; clip: true
                        DeviceCard {
                            x: Math.round((parent.width - 420) / 2)
                            item: Moments.card || isl.keep
                            bar: ({ screenName: "" })
                            opacity: Math.max(0, Math.min(1, (grow.value - 0.3) / 0.5))
                        }
                    }
                }
            }
        }
        Component { id: lockC; LockView { lock: root; preview: root.scene !== "lock-locking" } }
        Component { id: greetC; GreeterView { lock: root; preview: root.scene !== "login-intro" } }

        property real t0: 0
        property int n: 0
        property bool busy: false
        property real lastT: -1000
        Timer {
            running: true; interval: 8; repeat: true
            onTriggered: {
                if (!win.t0) win.t0 = Date.now();
                const t = Date.now() - win.t0;
                if (t > root.length) { if (!win.busy) Qt.quit(); return; }
                // 40 fps is plenty for a GIF (and full-size BMPs are 6 MB each).
                if (win.busy || t - win.lastT < 25) return;
                win.lastT = t;
                win.busy = true;
                const k = win.n++;
                look.item.grabToImage(r => { r.saveToFile(root.out + "/" + String(k).padStart(4, "0") + "-" + t + ".bmp"); win.busy = false; }, Quickshell.env("FULL") ? Qt.size(1920, 1080) : Qt.size(960, 540));
            }
        }
    }

    Timer {
        id: typing
        property int k: 0
        interval: 130; repeat: true
        onTriggered: { root.password = "hunter22".slice(0, ++k); if (k >= 8) stop(); }
    }
    function note(app, title, body, severity, ago) {
        return { nid: Math.floor(Math.random() * 1e6), time: Date.now() - (ago || 0) * 60000, app: app, title: title, body: body,
                 severity: severity, urgency: 1, hasDefault: true, actions: [], discard: false, icon: "" };
    }

    Component.onCompleted: {
        const s = scene;
        if (s === "login-ask") at(400, () => find(look.item, "ask").ask());
        if (s === "login-error") { at(300, () => typing.start()); at(1500, () => checking = true); at(2100, () => { checking = false; password = ""; error = "Incorrect password"; failures++; }); }
        if (s === "login-handoff") { at(100, () => find(look.item, "ask").ask()); at(1000, () => { password = ""; leaving = true; }); }
        if (s === "login-hold") at(300, () => {
            const btn = findAll(look.item, "fired")[1];
            const a = Qt.createQmlObject("import QtQuick; NumberAnimation { property: 'held'; from: 0; to: 1; duration: 800 }", root);
            a.target = btn;
            a.finished.connect(() => farewell = "reboot");
            a.start();
        });
        if (s === "login-reboot") at(300, () => farewell = "reboot");
        if (s === "login-poweroff") at(300, () => farewell = "poweroff");
        if (s === "login-suspend") at(300, () => farewell = "suspend");
        if (s === "lock-unlock") { at(300, () => find(look.item, "ask").ask()); at(900, () => typing.start()); at(2100, () => { password = ""; leaving = true; }); }
        if (s === "lock-charge") at(300, () => find(look.item, "plugged").plugged());
        if (s === "lock-timer") at(300, () => Timers.timers = [{ id: 1, label: "Pizza", start: Date.now(), end: Date.now() + 3000 }]);
        if (s === "island-device") {
            const buds = { key: "wf-c510", glyph: Moments.kindGlyph.earbuds, image: "", title: "WF-C510", state: "Connected", tone: Theme.green, detail: "", battery: 0.8, gone: false };
            at(300, () => Moments.card = buds);
            at(3000, () => Moments.card = null);
            at(3700, () => Moments.card = Object.assign({}, buds, { state: "Disconnected", tone: Theme.textSecondary, detail: "Sound on Built-in Speakers", battery: -1, gone: true }));
            at(6200, () => Moments.card = null);
        }
        if (s === "lock-notifs") {
            Notifs.lastSeen = Date.now() - 3600000;
            const a = note("Battery", "Battery at 10%", "Plug in soon: about 20 minutes left.", "critical", 12);
            const b = Object.assign(note("Discord", "Mia", "the new lock screen is so good", "normal", 6), { groupKey: "discord:mia" });
            const b2 = Object.assign(note("Discord", "Mia", "ship it tonight?", "normal", 3), { groupKey: "discord:mia" });
            const c = note("Messages", "GitHub", "Your verification code is 482913", "normal", 1);
            const t = Object.assign(note("T3 Code", "Refactor the island", "Agent needs approval to run greeter/install", "warning", 0),
                                    { status: "Needs you", statusGlyph: "\u{f0026}", statusTone: "caution" });
            at(300, () => Notifs.items = [a]);
            at(1000, () => Notifs.items = [b, a]);
            at(1700, () => Notifs.items = [b2, b, a]);
            at(2400, () => Notifs.items = [c, b2, b, a]);
            at(3100, () => Notifs.items = [t, c, b2, b, a]);
        }
    }
}
