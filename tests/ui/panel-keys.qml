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
        width: 600; height: 460
        color: Theme.glassSolid
        FocusScope {
            id: host
            focus: true
            width: 560; height: 440
            property PanelKeys keys: PanelKeys { scope: loader }
            Keys.onPressed: e => { if (keys.handle(e, scene)) e.accepted = true; }
            Connections { target: scene; function onActiveFocusItemChanged() { host.keys.reveal(scene.activeFocusItem); } }
            Loader { id: loader; anchors.fill: parent; focus: true; active: false; sourceComponent: UpdatesPanel {} }
        }
        TestCase { id: t; name: "PanelKeys"; when: false }
        function fail(r) { console.log("UI_SMOKE_FAILED: " + r); Qt.quit(); }
        function inView(it, f) {
            const r = it.mapToItem(f, 0, 0);
            return r.y >= -1 && r.y + it.height <= f.height + 1;
        }
        Timer {
            interval: 400; running: true
            onTriggered: {
                const repo = [];
                for (let i = 0; i < 40; i++) repo.push({ name: "package-" + i, old: "1.0." + i + "-1", new: "1.0." + (i + 1) + "-1", repo: "extra" });
                Updates.data = { checkedAt: Date.now() - 600000, repo: repo, aur: [], repoError: false, lastUpgrade: Date.now() - 86400000,
                                 news: [], freeBytes: 48000000000, power: { ac: true, battery: 100 }, kernel: false, flatpak: [] };
                loader.active = true;
                t.wait(300);
                loader.item.showAllRepo = true;
                t.wait(600);
                const f = host.keys.mainFlick();
                if (!f) { scene.fail("the Updates list does not scroll with 40 packages"); return; }
                host.forceActiveFocus();
                t.keyClick(Qt.Key_PageDown);
                if (f.contentY <= 0) { scene.fail("PageDown did not scroll the list"); return; }
                t.keyClick(Qt.Key_End);
                if (Math.abs(f.contentY - (f.originY + f.contentHeight - f.height)) > 1) { scene.fail("End did not reach the bottom"); return; }
                t.keyClick(Qt.Key_Home);
                if (Math.abs(f.contentY - f.originY) > 1) { scene.fail("Home did not reach the top"); return; }
                const names = [];
                let update = false;
                for (let i = 0; i < 80; i++) {
                    t.keyClick(Qt.Key_Tab);
                    const it = scene.activeFocusItem;
                    if (!it || it === host) { scene.fail("Tab left the panel (" + i + ")"); return; }
                    const name = String(it.Accessible.name || "");
                    if (names.length && name === names[0] && names.length > 2) break;
                    names.push(name);
                    if (/^Update/.test(name)) update = true;
                    let p = it.parent; while (p && p !== f) p = p.parent;
                    if (p === f && !scene.inView(it, f)) { scene.fail("Tab reached " + name + " but left it out of view"); return; }
                }
                if (!update) { scene.fail("Tab never reached the Update button: " + names.join(" | ")); return; }
                t.keyClick(Qt.Key_Backtab);
                if (String(scene.activeFocusItem.Accessible.name) !== names[names.length - 1]) {
                    scene.fail("Shift+Tab did not go back (" + scene.activeFocusItem.Accessible.name + ")"); return;
                }
                console.log("PANEL_KEYS " + names.length + " stops: " + names.slice(0, 12).join(" | "));
                console.log("UI_SMOKE_CAPTURED");
                Qt.quit();
            }
        }
    }
}
