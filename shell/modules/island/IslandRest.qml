// The island at rest: workspaces · clock · status, with a live activity on
// either side while something is happening (Apple's compact presentation:
// a leading and a trailing view around the island). One at a time, by
// priority: dictation (voxtype) > Shazam > music. The privacy dot (an app
// is using the microphone) is always shown when true.
//
//   ◉ mic  ● ▮ ● ●  23:29  ▂▄▆ ▭  0:07        dictating
//   ♫ art  ● ▮ ● ●  23:29  ▂▄▆ ▭  ▂▅▃▆        music playing
import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import qs.config
import qs.components
import qs.services

Item {
    id: rest
    required property var bar
    // Left (activity + pills) and right (status + activity) take the same
    // width, so the time sits in the middle; the gap either side of it is
    // wider than the spacing inside each group (Apple's grouping).
    readonly property real side: Math.max(leftGroup.implicitWidth, rightGroup.implicitWidth)
    // Centred only when the two sides are within a few pixels anyway. Past
    // that, padding the lighter side reads as a hole next to the time (it was
    // 48 px: 9 pills vs signal + battery left ~30 px of nothing), so the groups
    // sit at equal gaps and the time is off-centre by half the difference.
    readonly property bool balanced: Math.abs(leftGroup.implicitWidth - rightGroup.implicitWidth) < 10
    readonly property bool pillsHovered: pills.hovered
    // On the music's art or waveform: Now Playing opens from there instead
    // of the whole island growing (IslandBar.overPills).
    property int musicHovers: 0
    readonly property bool musicHovered: musicHovers > 0
    // Minimal (Settings → Bar & Island): only what's alive; workspaces, time
    // and status come back while you near the island or press Super+Alt+I.
    // "auto" (default): as always, but a moment that matters (a password, an
    // update, dictation, Shazam) takes the stage and the details step back,
    // like a live activity. Music doesn't: it plays for hours beside them.
    // "minimal": only what's alive, always. Either way, nearing the top edge,
    // hovering or Super+Alt+I brings the details back.
    readonly property bool takeover: ["auth", "update", "vox", "rec", "timer", "shazam", "moment"].indexOf(activity) >= 0
    readonly property bool compact: (Settings.islandRest === "minimal" || Settings.islandTucked || (Settings.islandRest === "auto" && takeover))
                                    && !Island.peek && !bar.near && !bar.hovered
    // The mini notch: compact with nothing alive shows the time, and only
    // the time (plus a privacy dot when one is lit). Anything alive (music,
    // a moment, a password, dictation, a recording) takes its place.
    readonly property bool mini: compact && activity === ""
    readonly property real clockW: compact && !mini ? 0 : clock.width
    readonly property real gaps: mini ? (rightGroup.implicitWidth > 0 ? 12 : 0)
                               : compact ? (leftGroup.implicitWidth > 0 && rightGroup.implicitWidth > 0 ? gap : 0) : gap * 2
    // What the mini notch holds, and the room either side when it's
    // narrower than the notch's minimum: the time sits in the middle.
    readonly property real miniContent: clock.width + (soonText ? soonLabel.implicitWidth + 12 : 0) + rightGroup.implicitWidth + gaps
    readonly property real miniPad: Math.max(0, (56 - miniContent) / 2)
    implicitWidth: mini ? Math.max(56, miniContent)
                 : compact ? Math.max(activity === "moment" ? 220 : 78, leftGroup.implicitWidth + rightGroup.implicitWidth + gaps)
                 : balanced ? side * 2 + clockW + gaps
                            : leftGroup.implicitWidth + rightGroup.implicitWidth + clockW + gaps
    implicitHeight: 32
    readonly property int gap: 22
    // Activities whose value sits beside their icon when the full row shows.
    readonly property bool joined: !compact && ["update", "vox", "auth", "rec", "timer"].indexOf(activity) >= 0
    readonly property string timerLeft: Timers.next ? Timers.clock(Timers.remaining(Timers.next)) : ""
    // The next calendar event within half an hour: the mini notch says so.
    readonly property var soonEvent: {
        const t = bar.now.getTime();
        return Calendar.events.find(e => !e.allDay && e.start > t && e.start - t <= 30 * 60000) || null;
    }
    readonly property string soonText: soonEvent ? soonEvent.title + " · " + Math.max(1, Math.round((soonEvent.start - bar.now.getTime()) / 60000)) + "m" : ""
    function clockOf(secs) { const s = Math.max(0, Math.floor(secs)); return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0"); }
    property real recSecs: 0
    Timer {
        running: rest.activity === "rec"
        interval: 500; repeat: true; triggeredOnStart: true
        onTriggered: rest.recSecs = Date.now() / 1000 - Clipboard.recSince
    }
    readonly property string activityDetail: {
        const line = s => { s = String(s || "").trim(); return s.length > 70 ? s.slice(0, 69) + "…" : s; };
        if (activity === "update") return [Updates.phaseLabel || "Updating", line(Updates.currentLine)].filter(x => x).join(" · ") + " · click for details";
        if (activity === "vox") return Activities.voxListening ? "Dictating · click to finish · right-click to cancel" : "Writing out what you said…";
        if (activity === "auth") return "A password is needed · click to bring it here";
        if (activity === "rec") return "Recording " + (Clipboard.recTarget || "the screen") + " · click to stop";
        if (activity === "timer") return Timers.next.label + " · " + timerLeft + " left" + (Timers.timers.length > 1 ? " · " + (Timers.timers.length - 1) + " more" : "") + " · right-click to cancel";
        if (activity === "shazam") return Activities.shazamFound ? "Found: " + Activities.shazamFound.title + " · click to open" : "Listening for a song…";
        return "";
    }

    // Which live activity, if any.
    readonly property string activity: Island.authPending ? "auth"
        : Moments.now ? "moment"
        : Activities.voxActive ? "vox"
        : Clipboard.recSince > 0 ? "rec"
        : Timers.next ? "timer"
        : Updates.running ? "update"
        : Alerts.active.length ? "alert"
        : (Activities.shazamListening || Activities.shazamFound) ? "shazam"
        : bar.player && bar.player.isPlaying && Settings.restMedia ? "media" : ""

    property real voxSecs: 0
    Timer {
        running: Activities.voxListening
        interval: 250; repeat: true; triggeredOnStart: true
        onTriggered: rest.voxSecs = Math.max(0, (Date.now() - Activities.voxSince) / 1000)
    }

    Row {
      id: leftGroup
      anchors { left: parent.left; verticalCenter: parent.verticalCenter }
      spacing: 10
    // ── Leading ──────────────────────────────────────────────────────────
    // A moment (services/Moments): earbuds connecting, Focus, low battery.
    Row {
        id: momentLead
        visible: rest.activity === "moment"
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        readonly property var m: Moments.now || ({})
        Item {
            visible: !!parent.m.glyph || !!parent.m.image
            width: 22; height: 22
            anchors.verticalCenter: parent.verticalCenter
            // A face is round (Moments' hello); a device's photo isn't cut.
            ClippingRectangle {
                anchors.fill: parent
                radius: momentLead.m.round ? width / 2 : 0
                color: "transparent"
                visible: momentPic.status === Image.Ready
                Image { id: momentPic; anchors.fill: parent; source: momentLead.m.image || ""; sourceSize: Qt.size(44, 44); fillMode: momentLead.m.round ? Image.PreserveAspectCrop : Image.PreserveAspectFit; asynchronous: true; mipmap: true }
            }
            Text { visible: !momentPic.visible; anchors.centerIn: parent; text: parent.parent.m.glyph || ""; font.family: Theme.fontGlyph; font.pixelSize: 17; color: parent.parent.m.kind !== "device" && parent.parent.m.tone ? parent.parent.m.tone : Theme.textPrimary }
        }
        Label {
            visible: !!parent.m.label && parent.m.kind !== "device"
            anchors.verticalCenter: parent.verticalCenter
            text: parent.m.label || ""
            size: 13; weight: Theme.wSemibold
            color: Theme.textPrimary
        }
    }
    // The live activity, as one thing: its icon or ring and, with the full
    // row showing, its value beside it ("◔ 60%"), not split to the far
    // ends with the pills between. Compact, Apple's split returns (icon
    // leading, value trailing). Rest on it: what it's doing, in words.
    Row {
        id: actChip
        visible: rest.activity !== "" && rest.activity !== "moment"
        anchors.verticalCenter: parent.verticalCenter
        spacing: 7
        Item {
            width: 20; height: 20
            anchors.verticalCenter: parent.verticalCenter

            // A password prompt is waiting: a lock (click: bring it here).
            Icon {
                visible: rest.activity === "auth"
                anchors.centerIn: parent
                name: "lock-key"; size: 16
                active: true
                color: Theme.accent
                SequentialAnimation on opacity {
                    running: rest.activity === "auth" && !Theme.reduceMotion
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.55; duration: 700; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
                }
            }
            // Recording the screen: a red dot that breathes (click: stop).
        Rectangle {
            visible: rest.activity === "rec"
            anchors.centerIn: parent
            width: 10; height: 10; radius: 5
            color: Theme.red
            SequentialAnimation on opacity {
                running: rest.activity === "rec" && !Theme.reduceMotion
                loops: Animation.Infinite
                NumberAnimation { to: 0.45; duration: 700; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
            }
        }
        // A timer: a ring that empties as it runs.
        StatRing {
            visible: rest.activity === "timer"
            anchors.centerIn: parent
            size: 18
            stroke: 2.5
            value: Timers.next ? Timers.fraction(Timers.next) : 0
            color: Theme.orange
            text: ""
            label: ""
        }
        // Updating: a ring that fills as it goes (click: the Updates panel).
            StatRing {
                visible: rest.activity === "update"
                anchors.centerIn: parent
                size: 18
                stroke: 2.5
                value: Updates.progress
                color: Theme.accent
                text: ""
                label: ""
            }
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
                MusicTap {}
            }
        }
        Label {
            visible: rest.joined && text !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: rest.activity === "update" ? Math.round(Updates.progress * 100) + "%"
                : rest.activity === "vox" ? (Activities.voxListening ? Math.floor(rest.voxSecs / 60) + ":" + String(Math.floor(rest.voxSecs % 60)).padStart(2, "0") : "Writing")
                : rest.activity === "auth" ? "Password"
                : rest.activity === "rec" ? rest.clockOf(rest.recSecs)
                : rest.activity === "timer" ? rest.timerLeft : ""
            size: 13; weight: Theme.wSemibold; rounded: true
            color: Theme.textPrimary
            font.features: ({ "tnum": 1 })
        }
        HoverHandler { id: actHover }
        Tip { text: rest.activityDetail; shown: actHover.hovered; below: true }
    }

    Capsules { id: pills; bar: rest.bar; tips: false; visible: Settings.restWorkspaces && !rest.compact; anchors.verticalCenter: parent.verticalCenter }
    }

    // ── The time, centred ────────────────────────────────────────────────
    // Hovering a pill, the clock steps aside for what that pill is: its
    // number and the apps open there (in the clock's own room, so the island
    // doesn't resize and slide the pills out from under the pointer).
    readonly property var hint: pills.hint
    property var shownHint: null
    onHintChanged: { if (hint) { shownHint = hint; hintOut.stop(); } else hintOut.restart(); }
    Timer { id: hintOut; interval: 120; onTriggered: rest.shownHint = null }   // no flicker gliding pill to pill
    readonly property real hintOn: shownHint && !compact ? 1 : 0
    Item {
        id: hintBox
        visible: opacity > 0.01
        opacity: rest.hintOn
        Behavior on opacity { NumberAnimation { duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
        x: clock.x + clock.width / 2 - width / 2
        anchors.verticalCenter: parent.verticalCenter
        width: hintRow.implicitWidth
        height: 20
        readonly property var apps: rest.shownHint ? pills.entries(rest.shownHint.id) : []
        Row {
            id: hintRow
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            // Another screen's: a small mark of which one.
            Text {
                visible: !!rest.shownHint && rest.shownHint.screen !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: rest.shownHint && rest.shownHint.screen === "Laptop" ? "\u{f0322}" : "\u{f0379}"
                font.family: Theme.fontGlyph; font.pixelSize: 13
                color: Theme.textTertiary
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: rest.shownHint ? pills.num(rest.shownHint.id) : ""
                size: 15; weight: Theme.wSemibold; rounded: true
                color: Theme.accent
                font.features: ({ "tnum": 1 })
            }
            Repeater {
                model: hintBox.apps.slice(0, 2)
                Item {
                    required property var modelData
                    width: 16; height: 16
                    anchors.verticalCenter: parent.verticalCenter
                    readonly property string path: Quickshell.iconPath(modelData.icon, true)
                    IconImage { anchors.fill: parent; visible: parent.path !== ""; source: parent.path; asynchronous: true }
                    Text { visible: parent.path === ""; anchors.centerIn: parent; text: "\u{f05b5}"; font.family: Theme.fontGlyph; font.pixelSize: 13; color: Theme.textSecondary }
                }
            }
            Label {
                visible: hintBox.apps.length > 2 || hintBox.apps.length === 0
                anchors.verticalCenter: parent.verticalCenter
                text: hintBox.apps.length ? "+" + (hintBox.apps.length - 2) : "empty"
                size: 13; weight: Theme.wMedium
                color: Theme.textTertiary
            }
        }
    }

    IslandClock {
        id: clock
        visible: !rest.compact || rest.mini
        opacity: 1 - rest.hintOn
        Behavior on opacity { NumberAnimation { duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
        now: rest.bar.now; size: 15
        rounded: false
        weight: Theme.wMedium
        color: Qt.rgba(1, 0.98, 0.95, 0.92)
        x: rest.mini ? rest.miniPad : (rest.balanced ? rest.side : leftGroup.implicitWidth) + rest.gap
        anchors.verticalCenter: parent.verticalCenter
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: Island.toggle("calendar", rest.bar.screenName, "pointer", "island") }
    }
    // Mini notch, an event soon: "19:35 · Standup · 25m".
    Label {
        id: soonLabel
        visible: rest.mini && rest.soonText !== ""
        x: clock.x + clock.width + 12
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, 220)
        elide: Text.ElideRight
        text: rest.soonText
        size: 13; weight: Theme.wMedium
        color: Theme.textSecondary
    }

    Row {
      id: rightGroup
      anchors { right: parent.right; verticalCenter: parent.verticalCenter }
      spacing: 10
    Row {
        visible: Settings.restStatus
        spacing: 7
        anchors.verticalCenter: parent.verticalCenter
        // Something you missed that wants you (Notifs.missed): a white dot,
        // red if urgent. Hover the island's bell for them.
        Rectangle {
            visible: Notifs.missed.length > 0
            anchors.verticalCenter: parent.verticalCenter
            width: 6; height: 6; radius: 3
            color: Notifs.missed.some(i => i.severity === "critical") ? Theme.critical : Theme.textPrimary
            HoverHandler { id: missedHover; margin: 6 }
            Tip {
                text: Notifs.missed.length === 1 ? "You missed: " + (Notifs.missed[0].title || Notifs.missed[0].app)
                    : Notifs.missed.length + " you missed · " + Notifs.missed.slice(0, 2).map(i => i.title || i.app).join(", ")
                shown: missedHover.hovered; below: true
            }
        }
        Rectangle {
            visible: Activities.micInUse
            anchors.verticalCenter: parent.verticalCenter
            width: 6; height: 6; radius: 3
            color: Theme.orange
            HoverHandler { id: micHover; margin: 6 }
            Tip { text: "Microphone in use" + (Activities.micUsers.length ? " · " + [...new Set(Activities.micUsers)].join(", ") : ""); shown: micHover.hovered; below: true }
        }
        // Agents at work (kittymux): the first one's mark, and how many.
        // Click: the Agents tab. One needs you: a moment says so.
        Row {
            visible: Kittymux.working.length > 0
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3
            Image {
                id: agentMark
                anchors.verticalCenter: parent.verticalCenter
                width: 13; height: 13
                sourceSize: Qt.size(26, 26)
                source: Kittymux.working.length ? Kittymux.brand(Kittymux.working[0].agent) : ""
                visible: status === Image.Ready
            }
            Text {
                visible: !agentMark.visible
                anchors.verticalCenter: parent.verticalCenter
                text: "\u{f06a9}"; font.family: Theme.fontGlyph; font.pixelSize: 13
                color: Theme.textSecondary
            }
            Label {
                visible: Kittymux.working.length > 1
                anchors.verticalCenter: parent.verticalCenter
                text: Kittymux.working.length
                size: 11; weight: Theme.wSemibold; rounded: true
                color: Theme.textSecondary
            }
            HoverHandler { id: agentHover; margin: 6; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: Notifs.toggleCenter("agents", "pointer", rest.bar.screenName) }
            Tip { text: Kittymux.working.map(w => w.agent + " · " + w.title).join("  |  ") + " · working"; shown: agentHover.hovered; below: true }
        }
        // The camera is on: a green dot (Apple's), with who has it.
        Rectangle {
            visible: Activities.camInUse
            anchors.verticalCenter: parent.verticalCenter
            width: 6; height: 6; radius: 3
            color: Theme.green
            HoverHandler { id: camHover; margin: 6 }
            Tip { text: "Camera in use" + (Activities.camUsers.length ? " · " + Activities.camUsers.join(", ") : ""); shown: camHover.hovered; below: true }
        }
        IslandStatus { visible: !rest.compact; anchors.verticalCenter: parent.verticalCenter; bar: rest.bar }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: Notifs.toggleCenter("controls", "pointer", rest.bar.screenName) }
    }

    // ── Trailing ─────────────────────────────────────────────────────────
    // The moment's state: a battery ring, or "On", or "20 %" with a battery.
    Row {
        visible: rest.activity === "moment"
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6
        readonly property var m: Moments.now || ({})
        Label {
            visible: parent.m.ring === undefined || parent.m.ring < 0 || parent.m.kind !== "device"
            anchors.verticalCenter: parent.verticalCenter
            text: parent.m.value || ""
            size: 13; weight: Theme.wSemibold; rounded: true
            color: parent.m.tone || Theme.textPrimary
            font.features: ({ "tnum": 1 })
        }
        StatRing {
            visible: parent.m.kind === "device" && parent.m.ring >= 0
            anchors.verticalCenter: parent.verticalCenter
            size: 20; stroke: 2.5
            value: Math.max(0, parent.m.ring || 0)
            color: parent.m.tone || Theme.green
            text: ""; label: ""
        }
        // Low battery: the battery itself, nearly empty, in red.
        Item {
            visible: parent.m.kind === "battery"
            anchors.verticalCenter: parent.verticalCenter
            width: 26; height: 12
            Rectangle { anchors.fill: parent; anchors.rightMargin: 2; radius: 3.5; color: Qt.alpha(Theme.red, 0.25) }
            Rectangle { height: parent.height; radius: 3.5; width: Math.max(5, (parent.width - 2) * 0.2); color: Theme.red }
            Rectangle { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: 2; height: 5; radius: 1; color: Qt.alpha(Theme.red, 0.5) }
        }
    }
    Item {
        visible: rest.activity !== "" && rest.activity !== "alert" && rest.activity !== "moment" && !rest.joined
        width: trailing.implicitWidth
        height: 20
        anchors.verticalCenter: parent.verticalCenter
        Row {
            id: trailing
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            Label {
                visible: rest.activity === "timer"
                anchors.verticalCenter: parent.verticalCenter
                text: rest.timerLeft
                size: 13; weight: Theme.wSemibold; rounded: true
                color: Theme.orange
                font.features: ({ "tnum": 1 })
            }
            Label {
                visible: rest.activity === "rec"
                anchors.verticalCenter: parent.verticalCenter
                text: rest.clockOf(rest.recSecs)
                size: 13; weight: Theme.wSemibold; rounded: true
                color: Theme.red
                font.features: ({ "tnum": 1 })
            }
            Label {
                visible: rest.activity === "vox"
                anchors.verticalCenter: parent.verticalCenter
                text: Activities.voxListening ? Math.floor(rest.voxSecs / 60) + ":" + String(Math.floor(rest.voxSecs % 60)).padStart(2, "0") : "Writing"
                size: 13; weight: Theme.wSemibold; rounded: true
                color: Activities.voxListening ? Theme.red : Theme.textSecondary
                font.features: ({ "tnum": 1 })
            }
            Label {
                visible: rest.activity === "auth"
                anchors.verticalCenter: parent.verticalCenter
                // No words: the pulsing lock says it; on the other screen a
                // small arrow says "click to bring it here".
                text: Island.authScreen === rest.bar.screenName ? "" : "\u{f0045}"
                font.family: Theme.fontGlyph
                size: 12; weight: Theme.wSemibold
                color: Theme.accent
            }
            Label {
                visible: rest.activity === "update"
                anchors.verticalCenter: parent.verticalCenter
                text: Math.round(Updates.progress * 100) + "%"
                size: 13; weight: Theme.wSemibold; rounded: true
                color: Theme.accent
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
            // Music: a live waveform in the album art's colour (Apple's
            // compact music activity), moving with what you hear; still while paused.
            Item {
                visible: rest.activity === "media"
                anchors.verticalCenter: parent.verticalCenter
                width: musicBars.implicitWidth; height: 16
                MusicTap {}
                PwObjectTracker { objects: [Pipewire.defaultAudioSink] }
                PwNodePeakMonitor { id: restPeak; node: Pipewire.defaultAudioSink; enabled: rest.activity === "media" && Media.playing }
                readonly property real level: restPeak.enabled ? (restPeak.peaks && restPeak.peaks.length ? Math.max(...restPeak.peaks) : (restPeak.peak || 0)) : 0
                Row {
                    id: musicBars
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Repeater {
                        model: 5
                        Rectangle {
                            required property int index
                            readonly property real shape: [0.5, 0.85, 1, 0.75, 0.55][index]
                            property real jitter: 1
                            anchors.verticalCenter: parent.verticalCenter
                            width: 3; radius: 1.5
                            height: Math.max(3, 15 * Math.min(1, parent.parent.level * shape * jitter * 1.9))
                            color: Media.artColor
                            Behavior on height { NumberAnimation { duration: 90 } }
                            Behavior on color { ColorAnimation { duration: 400 } }
                            Timer { running: restPeak.enabled && !Theme.reduceMotion; interval: 120 + (index % 3) * 45; repeat: true; onTriggered: parent.jitter = 0.7 + Math.random() * 0.5 }
                        }
                    }
                }
            }
        }
    }

    }

    // A click on an activity acts on it: stop dictation, open the song.
    // (Music: its art and waveform open Now Playing; see musicTap.)
    TapHandler {
        enabled: rest.activity === "auth" || rest.activity === "vox" || rest.activity === "update" || rest.activity === "rec" || rest.activity === "timer" || (rest.activity === "shazam" && !!Activities.shazamFound)
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onTapped: (point, button) => {
            if (rest.activity === "auth") { Island.summonAuth(rest.bar.screenName); return; }
            if (rest.activity === "update") { Island.open("updates", rest.bar.screenName, "pointer", "island"); return; }
            if (rest.activity === "rec") { Clipboard.recordKey(); return; }
            if (rest.activity === "timer") { if (button === Qt.RightButton && Timers.next) Timers.cancel(Timers.next.id); return; }
            if (rest.activity === "vox") { if (button === Qt.RightButton) Activities.voxCancel(); else Activities.voxToggle(); }
            else Activities.shazamOpen();
        }
    }

    // Music's art and waveform. Rest on it: Now Playing opens, and folds
    // away when you leave the island. Click: it stays (pinned). Ctrl+click:
    // go to the player. Right-click: play / pause.
    component MusicTap: MouseArea {
        anchors.fill: parent
        anchors.margins: -4
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onContainsMouseChanged: { rest.musicHovers += containsMouse ? 1 : -1; if (containsMouse) peek.restart(); else peek.stop(); }
        Component.onDestruction: if (containsMouse) rest.musicHovers = Math.max(0, rest.musicHovers - 1)
        Timer { id: peek; interval: Settings.hoverDelay; onTriggered: if (Island.panel === "") Island.preview("media", rest.bar.screenName) }
        onClicked: mouse => {
            peek.stop();
            if (mouse.button === Qt.RightButton) { if (Media.active) Media.active.togglePlaying(); }
            else if (mouse.modifiers & Qt.ControlModifier) { Island.close(); Media.goTo(); }
            else Island.open("media", rest.bar.screenName, "pointer", "island");
        }
    }
}
