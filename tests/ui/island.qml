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
        width: 320; height: 190
        color: Theme.glassSolid
        property int stage: 0
        property var widths: [320, 320, 200, 480, 1120]
        Rectangle {
            id: tipHost
            x: Theme.s4; y: scene.height - height - Theme.s4
            width: Theme.s5; height: Theme.s5
            visible: scene.stage === 0
            Tip { id: longTip }
        }
        Loader {
            id: morePanel
            y: 64
            width: scene.width
            height: scene.height - y
            active: Island.panel === "activities"
            sourceComponent: IslandActivities { sourceSplit: split }
        }
        QtObject {
            id: fakeBar
            property string screenName: "fixture"
            property var player: QtObject {
                property bool isPlaying: true
                property string trackTitle: "Fixture track"
                property string trackArtist: "Fixture artist"
                property string identity: "Fixture player"
                property string trackArtUrl: ""
                property var metadata: ({})
            }
        }
        IslandSplit {
            id: split
            anchors.fill: parent
            bar: fakeBar
            leftEdge: scene.width / 2 - 56
            rightEdge: scene.width / 2 + 56
            topY: 12
            h: 34
            activity: "vox"
            minimized: scene.stage > 0 ? [{address: "invalid-fixture-address", title: "Example window", lastIpcObject: {}}] : []
        }
        Rectangle { x: split.leftEdge; y: split.topY; width: 112; height: 34; radius: 17; color: Theme.cutout }
        TestCase { id: driver; name: "IsolatedCapsules"; when: false }
        // The real alert sampler reads the private namespace asynchronously.
        // Keep the fixture's external input stable while testing layout/actions.
        Timer {
            interval: 100; repeat: true; running: true
            onTriggered: Alerts.active = [{ id: "fixture", level: "warn", glyph: "!", title: "Fixture warning", detail: "Fixture" }]
        }
        Component.onCompleted: {
            Settings.set("textScale", Number(Quickshell.env("KUWAI_UI_TEXT_SCALE") || 1));
            Settings.set("islandSplit", true);
            Settings.set("restMedia", true);
            Kittymux.feedPinned = true;
            Kittymux.feed = { version: 1, agents: [
                { key: "fixture-1", agent: "claude", brand: "claude", title: "Fixture", state: "working", account: "main" },
                { key: "fixture-2", agent: "codex", brand: "codex", title: "Fixture", state: "limited", account: "personal", limit_reset: Math.round(Date.now() / 1000) + 5400 }
            ] };
            T3Code.running = 12;
            T3Code.rawFinished = 999;
            Alerts.active = [{ id: "fixture", level: "warn", glyph: "!", title: "Fixture warning", detail: "Fixture" }];
        }
        function fail(reason) {
            console.log("UI_SMOKE_FAILED: " + reason);
            scene.contentItem.grabToImage(result => { result.saveToFile("/out/island-failure.png"); Qt.quit(); });
        }
        function descendant(item, predicate) {
            if (predicate(item)) return item;
            for (const child of item.children || []) {
                const match = descendant(child, predicate);
                if (match) return match;
            }
            return null;
        }
        Timer {
            interval: 900; running: true; repeat: true
            onTriggered: {
                stop();
                if (Settings.pending || Settings.error) { scene.fail("settings did not acknowledge"); return; }
                const pills = split.pills.filter(p => p.visible);
                console.log("ISLAND_STATE", JSON.stringify({demand:split.demand, arrangement:split.arrangement, pills:split.pills.map(p => ({name:p.name,shown:p.shown,out:p.out,w:p.width}))}));
                const expected = [4, 4, 1, 5, 5][scene.stage];
                if (pills.length !== expected) { scene.fail("unexpected item count at stage " + scene.stage); return; }
                const more = pills.find(p => p.name === "more");
                if (scene.stage === 1 && (!more || split.arrangement.overflow.length !== 2 || !pills.some(p => p.name === "sys"))) {
                    scene.fail("five activities did not retain the urgent warning and group two items"); return;
                }
                if (scene.stage === 2 && (!more || !more.belowNotch || split.arrangement.overflow.length !== 5 || more.y <= split.topY + split.h)) {
                    scene.fail("full-width notch lost its More control"); return;
                }
                const boxes = pills.map(p => ({name:p.name, x:p.x, y:p.y, w:p.width, h:p.height}));
                console.log("ISLAND_GEOMETRY", scene.width, JSON.stringify(boxes));
                for (const p of pills) {
                    if (p.x < -0.5 || p.x + p.width > scene.width + 0.5) { scene.fail("capsule outside host at " + scene.width + ": " + p.name); return; }
                    if (p.inputTarget.width < 40 || p.inputTarget.height < 40) { scene.fail("dense target below 40 logical pixels"); return; }
                    const ring = driver.findChild(p, "rest-count-ring");
                    const count = driver.findChild(p, "rest-count-value");
                    if (ring && count && (count.implicitWidth + Theme.s1 > ring.width || count.implicitHeight > ring.height)) { scene.fail("count does not fit its ring"); return; }
                }
                for (let i = 0; i < boxes.length; i++) for (let j = i + 1; j < boxes.length; j++) {
                    if (Math.min(boxes[i].x + boxes[i].w, boxes[j].x + boxes[j].w) - Math.max(boxes[i].x, boxes[j].x) > 0.5) { scene.fail("capsules overlap"); return; }
                }
                // A capsule is its own target (IslandBar asks hitAt before it
                // takes the pointer for one reaching the island).
                for (const p of pills) {
                    const mx = p.x + p.width / 2, my = p.y + p.height / 2;
                    if (!split.hitAt(mx, my, 0)) { scene.fail("hitAt missed the middle of a capsule: " + p.name); return; }
                    if (!split.hitAt(p.x - 8, my, 10) || !split.hitAt(mx, p.y + p.height + 8, 10)) { scene.fail("hitAt has no margin around a capsule: " + p.name); return; }
                    if (split.hitAt(mx, p.y + p.height + 40, 10)) { scene.fail("hitAt reaches 40 px below a capsule: " + p.name); return; }
                }
                if (scene.stage !== 2 && split.hitAt(scene.width / 2, split.topY + split.h / 2, 0)) { scene.fail("hitAt counts the island itself as a capsule"); return; }
                for (const p of pills) {
                    if (p.name === "min") continue;
                    Island.close();
                    driver.mouseClick(p, p.width - 2, p.height / 2, Qt.LeftButton, Qt.NoModifier);
                    if (Island.panel !== p.panel) { scene.fail("capsule padding did not open its panel: " + p.name); return; }
                    Island.close();
                    driver.mouseClick(p.inputTarget, p.inputTarget.width / 2, 1, Qt.LeftButton, Qt.NoModifier);
                    if (Island.panel !== p.panel) { scene.fail("capsule vertical slop did not open its panel: " + p.name); return; }
                    Island.close();
                    p.forceActiveFocus();
                    driver.keyClick(Qt.Key_Return);
                    if (Island.panel !== p.panel) { scene.fail("keyboard action did not open its panel: " + p.name); return; }
                    if (p.name === "more") {
                        const firstAction = driver.findChild(morePanel.item, "activity-" + split.overflowSelection[0]);
                        if (!firstAction) { scene.fail("overflow action did not render"); return; }
                        if (morePanel.item.activities.length !== split.overflowSelection.length) { scene.fail("overflow lost an activity"); return; }
                        const route = split.pillOf(firstAction.modelData).panel;
                        if (route) {
                            firstAction.forceActiveFocus();
                            driver.keyClick(Qt.Key_Return);
                            if (Island.panel !== route) { scene.fail("overflow action failed to open its existing panel"); return; }
                            Island.back();
                            if (Island.panel !== "activities") { scene.fail("back did not restore More"); return; }
                        }
                    }
                    if (p.name === "agents" && !p.compact) {
                        const limit = scene.descendant(p, c => c.visible && c.tint !== undefined && String(c.tip || "").indexOf("Click: usage") >= 0);
                        if (limit) {
                            Island.close();
                            driver.mouseClick(limit, limit.width / 2, limit.height / 2, Qt.LeftButton, Qt.NoModifier);
                            if (Island.panel !== "usage") { scene.fail("nested limit badge lost its Usage action"); return; }
                        }
                    }
                }
                Island.close();
                if (scene.stage === 0) {
                    const fallback = Theme.panelS - 2 * Theme.s2;
                    if (longTip.availableTextWidth({width: 0}, null) !== fallback
                        || longTip.availableTextWidth({width: NaN}, {width: 0}) !== fallback
                        || longTip.availableTextWidth({width: 240}, {width: 1280}) !== 240 - 2 * (Theme.s4 + Theme.s2)) {
                        scene.fail("tooltip did not honor usable output geometry"); return;
                    }
                    longTip.shown = true;
                    longTip.text = "Zenta";
                    driver.wait(Theme.tipMs + Theme.quickMs + 120);
                    const tooltip = driver.findChild(longTip, "tooltip-popup");
                    const label = driver.findChild(longTip, "tooltip-label");
                    if (!tooltip || !label || label.lineCount !== 1 || label.truncated || label.width < Theme.s5) {
                        scene.fail("short tooltip collapsed into a narrow column"); return;
                    }
                    longTip.text = "Zenta\nClick to open";
                    driver.wait(100);
                    if (label.lineCount !== 2 || label.truncated) { scene.fail("tooltip failed to keep two authored lines"); return; }
                    longTip.text = "A long title with spaces and a very long address " + "表題".repeat(300);
                    driver.wait(100);
                    if (label.lineCount <= 1 || label.lineCount > 6 || tooltip.implicitWidth > Theme.panelS || label.width < Theme.panelS / 2) {
                        scene.fail("long tooltip did not wrap within bounds"); return;
                    }
                    longTip.text = "Zenta";
                    driver.wait(100);
                    if (label.lineCount !== 1 || label.truncated) { scene.fail("tooltip did not recover when the title shortened"); return; }
                    longTip.text = "";
                    driver.wait(Theme.quickMs + 120);
                    if (driver.findChild(longTip, "tooltip-popup")) { scene.fail("empty tooltip remained alive"); return; }
                    const target = pills.find(p => p.name === "music");
                    const origin = target.mapToItem(scene.contentItem, target.width / 2, target.height / 2);
                    driver.mousePress(scene.contentItem, origin.x, origin.y, Qt.LeftButton);
                    for (let step = 1; step <= 4; step++) driver.mouseMove(scene.contentItem, origin.x, origin.y + step * 17, 30, Qt.LeftButton);
                    if (!target.pullArmed) { scene.fail("drag did not arm in the isolated window"); return; }
                    driver.mouseRelease(scene.contentItem, origin.x, origin.y + 68, Qt.LeftButton);
                    driver.wait(100);
                    if (Island.panel !== "media") { scene.fail("released drag did not open the media panel"); return; }
                    Island.close();
                    driver.wait(500);
                    driver.mousePress(scene.contentItem, origin.x, origin.y, Qt.LeftButton);
                    for (let step = 1; step <= 4; step++) driver.mouseMove(scene.contentItem, origin.x, origin.y + step * 17, 30, Qt.LeftButton);
                    split.atRest = false;
                    driver.mouseRelease(scene.contentItem, origin.x, origin.y + 68, Qt.LeftButton);
                    driver.wait(100);
                    if (Island.panel !== "") { scene.fail("cancelled drag opened a panel"); return; }
                }
                split.atRest = false;
                driver.wait(700);
                if (split.pills.some(p => p.visible || p.enabled)) { scene.fail("folded capsules retained visibility or input"); return; }
                if (boxes.some(b => split.hitAt(b.x + b.w / 2, b.y + b.h / 2, 10))) { scene.fail("a folded capsule still counts as a target"); return; }
                split.atRest = true;
                driver.wait(700);
                if (split.pills.filter(p => p.enabled).length !== expected) { scene.fail("capsules did not recover after folding"); return; }
                const capturedWidth = scene.width + "-" + scene.stage;
                scene.contentItem.grabToImage(result => {
                    if (!result.saveToFile("/out/island-" + capturedWidth + ".png")) { scene.fail("capture failed"); return; }
                    if (++scene.stage < scene.widths.length) {
                        scene.width = scene.widths[scene.stage];
                        restart();
                        return;
                    }
                    console.log(result.saveToFile("/out/island.png") ? "UI_SMOKE_CAPTURED" : "UI_SMOKE_FAILED: capture failed");
                    Qt.quit();
                });
            }
        }
    }
}
