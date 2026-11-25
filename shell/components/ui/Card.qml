// Grouped content inside a panel: children stack in a column, 14 px in.
//
//   Card { Label { text: "Memory" } Meter { … } }
//   Card { spacing: 4; padding: 12; … }
import QtQuick
import qs.config

Rectangle {
    id: card
    default property alias body: col.data
    property int padding: 14
    property bool flush: false
    property alias spacing: col.spacing

    width: parent ? parent.width : 0
    implicitHeight: flush ? col.implicitHeight : col.implicitHeight + padding * 2 - 4
    height: implicitHeight
    radius: Theme.r3
    color: Theme.card
    border.width: 1
    border.color: Theme.cardEdge

    // A 1px drop, darker than the panel, so the card reads as sitting on it.
    Rectangle {
        z: -1
        x: 0
        y: 1
        width: card.width
        height: card.height
        radius: card.radius
        color: Theme.cardDrop
    }

    Column {
        id: col
        x: card.flush ? 0 : card.padding; y: card.flush ? 0 : card.padding - 2
        width: card.width - (card.flush ? 0 : card.padding * 2)
        spacing: card.flush ? 0 : 10
    }
}
