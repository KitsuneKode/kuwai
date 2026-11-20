// The island's cards from the keyboard alone (bin/kuwai-ui-test --case
// card-keys): an alarm card and a notification peek, each taking the keyboard
// only once asked (Island.cardKeys, Super+Ctrl+↵), walking its buttons,
// answering with ↵ and giving the keyboard back with Esc.
import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import qs.config
import qs.services
import qs.modules.island

ShellRoot {
    Window {
        id: scene
        visible: true
        width: 520; height: 320
        color: Theme.glassSolid
        property string answered: ""
        AlarmCard {
            id: alarm
            width: 480; height: 96; y: 8
            bar: null
            item: ({ id: 1, key: "a", kind: "alarm", title: "Wake up", sub: "07:30 · Alarm",
                     act: { secondary: ["Snooze", () => scene.answered = "snooze"], primary: ["Stop", () => scene.answered = "stop"] } })
        }
        NotifPeek {
            id: peek
            width: 480; height: 96; y: 120
            bar: null
            item: ({ id: 9002, app: "Fixture", title: "A message", body: "Hello", time: Date.now(), actions: [], status: "", statusGlyph: "", statusTone: "", severity: "normal" })
        }
        TestCase { id: t; name: "CardKeys"; when: false }
        function fail(reason) { console.log("UI_SMOKE_FAILED: " + reason); Qt.quit(); }
        Timer {
            interval: 600; running: true
            onTriggered: {
                if (scene.activeFocusItem && scene.activeFocusItem !== scene.contentItem && scene.activeFocusItem.activeFocusOnTab) { scene.fail("a card took the keyboard unasked"); return; }
                // Alarm: asked, its answer (Stop) takes the keyboard; ← reaches Snooze, ↵ snoozes.
                alarm.visible = true; peek.visible = false;
                Island.cardKeys = true;
                t.wait(100);
                if (!scene.activeFocusItem || scene.activeFocusItem.Accessible.name !== "Stop") { scene.fail("the alarm's Stop did not take the keyboard (" + (scene.activeFocusItem && scene.activeFocusItem.Accessible.name) + ")"); return; }
                t.keyClick(Qt.Key_Left);
                if (scene.activeFocusItem.Accessible.name !== "Snooze") { scene.fail("← did not reach Snooze"); return; }
                t.keyClick(Qt.Key_Return);
                if (scene.answered !== "snooze" || Island.cardKeys) { scene.fail("↵ on Snooze did not answer and give the keyboard back (" + scene.answered + ")"); return; }
                // Peek: Open takes it; → reaches nothing past Open, ← Dismiss; Esc gives it back.
                alarm.visible = false; peek.visible = true;
                Island.cardKeys = true;
                t.wait(100);
                if (!scene.activeFocusItem || scene.activeFocusItem.Accessible.name !== "Open") { scene.fail("the peek's Open did not take the keyboard (" + (scene.activeFocusItem && scene.activeFocusItem.Accessible.name) + ")"); return; }
                t.keyClick(Qt.Key_Left);
                if (scene.activeFocusItem.Accessible.name !== "Dismiss") { scene.fail("← did not reach Dismiss"); return; }
                t.keyClick(Qt.Key_Escape);
                if (Island.cardKeys) { scene.fail("Esc did not give the keyboard back"); return; }
                console.log("UI_SMOKE_CAPTURED");
                Qt.quit();
            }
        }
    }
}
