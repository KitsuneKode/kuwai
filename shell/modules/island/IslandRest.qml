// The island at rest: workspaces · clock · status, with a live activity on
// either side while something is happening (Apple's compact presentation:
// a leading and a trailing view around the island). One at a time, by
// priority: dictation (voxtype) > Shazam > music. The privacy dot (an app
// is using the microphone) is always shown when true.
//
//   ◉ mic  ● ▮ ● ●  23:29  ▂▄▆ ▭  0:07        dictating
//   ♫ art  ● ▮ ● ●  23:29  ▂▄▆ ▭  ▂▅▃▆        music playing
import QtQuick
import Quickshell.Widgets
import qs.config
import qs.components
import qs.services

Row {
    id: rest
    required property var bar
    spacing: 12

    // Which live activity, if any.
    readonly property string activity: Activities.voxActive ? "vox"
        : Alerts.active.length ? "alert"
        : (Activities.shazamListening || Activities.shazamFound) ? "shazam"
        : bar.player && bar.player.isPlaying && Settings.restMedia ? "media" : ""

    property real voxSecs: 0
    Timer {
        running: Activities.voxListening
        interval: 250; repeat: true; triggeredOnStart: true
        onTriggered: rest.voxSecs = Math.max(0, (Date.now() - Activities.voxSince) / 1000)
    }

    // ── Leading ──────────────────────────────────────────────────────────
    Item {
        visible: rest.activity !== ""
        width: 20; height: 20
        anchors.verticalCenter: parent.verticalCenter

        // Dictation: a mic that breathes while it listens, a spinner while it writes.
        Text {
            visible: rest.activity === "vox"
            anchors.centerIn: parent
            text: Activities.voxListening ? "\u{f036c}" : "\u{f0772}"
            font.family: Theme.fontGlyph
            font.pixelSize: 15
            color: Activities.voxListening ? Theme.red : Theme.accent
            SequentialAnimation on opacity {
                running: rest.activity === "vox" && Activities.voxListening && !Theme.reduceMotion
                loops: Animation.Infinite
                NumberAnimation { to: 0.45; duration: 700; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
            }
            RotationAnimation on rotation {
                running: rest.activity === "vox" && !Activities.voxListening && !Theme.reduceMotion
                loops: Animation.Infinite; from: 0; to: 360; duration: 1100
            }
        }
        // A warning that hasn't cleared: its mark, in its colour.
        Text {
            visible: rest.activity === "alert"
            anchors.centerIn: parent
            text: Alerts.active.length ? Alerts.active[0].glyph : ""
            font.family: Theme.fontGlyph
            font.pixelSize: 15
            color: Alerts.active.length && Alerts.active[0].level === "crit" ? Theme.red : Theme.orange
            HoverHandler { id: alertHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: Island.open("system", rest.bar.screenName, "pointer", "island") }
            Tip { text: Alerts.active.length ? Alerts.active.map(a => a.title).join(" · ") : ""; shown: alertHover.hovered; below: true }
        }
        // Shazam: its mark, pulsing while it listens.
        Text {
            visible: rest.activity === "shazam"
            anchors.centerIn: parent
            text: "\u{f0388}"
            font.family: Theme.fontGlyph
            font.pixelSize: 16
            color: Theme.accent
            SequentialAnimation on scale {
                running: rest.activity === "shazam" && Activities.shazamListening && !Theme.reduceMotion
                loops: Animation.Infinite
                NumberAnimation { to: 1.18; duration: 520; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 520; easing.type: Easing.InOutSine }
            }
        }
        // Music: the album art, tiny.
        ClippingRectangle {
            visible: rest.activity === "media"
            anchors.centerIn: parent
            width: 20; height: 20; radius: 5
            color: Theme.pill
            Image { anchors.fill: parent; source: rest.bar.player ? (rest.bar.player.trackArtUrl || "") : ""; sourceSize: Qt.size(40, 40); fillMode: Image.PreserveAspectCrop; asynchronous: true }
        }
    }

    // ── The core ─────────────────────────────────────────────────────────
    Capsules { bar: rest.bar; visible: Settings.restWorkspaces; anchors.verticalCenter: parent.verticalCenter }
    IslandClock {
        now: rest.bar.now; size: 14
        anchors.verticalCenter: parent.verticalCenter
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: Island.toggle("calendar", rest.bar.screenName, "pointer", "island") }
    }
    Row {
        visible: Settings.restStatus
        spacing: 7
        anchors.verticalCenter: parent.verticalCenter
        Rectangle {
            visible: Activities.micInUse
            anchors.verticalCenter: parent.verticalCenter
            width: 6; height: 6; radius: 3
            color: Theme.orange
        }
        IslandStatus { anchors.verticalCenter: parent.verticalCenter }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: Notifs.toggleCenter("controls", "pointer") }
    }

    // ── Trailing ─────────────────────────────────────────────────────────
    Item {
        visible: rest.activity !== "" && rest.activity !== "alert"
        width: trailing.implicitWidth
        height: 20
        anchors.verticalCenter: parent.verticalCenter
        Row {
            id: trailing
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            Label {
                visible: rest.activity === "vox"
                anchors.verticalCenter: parent.verticalCenter
                text: Activities.voxListening ? Math.floor(rest.voxSecs / 60) + ":" + String(Math.floor(rest.voxSecs % 60)).padStart(2, "0") : "Writing"
                size: 13; weight: Theme.wSemibold; rounded: true
                color: Activities.voxListening ? Theme.red : Theme.textSecondary
                font.features: ({ "tnum": 1 })
            }
            Label {
                visible: rest.activity === "shazam"
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, 170)
                elide: Text.ElideRight
                text: Activities.shazamFound ? Activities.shazamFound.title + " · " + Activities.shazamFound.artist : "Listening"
                size: 12; weight: Theme.wMedium
            }
            // Music: four bars, in the theme colour.
            Row {
                visible: rest.activity === "media"
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Repeater {
                    model: 4
                    Rectangle {
                        required property int index
                        anchors.verticalCenter: parent.verticalCenter
                        width: 3; radius: 1.5; height: 5
                        color: Theme.accent
                        SequentialAnimation on height {
                            running: rest.activity === "media" && !Theme.reduceMotion
                            loops: Animation.Infinite
                            NumberAnimation { to: 7 + (index * 5) % 9; duration: 300 + index * 70; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 4; duration: 280 + (index % 2) * 90; easing.type: Easing.InOutSine }
                        }
                    }
                }
            }
        }
    }

    // A click on an activity acts on it: stop dictation, open the song.
    TapHandler {
        enabled: rest.activity === "vox" || (rest.activity === "shazam" && !!Activities.shazamFound)
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onTapped: (point, button) => {
            if (rest.activity === "vox") { if (button === Qt.RightButton) Activities.voxCancel(); else Activities.voxToggle(); }
            else Activities.shazamOpen();
        }
    }
}
