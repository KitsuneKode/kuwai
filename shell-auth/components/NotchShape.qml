// VENDORED for the password prompt (shell-auth): a reviewed copy of
// shell/components/NotchShape.qml, not a link. Rule for everything in shell-auth/: read
// files and draw, nothing else — no Process, sockets, network or IPC here
// (`kuwai doctor` checks). Change the shell's copy freely; update this one
// on purpose (`kuwai auth diff` shows what drifted).
// The notch: a black shape that hangs from the screen's top edge, with
// concave "ears" where it meets the edge and continuous (squircle-like)
// bottom corners, like a MacBook's notch. `w`×`h` is the body; the ears
// add `ear` on each side. The fill is the island colour.
//
//   NotchShape { w: 220; h: 32; radius: 14 }
import QtQuick
import QtQuick.Shapes

Shape {
    id: notch
    property real w: 200
    property real h: 32
    property real radius: 14
    property real ear: 9
    property color fill: "black"
    property color edge: Qt.rgba(1, 1, 1, 0.06)

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
        strokeColor: notch.edge
        strokeWidth: 1
        startX: 0; startY: 0
        PathArc { x: notch.e; y: notch.e; radiusX: notch.e; radiusY: notch.e; direction: PathArc.Clockwise }
        PathLine { x: notch.e; y: notch.h - notch.k }
        PathCubic { x: notch.e + notch.k; y: notch.h; control1X: notch.e; control1Y: notch.h - notch.k * 0.3; control2X: notch.e + notch.k * 0.3; control2Y: notch.h }
        PathLine { x: notch.e + notch.w - notch.k; y: notch.h }
        PathCubic { x: notch.e + notch.w; y: notch.h - notch.k; control1X: notch.e + notch.w - notch.k * 0.3; control1Y: notch.h; control2X: notch.e + notch.w; control2Y: notch.h - notch.k * 0.3 }
        PathLine { x: notch.e + notch.w; y: notch.e }
        PathArc { x: notch.w + notch.e * 2; y: 0; radiusX: notch.e; radiusY: notch.e; direction: PathArc.Clockwise }
        PathLine { x: 0; y: 0 }
    }
}
