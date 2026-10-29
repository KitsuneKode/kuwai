// A keyboard key, drawn the way macOS menus and cheatsheets show them: a
// small rounded cap with the key's symbol in SF Pro (which carries Apple's
// own ⌘ ⌥ ⇧ ⌃ ↩ ⌫ ⌦ ⇥ ⎋ glyphs), centred, never narrower than it is tall.
//
//   KeyCap { text: "↩" }    KeyCap { text: "Super" }   (shown as ⌘; Ctrl ⌃, Shift ⇧, Alt ⌥, Esc ⎋)
import QtQuick
import qs.config

Rectangle {
    id: cap
    property string text
    property int size: 11
    // Modifier and special keys as macOS writes them (Super is ⌘ here).
    readonly property string glyph: ({ Super: "⌘", Meta: "⌘", Cmd: "⌘", Win: "⌘", Ctrl: "⌃", Control: "⌃", Shift: "⇧",
        Alt: "⌥", Option: "⌥", Esc: "⎋", Escape: "⎋", Enter: "↩", Return: "↩", Tab: "⇥", Backspace: "⌫", Delete: "⌦",
        Up: "↑", Down: "↓", Left: "←", Right: "→", "^": "⌃" })[text] || text
    readonly property bool word: glyph.length > 1

    height: size + 9
    width: Math.max(height, label.implicitWidth + (word ? 10 : 6))
    radius: 5
    color: Qt.rgba(1, 1, 1, 0.08)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.10)

    // A hairline of light along the bottom edge: the cap reads as raised.
    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 1 }
        height: 1
        radius: 0.5
        color: Qt.rgba(0, 0, 0, 0.25)
    }

    Label {
        id: label
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -0.5
        text: cap.glyph
        size: cap.size
        weight: cap.word ? Theme.wMedium : Theme.wSemibold
        color: Theme.textSecondary
    }
}
