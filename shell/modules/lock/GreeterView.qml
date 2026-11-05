// What the login screen shows (greeter.qml). Everything on one axis, as the
// Mac's login has it: the date, the big clock and a greeting at the top
// centre (where the lock screen puts its clock), you at the bottom centre
// (your picture, your name, "Press any key to log in"), and under you a
// quiet row of sleep / restart / shut down, each held to act (HoldButton),
// then a goodbye (Farewell). The status sits in the top-right corner
// (LockCorner). The picture is sharp at rest: it's art. The first key or
// click focuses it, in place: the picture blurs and dims, the clock steps
// back, your picture grows and the password pill takes the hint's place.
// Left empty for 20 s, or on Esc, it settles back.
//
// Motion: once per boot the picture comes up out of black and the rest
// rises in a short stagger. Logging in, your picture opens into your
// desktop's wallpaper with a welcome over it, which is where the session
// starts. A wrong password shakes the pill and flashes the ring around your
// picture red. Reduced motion keeps only the fades.
//
// `lock` carries the state (greeter.qml): password, checking, error,
// failures, leaving, farewell, submit(), name, face, wallpaper, desktopWall,
// accent, power(action), powered().
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import qs.config
import qs.components

Item {
    id: view
    required property var lock
    property bool preview: false

    readonly property color accent: view.lock.accent || Theme.accent
    readonly property color tint: Qt.tint(Qt.rgba(1, 1, 1, 0.92), Qt.alpha(accent, 0.22))
    readonly property real move: Theme.reduceMotion ? 0 : 1
    property date now: new Date()
    Timer { interval: 1000; running: true; repeat: true; onTriggered: view.now = new Date() }
    readonly property int hour: now.getHours()
    readonly property string greeting: hour < 5 ? "Up late" : hour < 12 ? "Good morning" : hour < 17 ? "Good afternoon" : "Good evening"

    // ── Rest ⇄ asking ────────────────────────────────────────────────────
    property bool asking: false
    function ask() { asking = true; settle.restart(); entry.focusField(); }
    Timer { id: settle; interval: 20000; onTriggered: if (view.lock.password === "" && !view.lock.checking) view.asking = false }
    Connections {
        target: view.lock
        function onPasswordChanged() { if (view.lock.password !== "") { view.asking = true; settle.restart(); } }
        function onErrorChanged() { if (view.lock.error !== "") view.asking = true; }
    }
    // One critically damped spring for every shared move, so the clock and
    // you travel as one gesture; `fp` is where things are (snaps under
    // reduced motion), `f` how visible.
    Spring { id: focusSpring; tier: Theme.springSlow; target: view.asking || view.lock.checking ? 1 : 0 }
    readonly property real f: Math.max(0, Math.min(1, focusSpring.value))
    readonly property real fp: move ? focusSpring.value : (asking ? 1 : 0)
    function mix(a, b, t) { return a + (b - a) * t; }

    // ── Choreography ─────────────────────────────────────────────────────
    property real tWall: 0
    property real tClock: 0
    property real tHint: 0
    property real tPower: 0
    property real tCorner: 0
    property real leave: 0

    component Step: SequentialAnimation {
        id: step
        property alias target: anim.target
        property alias property: anim.property
        property int delay: 0
        property int duration: 420
        PauseAnimation { duration: step.delay }
        NumberAnimation {
            id: anim
            to: 1
            duration: step.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.easeOut
        }
    }
    ParallelAnimation {
        id: intro
        Step { target: view; property: "tWall"; duration: 1400 }
        Step { target: view; property: "tClock"; delay: 260; duration: 560 }
        Step { target: view; property: "tHint"; delay: 520 }
        Step { target: view; property: "tPower"; delay: 600 }
        Step { target: view; property: "tCorner"; delay: 660; duration: 520 }
    }
    NumberAnimation {
        id: outro
        target: view; property: "leave"; to: 1
        duration: 380
        easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut
    }
    Component.onCompleted: {
        if (preview) { tWall = tClock = tHint = tPower = tCorner = 1; }
        else intro.start();
        if (view.lock.password !== "" || view.lock.error !== "" || view.lock.checking) {
            asking = true;
            if (preview) focusSpring.settle();
        }
        entry.focusField();
    }
    // A goodbye quiets everything under it.
    function shown(t) { return t * (1 - leave) * (1 - bye.tIn); }
    function lift(t) { return ((1 - t) * 12 - leave * 10) * move; }

    // ── The picture ──────────────────────────────────────────────────────
    // Sharp at rest; asking, a blurred copy fades in over it and it all
    // recedes a touch, so what you type into comes forward.
    Item {
        id: picture
        anchors.fill: parent
        opacity: view.tWall
        scale: 1 + (0.04 * (1 - view.tWall) + 0.03 * view.fp + 0.05 * view.leave) * view.move
        Image {
            id: wall
            anchors.fill: parent
            source: view.lock.wallpaper ? "file://" + view.lock.wallpaper : ""
            sourceSize: Qt.size(1920, 1080)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }
        Item {
            anchors.fill: parent
            visible: view.f > 0.01
            opacity: view.f
            layer.enabled: true
            Image {
                id: wallSmall
                anchors.fill: parent
                source: wall.source
                sourceSize: Qt.size(640, 360)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: false
            }
            MultiEffect { anchors.fill: parent; source: wallSmall; blurEnabled: true; blur: 1; blurMax: 64; saturation: 0.2 }
        }
        // Shade where the words sit: the clock at the top, you at the
        // bottom; all of it, a touch, when asking.
        Rectangle {
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: parent.height * 0.42
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.42) }
                GradientStop { position: 1; color: "transparent" }
            }
        }
        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: parent.height * 0.45
            gradient: Gradient {
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.55) }
            }
        }
        Rectangle { anchors.fill: parent; color: Qt.rgba(0.03, 0.02, 0.03, 0.38 * view.f) }
    }

    // ── The clock, top centre (where the lock screen has it) ─────────────
    // Asking, it only steps back a little: nothing travels across the screen.
    Column {
        id: clock
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(view.height * 0.075)
        transformOrigin: Item.Top
        scale: view.mix(1, 0.9, view.fp)
        opacity: view.shown(view.tClock) * view.mix(1, 0.85, view.f)
        transform: Translate { y: view.lift(view.tClock) }
        spacing: 0
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDate(view.now, "dddd, MMMM d")
            size: 24; weight: Theme.wSemibold
            color: Qt.alpha(view.tint, 0.88)
        }
        TextMorph {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Settings.clock24 ? Qt.formatTime(view.now, "HH:mm") : Qt.formatTime(view.now, "h:mm")
            size: 150; weight: Theme.wBold; rounded: true
            color: view.tint
            duration: 700; stagger: 60
        }
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: view.greeting
            size: 20; weight: Theme.wMedium
            color: Qt.alpha(view.tint, 0.72)
            opacity: 1 - view.f
        }
    }

    // ── You, bottom centre: always there; asking, the pill takes the hint's place
    Column {
        id: you
        anchors { horizontalCenter: parent.horizontalCenter; bottom: power.top; bottomMargin: Math.round(view.height * 0.05) }
        spacing: 0
        opacity: view.shown(view.tHint)
        transform: Translate { y: view.lift(view.tHint) }

        Item {
            id: avatar
            anchors.horizontalCenter: parent.horizontalCenter
            width: 96; height: 96
            transformOrigin: Item.Bottom
            scale: view.mix(0.72, 1, view.fp)
            // The ring: the accent while greetd checks, breathing; a wrong
            // password flashes it red once.
            property real miss: 0
            SequentialAnimation {
                id: missFlash
                NumberAnimation { target: avatar; property: "miss"; to: 1; duration: 90; easing.type: Easing.OutQuad }
                NumberAnimation { target: avatar; property: "miss"; to: 0; duration: 900; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
            }
            Connections { target: view.lock; function onFailuresChanged() { missFlash.restart(); } }
            Rectangle {
                anchors.centerIn: parent
                width: parent.width + avatar.miss * 8 * view.move; height: width
                radius: width / 2
                color: "transparent"
                border.width: 2 + avatar.miss
                border.color: Qt.tint(view.lock.checking ? view.accent : Qt.rgba(1, 1, 1, 0.22), Qt.alpha(Theme.red, avatar.miss))
                Behavior on border.color { enabled: avatar.miss === 0; ColorAnimation { duration: Theme.colorMs } }
                SequentialAnimation on opacity {
                    running: view.lock.checking && !Theme.reduceMotion
                    loops: Animation.Infinite
                    onRunningChanged: if (!running) parent.opacity = 1
                    NumberAnimation { to: 0.35; duration: 520; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1; duration: 520; easing.type: Easing.InOutSine }
                }
            }
            ClippingRectangle {
                anchors.centerIn: parent
                width: 88; height: 88; radius: 44
                color: Qt.alpha(view.accent, 0.5)
                Label {
                    anchors.centerIn: parent
                    visible: face.status !== Image.Ready
                    text: view.lock.name.charAt(0).toUpperCase()
                    size: 36; weight: Theme.wSemibold
                    color: "white"
                }
                Image {
                    id: face
                    anchors.fill: parent
                    source: view.lock.face ? "file://" + view.lock.face : ""
                    sourceSize: Qt.size(176, 176)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
            }
        }
        Item { width: 1; height: 12 }
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: view.lock.name
            size: 21; weight: Theme.wSemibold
            color: "white"
        }
        Item { width: 1; height: 16 }
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            // Room for the pill and its line (Caps Lock, a wrong password)
            // underneath, so either showing moves nothing.
            width: 320; height: 42 + 34
            Label {
                anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: Math.round((42 - height) / 2) }
                opacity: Math.max(0, 1 - view.f * 2.5)
                visible: opacity > 0.01
                text: "Press any key to log in"
                size: 15; weight: Theme.wMedium
                color: Qt.alpha(view.tint, 0.78)
            }
            PasswordPill {
                id: entry
                anchors { horizontalCenter: parent.horizontalCenter; top: parent.top }
                opacity: view.f
                scale: 0.96 + 0.04 * Math.min(1, view.fp)
                lock: view.lock
                preview: view.preview
                accent: view.accent
                onActivity: view.ask()
                onDismissed: view.asking = false
            }
        }
    }

    // ── Sleep, restart, shut down: held, a quiet row under you ───────────
    Row {
        id: power
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: Math.round(parent.height * 0.035) }
        spacing: 30
        opacity: view.shown(view.tPower) * view.mix(0.75, 1, view.f)
        transform: Translate { y: view.lift(view.tPower) }
        HoldButton { glyph: "\u{f04b2}"; label: "Sleep"; verb: "sleep"; accent: view.accent; onFired: view.lock.power("suspend") }
        HoldButton { glyph: "\u{f0709}"; label: "Restart"; verb: "restart"; accent: view.accent; onFired: view.lock.power("reboot") }
        HoldButton { glyph: "\u{f0425}"; label: "Shut Down"; verb: "shut down"; accent: view.accent; onFired: view.lock.power("poweroff") }
    }

    LockCorner { shown: view.shown(view.tCorner) }

    // A click anywhere asks (and puts the keyboard back in the field).
    TapHandler { onTapped: view.ask() }

    // ── Logging in: your picture opens into your desktop ─────────────────
    property real tReveal: 0
    property point revealAt: Qt.point(width / 2, height / 2)
    readonly property real revealMax: Math.hypot(Math.max(revealAt.x, width - revealAt.x), Math.max(revealAt.y, height - revealAt.y))
    SequentialAnimation {
        id: reveal
        NumberAnimation {
            target: view; property: "tReveal"; to: 1
            duration: 720
            easing.type: Easing.BezierSpline; easing.bezierCurve: [0.32, 0.72, 0, 1, 1, 1]
        }
    }
    Connections {
        target: view.lock
        function onLeavingChanged() {
            if (!view.lock.leaving) return;
            view.revealAt = avatar.mapToItem(view, avatar.width / 2, avatar.height / 2);
            outro.start();
            if (desk.status === Image.Ready) reveal.start();
        }
    }
    Rectangle { anchors.fill: parent; color: "black"; opacity: desk.status === Image.Ready ? 0 : view.leave }
    ClippingRectangle {
        id: hole
        readonly property real r: 44 + (view.revealMax - 44) * view.tReveal
        visible: view.tReveal > 0
        x: view.revealAt.x - r; y: view.revealAt.y - r
        width: 2 * r; height: 2 * r; radius: r
        color: "black"
        Image {
            id: desk
            x: -hole.x; y: -hole.y
            width: view.width; height: view.height
            scale: 1 + 0.08 * (1 - view.tReveal) * view.move
            source: view.lock.desktopWall ? "file://" + view.lock.desktopWall : ""
            sourceSize: Qt.size(view.width, view.height)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }
        Image {
            anchors.centerIn: parent
            width: 88; height: 88
            opacity: 1 - Math.min(1, view.tReveal * 4)
            source: face.source
            sourceSize: Qt.size(176, 176)
            fillMode: Image.PreserveAspectCrop
        }
    }
    // The welcome, over your wallpaper as it opens.
    Column {
        anchors.centerIn: parent
        spacing: 6
        opacity: Math.max(0, Math.min(1, (view.tReveal - 0.35) / 0.4))
        visible: opacity > 0
        transform: Translate { y: (1 - Math.min(1, view.tReveal)) * 10 * view.move }
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Welcome back"
            size: 34; weight: Theme.wSemibold
            color: "white"
            layer.enabled: true
            layer.effect: MultiEffect { shadowEnabled: true; shadowBlur: 0.8; shadowOpacity: 0.5 }
        }
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: view.lock.name
            size: 18; weight: Theme.wMedium
            color: Qt.rgba(1, 1, 1, 0.8)
            layer.enabled: true
            layer.effect: MultiEffect { shadowEnabled: true; shadowBlur: 0.8; shadowOpacity: 0.5 }
        }
    }

    // ── Goodbye ──────────────────────────────────────────────────────────
    Farewell {
        id: bye
        anchors.fill: parent
        kind: view.lock.farewell || ""
        name: view.lock.name
        onDone: view.lock.powered()
    }

    // Volume and brightness keys: their HUD (the session's own is under the lock).
    LockOsd {
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 72 }
        z: 50
    }
}
