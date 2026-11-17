import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import qs.config

ShellRoot {
    id: fixture
    property int phase: 0
    function check(ok, message) {
        if (!ok) { console.log("UI_SMOKE_FAILED: " + message); Qt.quit(); }
        return ok;
    }
    function edit(body) {
        editor.command = ["python", "-c", "import os,json,pathlib; p=pathlib.Path(os.environ['XDG_CONFIG_HOME'])/'kuwai/settings.json'; " + body];
        editor.running = true;
    }
    Process { id: editor }
    Window {
        id: scene
        visible: true; width: 640; height: 480
        color: Theme.glassIsland
        Text { anchors.centerIn: parent; color: Theme.textPrimary; text: "Private settings round-trip · phase " + fixture.phase }
        Component.onCompleted: {
            Settings.set("favoriteThemes", ["fixture"]);
            Settings.set("clock24", false);
            Settings.set("hoverDelay", 0);
        }
    }
    Timer {
        interval: 50; running: true; repeat: true
        onTriggered: {
            if (editor.running || Settings.pending) return;
            if (fixture.phase === 0) {
                if (!fixture.check(!Settings.error && Settings.clock24 === false && Settings.hoverDelay === 0, "queued writes failed " + Settings.error)) return;
                fixture.edit("d=json.loads(p.read_text()); d['future']=[None,[]]; d['showSeconds']=True; p.write_text(json.dumps(d))");
                fixture.phase = 1;
            } else if (fixture.phase === 1 && Settings.showSeconds) {
                if (!fixture.check(Settings.document.future.length === 2, "external fields missing")) return;
                fixture.edit("p.write_text('{broken')"); fixture.phase = 2;
            } else if (fixture.phase === 2 && Settings.loadError) {
                if (!fixture.check(Settings.clock24 === false && Settings.showSeconds, "malformed reload replaced last good values")) return;
                Settings.set("clock24", true); fixture.phase = 3;
            } else if (fixture.phase === 3 && Settings.writeError) {
                if (!fixture.check(Settings.clock24 === false, "failed write did not roll back")) return;
                fixture.edit("p.write_text(json.dumps({'future':[None,[]],'clock24':False,'hoverDelay':0}))"); fixture.phase = 4;
            } else if (fixture.phase === 4 && !Settings.loadError) {
                Settings.reset("clock24"); Settings.set("textScale", 2); fixture.phase = 5;
            } else if (fixture.phase === 5) {
                if (!fixture.check(!Settings.error && Settings.isDefault("clock24") && Settings.clock24 === true && Settings.textScale === 2 && Settings.document.future.length === 2, "reset/repair lost state " + Settings.error)) return;
                fixture.phase = 6;
                scene.contentItem.grabToImage(result => {
                    console.log(result.saveToFile("/out/primitives.png") ? "UI_SMOKE_CAPTURED" : "UI_SMOKE_FAILED: capture"); Qt.quit();
                });
            }
        }
    }
    Timer { interval: 8000; running: true; onTriggered: { console.log("UI_SMOKE_FAILED: settings lifecycle timed out at " + fixture.phase); Qt.quit(); } }
}
