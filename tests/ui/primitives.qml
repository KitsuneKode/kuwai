import QtQuick
import QtQuick.Window
import Quickshell
import qs.config
import qs.components


ShellRoot {
    Window {
        id: scene
        visible: true
        width: 640; height: 480
        color: Theme.glassIsland
        Rectangle { anchors.fill: parent; color: Qt.rgba(0.02, 0.02, 0.027, 1) }
        Component.onCompleted: Settings.set("textScale", Number(Quickshell.env("KUWAI_UI_TEXT_SCALE") || 1))
        Column {
            x: 24; y: 24; spacing: 16
            Label { text: "Isolated native control smoke test"; size: Theme.tHeadline }
            RaisedButton { text: "Readable action" }
            RaisedButton { text: "Destructive action"; kind: "danger" }
            Toggle { label: "Fixture switch" }
            SettingsRow { id: example; width: 280; label: "A long settings label"; detail: "Full help remains readable when the control needs its own row."; Segmented { id: rowChoices; options: [{id:"a",label:"Long first choice"},{id:"b",label:"Long second choice"}]; current:"a" } }
            Segmented { id: choices; width: 240; options: [{id:"a",label:"A very long first choice"},{id:"b",label:"An equally long second choice"}]; current: "a" }
        }
        Timer {
            interval: 1500; running: true
            onTriggered: {
                if (choices.naturalSum > choices.width && !choices.compact) {
                    console.log("UI_SMOKE_FAILED: long choices overflow their control"); Qt.quit(); return;
                }
                if (Math.abs(Theme.textScale - Number(Quickshell.env("KUWAI_UI_TEXT_SCALE") || 1)) > 0.01) { console.log("UI_SMOKE_FAILED: text scale not applied"); Qt.quit(); return; }
                if (Settings.pending || Settings.error) { console.log("UI_SMOKE_FAILED: settings write not acknowledged " + Settings.error); Qt.quit(); return; }
                for (const entry of Settings.schema.settings) {
                    if (Settings.value(entry.key) === undefined) { console.log("UI_SMOKE_FAILED: missing setting " + entry.key); Qt.quit(); return; }
                }
                const paths = JSON.parse(Quickshell.env("KUWAI_UI_COMPILE") || "[]");
                for (const path of paths) {
                    const component = Qt.createComponent("/app/shell/" + path, Component.PreferSynchronous);
                    if (component.status === Component.Error) {
                        console.log("UI_SMOKE_FAILED: " + path + " " + component.errorString()); Qt.quit(); return;
                    }
                    component.destroy();
                }
                function detailBottom(item) {
                    if (item.text === example.detail) return item.mapToItem(example, 0, item.height).y;
                    for (const child of item.children || []) { const found = detailBottom(child); if (found >= 0) return found; }
                    return -1;
                }
                const bounds = rowChoices.mapToItem(example, 0, 0, rowChoices.width, rowChoices.height);
                console.log("UI_GEOMETRY", JSON.stringify({control:bounds,detailBottom:detailBottom(example),rowHeight:example.height}));
                if (bounds.y < detailBottom(example) || bounds.x < 0 || bounds.x + bounds.width > example.width) { console.log("UI_SMOKE_FAILED: settings control overlaps help or exceeds row"); Qt.quit(); return; }
                if (!example.stacked) { console.log("UI_SMOKE_FAILED: constrained settings must stack"); Qt.quit(); return; }
                scene.contentItem.grabToImage(result => {
                const ok = result.saveToFile("/out/primitives.png");
                console.log(ok ? "UI_SMOKE_CAPTURED" : "UI_SMOKE_FAILED");
                Qt.quit();
                });
            }
        }
    }
}
