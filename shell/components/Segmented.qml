// Segmented tabs, Fluid Functionalism's sizing: a 36px track with 4px
// padding around 28px segments; the selected pill slides on the moderate
// spring (critically damped: it lands exactly). Corners are concentric
// (pill radius = track radius − padding). The selected label turns semibold.
//
//   Segmented { options: [{ id: "a", label: "Notifications", badge: 3 }, …]; current: "a"; onPicked: id => … }
import QtQuick
import qs.config

Rectangle {
    id: seg

    property var options: []
    property string current: ""
    signal picked(string id)

    readonly property int pad: 4
    height: 36
    radius: 12
    // Given a width, the segments share the spare room evenly on top of
    // their natural widths (so a long label never squeezes a short one).
    implicitWidth: naturalSum + pad * 2
    // Summed when segments come and go or change size (itemAt() isn't
    // something a binding can watch: built in the background, the segments
    // arrive after a binding would have run).
    property real naturalSum: 0
    function measure() {
        let sum = 0;
        for (let k = 0; k < rep.count; k++) { const it = rep.itemAt(k); if (it) sum += it.natural; }
        naturalSum = sum;
    }
    readonly property real extra: rep.count ? Math.max(0, (width - pad * 2 - naturalSum) / rep.count) : 0
    color: Qt.rgba(1, 1, 1, 0.06)

    readonly property Item currentItem: {
        for (let k = 0; k < rep.count; k++) {
            const it = rep.itemAt(k);
            if (it && it.optionId === current) return it;
        }
        return null;
    }
    onCurrentItemChanged: place(false)
    onExtraChanged: Qt.callLater(() => seg.place(true))
    Component.onCompleted: Qt.callLater(() => seg.place(true))
    function place(snap) {
        if (!currentItem) return;
        if (snap) { px.snap(currentItem.x); pw.snap(currentItem.width); }
        else { px.target = currentItem.x; pw.target = currentItem.width; }
    }
    Spring { id: px; tier: Theme.springModerate; epsilon: 0.25 }
    Spring { id: pw; tier: Theme.springModerate; epsilon: 0.25 }

    Rectangle {
        x: seg.pad + px.value
        y: seg.pad
        width: pw.value
        height: 28
        radius: seg.radius - seg.pad
        color: Qt.rgba(1, 1, 1, 0.14)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.08)
    }

    Row {
        id: row
        x: seg.pad
        y: seg.pad
        Repeater {
            id: rep
            model: seg.options
            onItemAdded: Qt.callLater(seg.measure)
            onItemRemoved: Qt.callLater(seg.measure)
            delegate: Item {
                id: opt
                required property var modelData
                readonly property string optionId: modelData.id
                readonly property bool on: seg.current === modelData.id
                readonly property real natural: inner.implicitWidth + 20
                onNaturalChanged: Qt.callLater(seg.measure)
                width: natural + seg.extra
                height: 28
                scale: optArea.pressed ? 0.97 : 1
                Behavior on scale { NumberAnimation { duration: Theme.pressMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }

                Row {
                    id: inner
                    anchors.centerIn: parent
                    spacing: 6
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: opt.modelData.label
                        size: 13
                        weight: opt.on ? Theme.wSemibold : Theme.wRegular
                        color: opt.on ? Theme.textPrimary : Theme.textSecondary
                    }
                    Rectangle {
                        visible: (opt.modelData.badge || 0) > 0
                        anchors.verticalCenter: parent.verticalCenter
                        height: 16; radius: 8
                        width: Math.max(16, badgeText.implicitWidth + 9)
                        color: opt.modelData.alert ? Theme.red : Qt.rgba(1, 1, 1, 0.16)
                        Label {
                            id: badgeText
                            rounded: true
                            anchors.centerIn: parent
                            text: opt.modelData.badge || ""
                            size: 11
                            weight: Theme.wSemibold
                            font.features: ({ "tnum": 1 })
                        }
                    }
                }
                MouseArea {
                    id: optArea
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: seg.picked(opt.modelData.id)
                }
            }
        }
    }
}
