// A Control Center tile: the mark in a disc (filled in its tone while on),
// a title and one line of state. Expandable ones (Wi-Fi): the disc toggles,
// the rest opens more (and says which half does what through tip()).
//
//   ControlTile { glyph: "\u{f05a9}"; title: "Wi-Fi"; subtitle: "Home"; on: true; expandable: true; moreText: "Show networks" }
import QtQuick
import qs.config
import qs.components

Rectangle {
    id: tile
    property string glyph
    property string title
    property string subtitle
    property bool on: false
    property color tone: Theme.blue
    // Expandable tiles (Wi‑Fi): the disc toggles, the rest opens more.
    property bool expandable: false
    property bool expanded: false
    property string moreText: "Show more"
    signal toggled()
    signal opened()
    signal tip(bool shown, string text)   // expandable: which half does what

    implicitWidth: 200
    implicitHeight: 56
    radius: Theme.r3
    color: area.containsMouse ? Qt.rgba(1, 1, 1, 0.11) : Qt.rgba(1, 1, 1, 0.075)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.06)
    scale: area.pressed ? 0.97 : 1
    Behavior on color { ColorAnimation { duration: Theme.hoverMs } }
    Behavior on scale { NumberAnimation { duration: Theme.pressMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }

    Rectangle {
        id: disc
        x: 10
        anchors.verticalCenter: parent.verticalCenter
        width: 34; height: 34; radius: 17
        color: tile.on ? tile.tone : Qt.rgba(1, 1, 1, 0.12)
        Behavior on color { ColorAnimation { duration: Theme.colorMs } }
        Text {
            anchors.centerIn: parent
            text: tile.glyph
            font.family: Theme.fontGlyph
            font.pixelSize: 16
            color: tile.on && tile.tone === Theme.yellow ? "#1c1c1e" : Theme.textPrimary
        }
    }
    Column {
        anchors { left: disc.right; leftMargin: 10; right: chevron.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
        spacing: 1
        Label { width: parent.width; elide: Text.ElideRight; text: tile.title; size: 13; weight: Theme.wSemibold }
        Label { width: parent.width; elide: Text.ElideRight; text: tile.subtitle; size: 11; color: Theme.textTertiary }
    }
    Text {
        id: chevron
        anchors { right: parent.right; rightMargin: tile.expandable ? 10 : 0; verticalCenter: parent.verticalCenter }
        width: tile.expandable ? implicitWidth : 0
        visible: tile.expandable
        text: "\u{f0142}"                                     // chevron-right
        font.family: Theme.fontGlyph
        font.pixelSize: 16
        color: Theme.textTertiary
        rotation: tile.expanded ? 90 : 0
        Behavior on rotation { enabled: !Theme.reduceMotion; NumberAnimation { duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        // Expandable tiles say which half does what.
        property bool onDisc: mouseX < disc.x + disc.width + 4
        onContainsMouseChanged: if (tile.expandable) tile.tip(containsMouse, onDisc ? "Turn " + tile.title + (tile.on ? " off" : " on") : tile.moreText)
        onOnDiscChanged: if (tile.expandable && containsMouse) tile.tip(true, onDisc ? "Turn " + tile.title + (tile.on ? " off" : " on") : tile.moreText)
        onClicked: mouse => {
            if (tile.expandable && mouse.x > disc.x + disc.width + 4) tile.opened();
            else tile.toggled();
        }
    }
}
