import QtQuick
import qs.config
import qs.components

Item {
    id: sv
    property bool loading: false
    property bool empty: false
    property string error: ""
    property string emptyGlyph: ""
    property string emptyTitle: ""
    property string emptyBody: ""
    property string actionLabel: ""
    default property alias readyContent: readyHost.data
    signal actionTriggered()

    property bool showSkeleton: false
    property real shownAt: 0

    Timer {
        id: delayTimer
        interval: Theme.microMs
        onTriggered: {
            if (sv.loading) {
                sv.showSkeleton = true;
                sv.shownAt = Date.now();
            }
        }
    }

    Timer {
        id: holdTimer
        interval: Theme.artMs
        onTriggered: {
            if (!sv.loading) sv.showSkeleton = false;
        }
    }

    onLoadingChanged: {
        if (loading) {
            holdTimer.stop();
            delayTimer.restart();
        } else {
            delayTimer.stop();
            if (showSkeleton) {
                const elapsed = Date.now() - shownAt;
                const rem = Theme.artMs - elapsed;
                if (rem > 20) {
                    holdTimer.interval = rem;
                    holdTimer.restart();
                } else {
                    showSkeleton = false;
                }
            }
        }
    }

    implicitWidth: readyHost.implicitWidth
    implicitHeight: Math.max(readyHost.implicitHeight, stateBox.visible ? stateBox.implicitHeight + Theme.s5 : 0)

    Item {
        id: readyHost
        anchors.fill: parent
        visible: !sv.showSkeleton && sv.error === "" && !sv.empty
    }

    Column {
        id: skeletonBox
        visible: sv.showSkeleton
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
        spacing: Theme.s2
        Skeleton { width: parent.width; height: Theme.sp(32); radius: Theme.r2 }
        Skeleton { width: parent.width * 0.85; height: Theme.sp(32); radius: Theme.r2 }
        Skeleton { width: parent.width * 0.65; height: Theme.sp(32); radius: Theme.r2 }
    }

    EmptyState {
        id: stateBox
        visible: !sv.showSkeleton && (sv.error !== "" || sv.empty)
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
        glyph: sv.error !== "" ? "\u{f0026}" : sv.emptyGlyph
        title: sv.error !== "" ? "Something went wrong" : sv.emptyTitle
        body: sv.error !== "" ? sv.error : sv.emptyBody
        actionLabel: sv.actionLabel
        onActionTriggered: sv.actionTriggered()
    }
}
