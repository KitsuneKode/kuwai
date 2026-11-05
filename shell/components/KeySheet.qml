// Every key a surface knows, on one sheet (?, F1 or ⌃/ toggles it).
// Grouped in columns, keys drawn as keycaps, the sheet fading in over a
// backdrop with a 2% rise (140ms ease-out; 90ms out). Any key or click closes.
//
//   KeySheet {
//       sections: [{ title: "Paste", items: [{ k: ["↵"], t: "Paste into the window you came from" }, …] }, …]
//       columns: 3
//   }
import QtQuick
import qs.config

Item {
    id: sheet

    property var sections: []
    property int columns: 3
    property string title: "Keyboard shortcuts"
    property bool open: false

    anchors.fill: parent
    z: 40
    visible: opacity > 0.01
    opacity: open ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: sheet.open ? 140 : 90; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }

    // Keys from whoever owns the keyboard: anything closes it.
    function key(event) {
        if (!open) return false;
        open = false;
        return true;
    }

    Rectangle {
        anchors.fill: parent
        radius: 24
        color: Qt.rgba(0.05, 0.05, 0.07, 0.86)
        MouseArea { anchors.fill: parent; onClicked: sheet.open = false }
    }

    Item {
        id: body
        anchors.fill: parent
        anchors.margins: 28
        transform: Translate { y: sheet.open || Theme.reduceMotion ? 0 : 8 }

        Label {
            id: head
            text: sheet.title
            size: Theme.tTitle3
            weight: Theme.wSemibold
        }
        Label {
            anchors { right: parent.right; verticalCenter: head.verticalCenter }
            text: "any key to close"
            size: 11
            color: Theme.textTertiary
        }

        Row {
            anchors { left: parent.left; right: parent.right; top: head.bottom; topMargin: 18 }
            spacing: 28
            readonly property real colW: (body.width - spacing * (sheet.columns - 1)) / sheet.columns
            Repeater {
                model: sheet.columns
                Column {
                    id: col
                    required property int index
                    width: parent.colW
                    spacing: 18
                    Repeater {
                        model: sheet.sections.filter((s, i) => i % sheet.columns === col.index)
                        Column {
                            id: sec
                            required property var modelData
                            width: col.width
                            spacing: 7
                            Label {
                                text: sec.modelData.title.toUpperCase()
                                size: 11
                                weight: Theme.wSemibold
                                extraTracking: 0.8
                                color: Theme.textTertiary
                            }
                            Repeater {
                                model: sec.modelData.items
                                Item {
                                    id: line
                                    required property var modelData
                                    width: sec.width
                                    height: 22
                                    Row {
                                        id: caps
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 3
                                        Repeater { model: line.modelData.k; KeyCap { required property string modelData; text: modelData } }
                                    }
                                    Label {
                                        anchors { left: parent.left; leftMargin: 92; right: parent.right; verticalCenter: parent.verticalCenter }
                                        elide: Text.ElideRight
                                        text: line.modelData.t
                                        size: 12
                                        color: Theme.textSecondary
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
