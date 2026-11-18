// More that way: a scrolling list fades out at the end where more lies,
// instead of stopping on a row cut through its middle (which reads as broken,
// not as "scroll me"). Nothing fades at an end that is the end. The rehearsal
// fails a list that cuts a row at full strength (rule `cut-row`).
//
// It fades the rows themselves (a mask on the list), not a band of colour
// laid over them: the island's ground is glass over whatever is behind it,
// so a painted band never matches and shows as a darker strip. The list is
// drawn through a layer only while it has something to scroll.
//
//   ListView { id: list … }
//   ScrollFade { flickable: list }       written anywhere beside it
import QtQuick
import QtQuick.Effects
import qs.config

Item {
    id: fade
    required property Flickable flickable
    property real reach: Theme.sp(36)
    readonly property bool scrolls: flickable.contentHeight > flickable.height + 1
    readonly property real span: Math.min(reach, flickable.height / 3)
    // 1: fades at that end; 0: that end is the end.
    property real head: scrolls && !flickable.atYBeginning ? 1 : 0
    property real foot: scrolls && !flickable.atYEnd ? 1 : 0
    Behavior on head { NumberAnimation { duration: Theme.hoverMs } }
    Behavior on foot { NumberAnimation { duration: Theme.hoverMs } }

    // Not laid out where it is written (in a Column it would be a row), and not seen itself.
    parent: flickable.parent
    x: flickable.x; y: flickable.y
    width: flickable.width; height: flickable.height
    visible: false
    layer.enabled: scrolls

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 1 - fade.head) }
            GradientStop { position: Math.max(0.001, fade.span / Math.max(1, fade.height)); color: "black" }
            GradientStop { position: Math.min(0.999, 1 - fade.span / Math.max(1, fade.height)); color: "black" }
            GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 1 - fade.foot) }
        }
    }
    Component {
        id: masked
        MultiEffect { maskEnabled: true; maskSource: fade; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
    }
    function apply() {
        flickable.layer.enabled = scrolls;
        flickable.layer.effect = scrolls ? masked : null;
    }
    onScrollsChanged: apply()
    Component.onCompleted: apply()
    Component.onDestruction: if (flickable) { flickable.layer.effect = null; flickable.layer.enabled = false; }
}
