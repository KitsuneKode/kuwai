// A row of keys and what they do, for a panel opened from the keyboard
// (the launcher's footer, as one piece): "↑↓ Choose  ↩ Go  esc Back".
//   KeyHints { visible: Island.via === "key"; hints: [["↑↓", "Choose"], ["↩", "Go"]] }
import QtQuick
import qs.config

Flow {
    property var hints: []
    width: parent ? parent.width : 0
    spacing: 14
    Repeater {
        model: parent.hints
        Row {
            required property var modelData
            spacing: 6
            KeyCap { anchors.verticalCenter: parent.verticalCenter; text: parent.modelData[0] }
            Label { anchors.verticalCenter: parent.verticalCenter; text: parent.modelData[1]; size: Theme.tSub; color: Theme.textTertiary }
        }
    }
}
