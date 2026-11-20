// Idle cost: the island with a capsule out and the login face, at rest, must
// draw nothing. Counts each window's frames over a quiet 7 s once everything
// settled (private X11, real motion: bin/kuwai-ui-test --case idle --backend
// x11 --motion full; bin/kuwai-rehearse runs it). Before 2026-11-20 a capsule
// re-took its swap snapshot every 500 ms (8 frames in 4 s), a hidden working
// ring turned on every beat (a frame every 3 s), and the login's clock woke
// every second for a face that shows minutes.
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
        id: scene
        visible: true
        width: 480; height: 120
        color: Theme.glassSolid
        property int frames: 0
        property bool counting: false
        onFrameSwapped: if (counting) { frames++; console.log("IDLE_FRAME_AT island", Date.now() % 100000); }
        QtObject {
            id: fakeBar
            property string screenName: "fixture"
            property var player: QtObject {
                property bool isPlaying: false
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
        }
        Component.onCompleted: {
            Settings.set("islandSplit", true);
            Kittymux.feedPinned = true;
            // A state that draws nothing by itself (no spinner, no working ring).
            Kittymux.feed = { version: 1, agents: [
                { key: "fixture-1", agent: "codex", brand: "codex", title: "Fixture", state: "limited", account: "personal", limit_reset: Math.round(Date.now() / 1000) + 5400 }
            ] };
            T3Code.running = 0;
        }
        Timer {
            id: settle
            interval: 2500; running: true
            onTriggered: {
                const out = split.pills.filter(p => p.out).map(p => p.name);
                console.log("IDLE_OUT", JSON.stringify(out));
                if (!out.length) { console.log("UI_SMOKE_FAILED: no capsule came out"); Qt.quit(); return; }
                scene.frames = 0; loginScene.frames = 0; loginScene.ticks = 0;
                scene.counting = true; console.log("IDLE_COUNT_FROM", Date.now() % 100000);
                quiet.start();
            }
        }
        Timer {
            id: quiet
            interval: 7000
            onTriggered: {
                scene.counting = false;
                console.log("IDLE_FRAMES island", scene.frames, "login", loginScene.frames, "login clock ticks", loginScene.ticks);
                // The login clock may turn over a minute in the window (its digits
                // morph once, ~1 s of frames); otherwise nothing draws.
                const ok = scene.frames === 0 && loginScene.ticks <= 1 && (loginScene.frames === 0 || loginScene.ticks === 1 && loginScene.frames <= 90);
                console.log(ok ? "UI_SMOKE_CAPTURED" : "UI_SMOKE_FAILED: drew or woke at rest (above)");
                Qt.quit();
            }
        }
    }

    // The login face at rest (previewed: no intro, no PAM, no power).
    Window {
        id: loginScene
        visible: true
        width: 640; height: 400
        color: "black"
        property int frames: 0
        property int ticks: 0
        onFrameSwapped: if (scene.counting) { frames++; console.log("IDLE_FRAME_AT login", Date.now() % 100000); }
        QtObject {
            id: fakeLock
            property color accent: Theme.accent
            property bool checking: false
            property int failures: 0
            property string desktopWall: ""
            property string error: ""
            property string face: ""
            property string farewell: ""
            property bool leaving: false
            property string name: "Fixture"
            property string password: ""
            property bool powered: false
            property string wallpaper: ""
            function power(what) {}
            function submit() {}
        }
        GreeterView { id: login; anchors.fill: parent; lock: fakeLock; preview: true; onNowChanged: if (scene.counting) loginScene.ticks++ }
    }
}
