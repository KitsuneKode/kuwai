import QtQuick
import qs.config

Text {
    property int size: 13
    property int weight: Theme.wRegular
    property bool rounded: false
    property real extraTracking: 0
    property real opsz: Theme.opszFor(size)

    font.family: rounded ? Theme.fontRounded : (size >= 20 ? Theme.fontDisplay : Theme.fontText)
    font.pixelSize: size
    font.weight: weight
    font.letterSpacing: Theme.tracking(size, rounded) + extraTracking
    renderType: Text.NativeRendering
    color: Theme.textPrimary
}
