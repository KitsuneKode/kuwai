import QtQuick
import qs.config
import qs.components

Item {
    id: surface
    property real radius: Theme.r2
    property real strength: 0.5
    Elevation { target: surface; radius: surface.radius; strength: surface.strength }
    Rectangle {
        anchors.fill: parent
        radius: surface.radius
        color: Theme.menuSurface
        border.width: 1
        border.color: Theme.menuEdge
    }
}
