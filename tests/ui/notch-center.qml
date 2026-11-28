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
        width: 600; height: 640
        color: Theme.glassSolid
        Loader {
            id: shown
            anchors.fill: parent
            active: Island.isCenter(Island.panel)
            sourceComponent: CenterPanel {}
        }
        TestCase { id: t; name: "NotchCenter"; when: false }
        function fail(r) { console.log("UI_SMOKE_FAILED: " + r + " (panel " + Island.panel + ", tab " + Notifs.centerTab + ", open " + Notifs.centerOpen + ")"); Qt.quit(); }
        Component.onCompleted: { Settings.set("bar", "island"); Settings.set("islandStyle", "notch"); }
        Timer {
            interval: 600; running: true
            onTriggered: {
                if (!Island.hostsCenter) { scene.fail("notch settings did not take"); return; }
                Island.openOn("agents", "fixture", "key");
                Notifs.toggleCenter("notifications", "key", "fixture");
                t.wait(300);
                if (Island.panel !== "notifications" || !Notifs.centerOpen || Notifs.centerTab !== "notifications") { scene.fail("Notifications did not open as the island's panel"); return; }
                if (!shown.item || shown.item.implicitHeight < 300) { scene.fail("the panel has no content"); return; }
                Notifs.toggleCenter("controls", "key", "fixture");
                t.wait(200);
                if (Island.panel !== "controls" || Notifs.centerTab !== "controls") { scene.fail("Controls did not take over the same surface"); return; }
                Notifs.toggleCenter("sound", "key", "fixture");
                t.wait(100);
                if (Island.panel !== "controls" || Notifs.centerTab !== "sound") { scene.fail("Sound is not a tab of Controls"); return; }
                Notifs.centerBack();
                t.wait(100);
                if (Island.panel !== "agents" || Notifs.centerOpen) { scene.fail("Esc did not go back to where it came from"); return; }
                Notifs.toggleCenter("notifications", "key", "fixture");
                t.wait(100);
                Notifs.toggleCenter("notifications", "key", "fixture");
                t.wait(100);
                if (Island.panel !== "" || Notifs.centerOpen) { scene.fail("toggling Notifications again did not close it"); return; }
                Notifs.setCenter(true, "key");
                t.wait(100);
                if (Island.panel !== "notifications") { scene.fail("setCenter did not open the panel"); return; }
                Island.openOn("usage", "fixture", "key");
                t.wait(100);
                if (Notifs.centerOpen || Island.panel !== "usage") { scene.fail("another panel did not take over from Notifications"); return; }
                Island.close();
                Settings.set("islandStyle", "floating");
                t.wait(400);
                if (!Island.hostsCenter) { scene.fail("the floating island does not host the centre"); return; }
                Notifs.toggleCenter("notifications", "key", "fixture");
                t.wait(200);
                if (Island.panel !== "notifications" || !Notifs.centerOpen) { scene.fail("Notifications did not open in the floating island"); return; }
                console.log("UI_SMOKE_CAPTURED");
                Qt.quit();
            }
        }
    }
}
