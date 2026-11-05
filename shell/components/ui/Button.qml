// The rice's one button. Primary (accent) · secondary · danger are the raised
// plate (components/RaisedButton); quiet is text on a hover wash, for the
// third action in a row ("Later", "Details").
//
//   Button { text: "Update 31"; onClicked: … }
//   Button { text: "Keep mine"; kind: "secondary" }
//   Button { text: "Details"; kind: "quiet" }
//   Button { primary: true; … }                  (the older API, same as kind: "primary")
import QtQuick
import qs.config
import qs.components

Item {
    id: b
    property string text
    property string glyph: ""
    property string kind: primary ? "primary" : "secondary"   // primary · secondary · danger · quiet
    property bool primary: false
    property bool enabled: true
    property int size: 13
    signal clicked()

    implicitHeight: 34
    implicitWidth: kind === "quiet" ? quiet.implicitWidth : raised.implicitWidth

    RaisedButton {
        id: raised
        visible: b.kind !== "quiet"
        anchors.fill: parent
        text: b.text; glyph: b.glyph; kind: b.kind; enabled: b.enabled; size: b.size
        onClicked: b.clicked()
    }
    Rectangle {
        id: quiet
        visible: b.kind === "quiet"
        anchors.fill: parent
        implicitWidth: qrow.implicitWidth + 24
        radius: height / 2
        color: qArea.containsMouse && b.enabled ? Theme.pill : "transparent"
        scale: qArea.pressed && b.enabled ? 0.97 : 1
        Behavior on color { ColorAnimation { duration: Theme.colorMs } }
        Behavior on scale { NumberAnimation { duration: Theme.pressMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
        Row {
            id: qrow
            anchors.centerIn: parent
            spacing: 6
            Text { visible: b.glyph !== ""; anchors.verticalCenter: parent.verticalCenter; text: b.glyph; font.family: Theme.fontGlyph; font.pixelSize: b.size; color: b.enabled ? Theme.textSecondary : Theme.textTertiary }
            Label { anchors.verticalCenter: parent.verticalCenter; text: b.text; size: b.size; weight: Theme.wMedium; color: b.enabled ? Theme.textSecondary : Theme.textTertiary }
        }
        MouseArea { id: qArea; anchors.fill: parent; hoverEnabled: true; enabled: b.enabled; cursorShape: Qt.PointingHandCursor; onClicked: b.clicked() }
        activeFocusOnTab: b.kind === "quiet"
        Accessible.role: Accessible.Button
        Accessible.name: b.text
        Accessible.onPressAction: if (b.enabled) b.clicked()
        Keys.onPressed: e => { if (b.enabled && (e.key === Qt.Key_Space || e.key === Qt.Key_Return || e.key === Qt.Key_Enter)) { b.clicked(); e.accepted = true; } }
        FocusRing {}
    }
}
