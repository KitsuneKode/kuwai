// The split island (Apple's Dynamic Island: a second live activity leaves
// the island for a bubble of its own). At rest the notch keeps the time and
// the one thing live; everything else that's going on sits beside it in
// small floating capsules, shared out evenly left and right so the notch
// stays the centre:
//
//        ( ▣ ) ( ✳◐ )   [   21:08 ·  live   ]   ( T3 ② ) ( ⟲ 3 )
//
// What gets a capsule: music, stepped aside while dictation, a recording, a
// timer or an update has the island (always on the left: it's yours); the
// kitty agents at work; T3's threads; system news (updates waiting, a
// warning, a used-up limit). Each new one goes to the side with fewer, and
// keeps its side while it's out (nothing jumps across); the nearer the
// notch, the more it matters.
//
// A capsule buds from under the island's edge on its own spring (carried by
// the edge, and by the capsules inside it, as they resize), and folds back
// under when the island grows: the grown island holds everything again.
// A capsule whose work blinks out for a moment (T3 between two runs of a
// thread) waits a few seconds before it goes. Settings → Bar & Island →
// Separate pills.
import QtQuick
import Quickshell.Widgets
import qs.config
import qs.components
import qs.services

Item {
    id: split
    required property var bar
    // The island's body edges (window x), its top and height, and whether
    // it's at rest (not grown, hidden or tucked).
    property real leftEdge: 0
    property real rightEdge: 0
    property real topY: 0
    property real h: 34
    property bool atRest: true
    property string activity: ""

    readonly property bool on: Settings.islandSplit
    readonly property var player: bar.player
    readonly property real ph: h - 6                 // a capsule: a little shorter, centred on the island
    readonly property real gap: 8                    // island to capsule, capsule to capsule (Apple's ~8 pt)

    // ── What's out ──
    readonly property bool musicLive: !!player && player.isPlaying && Settings.restMedia
        && ["vox", "rec", "timer", "update"].indexOf(activity) >= 0
    // ── What state each is in: the light and the glyph say which ──
    //   waiting on you  orange  edge + halo, steady   (the agent's own ring)
    //   error           red     edge + halo, steady   ⚠
    //   hit a limit     amber   edge only (nothing to do)  ⏳ and when it resets
    //   finished, not yet seen  green  edge (a halo flashes once as each arrives)  ✓ and how many
    //   working         none    (its marks turn)
    // "Not yet seen" is each tool's own: kittymux's unread `done` events
    // (read once you visit that pane), T3's threads finished since you last
    // opened them. Nothing here keeps a second copy that could drift.
    readonly property var agentRows: Kittymux.running
    readonly property var agentsErr: agentRows.filter(r => r.state === "error")
    readonly property var agentsLim: agentRows.filter(r => r.state === "limited")
    readonly property string limReset: {
        const m = agentsLim.map(r => (String(r.status || "").match(/resets in (.+)$/) || [])[1]).filter(x => x);
        return m.length ? m[0] : "";
    }
    // Finished and not yet seen (kittymux's unread `done` events, newest first).
    readonly property var agentsDone: Kittymux.attention.filter(e => e.kind === "done")
    property int agentsDoneWas: -1
    onAgentsDoneChanged: {
        if (agentsDoneWas >= 0 && agentsDone.length > agentsDoneWas) agentsPill.celebrate();
        agentsDoneWas = agentsDone.length;
    }
    function goDone() {
        const e = agentsDone[0];
        if (e) Kittymux.jumpEvent(e.id);
    }
    // T3: threads finished since you last opened them.
    property int t3Finished: T3Code.finished
    property int t3FinishedWas: -1
    onT3FinishedChanged: {
        if (t3FinishedWas >= 0 && T3Code.finished > t3FinishedWas) t3Pill.celebrate();
        t3FinishedWas = T3Code.finished;
    }

    readonly property bool agentsLive: agentStack.list.length > 0 || agentsErr.length > 0 || agentsLim.length > 0 || agentsDone.length > 0
    readonly property bool t3Live: T3Code.total > 0 || T3Code.finished > 0
    readonly property bool sysLive: sysMarks.any
    // A capsule folds only after its work has been gone a few seconds, and
    // shows its last value meanwhile.
    onAgentsLiveChanged: if (!agentsLive) agentsLinger.restart()
    onT3LiveChanged: if (!t3Live) t3Linger.restart()
    onSysLiveChanged: if (!sysLive) sysLinger.restart()
    Timer { id: agentsLinger; interval: 3000 }
    Timer { id: t3Linger; interval: 4000 }
    Timer { id: sysLinger; interval: 2000 }
    property string t3Value: ""
    property bool t3Waiting: false
    readonly property var t3Now: [T3Code.running, T3Code.waiting]
    onT3NowChanged: if (t3Live) { t3Value = String(T3Code.waiting > 0 ? T3Code.waiting : T3Code.running); t3Waiting = T3Code.waiting > 0; }
    readonly property var wants: ({
        music: on && atRest && musicLive,
        agents: on && atRest && (agentsLive || agentsLinger.running),
        t3: on && atRest && (t3Live || t3Linger.running),
        sys: on && atRest && (sysLive || sysLinger.running)
    })

    // ── Who sits where ──
    // Nearest the notch first. Music always left; the rest to the side with
    // fewer out (a tie: the first of a pair left, the next right). A side,
    // once given, holds until that capsule has folded away.
    readonly property var order: ["music", "agents", "t3", "sys"]
    property var sideOf: ({})
    onWantsChanged: assign()
    function pillOf(k) { return ({ music: musicPill, agents: agentsPill, t3: t3Pill, sys: sysPill })[k]; }
    function assign() {
        const next = {};
        let left = 0, right = 0;
        for (const k of order) {
            const s = sideOf[k];
            if (s && (wants[k] || pillOf(k).out)) { next[k] = s; s < 0 ? left++ : right++; }
        }
        for (const k of order) {
            if (!wants[k] || next[k]) continue;
            const s = k === "music" ? -1 : left < right ? -1 : left > right ? 1 : (left + right) % 2 === 0 ? -1 : 1;
            next[k] = s;
            s < 0 ? left++ : right++;
        }
        sideOf = next;
    }
    // Where a capsule starts: the island's edge, past the capsules nearer it
    // on the same side (their room grows and shrinks with their springs).
    function fromOf(k) {
        const s = sideOf[k] || 1;
        let x = s > 0 ? rightEdge : leftEdge;
        for (const o of order) {
            if (o === k) break;
            if ((sideOf[o] || 0) === s) x += s * pillOf(o).room;
        }
        return x;
    }
    Component.onCompleted: { t3NowChanged(); t3FinishedWas = T3Code.finished; agentsDoneWas = agentsDone.length; assign(); }

    // What waits on you, by capsule: the light goes on what's asking
    // (IslandBar keeps its own rim for what's still in the island).
    readonly property bool agentsNeed: agentStack.list.some(a => a.needs) || Kittymux.running.some(r => r.needs)
    readonly property bool agentsHold: agentsPill.shown
    readonly property bool t3Hold: t3Pill.shown
    // For the window's input mask (IslandBar): what's out takes clicks.
    readonly property var pills: [musicPill, agentsPill, t3Pill, sysPill]

    // One capsule: black glass like the island, sized to `content` (a
    // circle at least), budding from `from` toward `side`.
    component Pill: Item {
        id: pill
        property string name
        property bool needs: false        // something here waits on you: an orange glass edge
        // Its state's light (see "What state each is in"): a colour, and
        // whether it asks for you (a halo) or only says so (the edge).
        property color tone: needs ? Theme.orange : "transparent"
        property bool attention: needs
        readonly property bool toned: tone.a > 0
        // One finished just now: the halo flashes once (the edge stays green
        // while it's unseen, from `tone`).
        property real flash: 0
        function celebrate() { if (!Theme.reduceMotion) flashIn.restart(); }
        SequentialAnimation {
            id: flashIn
            NumberAnimation { target: pill; property: "flash"; to: 1; duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
            NumberAnimation { target: pill; property: "flash"; to: 0; duration: Theme.breathOutMs; easing.type: Easing.InOutSine }
        }
        readonly property int side: split.sideOf[name] || 1
        readonly property bool shown: !!split.wants[name] && !!split.sideOf[name]
        readonly property real from: split.fromOf(name)
        default property alias content: slot.data
        readonly property real bodyW: Math.max(split.ph, Math.round(slot.childrenRect.width) + 20)
        readonly property bool out: sv.value > 0.02
        onOutChanged: if (!out) split.assign()
        // The room it takes along its side (for the capsules beyond it).
        readonly property real room: (bodyW + split.gap) * sv.value
        Spring { id: sv; tier: pill.shown ? Theme.surfaceIn : Theme.surfaceOut; epsilon: 0.002; target: pill.shown ? 1 : 0; Component.onCompleted: settle() }
        // From 60 % tucked behind the edge to a gap clear of it.
        readonly property real off: -bodyW * 0.6 + (bodyW * 0.6 + split.gap) * sv.value
        x: side > 0 ? from + off : from - off - bodyW
        y: split.topY + Math.round((split.h - split.ph) / 2)
        width: bodyW
        height: split.ph
        visible: out
        opacity: Math.min(1, sv.value * 2)
        scale: 0.86 + 0.14 * sv.value
        transformOrigin: side > 0 ? Item.Left : Item.Right

        // Asking for you: a soft halo outside, the edge lit inside (the
        // island's needs-you light, at capsule size); just finished: the
        // same in green, fading.
        Rectangle {
            anchors { fill: parent; margins: -3 }
            radius: height / 2
            color: "transparent"
            border.width: 3
            border.color: Qt.alpha(pill.toned ? pill.tone : Theme.green, 0.22)
            opacity: Math.max(pill.toned && pill.attention ? 1 : 0, pill.flash)
            visible: opacity > 0.01
            Behavior on opacity { enabled: pill.flash < 0.01; NumberAnimation { duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
        }
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Qt.rgba(0, 0, 0, 0.94)
            // A hairline of light at the edge: glass, not a hole in the screen.
            border.width: pill.toned ? 1.5 : 1
            border.color: pill.toned ? Qt.alpha(pill.tone, pill.attention ? 0.9 : 0.6) : Qt.rgba(1, 1, 1, 0.07)
            Behavior on border.color { ColorAnimation { duration: Theme.colorMs } }
        }
        Item {
            id: slot
            x: Math.round((pill.bodyW - childrenRect.width) / 2)
            y: Math.round((split.ph - childrenRect.height) / 2)
            width: childrenRect.width; height: childrenRect.height
            // The content arrives once the capsule is mostly out, leaves first.
            opacity: Math.max(0, Math.min(1, (sv.value - (pill.shown ? 0.45 : 0.6)) / 0.35))
        }
    }

    // A state's glyph, and a word or time beside it, in its colour.
    component Badge: Row {
        id: badge
        property string glyph
        property string text: ""
        property color tint: Theme.textSecondary
        property string tip: ""
        signal clicked()
        spacing: 4
        anchors.verticalCenter: parent.verticalCenter
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: badge.glyph
            font.family: Theme.fontGlyph; font.pixelSize: Theme.tCallout
            color: badge.tint
        }
        Label {
            visible: badge.text !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: badge.text
            size: Theme.tSub; weight: Theme.wSemibold
            color: badge.tint
            font.features: ({ "tnum": 1 })
        }
        HoverHandler { id: badgeHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: badge.clicked() }
        Tip { text: badge.tip; shown: badgeHover.hovered && badge.tip !== ""; below: true }
        Accessible.role: Accessible.StaticText
        Accessible.name: badge.tip || badge.text
    }

    // ── Music, stepped aside ──
    Pill {
        id: musicPill
        name: "music"
        ClippingRectangle {
            width: 18; height: 18; radius: 5
            color: Qt.rgba(1, 1, 1, 0.08)
            Image { anchors.fill: parent; source: split.player ? (split.player.trackArtUrl || "") : ""; sourceSize: Qt.size(36, 36); fillMode: Image.PreserveAspectCrop; asynchronous: true }
            HoverHandler { id: musicHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: Island.open("media", split.bar.screenName, "pointer", "island") }
            Tip { text: (split.player ? (split.player.trackTitle || split.player.identity || "Playing") : "") + " · click for Now Playing"; shown: musicHover.hovered; below: true }
            Accessible.role: Accessible.Button
            Accessible.name: "Now playing: " + (split.player ? (split.player.trackTitle || split.player.identity || "music") : "music")
            Accessible.onPressAction: Island.open("media", split.bar.screenName, "pointer", "island")
        }
    }

    // ── Agents at work in kitty ──
    Pill {
        id: agentsPill
        name: "agents"
        needs: split.agentsNeed
        // An error outranks a question; a limit only says so.
        tone: split.agentsErr.length ? Theme.red : split.agentsNeed ? Theme.orange : split.agentsLim.length ? Theme.yellow
            : split.agentsDone.length ? Theme.green : "transparent"
        attention: split.agentsErr.length > 0 || split.agentsNeed
        Row {
            spacing: 6
            AgentStack { id: agentStack; bar: split.bar; visible: list.length > 0; anchors.verticalCenter: parent.verticalCenter }
            Badge {
                visible: split.agentsErr.length > 0
                glyph: "\u{f0028}"                       // alert-circle
                tint: Theme.red
                tip: split.agentsErr.map(r => Kittymux.agentLabel(r.agent) + ": " + (r.status || "error")).join(" · ")
            }
            Badge {
                visible: split.agentsLim.length > 0 && split.agentsErr.length === 0
                glyph: "\u{f051f}"                       // timer-sand
                text: split.limReset
                tint: Theme.yellow
                tip: split.agentsLim.map(r => Kittymux.agentLabel(r.agent) + " " + (r.status || "hit a limit")).join(" · ")
            }
            Badge {
                visible: split.agentsDone.length > 0
                glyph: "\u{f05e0}"                       // check-circle
                text: split.agentsDone.length > 1 ? String(split.agentsDone.length) : ""
                tint: Theme.green
                tip: split.agentsDone.slice(0, 3).map(e => Kittymux.agentLabel(e.agent) + " finished" + (e.tab ? " · " + Kittymux.clean(e.tab) : "")).join(" · ") + " · click to go there"
                onClicked: split.goDone()
            }
        }
    }

    // ── T3's threads ──
    Pill {
        id: t3Pill
        name: "t3"
        needs: split.t3Waiting && T3Code.total > 0
        tone: needs ? Theme.orange : T3Code.finished > 0 ? Theme.green : "transparent"
        Row {
          spacing: 6
          RestMark {
            visible: T3Code.total > 0
            wordmark: "T3"
            value: split.t3Value
            ring: split.t3Waiting ? "solid" : "spin"
            tone: split.t3Waiting ? Theme.orange : Theme.cyan
            previews: true
            onPreviewRequested: if (Island.panel === "") Island.preview("t3", split.bar.screenName)
            onClicked: T3Code.openBest()
          }
          // Finished since you last looked: T3's own "seen" (each thread's
          // last visit), so it clears as you open them there.
          Badge {
            visible: T3Code.finished > 0
            glyph: "\u{f05e0}"                         // check-circle
            text: (T3Code.total > 0 ? "" : "T3 ") + T3Code.finished
            tint: Theme.green
            tip: T3Code.items.filter(i => i.status === "completed").slice(0, 3).map(i => i.title).join(" · ") + " · finished · click to open"
            onClicked: T3Code.openBest()
          }
        }
    }

    // ── System news: updates waiting, a warning, a used-up limit ──
    Pill {
        id: sysPill
        name: "sys"
        // A warning in its level's colour (asking: a halo); a used-up limit amber (only saying so).
        tone: Alerts.active.length ? (Alerts.active[0].level === "crit" ? Theme.red : Theme.orange) : Limits.markShown ? Theme.yellow : "transparent"
        attention: Alerts.active.length > 0
        SysMarks {
            id: sysMarks
            bar: split.bar
            quiet: split.activity !== "" && split.activity !== "media"
            updateOffStage: Updates.running && split.activity !== "update"
        }
    }
}
