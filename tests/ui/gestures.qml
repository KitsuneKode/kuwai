// The swipe, driven by a real pointer in a private window (bin/kuwai-ui-test
// --case gestures --motion full). What a gesture has to do, each as a check:
//
//   while the pointer is down the row IS the pointer (1:1, fade tied to distance)
//   let go short and slow: it comes home
//   let go past 40 % of its width: it leaves
//   a flick leaves from anywhere; a flick back home keeps it
//   caught on its way home, it stays under the pointer (no jump)
//   sent away by a button it leaves without a throw
//
// and the lock screen's cards are that same swipe (they had their own once).
// With --motion reduced the same run checks that nothing is left mid-way.
import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import qs.components
import qs.config
import qs.services
import qs.modules.lock

ShellRoot {
    Window {
        id: scene
        visible: true
        width: 480; height: 460
        color: Theme.glassSolid
        property int left: 0                  // times the row said it was leaving

        Rectangle {
            id: row
            x: 40; y: 20
            width: 400; height: 56; radius: Theme.r2
            color: Theme.pill
            transform: Translate { x: swipe.offset }
            opacity: swipe.fade
            Label { anchors.centerIn: parent; text: "Swipe me" }
            SwipeAway { id: swipe; span: row.width; onLeaving: scene.left++ }
        }
        LockNotifs { id: lockStack; x: 25; y: 120 }
        Component {
            id: note
            QtObject {
                property int nid: 0
                property real time: Date.now()
                property string app: "Mail"
                property string title: ""
                property string body: ""
                property string full: ""
                property string severity: "warning"
                property string groupKey: ""
                property string status: ""
                property string statusGlyph: ""
                property string statusTone: ""
                property string icon: ""
                property bool discard: false
                property bool quiet: false
                property bool popup: false
                property bool hasDefault: true
                property int urgency: 1
                property var actions: []
                property var notification: null
            }
        }

        TestCase { id: driver; name: "Gestures"; when: false }
        readonly property real cy: row.y + row.height / 2
        readonly property real cx: row.x + row.width / 2
        function fail(reason) {
            console.log("UI_SMOKE_FAILED: " + reason + " (offset " + Math.round(swipe.offset) + ", gone " + swipe.gone + ", left " + scene.left + ")");
            scene.contentItem.grabToImage(result => { result.saveToFile("/out/gestures-failure.png"); Qt.quit(); });
        }
        function near(a, b, tol) { return Math.abs(a - b) <= tol; }
        // Press on the row and move `to` px sideways in `steps` moves, `ms` apart.
        function pull(to, steps, ms, y) {
            const at = y === undefined ? cy : y;
            driver.mousePress(scene.contentItem, cx, at, Qt.LeftButton);
            for (let i = 1; i <= steps; i++) driver.mouseMove(scene.contentItem, cx + to * i / steps, at, ms, Qt.LeftButton);
        }
        function drop(to, y) { driver.mouseRelease(scene.contentItem, cx + to, y === undefined ? cy : y, Qt.LeftButton); }
        function home() { swipe.reset(); driver.wait(50); }

        Timer {
            interval: 1000; running: true
            onTriggered: {
                const still = Theme.reduceMotion;

                // 1 · Down: the row is the pointer, and the fade is the distance.
                scene.pull(80, 8, 20);
                if (!swipe.active) { scene.fail("a sideways drag did not take the row"); return; }
                const first = swipe.offset;
                if (!scene.near(first, 80, 14)) { scene.fail("the row is not under the pointer after 80 px"); return; }
                driver.mouseMove(scene.contentItem, scene.cx + 100, scene.cy, 20, Qt.LeftButton);
                if (!scene.near(swipe.offset - first, 20, 1)) { scene.fail("20 px of pointer did not move the row 20 px"); return; }
                if (!scene.near(swipe.fade, 1 - swipe.offset / row.width, 0.01)) { scene.fail("the fade is not the distance travelled"); return; }

                // 2 · Let go short, having stopped: it comes home, and says nothing.
                driver.wait(180);
                scene.drop(100);
                if (swipe.gone || scene.left !== 0) { scene.fail("a short, stopped drag sent the row away"); return; }
                driver.wait(700);
                if (!scene.near(swipe.offset, 0, 1)) { scene.fail("the row did not come home"); return; }

                // 3 · Caught on its way home: it stays under the pointer.
                if (!still) {
                    scene.pull(150, 10, 16);
                    driver.wait(180);
                    scene.drop(150);
                    driver.wait(50);
                    const flying = swipe.offset;
                    if (flying <= 20 || flying >= 150) { scene.fail("the row was not on its way home 50 ms after release"); return; }
                    scene.pull(24, 3, 12);                       // press again where the pointer is and nudge it
                    if (!swipe.active) { scene.fail("the row could not be caught mid-flight"); return; }
                    const held = swipe.offset;
                    // From where it was when the hand took it (it flew on for the few
                    // milliseconds a drag takes to be recognised), not from home.
                    if (swipe.grab < 5 || swipe.grab > flying + 1) { scene.fail("caught mid-flight, the row was not taken from where it was (was " + Math.round(flying) + ", taken at " + Math.round(swipe.grab) + ")"); return; }
                    if (!scene.near(held, swipe.grab + 24, 1.5)) { scene.fail("caught mid-flight, the row jumped away from the pointer"); return; }
                    driver.wait(200);
                    if (!scene.near(swipe.offset, held, 1)) { scene.fail("held still, the row kept moving"); return; }
                    scene.drop(24);
                    driver.wait(700);
                    if (swipe.gone || !scene.near(swipe.offset, 0, 1)) { scene.fail("released after a catch, the row did not come home"); return; }
                }

                // 4 · A flick leaves from a quarter of the way.
                scene.pull(100, 4, 8);
                scene.drop(100);
                if (!swipe.gone || scene.left !== 1) { scene.fail("a flick outward did not send the row away"); return; }
                driver.wait(700);
                if (!scene.near(Math.abs(swipe.offset), row.width, 2) || swipe.fade > 0.02) { scene.fail("a row that left is not out and faded"); return; }
                scene.home();

                // 5 · Past 40 % of its width, however slowly.
                scene.pull(180, 12, 20);
                driver.wait(180);
                scene.drop(180);
                if (!swipe.gone || scene.left !== 2) { scene.fail("released past 40 % of its width, the row stayed"); return; }
                driver.wait(400);
                scene.home();

                // 6 · Out, then flicked back: it stays, though it is let go past the line.
                // (A hand's flick: about a tenth of a second. Speed is read over the
                // last 100 ms of the drag, so a twitch shorter than that is not one.)
                scene.pull(340, 17, 20);
                for (let i = 1; i <= 6; i++) driver.mouseMove(scene.contentItem, scene.cx + 340 - 25 * i, scene.cy, 16, Qt.LeftButton);
                scene.drop(190);
                if (swipe.gone || scene.left !== 2) { scene.fail("flicked back toward home, the row left anyway"); return; }
                driver.wait(700);
                if (!scene.near(swipe.offset, 0, 1)) { scene.fail("flicked back, the row did not come home"); return; }

                // 7 · Sent away by a button: it leaves, with no throw.
                swipe.away(-1);
                if (!swipe.gone || scene.left !== 3 || swipe.sx.velocity !== 0) { scene.fail("away() did not send the row off from rest"); return; }
                driver.wait(700);
                if (!scene.near(swipe.offset, -row.width, 2)) { scene.fail("away(-1) did not end one width to the left"); return; }

                // 8 · The lock screen's card is the same swipe: a flick clears its conversation.
                const a = note.createObject(scene, { nid: 1, title: "Ada Lovelace", body: "Lunch on Thursday?", groupKey: "mail-ada" });
                const b = note.createObject(scene, { nid: 2, title: "Build failed", body: "2 tests", app: "CI", groupKey: "ci", time: Date.now() - 60000 });
                Notifs.lastSeen = Date.now() - 600000;
                Notifs.items = [a, b];
                driver.wait(500);
                if (lockStack.shownGroups.length !== 2) { scene.fail("the lock stack did not show two conversations"); return; }
                const top = lockStack.y + 36;
                scene.pull(60, 6, 20, top);
                const mid = driver.findChild(lockStack, "") && Notifs.items.length;
                if (mid !== 2) { scene.fail("a card cleared while it was still held"); return; }
                driver.wait(180);
                scene.drop(60, top);
                driver.wait(500);
                if (Notifs.items.length !== 2) { scene.fail("a short, stopped drag cleared a lock-screen card"); return; }
                scene.pull(110, 4, 8, top);
                scene.drop(110, top);
                driver.wait(600);
                if (Notifs.items.length !== 1 || Notifs.items[0].groupKey !== "ci") { scene.fail("a flick did not clear the lock-screen card's conversation (left: " + Notifs.items.length + ")"); return; }

                scene.contentItem.grabToImage(result => {
                    console.log(result.saveToFile("/out/gestures.png") ? "UI_SMOKE_CAPTURED" : "UI_SMOKE_FAILED: capture failed");
                    Qt.quit();
                });
            }
        }
    }
}
