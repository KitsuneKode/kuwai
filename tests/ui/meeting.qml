import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import qs.config
import qs.services
import qs.modules.island

ShellRoot {
    Window {
        id: scene
        visible: true
        width: 520; height: 640
        color: Theme.cutout
        Rectangle { anchors.fill: parent; color: Theme.cutout }

        Loader { id: panelHost; x: 30; y: 20; active: false; sourceComponent: MeetingPanel {} }
        Item {
            id: markHost
            visible: false
            x: 20; y: 600
            width: mark.implicitWidth; height: mark.implicitHeight
            MeetingMark { id: mark; line: true; bars: true; moving: false; now: Date.now() }
        }

        FileView { id: log; path: Quickshell.env("XDG_RUNTIME_DIR") + "/fake-voxtype.log"; printErrors: false; watchChanges: true; onFileChanged: reload() }
        FileView { id: saved; path: Quickshell.env("HOME") + "/Documents/Meetings/2026-11-11 Release sync.md"; printErrors: false; blockLoading: true }
        FileView { id: requestFile; path: Quickshell.env("XDG_RUNTIME_DIR") + "/voxtype/meeting-view.request"; printErrors: false; blockLoading: true }

        function fail(why) { console.log("UI_SMOKE_FAILED: meeting: " + why); Qt.quit(); }
        function called(words) { return log.text().split("\n").some(l => l === JSON.stringify(words)); }
        property int step: 0
        property int waited: 0
        property var until: null
        property string waitingFor: ""
        function wait(what, test, then) { waitingFor = what; waited = 0; until = { test: test, then: then }; poll.restart(); }
        Timer {
            id: poll
            interval: 100; repeat: true
            onTriggered: {
                const u = scene.until;
                if (!u) { stop(); return; }
                if (u.test()) { stop(); scene.until = null; u.then(); return; }
                if (++scene.waited > 120) scene.fail("timed out waiting for " + scene.waitingFor + " (status " + Meeting.status + ", following " + Meeting.following + ")");
            }
        }
        function shot(name, item, then) {
            scene.contentItem.grabToImage(r => { r.saveToFile("/out/" + name + ".png"); then(); });
        }

        Component.onCompleted: Qt.callLater(begin)
        function begin() {
            if (Meeting.active || Meeting.following) return fail("something runs at rest");
            Meeting.start({ title: "Standup", url: "https://meet.google.com/abc-defg-hij" });
            wait("the meeting to start and its lines to arrive", () => Meeting.active && Meeting.segments.length >= 5 && Meeting.micLevel > 0 && called(["meeting", "start", "--title", "Standup", "--url", "https://meet.google.com/abc-defg-hij"]), recording);
        }
        function recording() {
            if (!called(["meeting", "start", "--title", "Standup", "--url", "https://meet.google.com/abc-defg-hij"])) return fail("start wasn't called with its arguments");
            if (!Meeting.following) return fail("no reader while recording");
            if (Meeting.title !== "Pete <> Chad Bi-Weekly") return fail("title " + Meeting.title);
            if (Meeting.segments.map(s => s.id).join() !== "0,1,2,3,4") return fail("lines out of order: " + Meeting.segments.map(s => s.id).join());
            if (Meeting.lineOf(Meeting.latest) !== "Dana: Only one. The restart banner stays visible after the daemon restarts.") return fail("latest line " + Meeting.lineOf(Meeting.latest));
            if (!Activities.micInUse) return fail("the mic dot is off during a meeting");
            if (Meeting.speakers.length !== 2) return fail("speakers " + JSON.stringify(Meeting.speakers));
            if (Meeting.callLevel !== -1) return fail("a silent call track should read -1, got " + Meeting.callLevel);
            panelHost.active = true;
            markHost.visible = true;
            wait("the panel", () => !!panelHost.item && panelHost.item.height > 100, () => scene.shot("meeting-live", panelHost.item, () => scene.shot("meeting-mark", markHost, pausing)));
        }
        function pausing() {
            Meeting.control("pause");
            wait("pause", () => Meeting.status === "paused" && Meeting.asked === "" && called(["meeting", "pause"]), () => {
                if (!Activities.micInUse) return scene.fail("the mic dot went out while paused");
                scene.shot("meeting-paused", panelHost.item, resuming);
            });
        }
        function resuming() {
            Meeting.control("resume");
            wait("resume", () => Meeting.status === "recording", stopping);
        }
        function stopping() {
            Meeting.control("stop");
            wait("the summary and the reader letting go", () => !Meeting.active && Meeting.summary !== null && !Meeting.following, ended);
        }
        function ended() {
            if (Meeting.summary.actions.length !== 2) return fail("action items " + JSON.stringify(Meeting.summary));
            if (Meeting.lastTitle !== "Pete <> Chad Bi-Weekly") return fail("last title " + Meeting.lastTitle);
            if (Activities.micInUse) return fail("the mic dot stayed after the meeting");
            scene.shot("meeting-ended", panelHost.item, listing);
        }
        function listing() {
            panelHost.item.pick("past");
            wait("the list", () => Meeting.listLoaded && Meeting.meetings.length === 2, () => scene.shot("meeting-list", panelHost.item, detail));
        }
        function detail() {
            Meeting.show("a32baa9b-b9df-4051-8830-b422d21495ed");
            wait("the meeting's detail", () => !!Meeting.detail && Meeting.detail.segments.length === 1, () => scene.shot("meeting-detail", panelHost.item, saving));
        }
        function saving() {
            Meeting.save(Meeting.detailId, Meeting.detail.title, new Date(2026, 10, 11, 15, 0).getTime());
            wait("the saved file", () => Meeting.done === "saved", () => {
                saved.reload();
                if (saved.text().indexOf("# Release sync") !== 0) return scene.fail("nothing saved in Documents/Meetings");
                deleting();
            });
        }
        function deleting() {
            const id = "b11c0de0-0000-4000-8000-000000000002";
            Meeting.remove(id);
            if (called(["meeting", "delete", id, "--force"])) return fail("one press deleted");
            Meeting.remove(id);
            wait("the delete", () => called(["meeting", "delete", id, "--force"]) && Meeting.meetings.length === 1, offering);
        }
        function offering() {
            Moments.dropCard();
            const t = Date.now();
            Calendar.events = [{ start: t - 30000, end: t + 1800000, title: "Weekly sync", location: "", allDay: false, private: false, call: "https://meet.google.com/x" }];
            Meeting.lookCalendar();
            wait("the offer", () => !!Moments.card && Moments.card.kind === "meeting", () => {
                if (Moments.card.title !== "Weekly sync" || Moments.card.sub !== "Record this meeting?") return scene.fail("offer card " + JSON.stringify(Moments.card));
                Moments.dropCard();
                Meeting.lookCalendar();
                Qt.callLater(() => {
                    if (Moments.card) return scene.fail("offered twice");
                    requesting();
                });
            });
        }
        function requesting() {
            requestFile.setText(JSON.stringify({ meeting_id: "latest", open: true, requested_at: Date.now(), tab: "transcript", window: null }));
            requestFile.reload();
            Meeting.serve(requestFile.text());
            if (Island.panel !== "meeting") return fail("a meeting-view request didn't open the panel");
            wait("the request to be taken", () => { requestFile.reload(); return !requestFile.loaded || requestFile.text() === ""; }, () => { console.log("UI_SMOKE_CAPTURED"); Qt.quit(); });
        }
    }
}
