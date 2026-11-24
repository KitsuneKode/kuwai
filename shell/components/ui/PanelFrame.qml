import QtQuick
import qs.config
import qs.components

FocusScope {
    id: frame
    property string title: ""
    property string subtitle: ""
    property bool canBack: false
    property var hints: []
    default property alias body: bodySlot.data
    signal back()

    implicitWidth: Theme.panelM
    implicitHeight: col.implicitHeight + Theme.s5 * 2

    Keys.onPressed: e => {
        if (e.key === Qt.Key_Escape && frame.canBack) {
            e.accepted = true;
            frame.back();
        }
    }

    Column {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.s5 }
        spacing: Theme.s3

        Row {
            visible: frame.title !== "" || frame.canBack
            width: parent.width
            spacing: Theme.s2

            Button {
                visible: frame.canBack
                text: "Back"
                onClicked: frame.back()
            }

            Column {
                spacing: Theme.s1
                Label {
                    visible: frame.title !== ""
                    text: frame.title
                    size: Theme.tTitle3
                    weight: Theme.wSemibold
                    color: Theme.textPrimary
                }
                Label {
                    visible: frame.subtitle !== ""
                    text: frame.subtitle
                    size: Theme.tFootnote
                    color: Theme.textSecondary
                }
            }
        }

        Item {
            id: bodySlot
            width: parent.width
            implicitHeight: childrenRect.height
            height: implicitHeight
        }

        KeyHints {
            visible: frame.hints && frame.hints.length > 0
            width: parent.width
            hints: frame.hints
        }
    }
}
