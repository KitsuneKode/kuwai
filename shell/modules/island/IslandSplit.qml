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
    readonly property bool agentsLive: agentStack.list.length > 0
    readonly property bool t3Live: T3Code.total > 0
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
    Component.onCompleted: { t3NowChanged(); assign(); }

    // For the window's input mask (IslandBar): what's out takes clicks.
    readonly property var pills: [musicPill, agentsPill, t3Pill, sysPill]

    // One capsule: black glass like the island, sized to `content` (a
    // circle at least), budding from `from` toward `side`.
    component Pill: Item {
        id: pill
        property string name
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

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Qt.rgba(0, 0, 0, 0.94)
            // A hairline of light at the edge: glass, not a hole in the screen.
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.07)
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
        AgentStack { id: agentStack; bar: split.bar }
    }

    // ── T3's threads ──
    Pill {
        id: t3Pill
        name: "t3"
        RestMark {
            wordmark: "T3"
            value: split.t3Value
            ring: split.t3Waiting ? "solid" : "spin"
            tone: split.t3Waiting ? Theme.orange : Theme.cyan
            previews: true
            onPreviewRequested: if (Island.panel === "") Island.preview("t3", split.bar.screenName)
            onClicked: T3Code.openBest()
        }
    }

    // ── System news: updates waiting, a warning, a used-up limit ──
    Pill {
        id: sysPill
        name: "sys"
        SysMarks {
            id: sysMarks
            bar: split.bar
            quiet: split.activity !== "" && split.activity !== "media"
            updateOffStage: Updates.running && split.activity !== "update"
        }
    }
}
