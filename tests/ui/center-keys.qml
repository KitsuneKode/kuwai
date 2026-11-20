// The notification center from the keyboard alone (bin/kuwai-ui-test --case
// center-keys): the real CenterContent with a stand-in for Center's shared
// state, keys sent by QtTest into a private window. Sound and Controls are
// entered from the search field and left with Esc or typing; a selected
// notification's buttons and snooze are reached; Ctrl+Tab cycles the three tabs.
// The sandboxed qs crashes tearing the center down at quit (it did before
// these keys existed, 2026-11-20); the harness counts a crash only after a
// full pass as a pass, and says so.
import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import qs.config
import qs.services
import qs.modules.notifications

ShellRoot {
    Window {
        id: scene
        visible: true
        width: 440; height: 760
        color: Theme.glassSolid
        QtObject {
            id: fake
            property bool open: true
            readonly property string tab: Notifs.centerTab
            property Item ui: content
            property string query: ""
            readonly property var terms: query.toLowerCase().split(/\s+/).filter(t => t)
            function matchesText(text) { return !terms.length || terms.every(t => (text || "").toLowerCase().includes(t)); }
            function highlight(text) { return (text || "").replace(/&/g, "&amp;").replace(/</g, "&lt;"); }
            property bool instant: true
            function snap() {}
            function revealAt(ms) { return 1; }
            function tip(item, on, text, keys) {}
            property var selected: null
            property Item selectedRow: null
            property Item hoverRow: null
            property bool keyboard: false
            function setExpanded(app, on) {}
            function setHover(row, on) {}
        }
        CenterContent { id: content; anchors.fill: parent; center: fake; hosting: true }
        TestCase { id: t; name: "CenterKeys"; when: false }
        function fail(reason) { console.log("UI_SMOKE_FAILED: " + reason); Qt.quit(); }
        function within(item, root) { for (let p = item; p; p = p.parent) if (p === root) return true; return false; }
        function focused() { return scene.activeFocusItem; }
        Timer {
            interval: 600; running: true
            onTriggered: {
                // Ctrl+Tab steps through the three tabs and comes round (it landed on nothing).
                Notifs.centerTab = "notifications";
                content.search.forceActiveFocus();
                const seen = [];
                for (let i = 0; i < 3; i++) { t.keyClick(Qt.Key_Tab, Qt.ControlModifier); seen.push(Notifs.centerTab); }
                if (seen.join() !== "sound,controls,notifications") { scene.fail("Ctrl+Tab went " + seen.join()); return; }
                t.keyClick(Qt.Key_Backtab, Qt.ControlModifier | Qt.ShiftModifier);
                if (Notifs.centerTab !== "controls") { scene.fail("Ctrl+Shift+Tab went to " + Notifs.centerTab); return; }

                // Controls: ↓ from the search enters the tiles; Tab walks; typing goes back with the key.
                content.search.forceActiveFocus();
                t.wait(50);
                t.keyClick(Qt.Key_Down);
                const first = scene.focused();
                if (!first || !scene.within(first, content.display)) { scene.fail("↓ did not enter Controls (" + first + ")"); return; }
                t.keyClick(Qt.Key_Tab);
                if (scene.focused() === first) { scene.fail("Tab did not move inside Controls"); return; }
                t.keyClick(Qt.Key_Q);
                if (scene.focused() !== content.search || content.search.text !== "q") { scene.fail("typing in Controls did not return to the search with the key"); return; }
                content.search.text = "";

                // Sound: in with ↓, Esc returns to the search.
                Notifs.centerTab = "sound";
                t.wait(50);
                content.search.forceActiveFocus();
                t.keyClick(Qt.Key_Down);
                if (!scene.within(scene.focused(), content.sound)) { scene.fail("↓ did not enter Sound (" + scene.focused() + ")"); return; }
                t.keyClick(Qt.Key_Escape);
                if (scene.focused() !== content.search) { scene.fail("Esc in Sound did not return to the search"); return; }

                // Notifications: a selected row's buttons by Space, snooze by S, back by Esc.
                Notifs.centerTab = "notifications";
                Notifs.items = [{ id: 9001, app: "Fixture", title: "A message", body: "Hello there, a body long enough to read.", time: Date.now(), url: "https://example.com/x", actions: [], status: "", statusGlyph: "", statusTone: "", severity: "normal" }];
                t.wait(300);
                content.search.forceActiveFocus();
                t.keyClick(Qt.Key_Down);
                if (!content.notifications.selected) { scene.fail("↓ selected nothing in Notifications"); return; }
                t.wait(100);
                t.keyClick(Qt.Key_Space);
                const chip = scene.focused();
                if (!chip || chip === content.search || !chip.text) { scene.fail("Space did not reach the row's buttons (" + chip + ")"); return; }
                t.keyClick(Qt.Key_Right);
                if (scene.focused() === chip) { scene.fail("→ did not move along the row's buttons"); return; }
                t.keyClick(Qt.Key_Escape);
                if (scene.focused() !== content.search) { scene.fail("Esc on a button did not return to the search"); return; }
                t.keyClick(Qt.Key_S);
                t.wait(50);
                const snooze = scene.focused();
                if (!content.notifications.selectedRow.snoozing || !snooze || !/min|hour|tomorrow|evening|morning|\d/i.test(snooze.text || "")) { scene.fail("S did not open snooze on its first time (" + (snooze && snooze.text) + ")"); return; }
                t.keyClick(Qt.Key_Escape);
                if (content.notifications.selectedRow.snoozing || scene.focused() !== content.search) { scene.fail("Esc did not close snooze back to the search"); return; }
                Notifs.items = [];
                t.wait(300);
                console.log("UI_SMOKE_CAPTURED");
                Qt.quit();
            }
        }
    }
}
