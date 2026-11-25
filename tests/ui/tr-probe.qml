// Tr in a real (offscreen) Quickshell: run by tests/shell/test_tr_quickshell.py
// under several locales, inside the same bwrap sandbox as bin/kuwai-ui-test.
// Builds the real PowerPanel, reads what its tiles and hint say, measures the
// labels against their tiles, saves a picture, prints one TR_RESULT line.
import QtQuick
import QtQuick.Window
import Quickshell
import qs.config
import qs.components
import qs.modules.island

ShellRoot {
    Window {
        id: scene
        visible: true
        width: Theme.panelM + 40; height: 280
        color: Qt.rgba(0.02, 0.02, 0.027, 1)
        Rectangle { anchors.fill: parent; color: Qt.rgba(0.02, 0.02, 0.027, 1) }
        PowerPanel { id: panel; x: 20; y: 20; width: Theme.panelM; height: implicitHeight }
        Label { id: probe; visible: false; size: Theme.tSub }
        Timer {
            id: grab; interval: 400
            onTriggered: scene.contentItem.grabToImage(r => { r.saveToFile("/out/power.png"); console.log("TR_CAPTURED"); Qt.quit(); })
        }
        Timer {
            interval: 1200; running: true
            onTriggered: {
                function labels(item, out) {
                    // A tile's label: its tile carries the action (tiles grow with their longest label).
                    const tile = item.parent && item.parent.parent;
                    if (item.text !== undefined && item.size === Theme.tSub && tile && tile.modelData && item.text === tile.modelData.label) out.push({ text: item.text, w: Math.ceil(item.implicitWidth), tile: tile.width });
                    for (const c of item.children || []) labels(c, out);
                    return out;
                }
                const hints = panel.actions.map(a => { probe.text = a.hint; return { text: a.hint, w: Math.ceil(probe.implicitWidth) }; });
                const now = new Date();
                const out = {
                    language: Tr.language,
                    locale: Qt.locale().name,
                    tiles: labels(panel, []),
                    tileWidth: (labels(panel, [])[0] || {}).tile || 0,
                    hints: hints,
                    panelWidth: Theme.panelM,
                    today: Dates.day(now),
                    yesterday: Dates.relativeDay(new Date(now.getTime() - 86400000)),
                    missing: Tr.t("A string no catalogue has"),
                    one: Tr.n(1, "{n} update", "{n} updates"),
                    many: Tr.n(5, "{n} update", "{n} updates"),
                    outside: Tr.t("{title}", { title: "Shut Down" }),
                };
                console.log("TR_RESULT " + JSON.stringify(out));
                grab.start();
            }
        }
    }
}
