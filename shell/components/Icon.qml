// An icon from Phosphor (1,530 of them; phosphoricons.com for names), drawn
// duotone by default: a 20% "fill" layer behind a crisp outline, the
// premium two-tone look. `active` is its one animation, a state change, not
// decoration: the fill rises to full and the outline steps back, 160 ms.
//
//   Icon { name: "bell" }                       duotone, 16 px, the text colour
//   Icon { name: "wifi-high"; active: on; color: Theme.accent }
//   Icon { name: "gear"; style: "regular" }     thin · light · regular · bold · fill
import QtQuick
import qs.config

Item {
    id: icon
    property string name
    property string style: "duotone"
    property int size: 16
    property color color: Theme.textPrimary
    property bool active: false

    implicitWidth: size
    implicitHeight: size
    readonly property bool duo: style === "duotone" && Icons.glyph(name, "df") !== ""
    readonly property string family: ({ thin: "Phosphor-Thin", light: "Phosphor-Light", regular: "Phosphor", bold: "Phosphor-Bold", fill: "Phosphor-Fill" })[style] || "Phosphor"
    property real k: active ? 1 : 0
    Behavior on k { NumberAnimation { duration: 160; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }

    // Duotone: the fill layer (20% → full when active) and the outline.
    Text {
        visible: icon.duo
        anchors.centerIn: parent
        text: Icons.glyph(icon.name, "db")
        font.family: "Phosphor-Duotone"; font.pixelSize: icon.size
        color: icon.color
        opacity: 0.2 + 0.8 * icon.k
    }
    Text {
        visible: icon.duo
        anchors.centerIn: parent
        text: Icons.glyph(icon.name, "df")
        font.family: "Phosphor-Duotone"; font.pixelSize: icon.size
        color: icon.color
        opacity: 1 - 0.35 * icon.k
    }
    // Single weight: the outline, crossfading to the filled glyph when active.
    Text {
        visible: !icon.duo
        anchors.centerIn: parent
        text: Icons.glyph(icon.name, "r")
        font.family: icon.family; font.pixelSize: icon.size
        color: icon.color
        opacity: icon.style === "fill" ? 1 : 1 - icon.k
    }
    Text {
        visible: !icon.duo && icon.style !== "fill"
        anchors.centerIn: parent
        text: Icons.glyph(icon.name, "r")
        font.family: "Phosphor-Fill"; font.pixelSize: icon.size
        color: icon.color
        opacity: icon.k
    }
}
