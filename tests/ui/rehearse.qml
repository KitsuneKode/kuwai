// The rehearsal stage (docs/design/REHEARSAL.md): every island panel, in each
// of its states, in a private window, as the island would hold it. For each
// scene it takes a picture and writes down what is on it (every text with its
// box, size and colour; every click target; every scrolling area), so
// bin/kuwai-rehearse can judge the frame by rule and put it on a contact sheet.
//
// Run by bin/kuwai-ui-test --case rehearse (never by hand in the session): the
// helpers are inert there, so a panel with no scene data shows what a new
// machine shows.
import QtQuick
import QtQuick.Window
import Quickshell
import qs.components
import qs.config
import qs.services
import qs.modules.island
import qs.modules.lock

ShellRoot {
    Window {
        id: stage
        visible: true
        // The island's window on a 1080p screen (IslandBar: 1120 x 640, and a
        // panel may take all but 40 of each).
        width: 1120; height: 640
        // The brightest thing a wallpaper can put behind the island: the
        // island's black is 94 % opaque, so this is its lightest ground.
        color: "#ffffff"

        readonly property var scenes: /*SCENES*/[]
        property int at: -1
        property var undo: []

        function service(name) {
            switch (name) {
            /*SERVICES*/
            }
            return null;
        }

        readonly property bool screen: at >= 0 && at < scenes.length && !!scenes[at].screen
        QtObject {
            id: fakeLock
            property string password: ""
            property bool checking: false
            property string error: ""
            property int failures: 0
            property bool leaving: false
            property string challenge: ""
            property var openAfter: null
            property bool fingerReady: false
            property string note: ""
            function submit() {}
        }
        Item {
            id: island
            anchors.horizontalCenter: parent.horizontalCenter
            width: stage.screen ? 1066 : panel.item ? Math.min(panel.item.implicitWidth, stage.width - 40) : 0
            height: stage.screen ? 600 : panel.item ? Math.min(panel.item.implicitHeight, stage.height - 40) : 0
            Rectangle { visible: !stage.screen; anchors.fill: parent; radius: Theme.r4; color: Qt.rgba(0, 0, 0, 0.94) }
            Loader { id: panel; anchors.fill: parent; focus: true }
        }

        function fail(reason) { console.log("UI_SMOKE_FAILED: " + reason); Qt.quit(); }
        function r1(v) { return Math.round(v * 10) / 10; }
        function box(item, x, y, w, h) {
            const r = item.mapToItem(island, x, y, w, h);
            return [r1(r.x), r1(r.y), r1(r.width), r1(r.height)];
        }
        function meet(a, b) {            // two boxes' common part
            if (!a) return b;
            const x = Math.max(a[0], b[0]), y = Math.max(a[1], b[1]);
            return [x, y, Math.max(0, Math.min(a[0] + a[2], b[0] + b[2]) - x), Math.max(0, Math.min(a[1] + a[3], b[1] + b[3]) - y)];
        }
        function kind(item) { return String(item).replace(/_QML.*|\(.*/g, "").replace(/^QQuick/, ""); }

        // What is on the frame. `ctx`: the clip in force, the opacity so far,
        // whether a scrolling area holds this, the path of types to here, and
        // how many floating surfaces it sits in (`layer`). A surface that floats
        // over the panel (a menu) says `floats: true`; what it covers is
        // recorded so the gate doesn't judge what lies beneath it.
        function walk(item, ctx, out) {
            if (!item.visible || item.opacity < 0.02) return;
            const name = kind(item);
            const here = { clip: ctx.clip, op: ctx.op * item.opacity, scroll: ctx.scroll, path: ctx.path.concat(name).slice(-5), layer: ctx.layer };
            if (item.floats === true) {
                here.layer = ctx.layer + 1;
                out.covers.push({ box: box(item, 0, 0, item.width, item.height), layer: here.layer });
            }
            if (item instanceof Flickable) {
                const b = box(item, 0, 0, item.width, item.height);
                out.scrolls.push({ box: b, clips: item.clip, w: r1(item.contentWidth), h: r1(item.contentHeight) });
                here.scroll = true;
                here.clip = meet(here.clip, b);
            } else if (item.clip || name === "ClippingRectangle") {
                here.clip = meet(here.clip, box(item, 0, 0, item.width, item.height));
            }
            if (item instanceof Text && item.text !== "") {
                const cw = item.contentWidth, ch = item.contentHeight;
                const freeW = item.width - item.leftPadding - item.rightPadding - cw;
                const freeH = item.height - item.topPadding - item.bottomPadding - ch;
                const ha = item.effectiveHorizontalAlignment, va = item.verticalAlignment;
                const cx = item.leftPadding + (ha === Text.AlignHCenter ? freeW / 2 : ha === Text.AlignRight ? freeW : 0);
                const cy = item.topPadding + (va === Text.AlignVCenter ? freeH / 2 : va === Text.AlignBottom ? freeH : 0);
                out.texts.push({
                    t: item.text.slice(0, 60), box: box(item, cx, cy, cw, ch), own: box(item, 0, 0, item.width, item.height),
                    size: item.font.pixelSize, weight: item.font.weight, family: item.font.family, drawn: item.fontInfo.family,
                    color: String(item.color), op: r1(here.op), on: item.enabled,
                    cut: item.truncated, elides: item.elide !== Text.ElideNone, wraps: item.wrapMode !== Text.NoWrap,
                    lines: item.lineCount, clip: here.clip, scroll: here.scroll, path: here.path.join(">"), layer: here.layer
                });
            }
            if (name === "Skeleton") out.waiting++;
            if (item instanceof MouseArea && item.enabled && item.acceptedButtons !== Qt.NoButton)
                out.targets.push({ box: box(item, 0, 0, item.width, item.height), how: "area", clip: here.clip, scroll: here.scroll, path: here.path.join(">"), layer: here.layer });
            const more = item.resources || [];
            for (let i = 0; i < more.length; i++) {
                const h = more[i];
                if (h instanceof TapHandler && h.enabled && (h.acceptedButtons & Qt.LeftButton)) {
                    const m = h.margin || 0;
                    out.targets.push({ box: box(item, -m, -m, item.width + 2 * m, item.height + 2 * m), how: "tap", clip: here.clip, scroll: here.scroll, path: here.path.join(">"), layer: here.layer });
                }
            }
            const kids = item.children || [];
            for (let i = 0; i < kids.length; i++) walk(kids[i], here, out);
        }

        function restore() {
            for (let i = undo.length - 1; i >= 0; i--) {
                if (undo[i][0] === Settings) Settings.set(undo[i][1], undo[i][2]);
                else undo[i][0][undo[i][1]] = undo[i][2];
            }
            undo = [];
        }
        function applySets(s, sets) {
            for (const one of sets) {
                if (one[0] === "@setting") {
                    undo.push([Settings, one[1], Settings.value(one[1])]);
                    if (!Settings.set(one[1], one[2])) { fail("scene " + s.id + ": setting " + one[1] + " refused"); return false; }
                    continue;
                }
                const svc = service(one[0]);
                if (!svc) { fail("scene " + s.id + " names an unknown service: " + one[0]); return false; }
                if (one[1] === "call") { svc[one[2]].apply(svc, one[3] || []); continue; }
                if (!(one[1] in svc)) { fail("scene " + s.id + ": " + one[0] + " has no " + one[1]); return false; }
                undo.push([svc, one[1], svc[one[1]]]);
                svc[one[1]] = one[2];
            }
            return true;
        }
        property bool lateDone: false
        property bool hideDone: false
        function hideKinds(item, kinds) {
            if (kinds.indexOf(kind(item)) >= 0) { item.visible = false; return; }
            const kids = item.children || [];
            for (let i = 0; i < kids.length; i++) hideKinds(kids[i], kinds);
        }
        function next() {
            restore();
            lateDone = false;
            hideDone = false;
            panel.source = "";
            if (++at >= scenes.length) { console.log("UI_SMOKE_CAPTURED"); Qt.quit(); return; }
            const s = scenes[at];
            if (!applySets(s, [["Island", "panel", s.name]].concat(s.set || []))) return;
            // A property given as "@date:2026-11-18T10:10:00" is that moment (a
            // panel that shows today would otherwise differ every day).
            const props = {};
            for (const k in (s.props || {})) {
                const v = s.props[k];
                props[k] = v === "@lock" ? fakeLock : typeof v === "string" && v.indexOf("@date:") === 0 ? new Date(v.slice(6)) : v;
            }
            panel.setSource(Qt.resolvedUrl("modules/island/" + s.panel + ".qml"), props);
            if (panel.status === Loader.Error) { fail("scene " + s.id + ": " + s.panel + " did not load"); return; }
            settle.interval = s.settle || 700;
            settle.restart();
        }
        Timer {
            id: settle
            onTriggered: {
                const s = stage.scenes[stage.at], it = panel.item;
                if (!it) { stage.fail("scene " + s.id + ": nothing loaded"); return; }
                if (s.hide && !stage.hideDone) {
                    stage.hideDone = true;
                    stage.hideKinds(it, s.hide);
                    settle.interval = 250;
                    settle.restart();
                    return;
                }
                if (s.late && !stage.lateDone) {
                    stage.lateDone = true;
                    if (!stage.applySets(s, s.late)) return;
                    settle.interval = 250;
                    settle.restart();
                    return;
                }
                const out = { id: s.id, panel: s.panel, kind: s.kind || "typical", scale: Theme.textScale,
                              w: island.width, h: island.height, wants: stage.screen ? [island.width, island.height] : [stage.r1(it.implicitWidth), stage.r1(it.implicitHeight)],
                              texts: [], targets: [], scrolls: [], covers: [], waiting: 0 };
                stage.walk(it, { clip: null, op: 1, scroll: false, path: [], layer: 0 }, out);
                // In pieces: a log line has a length the logger may cut.
                const json = JSON.stringify(out);
                for (let i = 0, n = 0; i < json.length; i += 3000, n++) console.log("REHEARSE_PART", s.id, n, json.slice(i, i + 3000));
                console.log("REHEARSE_END", s.id);
                const px = Number(Quickshell.env("KUWAI_UI_PIXELS") || 1);
                island.grabToImage(result => {
                    if (!result.saveToFile("/out/" + s.id.replace(/[^\w.-]+/g, "_") + ".png")) { stage.fail("capture failed: " + s.id); return; }
                    stage.next();
                }, px === 1 ? Qt.size(0, 0) : Qt.size(Math.round(island.width * px), Math.round(island.height * px)));
            }
        }
        Timer {
            // Settings answers through its helper; the first scene waits for it.
            interval: 900; running: true
            onTriggered: {
                if (Settings.pending || Settings.error) { stage.fail("settings did not acknowledge"); return; }
                stage.next();
            }
        }
        Component.onCompleted: {
            Settings.set("textScale", Number(Quickshell.env("KUWAI_UI_TEXT_SCALE") || 1));
            // A service starts when it is first named, and reads its files a
            // moment later: every service a scene sets is woken now, so what a
            // seed file holds is loaded before the first scene and not into the
            // middle of one (a scene's "empty" list was filled behind its back).
            for (const s of scenes) for (const one of (s.set || [])) service(one[0]);
        }
    }
}
