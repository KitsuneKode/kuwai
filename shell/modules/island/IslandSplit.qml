// The split island (Apple's Dynamic Island: a second live activity leaves
// the island for a bubble of its own). At rest the notch keeps the time and
// the one thing live; everything else that's going on sits beside it in
// small floating capsules, shared out evenly left and right so the notch
// stays the centre:
//
//        ( ▣ ) ( ✳◐ Approval )   [   21:08 ·  live   ]   ( ⟲ 3 )
//
// What gets a capsule: music, stepped aside while dictation, a recording, a
// timer or an update has the island (always on the left: it's yours); the
// agents at work, kitty panes and T3 threads in one; system news (updates waiting, a
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
import QtQuick.Effects
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
    FontMetrics { id: pillMetrics; font.family: Theme.fontText; font.pixelSize: Theme.tBody * Theme.textScale }
    readonly property real ph: Math.max(h - 6, pillMetrics.height + Theme.s2)
    readonly property real minimumTarget: Theme.s5 + Theme.s4
    readonly property real gap: Theme.s2                    // island to capsule, capsule to capsule (Apple's ~8 pt)

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
    // Whose limit: the capsule's logos are the agents at work, not the one
    // that's out, so with more than one kind of agent out the ⏳ names it
    // ("Claude · 41m"). Without it, a working agy's logo beside Claude's
    // limit read as "agy hit a limit". Two accounts add which one.
    readonly property bool manyKinds: new Set(agentRows.map(r => r.agent)).size > 1
    readonly property string limWho: !agentsLim.length ? ""
        : (manyKinds ? Kittymux.agentLabel(agentsLim[0].agent) : "") + (manyKinds && manyAccounts ? " " : "") + (manyAccounts ? accountName(agentsLim[0]) : "")
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
    property int t3Finished: T3Code.finished
    property int t3FinishedWas: -1
    onT3FinishedChanged: {
        if (t3FinishedWas >= 0 && T3Code.finished > t3FinishedWas) agentsPill.celebrate();
        t3FinishedWas = T3Code.finished;
    }

    readonly property var agentsHead: Agents.head
    readonly property bool asking: agentsHead.tone === "attention"
    readonly property bool agentsWord: agentsHead.tone === "error"
    readonly property bool agentsLive: agentStack.list.length > 0 || agentsHead.tone === "error" || agentsHead.done > 0
    readonly property string sysKey: sysPill.stateKey + ":" + Updates.setKey + ":" + Alerts.active.map(a => a.id).join()
    property string sysHidden: ""
    readonly property bool sysLive: sysMarks.any && sysKey !== sysHidden
    readonly property var limitsPartition: Limits.partitionWith(Agents.extraLimited)
    readonly property var limitsNow: Settings.limitAlerts ? Limits.summarize(limitsPartition) : Limits.summarize(null)
    readonly property string limitsKey: limitsNow.tone + ":" + limitsNow.providers.map(p => p.id).join()
    property string limitsHidden: ""
    readonly property bool limitsLive: limitsNow.items.length > 0 && limitsKey !== limitsHidden
    property var limits: Limits.summarize(null)
    onLimitsNowChanged: if (limitsNow.items.length) limits = limitsNow
    readonly property color limitTint: limits.tone === "soon" ? Theme.orange : Theme.red
    // A capsule folds only after its work has been gone a few seconds, and
    // shows its last value meanwhile.
    onAgentsLiveChanged: if (!agentsLive) agentsLinger.restart()
    onAskingChanged: if (!asking) askLinger.restart()
    Timer { id: askLinger; interval: 1500 }
    onSysLiveChanged: if (!sysLive) sysLinger.restart()
    onLimitsLiveChanged: if (!limitsLive) limitsLinger.restart()
    Timer { id: agentsLinger; interval: 3000 }
    Timer { id: sysLinger; interval: 2000 }
    Timer { id: limitsLinger; interval: 2000 }
    readonly property var demand: ({
        ask: on && (asking || askLinger.running),
        music: on && musicLive,
        min: on && minimized.length > 0,
        agents: on && (agentsLive || agentsLinger.running),
        sys: on && (sysLive || sysLinger.running),
        limits: on && (limitsLive || limitsLinger.running)
    })

    // ── Who sits where ──
    // Fixed lanes, nearest the notch first: left is what you run, right is
    // what the system tells you. A lane never depends on what came first.
    readonly property var order: ["ask", "music", "agents", "sys", "limits", "min"]
    // Windows tucked away with Super+O (special:minimized): a capsule of their
    // icons, each one a way back. Without it they were nowhere to be seen.
    property var minimized: Hyprland.toplevels.values.filter(t => t.workspace && t.workspace.name === "special:minimized")
    // Onto the workspace you're on, focused (what Super+Shift+O does for the last one).
    function bringBack(t) {
        if (!t) return;
        const address = "0x" + String(t.address || "").replace(/^0x/, "");
        if (!/^0x[0-9a-f]+$/i.test(address)) return;
        const candidates = [bar && bar.screenWs ? bar.screenWs.id : 0, Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 0, 1];
        const ws = candidates.map(Number).find(n => Number.isInteger(n) && n > 0 && n <= 2147483647);
        Hyprland.dispatch("hl.dsp.window.move({ window = " + JSON.stringify("address:" + address) + ", workspace = " + ws + " })");
        Hyprland.dispatch("hl.dsp.focus({ window = " + JSON.stringify("address:" + address) + " })");
    }
    readonly property var sideOf: ({ ask: -1, music: -1, agents: -1, min: -1, sys: 1, limits: 1 })
    function pillOf(k) { return ({ ask: askPill, music: musicPill, agents: agentsPill, sys: sysPill, limits: limitsPill, min: minPill, more: morePill })[k]; }

    // Reserve one slot for More when there are too many activities. Urgent
    // items take the available direct slots first, then keep their usual sides
    // wherever there is space. Side zero places More below a full-width notch.
    function arrange(keys, preferred, leftSlots, rightSlots) {
        const sides = {}, overflow = [];
        const free = { "-1": leftSlots, "1": rightSlots };
        const total = leftSlots + rightSlots;
        const directCount = keys.length > total ? Math.max(0, total - 1) : keys.length;
        for (const [index, key] of keys.entries()) {
            if (index >= directCount) { overflow.push(key); continue; }
            const side = preferred[key] || -1;
            const lane = free[side] > 0 ? side : -side;
            sides[key] = lane;
            free[lane]--;
        }
        if (overflow.length) sides.more = free[1] > 0 ? 1 : free[-1] > 0 ? -1 : 0;
        return { sides, overflow };
    }
    readonly property var activeKeys: order.filter(k => demand[k])
    readonly property var priorityKeys: {
        const urgent = [];
        if (Alerts.active.length) urgent.push("sys");
        if (asking) urgent.push("ask");
        if (agentsErr.length || agentsHead.tone === "error") urgent.push("agents");
        return urgent.filter(k => demand[k]).concat(activeKeys.filter(k => !urgent.includes(k)));
    }
    readonly property real leftRoom: Math.max(0, leftEdge - Theme.s2)
    readonly property real rightRoom: Math.max(0, width - rightEdge - Theme.s2)
    readonly property int leftSlots: Math.floor(leftRoom / (minimumTarget + gap))
    readonly property int rightSlots: Math.floor(rightRoom / (minimumTarget + gap))
    readonly property var arrangement: arrange(priorityKeys, sideOf, leftSlots, rightSlots)
    readonly property var displayOrder: [...order, "more"]
    function placement(k) {
        const lane = arrangement.sides[k];
        if (lane !== undefined) return lane;
        // A departing activity can animate in its old lane only while a
        // complete target still fits there. New activity owns the space.
        const previous = sideOf[k];
        if (demand[k] || !previous || !pillOf(k).out) return undefined;
        const capacity = previous < 0 ? leftSlots : rightSlots;
        const occupied = Object.values(arrangement.sides).filter(s => s === previous).length;
        const earlier = order.slice(0, order.indexOf(k)).filter(other => !demand[other] && sideOf[other] === previous && pillOf(other).out).length;
        return occupied + earlier < capacity ? previous : undefined;
    }
    function fromOf(k) {
        const side = placement(k);
        if (!side) return width / 2;
        let x = side > 0 ? rightEdge : leftEdge;
        for (const other of displayOrder) {
            if (other === k) break;
            if (placement(other) === side) x += side * pillOf(other).room;
        }
        return x;
    }
    function spaceFor(k) {
        const side = placement(k);
        if (!side) return k === "more" ? Math.max(1, width - 2 * Theme.s2) : minimumTarget + gap;
        const count = displayOrder.filter(other => placement(other) === side && (arrangement.sides[other] !== undefined || pillOf(other).out)).length;
        return (side < 0 ? leftRoom : rightRoom) / Math.max(1, count);
    }
    function labelFor(k) {
        if (k === "more") {
            const count = arrangement.overflow.length;
            return count === 1 ? "1 more activity" : count + " more activities";
        }
        return ({ask: "Needs you", music: "Now Playing", agents: "Agents", sys: "System status", limits: "Usage limits", min: "Restore minimized window"})[k] || k;
    }
    property var overflowSelection: []
    function openOverflow(how) {
        overflowSelection = arrangement.overflow.slice();
        Island.open("activities", bar.screenName, how);
    }
    function glyphFor(k) {
        if (k === "sys" && Alerts.active.length) return Alerts.active[0].glyph;
        return ({ask: "\u{f0026}", music: "\u{f0387}", agents: "\u{f06a9}", sys: "\u{f06b0}", limits: "\u{f051f}", min: "\u{f05b6}"})[k] || "";
    }
    readonly property bool hovered: pills.some(p => p.enabled && p.hovered)
    Component.onCompleted: { t3FinishedWas = T3Code.finished; agentsDoneWas = agentsDone.length; if (limitsNow.items.length) limits = limitsNow; }

    // What waits on you, by capsule: the light goes on what's asking
    // (IslandBar keeps its own rim for what's still in the island).
    readonly property bool agentsNeed: agentStack.list.some(a => a.needs) || Kittymux.running.some(r => r.needs) || Agents.desktop.some(d => d.state === "waiting" || d.state === "woke")
    readonly property bool agentsHold: agentsPill.shown
    // For the window's input mask (IslandBar): what's out takes clicks.
    readonly property var pills: [askPill, musicPill, agentsPill, sysPill, limitsPill, minPill, morePill]
    // Is this point (in this item's coordinates) on a capsule, or within
    // `margin` of one? A capsule is its own target: the island does not take
    // a pointer that is on its way to one for a pointer reaching the island.
    function hitAt(x, y, margin) {
        const m = margin || 0;
        for (const p of pills)
            if (p.visible && p.enabled && x >= p.x - m && x <= p.x + p.width + m && y >= p.y - m && y <= p.y + p.height + m) return true;
        return false;
    }

    // One capsule: black glass like the island, sized to `content` (a
    // circle at least), budding from `from` toward `side`.
    component Pill: Item {
        id: pill
        property string name
        // Where a click on it, or pulling it down, takes you: the panel that
        // lists what it holds, to act on from there (not straight to one of
        // them; right-click does that where there's one to go to).
        property string panel: ""
        function openPanel(how = "pointer") {
            if (name === "more") split.openOverflow(how);
            else if (panel) Island.open(panel, split.bar.screenName, how);
        }
        function activate(how = "pointer") { if (name === "ask") Agents.goNeeds(); else if (panel) openPanel(how); else if (name === "min") split.bringBack(split.minimized[split.minimized.length - 1]); }
        readonly property bool hovered: pillHover.hovered
        readonly property alias inputTarget: hitTarget
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
            NumberAnimation { target: pill; property: "flash"; to: 0; duration: Theme.breathOutMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeSine }
        }
        readonly property var lane: split.placement(name)
        readonly property int side: lane || 1
        readonly property bool belowNotch: lane === 0
        // Never an empty capsule: what it holds decides too (a linger, or a
        // state its marks don't draw, left a black pill with nothing in it).
        readonly property bool shown: split.atRest && split.arrangement.sides[name] !== undefined
        readonly property real from: split.fromOf(name)
        default property alias content: slot.data
        readonly property real naturalW: Math.max(split.minimumTarget, split.ph, Math.ceil(slot.childrenRect.width) + Theme.s4 + Theme.s1)
        readonly property real pillGap: belowNotch ? 0 : Math.min(split.gap, Math.max(0, split.spaceFor(name) - split.minimumTarget))
        readonly property real maximumW: Math.max(1, split.spaceFor(name) - pillGap)
        readonly property real bodyW: Math.min(naturalW, maximumW)
        readonly property bool compact: naturalW > maximumW + 0.5 || slot.childrenRect.width <= 0.5
        // The capsule's drawn width springs to its content's (it snapped to
        // each new width): wider with the island's give, narrower clean.
        readonly property real w: Math.max(1, Math.min(wv.value, maximumW))
        // settle(), not snap(): snap assigns the target and breaks its binding
        // to bodyW, and the capsule froze at its first width (T3's ✓ 4 spilled
        // out of it, 2026-11-17).
        Spring { id: wv; tier: pill.bodyW > wv.value ? Theme.surfaceIn : Theme.surfaceOut; epsilon: 0.25; target: pill.bodyW; Component.onCompleted: settle() }
        onShownChanged: if (shown && !out) wv.settle()
        readonly property bool out: sv.value > 0.02
        // The room it takes along its side (for the capsules beyond it).
        readonly property real progress: Math.max(0, Math.min(1, sv.value))
        readonly property real room: (w + pillGap) * progress

        // ── A state change inside the capsule (Clove's contentReveal, Emil's
        // island lesson): what it showed leaves in 110 ms (a snapshot, frozen
        // the moment the key changed), what it shows now arrives 30 ms later:
        // opacity, 0.97 → 1 from its centre, a 3 px blur clearing. One shape,
        // springing once to the new width. `stateKey` changes on a state, not
        // on every count (a new track, working → waiting → done).
        property string stateKey: ""
        property real reveal: 1
        onStateKeyChanged: {
            if (!out || Theme.reduceMotion) return;
            ghost.x = slot.x;
            ghost.opacity = 1;
            pill.reveal = 0;                 // now, not on the animation's first tick (one frame of the new at full)
            swap.restart();
        }
        SequentialAnimation {
            id: swap
            onFinished: Qt.callLater(pill.snap)
            ParallelAnimation {
                // Overlapping, so the capsule is never empty between them.
                NumberAnimation { target: ghost; property: "opacity"; to: 0; duration: Theme.quickMs - 10; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
                SequentialAnimation {
                    PauseAnimation { duration: Theme.handoffMs }
                    NumberAnimation { target: pill; property: "reveal"; to: 1; duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
                }
            }
        }
        Spring { id: sv; tier: pill.shown ? Theme.surfaceIn : Theme.surfaceOut; epsilon: 0.002; target: pill.shown ? 1 : 0; Component.onCompleted: settle() }
        // From 60 % tucked behind the edge to a gap clear of it.
        readonly property real off: -w * 0.6 + (w * 0.6 + pillGap) * progress
        x: belowNotch ? (split.width - w) / 2 : side > 0 ? from + off : from - off - w
        // Pulled down (gestures skill): its bottom edge is the pointer, 1:1 up
        // to the line, the capsule stretching like a drop (top 60 %, length
        // 40 % of the travel); past the line it resists, and its edge lights:
        // let go now and it opens. Released, a spring seeded with the
        // pointer's speed takes it home (catchable: a press reads where it is).
        readonly property real pullLine: Theme.swipeThreshold * 0.8
        readonly property real pullP: Math.max(0, Math.min(1, pull.value / pullLine))
        readonly property bool pullArmed: pullDrag.active && pull.value >= pullLine
        property bool dismissible: false
        signal dismissed()
        y: split.topY + (belowNotch ? split.h + Theme.s2 : Math.round((split.h - split.ph) / 2)) + Math.max(0, pull.value) * 0.6 + Math.min(0, pull.value)
        Spring { id: pull; tier: Theme.springFast; target: 0; epsilon: 0.2 }
        DragHandler {
            id: pullDrag
            parent: hitTarget
            enabled: pill.enabled && pill.panel !== "" && pill.name !== "more"
            target: null
            xAxis.enabled: false
            dragThreshold: 4
            property real grab: 0
            property real raw: 0
            property int gesture: 0
            onCanceled: gesture++
            onActiveChanged: {
                if (active) {
                    gesture++;
                    grab = pull.value;
                    raw = 0;
                    pull.snap(pull.value);
                    return;
                }
                const ended = gesture;
                const speed = centroid.velocity.y;
                const opens = pull.value >= pill.pullLine || speed / 1000 > Theme.swipeFlick;
                const away = pill.dismissible && (raw <= -Theme.s3 || speed / 1000 < -Theme.swipeFlick * 0.6);
                pull.velocity = Theme.reduceMotion ? 0 : speed;
                pull.target = 0;
                if (away) { Qt.callLater(() => { if (ended === gesture && !active) pill.dismissed(); }); return; }
                // Cancellation and losing the grab can end the gesture too.
                // Give Qt's cancellation signal a chance to invalidate it.
                if (opens) Qt.callLater(() => {
                    if (ended === gesture && pill.enabled && !active) pill.openPanel();
                });
            }
            onTranslationChanged: {
                if (!active) return;
                const d = grab + translation.y, L = pill.pullLine;
                raw = translation.y;
                // 1:1 to the line, then rubber-banded; upward only a hint.
                pull.snap(d <= 0 ? (pill.dismissible ? -Theme.swipeDamp(-d) : -Theme.swipeDamp(-d) * 0.25) : d <= L ? d : L + (d - L) * L * 0.55 / (L + 0.55 * (d - L)));
            }
        }
        width: w
        height: split.ph + Math.max(0, pull.value) * 0.4
        visible: out && lane !== undefined
        enabled: shown && w >= split.minimumTarget - 0.5 && progress >= 0.995
        activeFocusOnTab: enabled
        Accessible.role: Accessible.Button
        Accessible.name: split.labelFor(name)
        Accessible.onPressAction: activate()
        Keys.onReturnPressed: activate("key")
        Keys.onEnterPressed: activate("key")
        Keys.onSpacePressed: activate("key")
        // Vertical slop adds a dense-desktop target without increasing the
        // painted capsule. Horizontal targets keep their allocated lanes.
        Item {
            id: hitTarget
            width: pill.width
            height: Math.max(split.minimumTarget, pill.height)
            y: Math.max(-pill.y, (pill.height - height) / 2)
        }
        HoverHandler { id: pillHover; parent: hitTarget; enabled: pill.enabled; cursorShape: Qt.PointingHandCursor }
        TapHandler {
            parent: hitTarget
            acceptedButtons: Qt.LeftButton
            gesturePolicy: TapHandler.WithinBounds
            onTapped: point => {
                const p = slot.mapFromItem(hitTarget, point.position.x, point.position.y);
                if (pill.name === "min" && !pill.compact && p.x >= 0 && p.x < slot.width && p.y >= 0 && p.y < slot.height) return;
                pill.activate();
            }
        }
        FocusRing { cornerRadius: split.ph / 2 }
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
          anchors.fill: parent
          clip: true
          Item {
            id: slot
            x: Math.round((pill.w - childrenRect.width) / 2)
            y: Math.round((split.ph - childrenRect.height) / 2)
            width: childrenRect.width; height: childrenRect.height
            // The content arrives once the capsule is mostly out, leaves first.
            readonly property real arrive: Math.max(0, Math.min(1, (sv.value - (pill.shown ? 0.45 : 0.6)) / 0.35))
            opacity: pill.compact ? 0 : arrive * pill.reveal
            enabled: !pill.compact
            // Clove's live ears: the icon comes once its capsule has opened,
            // growing from 70 % on the capsule's own spring (its give included).
            readonly property real grown: Math.max(0, Math.min(1.05, (sv.value - 0.45) / 0.55))   // past 1 with the spring's give
            scale: (0.7 + 0.3 * grown) * (0.97 + 0.03 * pill.reveal)
            layer.enabled: pill.reveal < 0.999
            layer.effect: MultiEffect { blurEnabled: true; blurMax: 12; blur: (1 - pill.reveal) * 0.25; autoPaddingEnabled: true }
        }
        // The old content, for the swap: a snapshot taken when the capsule
        // settles into a state (snap() below), never live (live, an animating
        // capsule — T3's spinner — rendered twice every frame: +3 % CPU at
        // rest). States change rarely; a count a minute old is still the old
        // state for the 110 ms it takes to leave.
        ShaderEffectSource {
            id: ghost
            y: slot.y
            width: slot.width; height: slot.height
            sourceItem: slot
            live: false
            hideSource: false
            opacity: 0
            visible: opacity > 0.01
        }
          Text {
            anchors.centerIn: parent
            visible: pill.compact
            textFormat: Text.PlainText
            text: pill.name === "more" ? "+" + split.arrangement.overflow.length : split.glyphFor(pill.name)
            font.family: pill.name === "more" ? Theme.fontText : Theme.fontGlyph
            font.pixelSize: Theme.tSub * Theme.textScale
            font.weight: Theme.wSemibold
            color: pill.toned ? pill.tone : Theme.textPrimary
          }
        }
        Tip { text: split.labelFor(pill.name) + " · open for details"; shown: pill.compact && pill.hovered; below: true }
        // Snapshot the moments the capsule shows a state at rest: as it comes
        // out, once it has arrived, after a swap, and when what it holds
        // changes size (a count, a time). A timer refreshing it twice a second
        // drew a frame every 500 ms for as long as a capsule was out.
        function snap() { if (pill.out && !pill.compact && !Theme.reduceMotion && !swap.running) ghost.scheduleUpdate(); }
        readonly property bool arrived: slot.arrive >= 1
        onOutChanged: if (out) Qt.callLater(snap)
        onArrivedChanged: if (arrived) Qt.callLater(snap)
        onCompactChanged: if (!compact) Qt.callLater(snap)
        onNaturalWChanged: Qt.callLater(snap)
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
            textFormat: Text.PlainText
            visible: badge.glyph !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: badge.glyph
            font.family: Theme.fontGlyph; font.pixelSize: Theme.tCallout
            color: badge.tint
        }
        Label {
            visible: badge.text !== ""
            anchors.verticalCenter: parent.verticalCenter
            // On the wordmark's baseline: "T3" is a size larger and already
            // sits 1 px low (RestMark), so a centred count read 1.5 px higher
            // than the "T3 ③" beside it (measured on both screens).
            anchors.verticalCenterOffset: 2
            text: badge.text
            size: Theme.tSub; weight: Theme.wSemibold
            color: badge.tint
            tabular: true
        }
        HoverHandler { id: badgeHover; enabled: badge.enabled; cursorShape: Qt.PointingHandCursor }
        TapHandler { acceptedButtons: Qt.LeftButton | Qt.RightButton; gesturePolicy: TapHandler.WithinBounds; onTapped: (point, button) => button === Qt.RightButton ? badge.altClicked() : badge.clicked() }
        Tip { text: badge.tip; shown: badgeHover.hovered && badge.tip !== ""; below: true }
        Accessible.role: Accessible.Button
        Accessible.name: badge.tip || badge.text
        Accessible.onPressAction: badge.clicked()
    }

    // ── Music, stepped aside ──
    Pill {
        id: musicPill
        name: "music"
        panel: "media"
        stateKey: split.player ? (split.player.trackTitle || "") : ""
        ClippingRectangle {
            width: 18; height: 18; radius: 5
            color: Theme.wash(2)
            ArtImage { anchors.fill: parent; source: split.player ? (split.player.trackArtUrl || "") : ""; px: 36 }
            HoverHandler { id: musicHover; enabled: parent.enabled; cursorShape: Qt.PointingHandCursor }
            TapHandler { gesturePolicy: TapHandler.WithinBounds; onTapped: Island.open("media", split.bar.screenName, "pointer", "island") }
            Tip { text: (split.player ? (Media.title(split.player) || split.player.identity || "Playing") : "") + " · click for Now Playing"; shown: musicHover.hovered; below: true }
            Accessible.role: Accessible.Button
            Accessible.name: "Now playing: " + (split.player ? (Media.title(split.player) || split.player.identity || "music") : "music")
            Accessible.onPressAction: Island.open("media", split.bar.screenName, "pointer", "island")
        }
    }

    Pill {
        id: askPill
        name: "ask"
        panel: "agents"
        needs: true
        stateKey: split.agentsHead.key
        tone: Theme.orange
        attention: true
        Row {
            spacing: 6
            AgentStack { id: askStack; bar: split.bar; withT3: true; withDesktop: true; only: "needs"; visible: list.length > 0; anchors.verticalCenter: parent.verticalCenter }
            Badge {
                glyph: split.agentsHead.glyph || "\u{f0026}"
                text: split.asking ? split.agentsHead.word : ""
                tint: Theme.orange
                tip: (Agents.next ? Kittymux.agentLabel(Agents.next.agent) + " · " + Agents.next.title : "") + "\nClick: go there (Super+Ctrl+A) · right-click: every agent"
                onClicked: Agents.goNeeds()
                onAltClicked: askPill.openPanel()
            }
        }
    }

    Pill {
        id: agentsPill
        name: "agents"
        panel: "agents"
        needs: false
        stateKey: [split.agentsHead.key, split.agentsHead.done > 0].join()
        tone: split.agentsHead.tone === "error" ? Theme.red : split.agentsHead.done > 0 && !agentStack.list.length ? Theme.green : "transparent"
        attention: split.agentsHead.tone === "error"
        Row {
            spacing: 6
            AgentStack { id: agentStack; bar: split.bar; withT3: true; withDesktop: true; only: "work"; visible: list.length > 0; anchors.verticalCenter: parent.verticalCenter }
            Badge {
                visible: split.agentsWord
                glyph: split.agentsHead.glyph || ({ error: "\u{f0028}" })[split.agentsHead.tone] || ""
                text: split.agentsHead.word
                tint: ({ attention: Theme.orange, error: Theme.red })[split.agentsHead.tone] || Theme.textSecondary
                tip: (Agents.next ? Agents.next.title : "") + "\nClick: every agent · right-click: go there (Super+Ctrl+A)"
                onClicked: agentsPill.openPanel()
                onAltClicked: Agents.goNeeds()
            }
            Badge {
                visible: split.agentsHead.done > 0 && !split.agentsWord
                glyph: "\u{f05e0}"
                text: split.agentsHead.done > 1 ? String(split.agentsHead.done) : ""
                tint: Theme.green
                tip: split.agentsDone.slice(0, 3).map(e => Kittymux.agentLabel(e.agent) + " finished" + (e.tab ? " · " + Kittymux.clean(e.tab) : ""))
                    .concat(T3Code.liveItems.filter(i => i.status === "completed").slice(0, 3).map(i => i.title + " finished"))
                    .concat(Agents.desktop.filter(d => d.state === "done").slice(0, 3).map(d => Kittymux.agentLabel(d.agent) + " finished" + (d.title ? " · " + d.title : ""))).slice(0, 3).join(" · ")
                    + "\nClick: every agent · right-click: go to the newest"
                onClicked: agentsPill.openPanel()
                onAltClicked: split.agentsDone.length ? split.goDone() : T3Code.openBest()
            }
        }
    }

    // ── System news: updates waiting, a warning, a used-up limit ──
    Pill {
        id: sysPill
        name: "sys"
        stateKey: Alerts.active.length ? Alerts.active[0].level + Alerts.active[0].id : Updates.fresh ? "updates" : Sweep.fresh ? "sweep" : ""
        // Pulled: what it's saying most loudly (a warning, else updates, else idle projects, else a used-up limit).
        panel: Alerts.active.length ? "system" : Updates.fresh || Updates.running ? "updates" : Sweep.fresh ? "sweep" : "updates"
        tone: Alerts.active.length ? (Alerts.active[0].level === "crit" ? Theme.red : Theme.orange) : "transparent"
        attention: Alerts.active.length > 0
        dismissible: true
        onDismissed: { split.sysHidden = split.sysKey; sysLinger.stop(); }
        SysMarks {
            id: sysMarks
            bar: split.bar
            showLimit: false
            quiet: split.activity !== "" && split.activity !== "media"
            updateOffStage: Updates.running && split.activity !== "update"
        }
    }

    // ── Usage limits: when you can carry on (orange: back within soonMs; red: later) ──
    Pill {
        id: limitsPill
        name: "limits"
        panel: "usage"
        stateKey: split.limits.tone + ":" + split.limits.providers.map(p => p.id + p.count).join()
        tone: split.limitTint
        attention: false
        dismissible: true
        onDismissed: { split.limitsHidden = split.limitsKey; limitsLinger.stop(); }
        Row {
            spacing: 5
            Item {
                id: leadMark
                readonly property var p: split.limits.providers[0] || null
                readonly property bool ringed: split.limits.tone === "soon"
                anchors.verticalCenter: parent.verticalCenter
                width: 20; height: 20
                StatRing {
                    visible: leadMark.ringed
                    anchors.fill: parent
                    size: 20; stroke: 2
                    value: split.limits.at > Limits.now ? Math.max(0, Math.min(1, (split.limits.at - Limits.now) / Limits.soonMs)) : 0
                    color: split.limitTint
                    text: ""; label: ""
                }
                Image {
                    id: leadImg
                    anchors.centerIn: parent
                    width: leadMark.ringed ? 10 : 14; height: width
                    source: leadMark.p ? leadMark.p.brand || "" : ""
                    sourceSize: Qt.size(28, 28)
                    asynchronous: true
                }
                Text {
                    visible: leadImg.status !== Image.Ready
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: "\u{f051f}"; font.family: Theme.fontGlyph; font.pixelSize: Theme.tFootnote
                    color: split.limitTint
                }
            }
            Badge {
                glyph: ""
                text: split.limits.label
                tint: split.limitTint
                tip: (leadMark.p ? leadMark.p.name + " is back " + (split.limits.at > Limits.now ? "in " + Limits.compact(split.limits.at - Limits.now) : "when its limit resets") : "Limit reached") + "\n"
                    + split.limits.items.map(x => x.name + (x.account && x.account.toLowerCase() !== x.name.toLowerCase() ? " (" + x.account + ")" : "")
                        + (x.resetsAt > Limits.now ? " · back in " + Limits.compact(x.resetsAt - Limits.now) : " · out")).join("\n")
                    + "\nClick: Usage · swipe up: hide until it changes" + (split.agentsLim.length ? " · right-click: dismiss agent limits" : "")
                onClicked: {
                    const first = split.limits.items[0];
                    if (first && first.id) Limits.usageTab = first.id;
                    Island.open("usage", split.bar.screenName, "pointer");
                }
                onAltClicked: {
                    if (split.agentsLim.length) split.agentsLim.forEach(r => Kittymux.quiet(r));
                    else Island.open("usage", split.bar.screenName, "pointer");
                }
            }
            Rectangle {
                visible: split.limits.providers.length > 1
                anchors.verticalCenter: parent.verticalCenter
                width: 1; height: 12
                color: Theme.edge(1)
            }
            Repeater {
                model: split.limits.providers.slice(1, 4)
                Image {
                    required property var modelData
                    anchors.verticalCenter: parent.verticalCenter
                    width: 11; height: 11
                    source: modelData.brand || ""
                    sourceSize: Qt.size(22, 22)
                    asynchronous: true
                    opacity: 0.55
                }
            }
            Label {
                visible: split.limits.providers.length > 4
                anchors.verticalCenter: parent.verticalCenter
                text: "+" + (split.limits.providers.length - 4)
                size: Theme.tCaption; weight: Theme.wSemibold; rounded: true
                color: Theme.textSecondary
            }
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
                        textFormat: Text.PlainText
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
                    HoverHandler { id: mwHover; enabled: parent.enabled; margin: 3; cursorShape: Qt.PointingHandCursor }
                    TapHandler { gesturePolicy: TapHandler.WithinBounds; onTapped: split.bringBack(mw.modelData) }
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
                tabular: true
                HoverHandler { id: moreHover; enabled: parent.enabled; cursorShape: Qt.PointingHandCursor }
                TapHandler { gesturePolicy: TapHandler.WithinBounds; onTapped: split.bringBack(split.minimized[split.minimized.length - 1]) }
                Accessible.role: Accessible.Button
                Accessible.name: (split.minimized.length - 3) + " more minimized, bring one back"
                Accessible.description: split.minimized.slice(3).map(t => t.title).join(", ")
                Accessible.onPressAction: split.bringBack(split.minimized[split.minimized.length - 1])
                Tip { text: split.minimized.slice(3).map(t => t.title).join(" · ") + "\nClick: bring one back (or Super+Shift+O)"; shown: moreHover.hovered; below: true }
            }
        }
    }

    Pill {
        id: morePill
        name: "more"
        panel: "activities"
        needs: split.arrangement.overflow.some(k => split.pillOf(k).attention)
        Label {
            text: "+" + split.arrangement.overflow.length
            size: Theme.tSub
            weight: Theme.wSemibold
        }
    }

}
