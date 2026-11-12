// The island on hover, before you ask for more: one row, a little bigger
// than the notch at rest. A click (anywhere on it) opens the whole hover view
// (IslandHover); hovering alone never does — big things answer a click
// (Settings → Bar & Island → Hover shows: a glance or everything).
//
//   ▣ Kitty              23:29  Thu, Oct 30              ▧ Rock It
//
// Where you are, when (in the same place as the full view's time chip, so the
// clock holds still while the island grows around it), and what's playing or
// waiting. Two doors: the time opens the calendar (as everywhere), the rest
// of the row opens everything.
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
    readonly property bool playing: !!player && player.isPlaying && Settings.hoverMedia
    readonly property var focusWin: bar.screenWin
    readonly property var topInfo: focusWin && focusWin.lastIpcObject ? focusWin.lastIpcObject : ({})
    readonly property string winClass: topInfo.class || (focusWin && focusWin.wayland ? (focusWin.wayland.appId || "") : "")
    readonly property var app: winClass ? DesktopEntries.heuristicLookup(winClass) : null

    readonly property real pad: 22
    readonly property real gap: 20
    // The time centred, the two sides the same width so it stays centred.
    // From the labels' own text widths: the rows' widths depend on sideW, and
    // sizing from them settled on almost nothing (the name ran under the clock).
    readonly property real leftNeed: 26 + appName.implicitWidth
    readonly property real rightNeed: rightText.implicitWidth + (glance.playing ? 30 : 0)
    readonly property real sideW: Math.min(170, Math.max(96, leftNeed, rightNeed))
    implicitWidth: Math.round(2 * (pad + sideW + gap) + when.implicitWidth)
    implicitHeight: 52

    // ── Where ──
    Row {
        id: left
        x: glance.pad
        anchors.verticalCenter: parent.verticalCenter
        width: glance.sideW
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
            width: Math.min(implicitWidth, glance.sideW - 26)
            elide: Text.ElideRight
            text: glance.app ? glance.app.name : glance.winClass ? glance.winClass.charAt(0).toUpperCase() + glance.winClass.slice(1) : "Desktop"
            size: Theme.tCallout; weight: Theme.wMedium
        }
    }

    // ── When ──
    Row {
        id: when
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        spacing: 9
        IslandClock {
            id: glanceClock
            visible: !glance.clockHidden
            now: glance.bar.now; size: Theme.tTitle2
            rounded: false; weight: Theme.wMedium
            color: Qt.rgba(1, 0.98, 0.95, 0.95)
            anchors.verticalCenter: parent.verticalCenter
        }
        Label {
            anchors.verticalCenter: parent.verticalCenter
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
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        layoutDirection: Qt.RightToLeft
        Label {
            id: rightText
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, glance.sideW - (art.visible ? 30 : 0))
            elide: Text.ElideRight
            text: glance.playing ? (glance.player.trackTitle || glance.player.identity || "Playing")
                : Notifs.dnd ? "Focus on"
                : Notifs.missed.length ? (Notifs.missed.length === 1 ? "1 missed" : Notifs.missed.length + " missed")
                : Notifs.inbox ? (Notifs.inbox === 1 ? "1 notification" : Notifs.inbox + " notifications")
                : "All caught up"
            size: Theme.tSub; weight: glance.playing ? Theme.wMedium : Theme.wRegular
            color: glance.playing ? Theme.textSecondary : Notifs.missed.length ? Theme.textPrimary : Theme.textTertiary
        }
        ClippingRectangle {
            id: art
            visible: glance.playing
            anchors.verticalCenter: parent.verticalCenter
            width: 22; height: 22; radius: 6
            color: Qt.rgba(1, 1, 1, 0.08)
            Image { anchors.fill: parent; source: glance.playing ? (glance.player.trackArtUrl || "") : ""; sourceSize: Qt.size(44, 44); fillMode: Image.PreserveAspectCrop; asynchronous: true }
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
            } else glance.bar.full = true;
        }
    }
    Accessible.role: Accessible.Button
    Accessible.name: "Island: " + (glance.app ? glance.app.name : "Desktop") + ", " + Qt.formatTime(glance.bar.now, "hh:mm") + ". Click for everything."
}
