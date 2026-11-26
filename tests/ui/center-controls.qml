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
        TestCase { id: t; name: "CenterControls"; when: false }
        function fail(reason) { console.log("UI_SMOKE_FAILED: " + reason); Qt.quit(); }
        function picture(name) { scene.contentItem.grabToImage(r => r.saveToFile("/out/" + name + ".png")); t.wait(200); }
        function find(root, test) {
            if (!root) return null;
            if (test(root)) return root;
            for (const c of root.children || []) { const f = scene.find(c, test); if (f) return f; }
            return null;
        }
        Timer {
            interval: 600; running: true
            onTriggered: {
                Notifs.centerTab = "controls";
                t.wait(400);
                const d = content.display;
                scene.picture("controls-home");
                d.openModule("wifi");
                t.wait(500);
                scene.picture("controls-wifi");
                if (d.module !== "wifi") { scene.fail("the Wi-Fi chevron did not open its module"); return; }
                const back = scene.find(d, c => c.label === "Back to Controls" && c.visible);
                if (!back) { scene.fail("the module has no Back"); return; }
                content.search.forceActiveFocus();
                t.keyClick(Qt.Key_Down);
                t.keyClick(Qt.Key_Escape);
                if (d.module !== "") { scene.fail("Esc in the Wi-Fi module did not return to the tiles (" + d.module + ")"); return; }
                d.openModule("bluetooth");
                t.wait(500);
                scene.picture("controls-bluetooth");
                if (d.module !== "bluetooth") { scene.fail("the Bluetooth chevron did not open its module"); return; }
                t.mouseClick(scene.find(d, c => c.label === "Back to Controls" && c.visible));
                t.wait(300);
                if (d.module !== "") { scene.fail("Back did not return to the tiles"); return; }
                fake.query = "jio";
                t.wait(300);
                if (d.module !== "wifi") { scene.fail("typing a search did not open the Wi-Fi module"); return; }
                fake.query = "";
                d.reset();
                t.wait(300);
                const warmth = scene.find(d, c => c.label === "Warmth" && c.visible && c.moved !== undefined);
                if (!warmth) { scene.fail("no Warmth slider to walk past"); return; }
                let moves = 0;
                warmth.moved.connect(() => moves++);
                warmth.forceActiveFocus(Qt.TabFocusReason);
                t.keyClick(Qt.Key_Down);
                if (moves !== 0) { scene.fail("↓ on a slider lying flat changed it instead of moving on"); return; }
                if (warmth.activeFocus) { scene.fail("↓ on a slider lying flat did not move to the next row"); return; }
                warmth.forceActiveFocus(Qt.TabFocusReason);
                t.keyClick(Qt.Key_Right);
                if (moves !== 1) { scene.fail("→ on a slider did not change it"); return; }
                console.log("UI_SMOKE_CAPTURED");
                Qt.quit();
            }
        }
    }
}
