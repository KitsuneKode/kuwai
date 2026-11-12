// The split island (Apple's: a second live activity leaves the island for a
// bubble of its own). Beside the notch, at rest, each in its own small pill:
//
//      ( ▣ )   [ 21:08 ·  live activity ]   ( ✳◐ )( T3 ② )
//      left: what's happening to you,          right: who's working for you
//      stepped aside (music, while dictation,  in the background (kitty
//      a recording, a timer or an update has  agents, T3 threads)
//      the island)
//
// The island keeps the time and the one thing live; the pills are the rest,
// so the notch stays short and every piece reads on its own. A pill buds
// out from under the island's edge (its own spring, carried by the edge as
// the island resizes), and folds back under it when the island grows: the
// grown island holds everything again. Settings → Bar & Island → Separate pills.
import QtQuick
import Quickshell.Widgets
import qs.config
import qs.components
import qs.services

Item {
    id: split
    required property var bar
    // The island's body edges (window x), its top and height, and how much
    // of the rest state shows (0 while it's grown, hidden or tucked).
    property real leftEdge: 0
    property real rightEdge: 0
    property real topY: 0
    property real h: 34
    property bool notch: true
    property real ear: 9
    property bool atRest: true
    property string activity: ""

    readonly property bool on: Settings.islandSplit
    readonly property var player: bar.player
    // Music stepped aside: playing, and a long-lived activity has the island
    // (not a moment: a 3-second "Copied" would pop it out and back).
    readonly property bool musicAside: on && atRest && !!player && player.isPlaying && Settings.restMedia
        && ["vox", "rec", "timer", "update"].indexOf(activity) >= 0
    readonly property bool agentsOut: on && atRest && agentStack.list.length > 0
    readonly property bool t3Out: on && atRest && T3Code.total > 0
    // For the window's input mask (IslandBar): what's out takes clicks.
    readonly property var pills: [musicPill, agentsPill, t3Pill]

    readonly property real gap: 10       // body to body; a notch's ears meet above it, one edge

    // One pill: a small notch (or a floating capsule) holding `content`,
    // sized to it (a circle at least), budding from `from` toward `side`.
    component Pill: Item {
        id: pill
        property int side: 1             // 1: right of `from`, -1: left of it
        property real from: 0            // the edge it buds from (window x)
        property bool shown: false
        default property alias content: slot.data
        readonly property real bodyW: Math.max(split.h, Math.round(slot.childrenRect.width) + 22)
        readonly property bool out: sv.value > 0.02
        Spring { id: sv; tier: pill.shown ? Theme.surfaceIn : Theme.surfaceOut; epsilon: 0.002; target: pill.shown ? 1 : 0; Component.onCompleted: settle() }
        // Out from under the edge: from 60 % tucked behind it to a gap clear of it.
        readonly property real off: -bodyW * 0.6 + (bodyW * 0.6 + split.gap) * sv.value
        x: side > 0 ? from + off - split.ear : from - off - bodyW - split.ear
        y: split.topY
        width: bodyW + split.ear * 2
        height: split.h
        visible: out
        opacity: Math.min(1, sv.value * 2)
        scale: 0.86 + 0.14 * sv.value
        transformOrigin: side > 0 ? Item.Left : Item.Right

        NotchShape {
            visible: split.notch
            w: pill.bodyW
            h: split.h
            ear: split.ear
            radius: 14
        }
        Rectangle {
            visible: !split.notch
            x: split.ear; width: pill.bodyW; height: split.h
            radius: height / 2
            color: Qt.rgba(0, 0, 0, 0.9)
        }
        Item {
            id: slot
            x: split.ear + Math.round((pill.bodyW - childrenRect.width) / 2)
            y: Math.round((split.h - childrenRect.height) / 2)
            width: childrenRect.width; height: childrenRect.height
            // The content arrives once the pill is mostly out, leaves first.
            opacity: Math.max(0, Math.min(1, (sv.value - (pill.shown ? 0.45 : 0.6)) / 0.35))
        }
    }

    // ── Left: music, stepped aside ───────────────────────────────────────
    Pill {
        id: musicPill
        side: -1
        from: split.leftEdge
        shown: split.musicAside
        ClippingRectangle {
            width: 20; height: 20; radius: 6
            color: Qt.rgba(1, 1, 1, 0.08)
            Image { anchors.fill: parent; source: split.player ? (split.player.trackArtUrl || "") : ""; sourceSize: Qt.size(40, 40); fillMode: Image.PreserveAspectCrop; asynchronous: true }
            HoverHandler { id: musicHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: Island.open("media", split.bar.screenName, "pointer", "island") }
            Tip { text: (split.player ? (split.player.trackTitle || split.player.identity || "Playing") : "") + " · click for Now Playing"; shown: musicHover.hovered; below: true }
            Accessible.role: Accessible.Button
            Accessible.name: "Now playing: " + (split.player ? (split.player.trackTitle || split.player.identity || "music") : "music")
            Accessible.onPressAction: Island.open("media", split.bar.screenName, "pointer", "island")
        }
    }

    // ── Right: who's working for you ─────────────────────────────────────
    Pill {
        id: agentsPill
        side: 1
        from: split.rightEdge
        shown: split.agentsOut
        AgentStack { id: agentStack; bar: split.bar }
    }
    Pill {
        id: t3Pill
        side: 1
        // After the agents' pill when it's out, else from the island.
        from: agentsPill.out ? agentsPill.x + agentsPill.width - split.ear : split.rightEdge
        shown: split.t3Out
        RestMark {
            wordmark: "T3"
            value: T3Code.waiting > 0 ? String(T3Code.waiting) : String(T3Code.running)
            ring: T3Code.waiting > 0 ? "solid" : "spin"
            tone: T3Code.waiting > 0 ? Theme.orange : Theme.cyan
            previews: true
            onPreviewRequested: if (Island.panel === "") Island.preview("t3", split.bar.screenName)
            onClicked: T3Code.openBest()
        }
    }
}
