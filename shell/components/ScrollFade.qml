// More that way: a scrolling list fades out at the end where more lies,
// instead of stopping on a row cut through its middle (which reads as broken,
// not as "scroll me"). Nothing fades at an end that is the end. The rehearsal
// fails a list that cuts a row at full strength (rule `cut-row`).
//
// It fades the rows themselves (a mask on the list), not a band of colour
// laid over them: the island's ground is glass over whatever is behind it,
// so a painted band never matches and shows as a darker strip. The list is
// drawn through a layer only while it is shown and has something to scroll.
//
// How strongly each end fades follows the scroll position (AI Elements'
// scroll fade): it comes in over the first `ramp` px scrolled away from an end
// and goes as you reach it. A value linked to the position can't lag behind it
// or drift when a fling turns round. The ramp is short: a list only a few
// px too tall still fades its cut last row (rule `cut-row`).
//
//   ListView { id: list … }
//   ScrollFade { flickable: list }       written anywhere beside it
//   ScrollFade { flickable: list; active: view === "list" }
//
// It draws nothing and takes no room: the root is not an Item, so no caller
// can make its mask show (UpdatesPanel set `visible` on the old one, and the
// mask, a black rectangle, covered the whole list).
import QtQuick
import QtQuick.Effects
import qs.config

QtObject {
    id: fade
    required property Flickable flickable
    property real reach: Theme.sp(36)
    property real ramp: Theme.sp(12)
    property bool active: true

    readonly property bool scrolls: active && !!flickable && flickable.visible
        && flickable.contentHeight + flickable.topMargin + flickable.bottomMargin > flickable.height + 1
    readonly property real span: flickable ? Math.max(1, Math.min(reach, flickable.height / 3)) : 1
    // 0: that end is the end · 1: a ramp's worth or more lies that way.
    // At an end (Flickable's own word for it) nothing fades there: a ListView's
    // originY drifts while its rows change height, and the top row of T3's list
    // faded with the list at its top.
    readonly property real head: !scrolls || flickable.atYBeginning ? 0
        : Math.max(0, Math.min(1, (flickable.contentY - flickable.originY + flickable.topMargin) / Math.max(1, fade.ramp)))
    readonly property real foot: !scrolls || flickable.atYEnd ? 0
        : Math.max(0, Math.min(1, (flickable.originY + flickable.contentHeight + flickable.bottomMargin - flickable.height - flickable.contentY) / Math.max(1, fade.ramp)))
    readonly property bool liveLayer: scrolls && (head > 0.01 || foot > 0.01)

    // The mask: the list's own rectangle, opaque where rows show and clear
    // where they fade. Rendered only into the layer, never on screen; a
    // positioner skips it (not visible), so it never becomes a row.
    readonly property Item mask: Item {
        parent: fade.flickable ? fade.flickable.parent : null
        x: fade.flickable ? fade.flickable.x : 0
        y: fade.flickable ? fade.flickable.y : 0
        width: fade.flickable ? fade.flickable.width : 0
        height: fade.flickable ? fade.flickable.height : 0
        visible: false
        layer.enabled: fade.layered
        Rectangle {
            id: maskRect
            anchors.fill: parent
            readonly property real edge: fade.span / Math.max(1, height)
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 1 - fade.head) }
                GradientStop { position: Math.max(0.001, maskRect.edge); color: "black" }
                GradientStop { position: Math.min(0.999, 1 - maskRect.edge); color: "black" }
                GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 1 - fade.foot) }
            }
        }
    }
    readonly property Component effect: Component {
        MultiEffect { maskEnabled: true; maskSource: fade.mask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
    }

    // On: the layer, then its effect. Off: the effect while the layer is
    // still there to take it down, then the layer.
    //
    // Decided a moment after `scrolls` changes, never inside the change that
    // caused it. Closing the notification centre crashed the shell (2026-11-20
    // 21:47 and 11-21 09:36; then Quickshell's restart came up on another
    // config): Qt unparents the list while tearing the view down, a listener
    // earlier in that same notification resizes it, `scrolls` turns false,
    // and taking the layer down right there left Qt (6.12, QQuickItemLayer::
    // itemParentChanged, called from its copy of the listeners) unparenting
    // the layer's source after it was deleted: a null pointer. The timer
    // belongs to this object, so a list being torn down never sees it fire.
    property bool layered: false
    function apply() {
        if (!flickable || liveLayer === layered) return;
        layered = liveLayer;
        if (layered) {
            flickable.layer.enabled = true;
            flickable.layer.effect = effect;
        } else {
            flickable.layer.effect = null;
            flickable.layer.enabled = false;
        }
    }
    readonly property Timer settle: Timer { interval: 0; onTriggered: fade.apply() }
    onScrollsChanged: settle.restart()
    onLiveLayerChanged: settle.restart()
    Component.onCompleted: apply()
    Component.onDestruction: if (flickable && layered) { flickable.layer.effect = null; flickable.layer.enabled = false; }
}
