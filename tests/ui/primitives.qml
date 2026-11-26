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
        Item {
            id: glide
            x: 360; y: 24; width: 240; height: 120
            property string err: "not run"
            Rectangle { id: rowA; y: 0; width: 240; height: 36; color: "transparent" }
            Rectangle { id: rowB; y: 48; width: 240; height: 36; color: "transparent" }
            FluidHighlight { id: hl; inset: 2 }
            property int outs: 0
            Connections { target: hl; function onLitChanged() { if (!hl.lit) glide.outs++; } }
            function step(list) {
                if (!list.length) { err = ""; return; }
                const why = list[0]();
                if (why) { err = why; return; }
                Qt.callLater(() => Qt.callLater(() => glide.step(list.slice(1))));
            }
            Timer {
                interval: 300; running: true
                onTriggered: glide.step([
                    () => { hl.target = rowA; return ""; },
                    () => (!hl.lit ? "a lit row is not lit" : Math.abs(hl.y - rowA.y) > 0.5 ? "the first row lit is not where the light lands" : Math.abs(hl.x - 2) > 0.5 || Math.abs(hl.width - 236) > 0.5 ? "the inset is not kept" : ""),
                    () => { hl.target = null; return ""; },
                    () => { hl.target = rowB; return ""; },
                    () => (glide.outs || !hl.lit ? "a row rebuilt a moment later put the light out" : ""),
                    () => { hl.instant = true; hl.target = rowA; return Math.abs(hl.y - rowA.y) > 0.5 ? "an instant move did not land at once" : ""; },
                    () => { hl.instant = false; hl.target = rowB; return Theme.reduceMotion || Math.abs(hl.y - rowB.y) > 0.5 ? "" : "a pointer move jumped instead of gliding"; },
                    () => { hl.target = null; return ""; }
                ])
            }
        }
        Timer {
            interval: 1500; running: true
            onTriggered: {
                if (choices.naturalSum > choices.width && !choices.compact) {
                    console.log("UI_SMOKE_FAILED: long choices overflow their control"); Qt.quit(); return;
                }
                if (Math.abs(Theme.textScale - Number(Quickshell.env("KUWAI_UI_TEXT_SCALE") || 1)) > 0.01) { console.log("UI_SMOKE_FAILED: text scale not applied"); Qt.quit(); return; }
                if (glide.err) { console.log("UI_SMOKE_FAILED: fluid highlight: " + glide.err); Qt.quit(); return; }
                if (hl.lit) { console.log("UI_SMOKE_FAILED: fluid highlight: no row lit, and the light stays on"); Qt.quit(); return; }
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
