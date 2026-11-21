import QtQuick
import qs.config

Item {
    id: b
    property string text
    property string glyph: ""
    property string kind: "primary"
    property bool enabled: true
    property int size: 13
    signal clicked()

    implicitHeight: 34
    implicitWidth: Math.max(88, row.implicitWidth + 30)

    readonly property bool pressed: area.pressed && enabled
    readonly property bool lit: area.containsMouse && enabled
    readonly property color fill: !enabled ? Qt.rgba(1, 1, 1, 0.08)
        : kind === "danger" ? Theme.red
        : kind === "secondary" ? Qt.rgba(1, 1, 1, 0.12)
        : Theme.accent
    readonly property bool solid: enabled && kind !== "secondary"
    readonly property color ink: !enabled ? Theme.textTertiary
        : kind === "secondary" ? Theme.textPrimary
        : kind === "danger" ? Theme.onDanger
        : Theme.onAccent

    Item {
        id: plate
        anchors.fill: parent
        scale: b.pressed && !Theme.reduceMotion ? 0.97 : 1
        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }

        Repeater {
            model: b.solid ? 3 : 1
            Rectangle {
                required property int index
                readonly property real s: index * 2
                x: -s; y: -s + 1 + index * 2
                width: plate.width + s * 2; height: plate.height + s * 2
                radius: height / 2
                color: Qt.rgba(0, 0, 0, (b.pressed ? 0.04 : 0.12) / (index + 1))
                Behavior on color { ColorAnimation { duration: 200 } }
            }
        }
        Rectangle {
            id: face
            anchors.fill: parent
            radius: height / 2
            color: b.lit && b.solid ? Qt.lighter(b.fill, 1.08) : b.lit ? Qt.rgba(1, 1, 1, 0.18) : b.fill
            Behavior on color { ColorAnimation { duration: 140 } }
            border.width: 1
            border.color: b.solid ? Qt.darker(b.fill, 1.45) : Qt.rgba(1, 1, 1, 0.1)
        }
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: height / 2
            opacity: b.pressed ? 0.4 : 1
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, b.solid ? 0.22 : 0.10) }
                GradientStop { position: 0.08; color: Qt.rgba(1, 1, 1, b.solid ? 0.10 : 0.04) }
                GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.0) }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, b.solid ? 0.08 : 0.04) }
            }
        }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6
        Text {
            textFormat: Text.PlainText
            visible: b.glyph !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: b.glyph
            font.family: Theme.fontGlyph; font.pixelSize: b.size
            color: b.ink
        }
        Label {
            anchors.verticalCenter: parent.verticalCenter
            text: b.text
            size: b.size
            weight: b.kind === "secondary" ? Theme.wMedium : Theme.wSemibold
            color: b.ink
        }
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: b.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (b.enabled) b.clicked()
    }
    Accessible.role: Accessible.Button
    Accessible.name: b.text
    Accessible.onPressAction: if (b.enabled) b.clicked()
}
