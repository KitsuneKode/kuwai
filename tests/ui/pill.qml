// The island's Agents capsule with T3 threads in its states (bin/kuwai-ui-test --case pill): it
// says what is wanted as a word ("Approval", "Question 2", "Limit reached"),
// the turning count only for plain work, and stays inside its outline. A
// picture of each goes to /out/pill-<state>.png.
import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import qs.components
import qs.config
import qs.services
import qs.modules.island

ShellRoot {
    Window {
        id: scene
        visible: true
        width: 520; height: 70
        color: Theme.glassSolid
        QtObject {
            id: fakeBar
            property string screenName: "fixture"
            property var player: null
        }
        IslandSplit {
            id: split
            anchors.fill: parent
            bar: fakeBar
            leftEdge: scene.width / 2 - 56
            rightEdge: scene.width / 2 + 56
            topY: 12
            h: 34
        }
        Rectangle { x: split.leftEdge; y: split.topY; width: 112; height: 34; radius: 17; color: Theme.cutout }
        TestCase { id: driver; name: "Pill"; when: false }
        readonly property var states: [
            { id: "approval", running: 1, waiting: 1, items: [{ thread: "a", status: "waiting", ask: "approval", title: "Approve the plan" }, { thread: "b", status: "running", title: "x" }], pill: "agents", want: "Approval" },
            { id: "questions", running: 0, waiting: 2, items: [{ thread: "a", status: "waiting", ask: "question", title: "q1" }, { thread: "b", status: "waiting", ask: "question", title: "q2" }], pill: "agents", want: "Question 2" },
            { id: "limit", running: 0, waiting: 0, items: [{ thread: "a", status: "failed", limited: true, provider: "claudeAgent", title: "l" }], pill: "limitOut", want: "Claude" },
            { id: "working", running: 2, waiting: 0, items: [{ thread: "a", status: "running", title: "w" }, { thread: "b", status: "running", title: "w2" }, { thread: "c", status: "completed", title: "d" }], pill: "agents", want: "" }
        ]
        property int at: 0
        function fail(r) { console.log("UI_SMOKE_FAILED: " + r); Qt.quit(); }
        function find(item, pred) { if (pred(item)) return item; for (const c of item.children || []) { const f = find(c, pred); if (f) return f; } return null; }
        function stage() {
            const s = states[at];
            Settings.set("islandSplit", true);
            Settings.set("limitAlerts", true);
            T3Code.alive = true;
            T3Code.running = s.running; T3Code.waiting = s.waiting;
            T3Code.rawItems = s.items; T3Code.rawFinished = s.items.filter(i => i.status === "completed").length;
            check.restart();
        }
        Timer {
            id: check
            interval: 1500
            onTriggered: {
                const s = scene.states[scene.at];
                const pill = split.pills.find(p => p.name === s.pill);
                if (!pill || !pill.out) { scene.fail(s.id + ": the " + s.pill + " capsule isn't out"); return; }
                if (s.pill === "limitOut" && pill.x < split.rightEdge) { scene.fail(s.id + ": limitOut must sit on the right"); return; }
                if (s.want) {
                    const said = scene.find(pill, c => c.text !== undefined && String(c.text) === s.want && c.visible);
                    if (!said) { scene.fail(s.id + ": the capsule doesn't say \"" + s.want + "\""); return; }
                    const r = said.mapToItem(pill, 0, 0);
                    if (r.x < 0 || r.x + said.width > pill.width + 0.5) { scene.fail(s.id + ": \"" + s.want + "\" runs outside its capsule"); return; }
                }
                scene.contentItem.grabToImage(img => {
                    img.saveToFile("/out/pill-" + s.id + ".png");
                    if (++scene.at < scene.states.length) scene.stage();
                    else { console.log("UI_SMOKE_CAPTURED"); Qt.quit(); }
                });
            }
        }
        Component.onCompleted: stage()
    }
}
