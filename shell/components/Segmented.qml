// Segmented tabs, Fluid Functionalism's sizing: a 36px track with 4px
// padding around 28px segments; the selected pill slides on the moderate
// spring (critically damped: it lands exactly). Corners are concentric
// (pill radius = track radius − padding). The selected label turns semibold.
//
//   Segmented { options: [{ id: "a", label: "Notifications", badge: 3 }, …]; current: "a"; onPicked: id => … }
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import qs.config

Rectangle {
    id: seg

    property var options: []
    property string current: ""
    signal picked(string id)

    readonly property int pad: 4
    implicitHeight: Math.max(36, Math.ceil(Theme.tBody * Theme.textScale) + 16)
    height: implicitHeight
    Layout.fillWidth: true
    Layout.minimumWidth: 0
    Layout.preferredWidth: implicitWidth
    radius: 12
    // Given a width, the segments share the spare room evenly on top of
    // their natural widths (so a long label never squeezes a short one).
    implicitWidth: naturalSum + pad * 2
    // Summed when segments come and go or change size (itemAt() isn't
    // something a binding can watch: built in the background, the segments
    // arrive after a binding would have run).
    // A pixel of slack: at 120 % text the natural width is a fraction, a
    // layout hands back a whole number, and the control fell into its
    // drop-down form for want of 0.4 px (Settings → Top bar).
    readonly property bool compact: width < naturalSum + pad * 2 - 1
    // Too narrow for its segments: the same choice as a drop-down, drawn as
    // the rest of the shell is (the toolkit's own is a white box).
    Controls.ComboBox {
        id: drop
        anchors.fill: parent
        visible: seg.compact
        model: seg.options
        textRole: "label"
        valueRole: "id"
        currentIndex: seg.options.findIndex(o => o.id === seg.current)
        font.pixelSize: Math.round(Theme.tBody * Theme.textScale)
        Accessible.name: "Choose section"
        onActivated: seg.picked(currentValue)
        background: Item {}
        contentItem: Label {
            leftPadding: 12; rightPadding: 28
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            text: drop.displayText
            size: Theme.tBody; weight: Theme.wSemibold
        }
        indicator: Text {
            textFormat: Text.PlainText
            x: drop.width - width - 10
            anchors.verticalCenter: parent.verticalCenter
            text: "\u{f0140}"                       // chevron down
            font.family: Theme.fontGlyph; font.pixelSize: Theme.glyphS
            color: Theme.textSecondary
        }
        delegate: Controls.ItemDelegate {
            id: choice
            required property var modelData
            required property int index
            width: drop.width
            height: Theme.sp(32)
            highlighted: drop.highlightedIndex === index
            background: Rectangle { radius: Theme.r1; color: choice.highlighted ? Theme.rowHover : "transparent" }
            contentItem: Label {
                leftPadding: 8
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                text: choice.modelData.label
                size: Theme.tBody; weight: choice.index === drop.currentIndex ? Theme.wSemibold : Theme.wRegular
            }
        }
        popup: Controls.Popup {
            y: drop.height + 4
            width: drop.width
            padding: 4
            implicitHeight: contentItem.implicitHeight + 8
            background: Rectangle { radius: Theme.r2; color: Theme.glassSolid; border.width: 1; border.color: Theme.cardEdge }
            contentItem: ListView {
                clip: true
                implicitHeight: contentHeight
                model: drop.popup.visible ? drop.delegateModel : null
                currentIndex: drop.highlightedIndex
            }
        }
    }
    property real naturalSum: 0
    function measure() {
        let sum = 0;
        for (let k = 0; k < rep.count; k++) { const it = rep.itemAt(k); if (it) sum += it.natural; }
        naturalSum = sum;
        pickCurrent();
    }
    readonly property real extra: rep.count ? Math.max(0, (width - pad * 2 - naturalSum) / rep.count) : 0
    color: Theme.wash(1)

    // Found, not bound: a binding over itemAt() ran once, before the
    // segments existed, and stayed null, so the selected pill never showed
    // (the center's tabs had only a bolder label). Looked up again whenever
    // the segments or the choice change.
    property Item currentItem: null
    function pickCurrent() {
        let found = null;
        for (let k = 0; k < rep.count; k++) {
            const it = rep.itemAt(k);
            if (it && it.optionId === current) { found = it; break; }
        }
        const first = !currentItem;
        currentItem = found;
        if (found) place(first);
    }
    onCurrentChanged: pickCurrent()
    // Deferred: on a reload the item can be gone by the time this runs.
    function placeLater() { Qt.callLater(() => { if (seg && typeof seg.place === "function") seg.place(true); }); }
    onExtraChanged: placeLater()
    Component.onCompleted: placeLater()
    function place(snap) {
        if (!currentItem) return;
        if (snap) { px.snap(currentItem.x); pw.snap(currentItem.width); }
        else { px.target = currentItem.x; pw.target = currentItem.width; }
    }
    Spring { id: px; tier: Theme.springModerate; epsilon: 0.25 }
    Spring { id: pw; tier: Theme.springModerate; epsilon: 0.25 }

    Rectangle {
        visible: !seg.compact
        x: seg.pad + px.value
        y: seg.pad
        width: pw.value
        height: seg.height - seg.pad * 2
        radius: seg.radius - seg.pad
        color: Theme.wash(3)
        border.width: 1
        border.color: Theme.edge(1)
    }

    Row {
        id: row
        visible: !seg.compact
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
                height: seg.height - seg.pad * 2
                scale: optArea.pressed && !Theme.reduceMotion ? 0.97 : 1
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
                        color: opt.modelData.alert ? Theme.red : Theme.wash(3)
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
                Accessible.role: Accessible.PageTab
                Accessible.name: opt.modelData.label
                Accessible.description: (opt.modelData.badge || 0) > 0 ? String(opt.modelData.badge) : ""
                Accessible.selected: opt.on
                Accessible.onPressAction: seg.picked(opt.modelData.id)
            }
        }
    }

    // Keyboard and screen readers: a tab bar; ←→ move between its options.
    activeFocusOnTab: true
    Accessible.role: Accessible.PageTabList
    Accessible.name: (seg.options.find(o => o.id === seg.current) || {}).label || ""
    Keys.onPressed: e => {
        const ids = seg.options.map(o => o.id), i = ids.indexOf(seg.current);
        if (e.key === Qt.Key_Right && i < ids.length - 1) seg.picked(ids[i + 1]);
        else if (e.key === Qt.Key_Left && i > 0) seg.picked(ids[i - 1]);
        else return;
        e.accepted = true;
    }
    FocusRing {}
}
