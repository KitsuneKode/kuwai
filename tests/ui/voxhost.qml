import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.services
import qs.modules.voxtype

ShellRoot {
    id: scene
    readonly property string run: Quickshell.env("XDG_RUNTIME_DIR")
    readonly property string custom: Quickshell.env("HOME") + "/config/voxtype/osd/test/Custom.qml"
    property var host: null
    FileView { id: style; path: scene.run + "/voxtype/quickshell-style.json"; printErrors: false }
    FileView { id: daemon; path: scene.run + "/voxtype/state"; printErrors: false }
    FileView { id: customFile; path: scene.custom; printErrors: false }
    Component { id: hostComp; VoxtypeHost {} }

    function version(n) { return 'import QtQuick\nItem { readonly property string version: "' + n + '" }\n'; }
    function shown() {
        if (!host || !host.hosting) return null;
        for (const n in host.osds) if (host.osds[n]) return host.osds[n];
        return null;
    }
    function current() { const o = shown(); return o && o.item ? String(o.item.version) : ""; }
    function fail(why) { console.log("UI_SMOKE_FAILED: voxhost: " + why); Qt.quit(); }

    property var until: null
    property int waited: 0
    property string waitingFor: ""
    function wait(what, test, then) { waitingFor = what; waited = 0; until = { test: test, then: then }; poll.restart(); }
    Timer {
        id: poll
        interval: 100; repeat: true
        onTriggered: {
            const u = scene.until;
            if (!u) { stop(); return; }
            if (u.test()) { stop(); scene.until = null; u.then(); return; }
            if (++scene.waited > 200) scene.fail("timed out waiting for " + scene.waitingFor + " (shown " + scene.current() + ", stale " + (scene.host ? scene.host.stale : "-") + ")");
        }
    }
    function after(ms, then) { pause.then = then; pause.interval = ms; pause.restart(); }
    Timer { id: pause; property var then: null; onTriggered: then() }

    Process {
        running: true
        command: ["mkdir", "-p", scene.run + "/voxtype", scene.run + "/kuwai", Quickshell.env("HOME") + "/config/voxtype/osd/test"]
        onExited: scene.begin()
    }
    function begin() {
        customFile.setText(version("one"));
        style.setText(JSON.stringify({ custom_qml: custom }) + "\n");
        daemon.setText("recording\n");
        wait("the take to be read", () => Activities.voxState === "recording", () => {
            host = hostComp.createObject(scene);
            wait("the HUD to be drawn from the first file", () => current() === "one", hidden);
        });
    }
    function hidden() {
        if (Settings.dictationPill !== "island") return fail("the island isn't the default");
        if (!shown().osdSuppressed) return fail("the pill shows although the island hosts dictation");
        Settings.set("dictationPill", "ticker");
        wait("the pill to come back for the ticker", () => !shown().osdSuppressed, () => {
            Settings.set("dictationPill", "island");
            wait("the pill to hide again", () => shown().osdSuppressed, midTake);
        });
    }
    function midTake() {
        customFile.setText(version("two"));
        wait("the change to be seen", () => host.stale, () => after(4000, () => {
            if (current() !== "one") return fail("the HUD was built again in the middle of a take");
            if (host.generation !== 0) return fail("a rebuild ran while a take was on");
            daemon.setText("idle\n");
            wait("the HUD to be built from the new file once idle", () => current() === "two", () => {
                if (host.generation !== 1) return fail("built " + host.generation + " times");
                if (!shown().osdSuppressed) return fail("the rebuilt pill forgot the island");
                console.log("UI_SMOKE_CAPTURED");
                Qt.quit();
            });
        }));
    }
}
