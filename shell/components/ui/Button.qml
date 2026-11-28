// kuwai's one button. Primary (accent) · secondary · danger are the raised
// plate (components/RaisedButton); quiet is text on a hover wash, for the
// third action in a row ("Later", "Details").
//
//   Button { text: "Update 31"; onClicked: … }
//   Button { text: "Keep mine"; kind: "secondary" }
//   Button { text: "Details"; kind: "quiet" }
//   Button { primary: true; … }                  (the older API, same as kind: "primary")
//   Button { kind: "quiet"; glyph: "…"; label: "Check again"; busy: checking }
//                                                 an icon button (shadcn's size="icon"): square,
//                                                 `label` names it for screen readers and its tip
//   Button { kind: "quiet"; glyph: "…"; tone: Theme.orange; text: "Line 12" }
//                                                 a quiet action whose mark carries a state's colour
import QtQuick
import qs.config
import qs.components

FocusScope {
    id: b
    property string text
    property string glyph: ""
    property string icon: ""
    property string iconStyle: "bold"
    property string kind: primary ? "primary" : "secondary"   // primary · secondary · danger · quiet
    property bool primary: false
    property bool enabled: true
    property bool elideText: false
    property int size: Theme.tBody
    property string label: ""               // what it does, when the face is only a glyph
    property color tone: Theme.textSecondary // quiet: the glyph's colour (a state's tone)
    property bool busy: false                // quiet: the glyph turns (a check running)
    readonly property bool iconOnly: text === "" && (glyph !== "" || icon !== "")
    readonly property bool hovered: kind === "quiet" ? qArea.containsMouse : raised.lit
    signal clicked()
    onBusyChanged: if (!busy) { qglyph.rotation = 0; qphicon.rotation = 0; }

    implicitHeight: Theme.sp(34)
    implicitWidth: kind === "quiet" ? (iconOnly ? implicitHeight : quiet.implicitWidth) : raised.implicitWidth

    RaisedButton {
        id: raised
        visible: b.kind !== "quiet"
        focus: b.kind !== "quiet"
        anchors.fill: parent
        text: b.text; glyph: b.glyph; icon: b.icon; iconStyle: b.iconStyle; kind: b.kind; enabled: b.enabled; elideText: b.elideText; size: b.size
        onClicked: b.clicked()
    }
    Rectangle {
        id: quiet
        visible: b.kind === "quiet"
        focus: b.kind === "quiet"
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
            Icon {
                id: qphicon
                visible: b.icon !== ""
                anchors.verticalCenter: parent.verticalCenter
                name: b.icon
                style: b.iconStyle
                size: Theme.sp(b.iconOnly ? Math.max(b.size, Theme.glyphS) : b.size)
                color: b.enabled ? b.tone : Theme.textTertiary
                RotationAnimation on rotation { running: b.busy && !Theme.reduceMotion; loops: Animation.Infinite; from: 0; to: 360; duration: Theme.spinMs }
            }
            Text {
                id: qglyph
                textFormat: Text.PlainText; visible: b.icon === "" && b.glyph !== ""; anchors.verticalCenter: parent.verticalCenter
                text: b.glyph; font.family: Theme.fontGlyph; font.pixelSize: Theme.sp(b.iconOnly ? Math.max(b.size, Theme.glyphS) : b.size)
                color: b.enabled ? b.tone : Theme.textTertiary
                RotationAnimation on rotation { running: b.busy && !Theme.reduceMotion; loops: Animation.Infinite; from: 0; to: 360; duration: Theme.spinMs }
            }
            Label { visible: b.text !== ""; anchors.verticalCenter: parent.verticalCenter; text: b.text; size: b.size; weight: Theme.wMedium; color: b.enabled ? Theme.textSecondary : Theme.textTertiary }
        }
        MouseArea { id: qArea; anchors.fill: parent; hoverEnabled: true; enabled: b.enabled; cursorShape: Qt.PointingHandCursor; onClicked: b.clicked() }
        activeFocusOnTab: b.kind === "quiet"
        Accessible.role: Accessible.Button
        Accessible.name: b.text || b.label
        Accessible.description: b.busy ? "busy" : ""
        Accessible.onPressAction: if (b.enabled) b.clicked()
        Keys.onPressed: e => { if (b.enabled && (e.key === Qt.Key_Space || e.key === Qt.Key_Return || e.key === Qt.Key_Enter)) { b.clicked(); e.accepted = true; } }
        FocusRing {}
    }
    Tip { text: b.label; shown: b.iconOnly && b.label !== "" && qArea.containsMouse; below: true }
}
