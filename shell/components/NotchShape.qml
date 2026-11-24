// The notch: a black shape that hangs from the screen's top edge, with
// concave "ears" where it meets the edge and continuous (squircle-like)
// bottom corners, like a MacBook's notch. `w`×`h` is the body; the ears
// add `ear` on each side. The fill is the island colour.
//
//   NotchShape { w: 220; h: 32; radius: 14 }
import QtQuick
import qs.config
import QtQuick.Shapes

Shape {
    id: notch
    property real w: 200
    property real h: 32
    property real radius: 14
    property real ear: 9
    property color fill: "black"
    property color edge: Theme.edge(0)
    property real expand: 0
    property real capH: 34
    function mix(a, b, t) { return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t); }
    readonly property real t: Math.max(0, Math.min(1, expand))
    property LinearGradient glass: LinearGradient {
        x1: 0; y1: 0; x2: 0; y2: notch.h
        GradientStop { position: 0; color: notch.fill }
        GradientStop { position: Math.min(0.97, notch.capH / Math.max(notch.capH + 1, notch.h)); color: notch.fill }
        GradientStop { position: Math.min(0.98, (notch.capH + 36) / Math.max(notch.capH + 37, notch.h)); color: notch.mix(notch.fill, Theme.notchGlassMid, notch.t) }
        GradientStop { position: 1; color: notch.mix(notch.fill, Theme.notchGlassBottom, notch.t) }
    }

    width: w + ear * 2
    height: h
    preferredRendererType: Shape.CurveRenderer

    readonly property real r: Math.max(0, Math.min(radius, h / 2, w / 2))
    // A continuous corner: the curve starts earlier (k) and its handles sit
    // closer to the corner than a circle's, so the curvature eases in.
    readonly property real k: r * 1.28
    readonly property real e: Math.min(ear, h / 2)

    ShapePath {
        fillColor: notch.fill
        fillGradient: notch.t > 0.001 ? notch.glass : null
        strokeWidth: -1
        startX: 0; startY: 0
        // The ear (shoulder): a continuous flare, not a quarter circle: it
        // leaves the screen edge flat and meets the side straight, with the
        // curvature easing in at both ends (the bottom corners' rule), so the
        // island reads as poured out of the edge. (After Clove's NotchShape,
        // MIT: its shoulders are quad curves with the control at the corner.)
        PathCubic { x: notch.e; y: notch.e; control1X: notch.e * 0.62; control1Y: 0; control2X: notch.e; control2Y: notch.e * 0.38 }
        PathLine { x: notch.e; y: notch.h - notch.k }
        PathCubic { x: notch.e + notch.k; y: notch.h; control1X: notch.e; control1Y: notch.h - notch.k * 0.3; control2X: notch.e + notch.k * 0.3; control2Y: notch.h }
        PathLine { x: notch.e + notch.w - notch.k; y: notch.h }
        PathCubic { x: notch.e + notch.w; y: notch.h - notch.k; control1X: notch.e + notch.w - notch.k * 0.3; control1Y: notch.h; control2X: notch.e + notch.w; control2Y: notch.h - notch.k * 0.3 }
        PathLine { x: notch.e + notch.w; y: notch.e }
        PathCubic { x: notch.w + notch.e * 2; y: 0; control1X: notch.e + notch.w; control1Y: notch.e * 0.38; control2X: notch.e + notch.w + notch.e * 0.38; control2Y: 0 }
        PathLine { x: 0; y: 0 }
    }
    ShapePath {
        fillColor: "transparent"
        strokeColor: notch.mix(notch.edge, Theme.contrast ? Theme.edge(3) : Theme.edge(1), notch.t)
        strokeWidth: 1
        startX: 0; startY: 0
        PathCubic { x: notch.e; y: notch.e; control1X: notch.e * 0.62; control1Y: 0; control2X: notch.e; control2Y: notch.e * 0.38 }
        PathLine { x: notch.e; y: notch.h - notch.k }
        PathCubic { x: notch.e + notch.k; y: notch.h; control1X: notch.e; control1Y: notch.h - notch.k * 0.3; control2X: notch.e + notch.k * 0.3; control2Y: notch.h }
        PathLine { x: notch.e + notch.w - notch.k; y: notch.h }
        PathCubic { x: notch.e + notch.w; y: notch.h - notch.k; control1X: notch.e + notch.w - notch.k * 0.3; control1Y: notch.h; control2X: notch.e + notch.w; control2Y: notch.h - notch.k * 0.3 }
        PathLine { x: notch.e + notch.w; y: notch.e }
        PathCubic { x: notch.w + notch.e * 2; y: 0; control1X: notch.e + notch.w; control1Y: notch.e * 0.38; control2X: notch.e + notch.w + notch.e * 0.38; control2Y: 0 }
    }
}
