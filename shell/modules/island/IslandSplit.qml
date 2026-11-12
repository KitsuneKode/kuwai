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
import Quickshell.Hyprland

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
    // More than one account in use (kittymux's `account`: "" for the default
    // config, else its label, e.g. "personal"): the limit says whose it is,
    // since the other account can carry on. One account says nothing extra.
    function accountOf(r) { return String(r.account || ""); }
    readonly property bool manyAccounts: new Set(agentRows.map(r => accountOf(r))).size > 1
    function accountName(r) { return accountOf(r) || "main"; }
    readonly property string limWho: manyAccounts && agentsLim.length ? accountName(agentsLim[0]) : ""
    readonly property string limTip: agentsLim.map(r => Kittymux.agentLabel(r.agent) + (manyAccounts ? " (" + accountName(r) + ")" : "") + " " + (r.status || "hit a limit")).join(" · ")
        + (manyAccounts ? "\n" + [...new Set(agentRows.filter(r => r.state !== "limited").map(r => accountName(r)))].map(a => a + " can carry on").join(" · ") : "")
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
        min: on && atRest && minimized.length > 0,
        agents: on && atRest && (agentsLive || agentsLinger.running),
        t3: on && atRest && (t3Live || t3Linger.running),
        sys: on && atRest && (sysLive || sysLinger.running)
    })

    // ── Who sits where ──
    // Nearest the notch first. Music always left; the rest to the side with
    // fewer out (a tie: the first of a pair left, the next right). A side,
    // once given, holds until that capsule has folded away.
    readonly property var order: ["music", "agents", "t3", "sys", "min"]
    // Windows tucked away with Super+O (special:minimized): a capsule of their
    // icons, each one a way back. Without it they were nowhere to be seen.
    readonly property var minimized: Hyprland.toplevels.values.filter(t => t.workspace && t.workspace.name === "special:minimized")
    // Onto the workspace you're on, focused (what Super+Shift+O does for the last one).
    function bringBack(t) {
        if (!t) return;
        const ws = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1;
        Hyprland.dispatch("hl.dsp.window.move({ window = 'address:0x" + t.address + "', workspace = " + ws + " })");
        Hyprland.dispatch("hl.dsp.focus({ window = 'address:0x" + t.address + "' })");
    }
    property var sideOf: ({})
    onWantsChanged: assign()
    function pillOf(k) { return ({ music: musicPill, agents: agentsPill, t3: t3Pill, sys: sysPill, min: minPill })[k]; }
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
    readonly property var pills: [musicPill, agentsPill, t3Pill, sysPill, minPill]

    // One capsule: black glass like the island, sized to `content` (a
    // circle at least), budding from `from` toward `side`.
    component Pill: Item {
        id: pill
        property string name
        // Where a click on it, or pulling it down, takes you: the panel that
        // lists what it holds, to act on from there (not straight to one of
        // them; right-click does that where there's one to go to).
        property string panel: ""
        function openPanel() { if (panel) Island.toggle(panel, split.bar.screenName, "pointer"); }
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
        // Never an empty capsule: what it holds decides too (a linger, or a
        // state its marks don't draw, left a black pill with nothing in it).
        readonly property bool shown: !!split.wants[name] && !!split.sideOf[name] && slot.childrenRect.width > 0.5
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
        // Pulled down (gestures skill): its bottom edge is the pointer, 1:1 up
        // to the line, the capsule stretching like a drop (top 60 %, length
        // 40 % of the travel); past the line it resists, and its edge lights:
        // let go now and it opens. Released, a spring seeded with the
        // pointer's speed takes it home (catchable: a press reads where it is).
        readonly property real pullLine: Theme.swipeThreshold * 0.8
        readonly property real pullP: Math.max(0, Math.min(1, pull.value / pullLine))
        readonly property bool pullArmed: pullDrag.active && pull.value >= pullLine
        y: split.topY + Math.round((split.h - split.ph) / 2) + Math.max(0, pull.value) * 0.6 + Math.min(0, pull.value)
        Spring { id: pull; tier: Theme.springFast; target: 0; epsilon: 0.2 }
        DragHandler {
            id: pullDrag
            enabled: pill.panel !== ""
            target: null
            xAxis.enabled: false
            property real grab: 0
            onActiveChanged: {
                if (active) { grab = pull.value; pull.snap(pull.value); return; }
                // Opens on distance past the line, or a flick down.
                if (pull.value >= pill.pullLine || centroid.velocity.y / 1000 > Theme.swipeFlick) pill.openPanel();
                pull.velocity = Theme.reduceMotion ? 0 : centroid.velocity.y;
                pull.target = 0;
            }
            onTranslationChanged: {
                if (!active) return;
                const d = grab + translation.y, L = pill.pullLine;
                // 1:1 to the line, then rubber-banded; upward only a hint.
                pull.snap(d <= 0 ? -Theme.swipeDamp(-d) * 0.25 : d <= L ? d : L + (d - L) * L * 0.55 / (L + 0.55 * (d - L)));
            }
        }
        width: bodyW
        height: split.ph + Math.max(0, pull.value) * 0.4
        visible: out
        opacity: Math.min(1, sv.value * 2)
        scale: 0.86 + 0.14 * sv.value
        transformOrigin: side > 0 ? Item.Left : Item.Right

        // Asking for you: a soft halo outside, the edge lit inside (the
        // island's needs-you light, at capsule size); just finished: the
        // same in green, fading.
        Rectangle {
            anchors { fill: parent; margins: -3 }
            radius: split.ph / 2 + 3
            color: "transparent"
            border.width: 3
            border.color: Qt.alpha(pill.toned ? pill.tone : Theme.green, 0.22)
            opacity: Math.max(pill.toned && pill.attention ? 1 : 0, pill.flash)
            visible: opacity > 0.01
            Behavior on opacity { enabled: pill.flash < 0.01; NumberAnimation { duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
        }
        Rectangle {
            anchors.fill: parent
            radius: split.ph / 2         // stays a capsule as it stretches
            color: Qt.rgba(0, 0, 0, 0.94)
            // A hairline of light at the edge: glass, not a hole in the screen.
            border.width: pill.toned || pill.pullArmed ? 1.5 : 1
            // Pulled, the glass edge brightens with the pull; at the line it's lit.
            border.color: pill.pullArmed ? Qt.rgba(1, 1, 1, 0.55)
                : pill.toned ? Qt.alpha(pill.tone, pill.attention ? 0.9 : 0.6) : Qt.rgba(1, 1, 1, 0.07 + 0.2 * pill.pullP)
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
        signal altClicked()
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
        TapHandler { acceptedButtons: Qt.LeftButton | Qt.RightButton; onTapped: (point, button) => button === Qt.RightButton ? badge.altClicked() : badge.clicked() }
        Tip { text: badge.tip; shown: badgeHover.hovered && badge.tip !== ""; below: true }
        Accessible.role: Accessible.StaticText
        Accessible.name: badge.tip || badge.text
    }

    // ── Music, stepped aside ──
    Pill {
        id: musicPill
        name: "music"
        panel: "media"
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
        panel: "agents"
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
                tip: split.agentsErr.map(r => Kittymux.agentLabel(r.agent) + ": " + (r.status || "error")).join(" · ") + "\nClick: every agent"
                onClicked: agentsPill.openPanel()
            }
            Badge {
                visible: split.agentsLim.length > 0 && split.agentsErr.length === 0
                glyph: "\u{f051f}"                       // timer-sand
                text: (split.limWho ? split.limWho + " · " : "") + split.limReset
                tint: Theme.yellow
                tip: split.limTip + "\nClick: usage, every account"
                onClicked: Island.toggle("usage", split.bar.screenName, "pointer")
            }
            Badge {
                visible: split.agentsDone.length > 0
                glyph: "\u{f05e0}"                       // check-circle
                text: split.agentsDone.length > 1 ? String(split.agentsDone.length) : ""
                tint: Theme.green
                tip: split.agentsDone.slice(0, 3).map(e => Kittymux.agentLabel(e.agent) + " finished" + (e.tab ? " · " + Kittymux.clean(e.tab) : "")).join(" · ") + "\nClick: every agent · right-click: go to the newest"
                onClicked: agentsPill.openPanel()
                onAltClicked: split.goDone()
            }
        }
    }

    // ── T3's threads ──
    Pill {
        id: t3Pill
        name: "t3"
        panel: "t3"
        needs: split.t3Waiting && T3Code.total > 0
        tone: needs ? Theme.orange : T3Code.finished > 0 ? Theme.green : "transparent"
        Row {
          spacing: 6
          RestMark {
            visible: T3Code.total > 0 || (t3Linger.running && T3Code.finished === 0)   // its last value while it lingers
            wordmark: "T3"
            value: split.t3Value
            ring: split.t3Waiting ? "solid" : "spin"
            tone: split.t3Waiting ? Theme.orange : Theme.cyan
            previews: true
            onPreviewRequested: if (Island.panel === "") Island.preview("t3", split.bar.screenName)
            onClicked: t3Pill.openPanel()
          }
          // Finished since you last looked: T3's own "seen" (each thread's
          // last visit), so it clears as you open them there.
          Badge {
            visible: T3Code.finished > 0
            glyph: "\u{f05e0}"                         // check-circle
            text: (T3Code.total > 0 ? "" : "T3 ") + T3Code.finished
            tint: Theme.green
            tip: T3Code.items.filter(i => i.status === "completed").slice(0, 3).map(i => i.title).join(" · ") + " · finished\nClick: the threads · right-click: open the newest"
            onClicked: t3Pill.openPanel()
            onAltClicked: T3Code.openBest()
          }
        }
    }

    // ── System news: updates waiting, a warning, a used-up limit ──
    Pill {
        id: sysPill
        name: "sys"
        // Pulled: what it's saying most loudly (a warning, else updates, else a used-up limit).
        panel: Alerts.active.length ? "system" : Limits.markShown && !Updates.fresh && !Updates.running ? "usage" : "updates"
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

    // ── Minimized windows (Super+O) ──
    Pill {
        id: minPill
        name: "min"
        Row {
            spacing: 6
            Repeater {
                model: split.minimized.slice(0, 3)
                delegate: Item {
                    id: mw
                    required property var modelData
                    readonly property string cls: modelData.lastIpcObject ? (modelData.lastIpcObject.class || "") : ""
                    width: 18; height: 18
                    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                    Text {
                        // No icon found (or not loaded yet): a window, so the slot isn't blank.
                        visible: mwImg.status !== Image.Ready
                        anchors.centerIn: parent
                        text: "\u{f05b6}"                   // window-maximize
                        font.family: Theme.fontGlyph; font.pixelSize: Theme.tCallout
                        color: Theme.textSecondary
                    }
                    Image {
                        id: mwImg
                        anchors.fill: parent
                        source: mw.cls ? NotifAdapters.iconForApp(mw.cls) : ""
                        sourceSize: Qt.size(36, 36)
                        asynchronous: true
                        opacity: mwHover.hovered ? 1 : 0.85
                    }
                    HoverHandler { id: mwHover; margin: 3; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: split.bringBack(mw.modelData) }
                    Tip { text: (mw.modelData.title || mw.cls) + "\nClick to bring it back"; shown: mwHover.hovered; below: true }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Bring back " + (mw.modelData.title || mw.cls)
                    Accessible.onPressAction: split.bringBack(mw.modelData)
                }
            }
            Label {
                visible: split.minimized.length > 3
                anchors.verticalCenter: parent.verticalCenter
                text: "+" + (split.minimized.length - 3)
                size: Theme.tSub; weight: Theme.wSemibold
                color: Theme.textSecondary
                font.features: ({ "tnum": 1 })
                HoverHandler { id: moreHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: split.bringBack(split.minimized[split.minimized.length - 1]) }
                Tip { text: split.minimized.slice(3).map(t => t.title).join(" · ") + "\nClick: bring one back (or Super+Shift+O)"; shown: moreHover.hovered; below: true }
            }
        }
    }
}
