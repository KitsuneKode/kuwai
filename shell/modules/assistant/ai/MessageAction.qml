import QtQuick
import qs.config
import qs.components

Rectangle {
    id: ab
    property string icon
    property string tip: ""
    property var hoverSource: abArea
    property int tipAlign: 0
    signal clicked()
    width: 28; height: 28
    radius: 8
    color: Qt.rgba(1, 1, 1, abArea.containsMouse ? 0.08 : 0)
    scale: abArea.pressed ? 0.97 : 1
    Behavior on color { ColorAnimation { duration: Theme.colorMs } }
    Behavior on scale { NumberAnimation { duration: Theme.pressMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
    Icon { anchors.centerIn: parent; name: ab.icon; size: 15; color: abArea.containsMouse ? Theme.textPrimary : Theme.textTertiary }
    MouseArea { id: abArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ab.clicked() }
    activeFocusOnTab: ab.enabled && ab.icon !== ""
    Accessible.ignored: ab.icon === ""
    Accessible.role: Accessible.Button
    Accessible.name: ab.tip || ab.icon
    Accessible.onPressAction: ab.clicked()
    Keys.onPressed: e => { if (e.key === Qt.Key_Space || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { ab.clicked(); e.accepted = true; } }
    FocusRing {}

    property bool tipShown: false
    Timer { id: tipDelay; interval: Theme.tipMs; onTriggered: ab.tipShown = true }
    Connections {
        target: ab.hoverSource
        function onContainsMouseChanged() {
            if (ab.hoverSource.containsMouse && ab.tip !== "") tipDelay.restart();
            else { tipDelay.stop(); ab.tipShown = false; }
        }
    }
    Rectangle {
        readonly property bool show: ab.tipShown
        visible: opacity > 0.01
        opacity: show ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: ab.tipShown ? Theme.enterMs : Theme.exitMs } }
        anchors.bottom: parent.top
        anchors.bottomMargin: 6
        anchors.horizontalCenter: ab.tipAlign === 0 ? parent.horizontalCenter : undefined
        anchors.right: ab.tipAlign === 1 ? parent.right : undefined
        anchors.left: ab.tipAlign === -1 ? parent.left : undefined
        width: tipLabel.implicitWidth + 14
        height: 22
        radius: 6
        color: Qt.rgba(0.15, 0.15, 0.18, 0.98)
        border.width: 1
        border.color: Theme.edge(1)
        z: 60
        Label { id: tipLabel; anchors.centerIn: parent; text: ab.tip; size: Theme.tFootnote; color: Theme.textPrimary }
    }
}
