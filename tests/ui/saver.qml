import QtQuick
import QtQuick.Window
import Quickshell
import qs.config
import qs.services
import qs.modules.screensaver

ShellRoot {
    Window {
        id: win
        visible: true
        width: 960; height: 540
        color: "black"

        property int step: -1
        property var accents: ["", "#fc2e64", "#2fb88a"]

        function fail(reason) { console.log("UI_SMOKE_FAILED: " + reason); Qt.quit(); }
        function save(item, name, then) {
            item.grabToImage(result => {
                if (!result.saveToFile("/out/" + name + ".png")) { fail("capture failed: " + name); return; }
                then();
            });
        }

        Item {
            id: paint
            width: 960; height: 540
            visible: false
            property color from: "#d9a066"
            property color to: "#7a3b52"
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0; color: paint.from }
                    GradientStop { position: 1; color: paint.to }
                }
                Rectangle { x: 120; y: 120; width: 220; height: 220; radius: 110; color: Qt.rgba(1, 1, 1, 0.25) }
            }
        }

        Item { id: stage; anchors.fill: parent }

        Rectangle {
            id: clockWall
            parent: stage
            anchors.fill: parent
            visible: false
            property color from: "#d9a066"
            property color to: "#7a3b52"
            gradient: Gradient {
                GradientStop { position: 0; color: clockWall.from }
                GradientStop { position: 1; color: clockWall.to }
            }
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.15) }
                    GradientStop { position: 0.6; color: Qt.rgba(0, 0, 0, 0.25) }
                    GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.55) }
                }
            }
            SaverClock { id: sclock; areaW: 960; areaH: 540; showing: false }
        }

        Rectangle {
            id: pulseBox
            parent: stage
            width: 640; height: 96
            color: "#0a0a0d"
            visible: false
            MediaPulse {
                id: pulse
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                active: true
                size: 22
                maxWidth: 520
                title: "Teardrop · Massive Attack"
            }
        }
        property var pulseTitles: ["Teardrop · Massive Attack", "A very long title that goes on and on about nothing in particular, the whole second movement · Some Orchestra of Somewhere"]

        Loader { id: flow; parent: stage; anchors.fill: parent; active: false; sourceComponent: FlowScene { running: false; t: win.flowT } }
        property real flowT: 0

        Loader {
            id: photos
            parent: stage; anchors.fill: parent
            active: false
            sourceComponent: PhotoShuffle {
                paths: ["/out/photo-1.png", "/out/photo-2.png", "/out/photo-3.png", "/out/missing.png"]
                seed: 7
                running: false
                holdMs: 60000
            }
        }

        property var wallPaints: [["#d9a066", "#7a3b52"], ["#4a7fa8", "#16304a"], ["#6fae7a", "#1d3b2a"]]
        property int made: 0
        function makePhotos() {
            if (made >= wallPaints.length) { next(); return; }
            paint.from = wallPaints[made][0]; paint.to = wallPaints[made][1];
            paint.visible = true;
            save(paint, "photo-" + (made + 1), () => { paint.visible = false; made++; makePhotos(); });
        }

        function flowFrame(i) {
            if (i >= accents.length) { flow.active = false; next(); return; }
            const was = Theme.accent;
            if (accents[i] !== "") Theme.accent = accents[i];
            flowT = i * 400;
            flow.active = true;
            settle.run(500, () => {
                const dark = flow.item ? true : false;
                if (!dark) { fail("flow did not load"); return; }
                save(stage, "flow-" + i, () => { Theme.accent = was; flowFrame(i + 1); });
            });
        }

        function photoRun() {
            photos.active = true;
            settle.run(1500, () => {
                const p = photos.item;
                if (!p || p.count !== 4) { fail("photos: " + (p ? p.count : "none")); return; }
                console.log("SAVER_PHOTOS first", JSON.stringify({ at: p.at, front: p.front.idx, back: p.back.idx, frontReady: p.front.status === Image.Ready, backReady: p.back.status === Image.Ready }));
                if (p.front.status !== Image.Ready) { fail("photos: nothing showing"); return; }
                save(stage, "photos-1", () => {
                    if (!p.advance()) { fail("photos: could not start the fade"); return; }
                    settle.run(Theme.saverPhotoFadeMs / 2, () => {
                        console.log("SAVER_PHOTOS mid", JSON.stringify({ fade: p.fade }));
                        save(stage, "photos-mid", () => {
                            settle.run(Theme.saverPhotoFadeMs, () => {
                                console.log("SAVER_PHOTOS landed", JSON.stringify({ at: p.at, fade: p.fade, front: p.front.idx, back: p.back.idx, bad: Object.keys(p.bad).join(",") }));
                                if (p.fade !== 0 || p.at !== p.front.idx) { fail("photos: the swap did not land"); return; }
                                save(stage, "photos-2", () => { photos.active = false; next(); });
                            });
                        });
                    });
                });
            });
        }

        function pulseRun() {
            pulseBox.visible = true;
            const moved = pulse.phase;
            settle.run(500, () => {
                console.log("SAVER_PULSE", JSON.stringify({ reduced: Theme.reduceMotion, moved: pulse.phase !== moved, phase: pulse.phase }));
                if (Theme.reduceMotion === (pulse.phase !== moved)) { fail("pulse: motion does not follow reduced motion"); return; }
                pulse.phase = 0.15;
                save(pulseBox, "pulse-0", () => {
                    pulse.phase = 0.7;
                    save(pulseBox, "pulse-1", () => {
                        pulse.title = pulseTitles[1];
                        pulse.phase = 0.4;
                        save(pulseBox, "pulse-long", () => { pulse.active = false; pulseBox.visible = false; next(); });
                    });
                });
            });
        }

        function clockRun() {
            Settings.set("notifPrivacy", "never");
            Weather.ok = true; Weather.temp = 14; Weather.desc = "Light rain";
            Calendar.events = [{ start: Date.now() + 900000, end: Date.now() + 4500000, title: "Design review with the platform team", location: "", allDay: false, private: false }];
            Media.stagePlayer({ identity: "Spotify", trackTitle: "Slow Tide", trackArtist: "The Paper Lanterns", metadata: {}, playbackState: 1, isPlaying: true });
            clockWall.visible = true;
            sclock.showing = true;
            settle.run(Theme.saverMoveMs + 600, () => {
                const inside = sclock.x >= 0 && sclock.y >= 0 && sclock.x + sclock.width <= sclock.areaW + 0.5 && sclock.y + sclock.height <= sclock.areaH + 0.5;
                console.log("SAVER_CLOCK", JSON.stringify({ scale: Theme.textScale, x: sclock.x, y: sclock.y, w: sclock.width, h: sclock.height, digits: sclock.digits.height, inside: inside, text: sclock.digits.text }));
                if (!inside) { fail("clock: the face does not fit the screen at text " + Theme.textScale); return; }
                save(clockWall, "clock-full", () => {
                    Weather.ok = false; Calendar.events = []; Media.active = null;
                    settle.run(Theme.saverMoveMs + 600, () => {
                        save(clockWall, "clock-bare", () => {
                            sclock.dark = true; sclock.level = 0.8;
                            settle.run(300, () => {
                                save(clockWall, "clock-long", () => { sclock.showing = false; clockWall.visible = false; next(); });
                            });
                        });
                    });
                });
            });
        }

        Timer {
            id: settle
            property var then: null
            function run(ms, fn) { then = fn; interval = ms; restart(); }
            onTriggered: { const f = then; then = null; if (f) f(); }
        }

        function next() {
            step++;
            if (step === 0) makePhotos();
            else if (step === 1) flowFrame(0);
            else if (step === 2) photoRun();
            else if (step === 3) pulseRun();
            else if (step === 4) clockRun();
            else { console.log("UI_SMOKE_CAPTURED"); Qt.quit(); }
        }
        Timer { interval: 600; running: true; onTriggered: { Settings.set("textScale", Number(Quickshell.env("KUWAI_UI_TEXT_SCALE") || 1)); win.next(); } }
    }
}
