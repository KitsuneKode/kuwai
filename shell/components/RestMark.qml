// A mark on the resting notch: a glyph (or an app's icon) and its value,
// bare on the black, like Apple's compact live activities. No capsule at rest:
// a capsule inside the notch's capsule read as boxes in a box, and only some
// marks had one. Hovering draws the surface (it is clickable); colour only
// for state (a warning, something waiting), never to decorate a count.
//
//   RestMark { glyph: "\u{f06b0}"; value: "4"; tip: "…"; onClicked: … }
//   RestMark { wordmark: "T3"; value: "3 active"; previews: true; onPreviewRequested: … }
// previews: resting on the mark (Settings.hoverDelay) asks for its panel
// (previewRequested); the owner opens it with Island.preview.
//   RestMark { icon: Quickshell.iconPath("t3code"); value: "3"; tone: Theme.orange }
//   RestMark { glyph: "…"; value: "15h"; ring: "solid" }   a solid ring widens to fit its value
import QtQuick
import Quickshell.Widgets
import qs.config

Item {
    id: mark
    property string glyph: ""
    property string icon: ""
    property string wordmark: ""         // a product's name as its mark ("T3")
    property bool previews: false        // rest on it: previewRequested() (its panel)
    // The count in a ring (live work): "spin" while it works, "solid" when it
    // needs you, "" for a plain count.
    property string ring: ""
    property string value: ""
    property color tone: Theme.textSecondary
    property string tip: ""
    readonly property alias hovered: area.containsMouse
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: tip || (wordmark + " " + value).trim() || "Open details"
    Accessible.onPressAction: mark.clicked()
    Keys.onReturnPressed: mark.clicked()
    Keys.onSpacePressed: mark.clicked()
    FocusRing { cornerRadius: Theme.r2 }
    signal clicked()
    signal previewRequested()

    implicitWidth: row.implicitWidth + 12
    implicitHeight: Math.max(22, row.implicitHeight + Theme.s1)

    // The hover surface, inset with the same 6 px the content sits in.
    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Qt.rgba(1, 1, 1, area.pressed ? 0.14 : 0.09)
        opacity: area.containsMouse ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.hoverMs } }
    }
    Row {
        id: row
        anchors.centerIn: parent
        spacing: 4
        scale: area.pressed ? 0.96 : 1
        Behavior on scale { NumberAnimation { duration: Theme.pressMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
        Label {
            visible: mark.wordmark !== ""
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 1
            text: mark.wordmark
            size: Theme.tBody; weight: Theme.wBold; rounded: true
            color: mark.tone
        }
        Text {
            textFormat: Text.PlainText
            visible: mark.glyph !== "" && mark.icon === "" && mark.wordmark === ""
            anchors.verticalCenter: parent.verticalCenter
            text: mark.glyph
            font.family: Theme.fontGlyph
            font.pixelSize: 14
            color: mark.tone
            Behavior on color { ColorAnimation { duration: Theme.colorMs } }
        }
        IconImage {
            visible: mark.icon !== "" && mark.wordmark === ""
            anchors.verticalCenter: parent.verticalCenter
            implicitSize: 14
            source: mark.icon
            asynchronous: true
        }
        // ③: the number centred in an 18 px ring. Working: a still
        // three-quarter arc. Needs you: a full ring. Nothing moves at rest;
        // when the count changes the arc makes one smooth turn (a stepping
        // arc read as a stuck spinner; a continuous one cost 15 % CPU).
        Item {
            objectName: "rest-count-ring"
            visible: mark.ring !== "" && mark.value !== ""
            anchors.verticalCenter: parent.verticalCenter
            // Same optical drop as the wordmark beside it. The ring used to
            // stay on the row's centre while "T3" sat 1 px lower, so the
            // digit read high.
            anchors.verticalCenterOffset: 1
            // A longer value ("15h") stretches a solid ring into a pill.
            width: Math.max(18, ringValue.implicitWidth + Theme.s2, mark.ring === "spin" ? ringValue.implicitHeight + Theme.s1 : 0)
            height: mark.ring === "spin" ? width : Math.max(18, ringValue.implicitHeight + Theme.s1)
            Rectangle {
                anchors.fill: parent; radius: height / 2
                color: "transparent"
                border.width: 1.5
                border.color: mark.ring === "solid" ? mark.tone : Qt.alpha(mark.tone, 0.25)
                Behavior on border.color { ColorAnimation { duration: Theme.colorMs } }
            }
            Canvas {
                id: arc
                visible: mark.ring === "spin"
                anchors.fill: parent
                property color ink: mark.tone
                onInkChanged: requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onPaint: {
                    const c = getContext("2d");
                    c.reset(); c.lineWidth = 1.5; c.lineCap = "round"; c.strokeStyle = ink;
                    c.beginPath(); c.arc(width / 2, height / 2, Math.max(0, Math.min(width, height) / 2 - c.lineWidth / 2), -Math.PI / 2, Math.PI); c.stroke();
                }
                // Steps: a third of a turn every 3 s, gliding 600 ms, then
                // still (the notch redraws only while it moves: ~1/5 of the
                // time; a continuous spin cost 15 % CPU at 200 Hz). A bigger
                // step when the count changes.
                // On the shared beat (Theme.step), so every ring on the notch
                // moves together; a count change adds a bigger step of its own.
                // Only while it shows: a hidden arc turned on every beat still
                // drew the notch once every 3 s. (No wrap: a modulo spun it
                // backwards at the wrap.)
                Behavior on rotation { enabled: arc.visible && !Theme.reduceMotion; NumberAnimation { duration: Theme.stepMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeInOut } }
                readonly property bool stepping: arc.visible && !Theme.reduceMotion
                property bool counted: false
                function count() { if (stepping !== counted) { Theme.stepUsers += stepping ? 1 : -1; counted = stepping; } }
                onSteppingChanged: count()
                Component.onCompleted: count()
                Component.onDestruction: if (counted) Theme.stepUsers--
                Connections {
                    target: Theme
                    enabled: arc.stepping
                    function onStepChanged() { arc.rotation += 120; }
                }
                Connections {
                    target: mark
                    function onValueChanged() { if (arc.visible && !Theme.reduceMotion) arc.rotation += 240; }
                }
            }
            Label {
                id: ringValue
                objectName: "rest-count-value"
                anchors.centerIn: parent           // measured: centred (a +1 sat 1 px low)
                text: mark.value
                size: Theme.tCaption; weight: Theme.wBold; rounded: true; compact: true
                color: mark.tone
                tabular: true
            }
        }
        Label {
            visible: mark.value !== "" && mark.ring === ""
            anchors.verticalCenter: parent.verticalCenter
            // Optical: measured on screen, SF digits rode 2 px above the
            // glyph's and the clock's centre (15.0 vs 16.5 / 17.0).
            anchors.verticalCenterOffset: 2
            text: mark.value
            size: Theme.tSub; weight: Theme.wSemibold
            color: mark.tone
            tabular: true
            Behavior on color { ColorAnimation { duration: Theme.colorMs } }
        }
    }
    MouseArea {
        id: area
        anchors.fill: parent
        anchors.margins: -Theme.s1 / 2         // 22 px drawn, 26 px to hit (WCAG's 24 px least)
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: mark.clicked()
    }
    Timer {
        id: intent
        interval: Settings.hoverDelay
        running: area.containsMouse && mark.previews
        onTriggered: mark.previewRequested()
    }
    // A tip only when there's no panel to preview (the panel says more).
    Tip { text: mark.tip; shown: (area.containsMouse || mark.activeFocus) && mark.tip !== "" && !mark.previews; below: true }
}
