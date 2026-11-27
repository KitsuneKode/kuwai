// Goodbye, before the machine sleeps, restarts or shuts down (the login
// screen's power buttons, the island's power menu): the screen goes quiet,
// a mark for what's happening draws itself in the middle, and a line says
// so in words, then it all goes to black. `kind` is "suspend", "reboot",
// "poweroff" or "logout"; empty is nothing. `done` fires when it's black,
// which is when the command should run.
//
//   Restarting          Shutting Down        Sleeping             Logging Out
//   See you in a moment Good night, Kit      Sweet dreams         See you soon, Kit
//
// The marks, all drawn as Shapes: a circular arrow that spins up, the power symbol drawing
// itself and powering down, a moon breathing, a door closing. Reduced
// motion: fades only.
import QtQuick
import QtQuick.Shapes
import qs.config
import qs.components

Item {
    id: bye
    property string kind: ""
    property string name: ""
    signal done()

    readonly property real move: Theme.reduceMotion ? 0 : 1
    readonly property int hour: new Date().getHours()
    readonly property bool late: hour >= 21 || hour < 5
    readonly property var copy: ({
        reboot: { title: "Restarting", line: "See you in a moment" },
        poweroff: { title: "Shutting Down", line: (late ? "Good night" : "Goodbye") + (name ? ", " + name : "") },
        suspend: { title: "Sleeping", line: late ? "Sweet dreams" : "Back when you are" },
        logout: { title: "Logging Out", line: "See you soon" + (name ? ", " + name : "") }
    })
    readonly property var c: copy[kind] || ({ title: "", line: "" })

    // in: the screen dims and the mark draws; mark: the mark's own motion;
    // out: everything to black.
    property real tIn: 0
    property real tMark: 0
    property real tOut: 0
    visible: kind !== "" || tIn > 0
    Component.onCompleted: if (kind) play.restart()
    onKindChanged: {
        if (kind) { tIn = tMark = tOut = 0; play.restart(); }
        else { play.stop(); back.restart(); }
    }
    SequentialAnimation {
        id: play
        NumberAnimation { target: bye; property: "tIn"; to: 1; duration: Theme.pulseMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
        NumberAnimation { target: bye; property: "tMark"; to: 1; duration: Theme.farewellMarkMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeInOut }
        PauseAnimation { duration: Theme.farewellHoldMs }
        // Into black: gathers pace, then lands softly (ease-in would hit black at full speed).
        NumberAnimation { target: bye; property: "tOut"; to: 1; duration: Theme.farewellOutMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeInOut }
        ScriptAction { script: bye.done() }
    }
    // Back from sleep: the screen returns without a show.
    NumberAnimation { id: back; target: bye; properties: "tIn,tMark,tOut"; to: 0; duration: Theme.settleMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }

    // The room going dark.
    Rectangle { anchors.fill: parent; color: "black"; opacity: Math.max(bye.tIn * 0.82, bye.tOut); visible: Theme.reduceMotion }
    ShaderEffect {
        anchors.fill: parent
        visible: !Theme.reduceMotion && (bye.kind !== "" || bye.tIn > 0)
        property color accent: Theme.accent
        property color coolTint: Theme.indigo
        property vector2d size: Qt.vector2d(width, height)
        property vector2d center: Qt.vector2d(width / 2, height / 2 - Theme.sp(30))
        property real mode: ({ poweroff: 0, reboot: 1, suspend: 2, logout: 3 })[bye.kind] ?? 0
        property real tIn: bye.tIn
        property real tMark: bye.tMark
        property real tOut: bye.tOut
        fragmentShader: Qt.resolvedUrl("../../shaders/farewell.frag.qsb")
    }
    MouseArea { anchors.fill: parent; enabled: bye.kind !== ""; hoverEnabled: true }

    Column {
        anchors.centerIn: parent
        spacing: 22
        opacity: bye.tIn * (1 - bye.tOut)
        transform: Translate { y: (1 - bye.tIn) * 14 * bye.move - bye.tOut * 6 * bye.move }

        Item {
            id: mark
            anchors.horizontalCenter: parent.horizontalCenter
            width: 64; height: 64
            readonly property color ink: Qt.rgba(1, 1, 1, 0.92)
            readonly property real r: 27

            // Restart: an arrow round a circle, drawing itself, then turning.
            Item {
                id: turn
                anchors.fill: parent
                visible: bye.kind === "reboot"
                rotation: bye.tMark * 540 * bye.move
                readonly property real sweep: 60 + 240 * bye.tIn
                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeColor: mark.ink; strokeWidth: 4; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                        PathAngleArc { centerX: 32; centerY: 32; radiusX: mark.r; radiusY: mark.r; startAngle: -90; sweepAngle: turn.sweep }
                    }
                }
                // The head rides the arc's end.
                Shape {
                    anchors.fill: parent
                    rotation: turn.sweep
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeColor: mark.ink; strokeWidth: 4; fillColor: "transparent"
                        capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                        startX: 26; startY: 32 - mark.r - 7
                        PathLine { x: 33; y: 32 - mark.r }
                        PathLine { x: 26; y: 32 - mark.r + 7 }
                    }
                }
            }

            // Shut down: the power symbol draws itself, then powers down:
            // dimming and settling, as a screen does going off.
            Shape {
                anchors.fill: parent
                visible: bye.kind === "poweroff"
                preferredRendererType: Shape.CurveRenderer
                opacity: 1 - 0.6 * bye.tMark
                scale: 1 - 0.1 * bye.tMark * bye.move
                ShapePath {
                    strokeColor: mark.ink; strokeWidth: 4; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                    PathAngleArc { centerX: 32; centerY: 32; radiusX: mark.r; radiusY: mark.r; startAngle: -60; sweepAngle: 300 * bye.tIn }
                }
                ShapePath {
                    strokeColor: mark.ink; strokeWidth: 4; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                    startX: 32; startY: 4
                    PathLine { x: 32; y: 4 + 24 * bye.tIn }
                }
            }

            // Sleep: a crescent, breathing.
            Shape {
                anchors.fill: parent
                visible: bye.kind === "suspend"
                preferredRendererType: Shape.CurveRenderer
                rotation: -20
                scale: 0.9 + 0.1 * bye.tIn - 0.06 * Math.sin(bye.tMark * Math.PI) * bye.move
                opacity: 1 - 0.35 * Math.sin(bye.tMark * Math.PI)
                ShapePath {
                    strokeWidth: 0; fillColor: mark.ink
                    startX: 42; startY: 12
                    PathArc { x: 42; y: 52; radiusX: 24; radiusY: 24; useLargeArc: true; direction: PathArc.Counterclockwise }
                    PathArc { x: 42; y: 12; radiusX: 20; radiusY: 20; direction: PathArc.Clockwise }
                }
            }

            // Log out: the door, swinging shut.
            Shape {
                id: door
                anchors.fill: parent
                visible: bye.kind === "logout"
                preferredRendererType: Shape.CurveRenderer
                readonly property real shut: bye.move > 0 ? bye.tMark : 1
                readonly property real leaf: 12 + 22 * shut
                readonly property real skew: 9 * (1 - shut)
                ShapePath {
                    strokeColor: mark.ink; strokeWidth: 4; fillColor: "transparent"; capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                    startX: 12; startY: 58
                    PathLine { x: 12; y: 6 }
                    PathLine { x: 52; y: 6 }
                    PathLine { x: 52; y: 58 }
                }
                ShapePath {
                    strokeWidth: 0; fillColor: mark.ink
                    startX: 12; startY: 6
                    PathLine { x: 12 + door.leaf; y: 6 + door.skew }
                    PathLine { x: 12 + door.leaf; y: 58 - door.skew }
                    PathLine { x: 12; y: 58 }
                }
                ShapePath {
                    strokeWidth: 0; fillColor: Qt.rgba(0, 0, 0, 0.55 * door.shut)
                    startX: 12 + door.leaf - 9; startY: 29
                    PathAngleArc { centerX: 12 + door.leaf - 9; centerY: 32; radiusX: 3; radiusY: 3; startAngle: -90; sweepAngle: 360 }
                }
            }
        }

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 6
            opacity: Math.min(1, Math.max(0, (bye.tIn - 0.25) / 0.75))
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: bye.c.title
                size: Theme.tFarewellTitle; weight: Theme.wSemibold
                color: "white"
            }
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: bye.c.line
                size: Theme.tLockBody
                color: Qt.rgba(1, 1, 1, 0.66)
            }
        }
    }
}
