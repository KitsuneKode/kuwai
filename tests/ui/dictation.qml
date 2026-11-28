import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import qs.components
import qs.config
import qs.services

ShellRoot {
    Window {
        id: stage
        visible: true
        width: 1600; height: 1000
        color: "#000000"

        readonly property string style: Quickshell.env("KUWAI_PILL_STYLE") || "ticker"
        readonly property string seat: Quickshell.env("KUWAI_PILL_SEAT") || ""
        readonly property var contexts: ["composer", "terminal", "maximised", "fullscreen"]
        readonly property var moments: ["quiet", "loud", "long", "transcribing", "delivered", "cancelled", "muted"]
        readonly property var frames: {
            let asked = null;
            try { asked = JSON.parse(Quickshell.env("KUWAI_PILL_FRAMES") || "null"); } catch (e) { asked = null; }
            if (Array.isArray(asked) && asked.length) return asked;
            const out = [];
            for (const c of contexts) for (const m of moments) out.push([c, m]);
            return out;
        }
        property int at: -1
        property string ctx: "composer"
        property string moment: "quiet"
        property var ring: null
        property var pill: null
        property var pillComp: null
        readonly property bool app: ctx !== "terminal" && ctx !== "maxterm"
        readonly property bool preedit: app && style !== "words"
        property bool moved: false
        readonly property var geo: ctx === "maximised" || ctx === "maxterm" ? { x: 0, y: 36, w: 1600, h: 964, fs: 1 }
            : ctx === "fullscreen" ? { x: 0, y: 0, w: 1600, h: 1000, fs: 2 }
            : ctx === "moving" && moved ? { x: 520, y: 60, w: 1000, h: 720, fs: 0 }
            : { x: 300, y: 120, w: 1000, h: 720, fs: 0 }

        readonly property string shortTake: "so the idea is we cache the tokens"
        readonly property string firstTake: "so the idea is we"
        readonly property string finalText: "So the idea is we cache the tokens."
        readonly property string longTake: "okay so for the pill I think the thing that matters most is that it never reads the same words out twice because when the field already shows them underlined the pill saying them again is just noise and my eye keeps jumping between the two places trying to decide which one is the real one and the answer should always be obvious so here is what I want to try first keep the pill small at the bottom of the window let it say that it hears me with the bars and maybe the last few words and then when the field cannot show anything like in the terminal let it open up and show the whole sentence instead and the timer should stay on the right so I know how long I have been talking and when I stop it should polish the text with that shimmer and then land it with the check and if I cancel it should say cancelled and fold away quickly and if the microphone is muted it should tell me straight away instead of listening to nothing for a whole minute and finally when the window is maximised or fullscreen the pill must not sit on top of the composer because that is exactly where the words are going to land and I need to see them while I am still talking so please try three versions and show me pictures of each one in the same places so I can choose the one that feels calm and clear"
        property string liveNow: ""

        Process { id: files; onExited: stage.afterFiles() }
        function writeFiles(then) {
            afterFiles = then;
            const cls = app ? "com.t3tools.T3Code" : "kitty";
            const win = JSON.stringify({ address: "0xa", class: cls, title: app ? "kuwai · dictation" : "~/Projects/kuwai", pid: 7 });
            files.command = ["sh", "-c", 'mkdir -p /run/test/voxtype /run/test/kuwai /run/test/hypr; printf %s "$3" > /run/test/hypr/clients.json; printf %s "$4" > /run/test/hypr/monitors.json; printf %s "$1" > /run/test/voxtype/target_window; if [ "$2" = 1 ]; then : > /run/test/voxtype/live_in_field; else rm -f /run/test/voxtype/live_in_field; fi',
                             "sh", win, preedit ? "1" : "0", JSON.stringify(client()), JSON.stringify(screenInfo())];
            files.running = true;
        }
        property var afterFiles: function() {}

        QtObject {
            id: fakeAudio
            property bool running: true
            signal frameReceived(real peak, real rms, bool vad, real tsMs)
            signal disconnected()
        }
        QtObject {
            id: fakeTheme
            property var config: ({ position: "bottom-center", margin_px: 50, offset_x: 0, offset_y: 0 })
            function color(role, fallback) { return fallback; }
        }
        property string voice: "none"
        property real t0: Date.now()
        Timer {
            interval: 20; repeat: true; running: stage.voice !== "none"
            onTriggered: {
                const t = (Date.now() - stage.t0) / 1000;
                const noise = 0.0011 + Math.random() * 0.0003;
                let p = noise;
                if (stage.voice === "loud") p = Math.max(noise, 0.06 * Math.abs(Math.sin(t * 9)) * (0.55 + 0.45 * Math.sin(t * 1.7)) + Math.random() * 0.01);
                else if (stage.voice === "quiet") p = noise + Math.random() * 0.0004;
                else if (stage.voice === "muted") p = 0;
                fakeAudio.frameReceived(p, p * 0.6, p > 0.01, Date.now());
                if (stage.ring) stage.ring.peak = p;
            }
        }

        function fail(r) { console.log("UI_SMOKE_FAILED: " + r); Qt.quit(); }
        function find(item, pred) { if (pred(item)) return item; for (const c of item.children || []) { const f = find(c, pred); if (f) return f; } return null; }

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0; color: "#2b3a55" }
                GradientStop { position: 0.55; color: "#4a3f63" }
                GradientStop { position: 1; color: "#1d2433" }
            }
        }
        Rectangle {
            visible: stage.ctx !== "fullscreen"
            width: parent.width; height: 36
            color: "#cc0b0b0f"
            Text { x: 16; anchors.verticalCenter: parent.verticalCenter; text: "1  2  3"; color: "#a1a1aa"; font.pixelSize: 13 }
            Text { anchors.centerIn: parent; text: "21:40"; color: "#e4e4e7"; font.pixelSize: 13; font.weight: Font.DemiBold }
        }
        Rectangle {
            id: win
            x: stage.geo.x; y: stage.geo.y; width: stage.geo.w; height: stage.geo.h
            radius: stage.geo.fs === 2 ? 0 : 18
            color: stage.app ? "#0e0e11" : "#0b0b0e"
            border.width: stage.geo.fs === 2 ? 0 : 2
            border.color: "#33333a"
            clip: true

            Item {
                id: t3
                anchors.fill: parent
                visible: stage.app
                Rectangle {
                    id: side
                    width: 230; height: parent.height
                    color: "#121216"
                    radius: win.radius
                    Column {
                        x: 18; y: 22; spacing: 14
                        Text { text: "Threads"; color: "#71717a"; font.pixelSize: 12; font.weight: Font.DemiBold }
                        Repeater {
                            model: ["Dictation pill variants", "Meeting activity", "Ring on fullscreen", "Shutdown crash", "Text size audit", "kittymux card"]
                            Text { required property string modelData; required property int index; text: modelData; color: index === 0 ? "#f4f4f5" : "#a1a1aa"; font.pixelSize: 13 }
                        }
                    }
                }
                Item {
                    id: main
                    x: side.width; width: parent.width - side.width; height: parent.height
                    Text { x: 24; y: 14; text: "kuwai · Dictation pill variants"; color: "#e4e4e7"; font.pixelSize: 14; font.weight: Font.DemiBold }
                    Rectangle { y: 44; width: parent.width; height: 1; color: "#1f1f24" }
                    Rectangle {
                        x: parent.width - width - 40; y: 76
                        width: ask.implicitWidth + 28; height: ask.implicitHeight + 18; radius: 14
                        color: "#1f1f25"
                        Text { id: ask; anchors.centerIn: parent; text: "Can the pill stop reading my words out twice?"; color: "#e4e4e7"; font.pixelSize: 14 }
                    }
                    Text {
                        x: 40; y: 140; width: Math.min(680, parent.width - 80)
                        wrapMode: Text.WordWrap; lineHeight: 1.3
                        color: "#d4d4d8"; font.pixelSize: 14
                        text: "Yes. Three ways to try: all the words in the pill with the field left alone, the words in the field with a short ticker on the window, or the words in the field with a pill that only shows the level and the time. Each one is pictured in the same places so you can compare them."
                    }
                    Rectangle {
                        id: composer
                        width: Math.min(720, main.width - 48)
                        x: (main.width - width) / 2
                        height: Math.min(field.contentHeight, 6 * 19) + 26 + 40
                        y: main.height - height - 18
                        radius: 18
                        color: "#18181c"
                        border.width: 1; border.color: "#2a2a30"
                        Item {
                            x: 16; y: 14; width: parent.width - 32
                            height: Math.min(field.contentHeight, 6 * 19)
                            clip: true
                            Text {
                                id: field
                                width: parent.width
                                y: Math.min(0, parent.height - contentHeight)
                                wrapMode: Text.WordWrap
                                lineHeight: 19; lineHeightMode: Text.FixedHeight
                                font.pixelSize: 14
                                font.underline: stage.fieldPreedit && stage.fieldText !== ""
                                color: stage.fieldText !== "" ? "#e4e4e7" : "#71717a"
                                text: stage.fieldText !== "" ? stage.fieldText : "Ask for follow-up changes or attach images"
                            }
                        }
                        Row {
                            x: 12; y: parent.height - 36; spacing: 8
                            Repeater {
                                model: ["Opus 5.5", "Full access"]
                                Rectangle { required property string modelData; width: chip.implicitWidth + 18; height: 26; radius: 13; color: "#222228"; Text { id: chip; anchors.centerIn: parent; text: parent.modelData; color: "#a1a1aa"; font.pixelSize: 12 } }
                            }
                        }
                        Rectangle {
                            x: parent.width - 40; y: parent.height - 38; width: 28; height: 28; radius: 14
                            color: "#e4e4e7"
                            Text { anchors.centerIn: parent; text: "↑"; color: "#18181c"; font.pixelSize: 15; font.weight: Font.Bold }
                        }
                    }
                }
            }
            Item {
                id: term
                readonly property Item prompt: termLines.children[termLines.children.length - 1]
                anchors.fill: parent
                visible: !stage.app
                Column {
                    id: termLines
                    x: 18; y: parent.height - height - 18; spacing: 3
                    Repeater {
                        model: ["~/Projects/kuwai  main ❯ git log --oneline -4", "148f8b0 Merge branch 't3/kuwai-meeting-activity-ui'", "3602b7a The dictation caption reads the in-field marker again", "38ba575 Meetings in the island: voxtype's meeting mode", "a68f48b The dictation ring shows on every window", "~/Projects/kuwai  main ❯ bun test", "  1486 pass", "  0 fail", "Ran 1486 tests across 212 files. [9.41s]"]
                        Text { required property string modelData; text: modelData; color: "#a1a1aa"; font.family: Theme.fontMono; font.pixelSize: 14 }
                    }
                    Row {
                        Text { text: "~/Projects/kuwai  main ❯ "; color: "#8be9fd"; font.family: Theme.fontMono; font.pixelSize: 14 }
                        Text { text: stage.fieldText; color: "#f4f4f5"; font.family: Theme.fontMono; font.pixelSize: 14 }
                        Rectangle { width: 9; height: 17; color: "#d4d4d8" }
                    }
                }
            }
        }
        property string fieldText: ""
        property bool fieldPreedit: false
        Item { id: ringLayer; width: parent.width; height: parent.height }
        Item { id: pillLayer; anchors.fill: parent }

        function adoptRing() {
            for (const w of RehearsalWindows.store.list) {
                if (!w || !w.contentItem) continue;
                for (const c of Array.from(w.contentItem.children)) c.parent = ringLayer;
            }
            RehearsalWindows.store.list = [];
        }
        function screenInfo() {
            return [{ id: 0, name: Quickshell.screens[0].name, x: 0, y: 0, width: 1600, height: 1000, scale: 1, transform: 0,
                      reserved: [0, 36, 0, 0], activeWorkspace: { id: 1, name: "1" }, specialWorkspace: { name: "" } }];
        }
        function client() {
            return [{ address: "0xa", mapped: true, hidden: false, monitor: 0, fullscreen: geo.fs,
                      workspace: { id: 1, name: "1" }, at: [geo.x, geo.y], size: [geo.w, geo.h] }];
        }
        function setVox(state, text) {
            Activities.voxState = state;
            Activities.voxInField = preedit;
            Activities.voxText = text.slice(-160);
        }
        function say(text) {
            liveNow = text;
            if (pill) pill.liveText = text;
            setVox(Activities.voxState, text);
            fieldPreedit = preedit;
            fieldText = preedit ? text : "";
        }

        property var steps: []
        Timer { id: stepper; onTriggered: stage.runStep() }
        function runStep() {
            const s = steps.shift();
            if (!s) return;
            s[1]();
            if (steps.length) { stepper.interval = Math.max(1, steps[0][0] - s[0]); stepper.restart(); }
        }
        function play(list) { steps = list; stepper.interval = list[0][0] || 1; stepper.restart(); }

        function next() {
            if (pill) { pill.destroy(); pill = null; }
            voice = "none";
            if (++at >= frames.length) { console.log("UI_SMOKE_CAPTURED"); Qt.quit(); return; }
            ctx = frames[at][0];
            moment = frames[at][1];
            fieldText = ""; fieldPreedit = false; liveNow = ""; moved = false;
            Activities.voxState = "idle";
            Activities.voxText = "";
            gap.restart();
        }
        Timer { id: gap; interval: 450; onTriggered: stage.writeFiles(stage.begin) }
        function begin() {
            setVox("streaming", "");
            ring.read("0xa", client(), screenInfo(), { int: 18 }, { int: 2 });
            adoptLater.restart();
            const props = { width: stage.width, height: stage.height, theme: fakeTheme, audio: fakeAudio };
            if (seat) props.insideSeat = seat;
            pill = pillComp.createObject(pillLayer, props);
            if (!pill) { fail("the pill did not start: " + pillComp.errorString()); return; }
            takeLater.restart();
        }
        Timer { id: takeLater; interval: 400; onTriggered: stage.take() }
        function take() {
            t0 = Date.now();
            pill.daemonState = "streaming";
            const back = moment === "long" ? 124000 : moment === "quiet" || moment === "muted" ? 3200 : 0;
            if (back) pill.localStart = Date.now() - back;
            voice = moment === "muted" ? "muted" : moment === "quiet" ? "quiet" : "loud";
            const words = moment === "long" ? [longTake.split(" ").slice(0, -12).join(" "), longTake] : [firstTake, shortTake];
            const finish = (ms) => [ms, () => stage.capture()];
            if (ctx === "moving") play([[300, () => say(words[0])], [700, () => say(words[1])],
                [900, () => { moved = true; ring.read("0xa", client(), screenInfo(), { int: 18 }, { int: 2 }); }],
                [940, () => stage.capture("move-mid", true)], finish(1700)]);
            else if (moment === "quiet") play([finish(1600)]);
            else if (moment === "muted") play([finish(1200)]);
            else if (moment === "loud" || moment === "long") play([[300, () => say(words[0])], [700, () => say(words[1])], finish(1500)]);
            else if (moment === "transcribing") play([[300, () => say(words[0])], [700, () => say(words[1])],
                [900, () => { voice = "none"; setVox("transcribing", liveNow); pill.daemonState = "transcribing"; }], finish(1500)]);
            else if (moment === "delivered") play([[300, () => say(words[0])], [700, () => say(words[1])],
                [900, () => { voice = "none"; setVox("transcribing", liveNow); pill.daemonState = "transcribing"; }],
                [1200, () => { pill.outputDoneAt = Date.now(); setVox("idle", ""); fieldPreedit = false; fieldText = finalText; pill.daemonState = "idle"; }], finish(1660)]);
            else if (moment === "cancelled") play([[300, () => say(words[0])], [700, () => say(words[1])],
                [1000, () => { voice = "none"; pill.cancelledAt = Date.now(); setVox("idle", ""); fieldPreedit = false; fieldText = ""; pill.daemonState = "idle"; }], finish(1300)]);
        }
        Timer { id: adoptLater; interval: 120; onTriggered: stage.adoptRing() }
        function rect(item) { if (!item) return null; const r = item.mapToItem(stage.contentItem, 0, 0, item.width, item.height); return [Math.round(r.x), Math.round(r.y), Math.round(r.width), Math.round(r.height)]; }
        function capture(tag, more) {
            adoptRing();
            const name = tag || moment;
            const card = pill ? find(pill, c => c.fullW !== undefined && c.morph !== undefined) : null;
            const fieldBox = app ? rect(composer) : ctx === "maxterm" ? rect(term.prompt) : rect(termLines);
            console.log("PILL_FRAME " + JSON.stringify({ ctx: ctx, moment: name, style: style, seat: seat, pill: card && card.opacity > 0.02 ? rect(card) : null, field: fieldBox,
                                                         window: [geo.x, geo.y, geo.w, geo.h], caption: Activities.voxListening }));
            stage.contentItem.grabToImage(result => {
                if (!result.saveToFile("/out/" + ctx + "__" + name + ".png")) { stage.fail("capture failed: " + ctx + " " + name); return; }
                if (!more) stage.next();
            });
        }
        Timer {
            id: ready
            interval: 900; running: true
            onTriggered: {
                if (Settings.pending || Settings.error) { stage.fail("settings did not acknowledge"); return; }
                const vt = Qt.createComponent(Qt.resolvedUrl("modules/voxtype/VoxTarget.qml"));
                if (vt.status !== Component.Ready) { stage.fail("VoxTarget did not load: " + vt.errorString()); return; }
                stage.ring = vt.createObject(stage);
                stage.pillComp = Qt.createComponent("file:///app/pill/KitsuneHud.qml");
                if (stage.pillComp.status !== Component.Ready) { stage.fail("the pill did not load: " + stage.pillComp.errorString()); return; }
                stage.next();
            }
        }
        Component.onCompleted: {
            Settings.set("textScale", Number(Quickshell.env("KUWAI_UI_TEXT_SCALE") || 1));
            Settings.set("dictationPill", style);
            Notifs.shareKnown = true;
        }
    }
}
