// The lock clock's ground, measured on a real picture (bin/kuwai-ui-test
// --case clock-ground). Three wallpapers painted here (snow, night, a dark
// picture with a bright sky behind the clock), each shown as the lock shows
// it (22 % scrim, ClockGround) with the clock's own text on top; one PNG
// each, and what ClockGround decided. tests/test_rehearse_gate.py reads the
// pictures and measures the text against them.
import QtQuick
import QtQuick.Window
import Quickshell
import qs.components
import qs.config
import qs.modules.lock

ShellRoot {
    Window {
        id: scene
        visible: true
        width: 960; height: 540
        color: "black"
        readonly property var walls: [
            { name: "snow", base: "#f5f5f5", band: "" },
            { name: "night", base: "#0c101e", band: "" },
            { name: "sky", base: "#141418", band: "#ebebf0" }
        ]
        property int at: 0
        property string shown: ""

        // The wallpaper being painted (to a file ClockGround can read as it would a real one).
        Rectangle {
            id: paint
            width: 960; height: 540
            color: scene.walls[scene.at].base
            Rectangle { visible: scene.walls[scene.at].band !== ""; y: 40; width: parent.width; height: 140; color: scene.walls[scene.at].band || "black" }
        }
        // The lock, as far as the clock's ground goes.
        Item {
            id: lock
            anchors.fill: parent
            visible: scene.shown !== ""
            Image { id: wall; anchors.fill: parent; source: scene.shown; fillMode: Image.PreserveAspectCrop; cache: false }
            Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.22) }
            ClockGround { id: ground; anchors.fill: parent; source: wall.source; ink: lock.tint; base: 0.22 }
            readonly property color tint: Qt.tint(Qt.rgba(1, 1, 1, 0.9), Qt.alpha(Theme.accent, 0.35))
            Label {
                id: clock
                anchors.horizontalCenter: parent.horizontalCenter
                y: Math.round(parent.height * 0.14)
                text: "10:10"
                size: Theme.tLockClock / 2; weight: Theme.wBold; rounded: true
                color: lock.tint
            }
        }
        function fail(reason) { console.log("UI_SMOKE_FAILED: " + reason); Qt.quit(); }
        Timer {
            id: step
            interval: 400; running: true
            onTriggered: {
                const w = scene.walls[scene.at];
                if (scene.shown === "") {
                    paint.grabToImage(result => {
                        if (!result.saveToFile("/out/wall-" + w.name + ".png")) { scene.fail("could not paint " + w.name); return; }
                        scene.shown = "file:///out/wall-" + w.name + ".png";
                        step.interval = 600 + 2 * Theme.colorMs; step.restart();   // read, then the shade's own fade
                    });
                    return;
                }
                const r = clock.mapToItem(lock, 0, 0, clock.width, clock.height);
                console.log("CLOCK_GROUND", JSON.stringify({ name: w.name, bright: ground.bright, shade: ground.shade, ink: String(lock.tint),
                                                             box: [r.x, r.y, r.width, r.height] }));
                lock.grabToImage(result => {
                    if (!result.saveToFile("/out/lock-" + w.name + ".png")) { scene.fail("capture failed"); return; }
                    scene.shown = "";
                    if (scene.at + 1 < scene.walls.length) { scene.at++; step.interval = 300; step.restart(); return; }
                    console.log("UI_SMOKE_CAPTURED");
                    Qt.quit();
                });
            }
        }
    }
}
