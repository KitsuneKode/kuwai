// Liquid-glass card: Hyprland blurs what is behind the surface (each rice
// layer namespace has a blur + ignore_alpha rule, see hypr/rice.conf), this
// draws the material on top of it.
//
//   base tint   dark, ~46% alpha, so the blur shows through
//   sheen       vertical light: bright at the top, clear in the middle,
//               a faint refracted band along the bottom edge
//   rim         1px specular edge, brightest top-left where light hits,
//               a weaker bounce bottom-right, near-clear along the sides
//
// The rim is painted on the CPU (Canvas), so it isn't repainted on every
// frame of a resize (a morph, a toast changing height): while the size is
// moving, a plain 1px edge stands in, and the rim repaints once it settles.
import QtQuick
import qs.config

Item {
    id: card
    property real radius: height / 2.9
    property color tint: Theme.glassTint

    Rectangle {
        anchors.fill: parent
        radius: card.radius
        color: card.tint
    }

    Rectangle {
        anchors.fill: parent
        radius: card.radius
        gradient: Gradient {
            GradientStop { position: 0.0;  color: Qt.rgba(1, 1, 1, 0.17) }
            GradientStop { position: 0.42; color: Qt.rgba(1, 1, 1, 0.03) }
            GradientStop { position: 0.80; color: Qt.rgba(1, 1, 1, 0.02) }
            GradientStop { position: 1.0;  color: Qt.rgba(1, 1, 1, 0.09) }
        }
    }

    property bool resizing: false
    onWidthChanged: { resizing = true; settle.restart(); }
    onHeightChanged: { resizing = true; settle.restart(); }
    Timer { id: settle; interval: 70; onTriggered: { card.resizing = false; rim.requestPaint(); } }

    Rectangle {
        anchors.fill: parent
        visible: card.resizing
        radius: card.radius
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.16)
    }

    Canvas {
        id: rim
        anchors.fill: parent
        antialiasing: true
        visible: !card.resizing
        renderStrategy: Canvas.Threaded
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const w = width, h = height, i = 0.5;
            if (w < 2 || h < 2) return;
            const r = Math.max(0, Math.min(card.radius, h / 2 - i, w / 2 - i));
            const g = ctx.createLinearGradient(0, 0, w * 0.6, h * 1.4);
            g.addColorStop(0.00, Qt.rgba(1, 1, 1, 0.62));
            g.addColorStop(0.30, Qt.rgba(1, 1, 1, 0.14));
            g.addColorStop(0.62, Qt.rgba(1, 1, 1, 0.05));
            g.addColorStop(1.00, Qt.rgba(1, 1, 1, 0.30));
            ctx.strokeStyle = g;
            ctx.lineWidth = 1;
            ctx.beginPath();
            ctx.moveTo(i + r, i);
            ctx.lineTo(w - i - r, i);
            ctx.arcTo(w - i, i, w - i, i + r, r);
            ctx.lineTo(w - i, h - i - r);
            ctx.arcTo(w - i, h - i, w - i - r, h - i, r);
            ctx.lineTo(i + r, h - i);
            ctx.arcTo(i, h - i, i, h - i - r, r);
            ctx.lineTo(i, i + r);
            ctx.arcTo(i, i, i + r, i, r);
            ctx.closePath();
            ctx.stroke();
        }
    }
}
