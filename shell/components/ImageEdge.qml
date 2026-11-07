// A hairline on an image's edge (interfaces.dev, "add an outline to
// images"): album art, an avatar or a thumbnail on black has no edge of its
// own, and a dark cover melts into the notch. 1 px of white at 10 %, drawn
// over the image, inside it, following its corners. Put it last inside the
// image's clipping rectangle:
//
//   ClippingRectangle { radius: 11; Image { … } ImageEdge { radius: 11 } }
import QtQuick

Rectangle {
    anchors.fill: parent
    color: "transparent"
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.1)
    antialiasing: true
}
