// Deliberate destructive confirmation. A held/repeated key cannot accept it.
import QtQuick
import QtQuick.Controls
import qs.config

Dialog {
    id: dialog
    property string message: ""
    property string confirmLabel: "Forget"
    signal confirmed()
    modal: true
    focus: true
    standardButtons: Dialog.Cancel | Dialog.Ok
    contentItem: Label { text: dialog.message; wrapMode: Text.WordWrap; implicitWidth: 300 }
    onOpened: {
        standardButton(Dialog.Ok).text = confirmLabel;
        standardButton(Dialog.Cancel).forceActiveFocus();
    }
    onAccepted: confirmed()
    Keys.onPressed: e => {
        if (e.isAutoRepeat && (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space)) e.accepted = true;
    }
}
