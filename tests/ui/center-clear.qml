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
        width: 440; height: 620
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
            property bool instant: false
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
        TestCase { id: t; name: "CenterClear"; when: false }

        property var log: []
        function fail(reason) { console.log("UI_SMOKE_FAILED: " + reason); Qt.quit(); }
        function item(id, app, title, ago) {
            const o = { id: id, app: app, title: title, body: "Body of " + title + ", long enough to wrap onto a second line here.", time: Date.now() - ago * 60000, actions: [], status: "", statusGlyph: "", statusTone: "", severity: "normal", icon: "", focusClass: app === "Firefox" ? "firefox" : "" };
            o.toJson = () => ({ nid: o.id, time: o.time, app: o.app, title: o.title, body: o.body });
            o.destroy = () => {};
            return o;
        }
        function seed() {
            const apps = ["Mail", "Slack", "T3 Code", "Firefox"];
            const out = [];
            let n = 0;
            for (let a = 0; a < apps.length; a++)
                for (let k = 0; k < 3; k++) out.push(item(7000 + n, apps[a], apps[a] + " message " + (k + 1), ++n));
            return out;
        }
        function shown() {
            const list = content.notifications.list;
            let drawn = 0, groups = 0;
            for (const c of list.contentItem.children) {
                if (!c.modelData || !c.modelData.items) continue;
                const top = c.y - list.contentY, bottom = top + c.height;
                if (bottom <= 0 || top >= list.height) continue;
                groups++;
                let o = c.opacity;
                for (let p = c.parent; p && p !== scene.contentItem; p = p.parent) o *= p.opacity;
                if (o > 0.5 && c.visible) drawn++;
            }
            return { drawn: drawn, inView: groups, groups: content.notifications.groups.length, listOpacity: list.opacity };
        }
        function find(root, test) {
            if (!root) return null;
            if (test(root)) return root;
            for (const c of root.children || []) { const f = scene.find(c, test); if (f) return f; }
            return null;
        }
        function rowOf(item) { return scene.find(content.notifications.list.contentItem, c => c.item === item && c.canOpen !== undefined && c.visible); }
        function picture(name) {
            scene.contentItem.grabToImage(r => r.saveToFile("/out/" + name + ".png"));
            t.wait(150);
        }
        function step(name, expectGroups) {
            t.wait(900);
            const s = scene.shown();
            console.log("CENTER_CLEAR " + name + " " + JSON.stringify(s));
            scene.picture(name);
            if (s.groups !== expectGroups) return "after " + name + ": " + s.groups + " groups, expected " + expectGroups;
            if (s.groups > 0 && s.drawn < Math.min(s.inView, s.groups)) return "after " + name + ": " + s.drawn + " of " + s.inView + " groups in view are drawn (list opacity " + s.listOpacity + ")";
            if (s.groups > 0 && s.listOpacity < 0.99) return "after " + name + ": the list is at opacity " + s.listOpacity;
            return "";
        }
        Timer {
            interval: 600; running: true
            onTriggered: {
                Notifs.centerTab = "notifications";
                Notifs.items = scene.seed();
                let why = scene.step("seeded", 4);
                if (!why) { Notifs.removeApp("Mail", "center"); why = scene.step("group-cleared", 3); }
                if (!why) { Notifs.undoClear(); why = scene.step("group-undone", 4); }
                if (!why) { content.notifications.clearAll(); why = scene.step("all-cleared", 0); }
                if (!why) { Notifs.undoClear(); why = scene.step("all-undone", 4); }
                if (!why) { content.notifications.clearAll(); t.wait(900); Notifs.items = [scene.item(7100, "Signal", "A new one", 0)].concat(Notifs.items); why = scene.step("new-after-clear", 1); }
                if (!why) { Notifs.items = scene.seed(); Notifs.removeApp("Slack", "center"); t.wait(100); Notifs.removeApp("Mail", "center"); why = scene.step("two-groups-quickly", 2); }
                if (!why) {
                    Notifs.items = scene.seed();
                    t.wait(900);
                    const ff = Notifs.items.find(i => i.app === "Firefox");
                    const mail = Notifs.items.find(i => i.app === "Mail");
                    let r = scene.rowOf(mail);
                    if (!r) why = "no row for Mail";
                    else {
                        t.mouseClick(r, r.width / 2, 20, Qt.RightButton);
                        t.wait(400);
                        const menu = scene.find(scene.contentItem, c => c.Accessible && c.Accessible.role === Accessible.PopupMenu && c.visible && c.opacity > 0.5);
                        scene.picture("row-menu");
                        if (!menu) why = "right-click on a row opened no menu";
                        else if (!Notifs.items.includes(mail)) why = "right-click dismissed the row instead of opening its menu";
                        t.keyClick(Qt.Key_Escape);
                        t.wait(300);
                    }
                    if (!why) {
                        content.notifications.list.positionViewAtEnd();
                        t.wait(400);
                        r = scene.rowOf(ff);
                        if (!r) why = "no row for Firefox";
                        else {
                            t.mouseClick(r, r.width / 2, 20);
                            t.wait(600);
                            if (!Notifs.items.includes(ff)) why = "a click on a folded stack opened its top notification instead of unfolding it";
                            r = scene.rowOf(ff);
                            if (!why && r) { t.mouseClick(r, r.width / 2, 20); t.wait(900); }
                            if (!why && Notifs.items.includes(ff)) why = "a click on a row that can open left it in the list";
                        }
                    }
                }
                if (why) { scene.fail(why); return; }
                Notifs.items = [];
                t.wait(300);
                console.log("UI_SMOKE_CAPTURED");
                Qt.quit();
            }
        }
    }
}
