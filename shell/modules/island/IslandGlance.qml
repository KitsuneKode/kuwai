// The island on hover, before you ask for more: one row, a little bigger
// than the notch at rest. A click (anywhere on it) opens the whole hover view
// (IslandHover); hovering alone never does — big things answer a click
// (Settings → Bar & Island → Hover shows: a glance or everything).
//
//   ▣ Kitty              23:29  Thu, Oct 30              ▧ Rock It
//
// Where you are, when (in the same place as the full view's time chip, so the
// clock holds still while the island grows around it), and what's playing or
// waiting (an agent asking you comes first, and goes to it). Three doors: the time opens the calendar (as everywhere), what's
// playing or waiting opens Now Playing or the notifications list, and the
// rest of the row opens everything.
import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.config
import qs.components
import qs.services

Item {
    id: glance
    required property var bar
    readonly property Item clockItem: glanceClock
    property bool clockHidden: false
    readonly property var player: bar.player
    readonly property bool playing: !!player && player.isPlaying && Settings.hoverMedia && !waiting
    // An agent waiting on you outranks a song: who, in the needs-you colour.
    readonly property bool waiting: bar.waitingCount > 0
    readonly property var focusWin: bar.screenWin
    readonly property var topInfo: focusWin && focusWin.lastIpcObject ? focusWin.lastIpcObject : ({})
    readonly property string winClass: topInfo.class || (focusWin && focusWin.wayland ? (focusWin.wayland.appId || "") : "")
    readonly property var app: winClass ? DesktopEntries.heuristicLookup(winClass) : null

    readonly property real pad: 22
    readonly property real gap: 20
    // One line of type: pad · where · gap · when · gap · what · pad, the gaps
    // equal, every label on the clock's baseline. Each side is as wide as
    // its own text, so the time sits a little off centre when the sides
    // differ. With both sides the width of the longer one (as before) a
    // short app name left a wide hole on one side of the time and the other
    // side crowded it.
    // From the labels' own text widths: the rows' widths depend on these,
    // and sizing from them settled on almost nothing (the name ran under the clock).
    readonly property real leftW: Math.min(170, 26 + appName.implicitWidth)
    readonly property real rightW: Math.min(170, rightText.implicitWidth + (glance.playing ? 30 : 0))
    implicitWidth: Math.round(2 * (pad + gap) + leftW + rightW + when.implicitWidth)
    implicitHeight: 52

    // ── Where ──
    Row {
        id: left
        x: glance.pad
        anchors.baseline: when.baseline
        baselineOffset: appName.y + appName.baselineOffset
        width: glance.leftW
        spacing: 8
        opacity: glance.bar.focusedHere ? 1 : 0.55
        Item {
            id: appIcon
            width: 18; height: 18
            anchors.verticalCenter: parent.verticalCenter
            readonly property string path: glance.app && glance.app.icon ? Quickshell.iconPath(glance.app.icon, true) : ""
            IconImage { anchors.fill: parent; visible: appIcon.path !== ""; source: appIcon.path; asynchronous: true }
            Text { visible: appIcon.path === ""; anchors.centerIn: parent; text: "\u{f05b5}"; font.family: Theme.fontGlyph; font.pixelSize: Theme.tCallout; color: Theme.textSecondary }
        }
        Label {
            id: appName
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, glance.leftW - 26)
            elide: Text.ElideRight
            text: glance.app ? glance.app.name : glance.winClass ? glance.winClass.charAt(0).toUpperCase() + glance.winClass.slice(1) : "Desktop"
            size: Theme.tCallout; weight: Theme.wMedium
        }
    }

    // ── When ──
    Row {
        id: when
        // Centred between the sides (from the middle, so it holds while the
        // island's width springs).
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.horizontalCenterOffset: (glance.leftW - glance.rightW) / 2
        anchors.verticalCenter: parent.verticalCenter
        baselineOffset: glanceClock.y + glanceClock.baselineOffset
        spacing: 9
        IslandClock {
            id: glanceClock
            opacity: glance.clockHidden ? 0 : 1   // not visible: the Row would close up under the flying clock
            now: glance.bar.now; size: Theme.tTitle2
            rounded: false; weight: Theme.wMedium
            color: Qt.rgba(1, 0.98, 0.95, 0.95)
            anchors.verticalCenter: parent.verticalCenter
        }
        Label {
            anchors.baseline: glanceClock.baseline
            text: Qt.formatDate(glance.bar.now, "ddd, MMM d")
            size: Theme.tCallout; weight: Theme.wMedium
            color: Theme.textTertiary
        }
    }

    // ── What's playing, else what's waiting ──
    Row {
        id: right
        anchors.right: parent.right
        anchors.rightMargin: glance.pad
        anchors.baseline: when.baseline
        baselineOffset: rightText.y + rightText.baselineOffset
        spacing: 8
        layoutDirection: Qt.RightToLeft
        Label {
            id: rightText
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, glance.rightW - (art.visible ? 30 : 0))
            elide: Text.ElideRight
            text: glance.waiting ? glance.bar.waitingWho
                : glance.playing ? (glance.player.trackTitle || glance.player.identity || "Playing")
                : Notifs.dnd ? "Focus on"
                : Notifs.missed.length ? (Notifs.missed.length === 1 ? "1 missed" : Notifs.missed.length + " missed")
                : Notifs.inbox ? (Notifs.inbox === 1 ? "1 notification" : Notifs.inbox + " notifications")
                : "All caught up"
            size: Theme.tSub; weight: glance.playing || glance.waiting ? Theme.wMedium : Theme.wRegular
            color: glance.waiting ? Theme.orange : glance.playing ? Theme.textSecondary : Notifs.missed.length ? Theme.textPrimary : Theme.textTertiary
        }
        ClippingRectangle {
            id: art
            visible: glance.playing
            anchors.verticalCenter: parent.verticalCenter
            width: 22; height: 22; radius: 6
            color: Qt.rgba(1, 1, 1, 0.08)
            ArtImage { anchors.fill: parent; source: glance.playing ? (glance.player.trackArtUrl || "") : ""; px: 44 }
        }
    }

    // The time is the calendar's door wherever it shows (at rest, here, in
    // the full view), and the clock travels into it; the rest of the row
    // opens everything.
    HoverHandler { cursorShape: Qt.PointingHandCursor }
    TapHandler {
        onTapped: eventPoint => {
            const p = when.mapFromItem(glance, eventPoint.position.x, eventPoint.position.y);
            if (p.x >= -6 && p.x <= when.width + 6 && p.y >= -8 && p.y <= when.height + 8) {
                glance.bar.clockFrom(glanceClock);
                Island.open("calendar", glance.bar.screenName, "pointer", "island");
            } else {
                // What's playing or waiting is its own door too: Now Playing,
                // or the notifications list (C there opens the center).
                const r = right.mapFromItem(glance, eventPoint.position.x, eventPoint.position.y);
                if (r.x >= -6 && r.x <= right.width + 6 && r.y >= -8 && r.y <= right.height + 8 && glance.waiting)
                    glance.bar.goWaiting();
                else if (r.x >= -6 && r.x <= right.width + 6 && r.y >= -8 && r.y <= right.height + 8)
                    Island.open(glance.playing ? "media" : "notifs", glance.bar.screenName, "pointer", "island");
                else glance.bar.full = true;
            }
        }
    }
    Accessible.role: Accessible.Button
    Accessible.name: "Island: " + (glance.app ? glance.app.name : "Desktop") + ", " + Qt.formatTime(glance.bar.now, "hh:mm") + ". Click for everything."
}
