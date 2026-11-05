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
import QtQuick
import Quickshell.Widgets
import qs.config

Item {
    id: mark
    property string glyph: ""
    property string icon: ""
    property string wordmark: ""         // a product's name as its mark ("T3")
    property bool previews: false        // rest on it: previewRequested() (its panel)
    property string value: ""
    property color tone: Theme.textSecondary
    property string tip: ""
    readonly property alias hovered: area.containsMouse
    signal clicked()
    signal previewRequested()

    implicitWidth: row.implicitWidth + 12
    implicitHeight: 22

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
        Behavior on scale { NumberAnimation { duration: Theme.pressMs; easing.type: Easing.OutCubic } }
        Label {
            visible: mark.wordmark !== ""
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 1
            text: mark.wordmark
            size: Theme.tBody; weight: Theme.wBold; rounded: true
            color: mark.tone
        }
        Text {
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
        Label {
            visible: mark.value !== ""
            anchors.verticalCenter: parent.verticalCenter
            // Optical: measured on screen, SF digits rode 2 px above the
            // glyph's and the clock's centre (15.0 vs 16.5 / 17.0).
            anchors.verticalCenterOffset: 2
            text: mark.value
            size: Theme.tSub; weight: Theme.wSemibold
            color: mark.tone
            font.features: ({ "tnum": 1 })
            Behavior on color { ColorAnimation { duration: Theme.colorMs } }
        }
    }
    MouseArea {
        id: area
        anchors.fill: parent
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
    Tip { text: mark.tip; shown: area.containsMouse && mark.tip !== "" && !mark.previews; below: true }
}
