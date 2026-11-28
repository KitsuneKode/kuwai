// An icon from Phosphor (1,530 of them; phosphoricons.com for names). Auto
// is bold at 16px and smaller, regular above it; heroes pass duotone for the
// two-tone look. `active` is its one animation, a state change, not
// decoration: the fill rises to full and the outline steps back, 160 ms.
//
//   Icon { name: "bell" }                       size-aware, 16 px, the text colour
//   Icon { name: "wifi-high"; active: on; color: Theme.accent }
//   Icon { name: "gear"; style: "regular" }     auto · regular · bold · fill · duotone
import QtQuick
import qs.config

Item {
    id: icon
    property string name
    property string style: "auto"
    property int size: Theme.glyphS
    property color color: Theme.textPrimary
    property bool active: false

    implicitWidth: size
    implicitHeight: size
    readonly property string effectiveStyle: style === "auto" ? (size <= 16 ? "bold" : "regular") : style
    readonly property bool duo: effectiveStyle === "duotone" && Icons.glyph(name, "df") !== ""
    readonly property string family: ({ regular: "Phosphor", bold: "Phosphor-Bold", fill: "Phosphor-Fill" })[effectiveStyle] || "Phosphor"
    property real k: active ? 1 : 0
    Behavior on k { NumberAnimation { duration: Theme.microMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }

    component Glyph: Text {
        textFormat: Text.PlainText
        renderType: Text.NativeRendering
        anchors.centerIn: parent
        font.hintingPreference: Font.PreferNoHinting
        Accessible.ignored: true
    }

    Loader {
        active: icon.duo
        anchors.fill: parent
        sourceComponent: Glyph {
            text: Icons.glyph(icon.name, "db")
            font.family: "Phosphor-Duotone"; font.pixelSize: icon.size
            color: icon.color
            opacity: 0.2 + 0.8 * icon.k
        }
    }
    Loader {
        active: icon.duo
        anchors.fill: parent
        sourceComponent: Glyph {
            text: Icons.glyph(icon.name, "df")
            font.family: "Phosphor-Duotone"; font.pixelSize: icon.size
            color: icon.color
            opacity: 1 - 0.35 * icon.k
        }
    }
    Loader {
        active: !icon.duo
        anchors.fill: parent
        sourceComponent: Glyph {
            text: Icons.glyph(icon.name, "r")
            font.family: icon.family; font.pixelSize: icon.size
            color: icon.color
            opacity: icon.effectiveStyle === "fill" ? 1 : 1 - icon.k
        }
    }
    Loader {
        active: !icon.duo && icon.effectiveStyle !== "fill" && (icon.active || icon.k > 0.001)
        anchors.fill: parent
        sourceComponent: Glyph {
            text: Icons.glyph(icon.name, "r")
            font.family: "Phosphor-Fill"; font.pixelSize: icon.size
            color: icon.color
            opacity: icon.k
        }
    }
}
