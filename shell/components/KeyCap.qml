// A keyboard key as a PC keyboard prints it: a small rounded cap with the
// key's name (Super, Ctrl, Alt, Shift, Esc, Tab), or its symbol where the
// keyboard prints one (↵ ⌫ ↑ ↓ ← →), centred, never narrower than it is tall.
//
//   KeyCap { text: "↵" }    KeyCap { text: "super" }   (shown as Super; "⌘" and "Cmd" too)
import QtQuick
import qs.config

Rectangle {
    id: cap
    property string text
    property int size: Theme.tCaption
    readonly property var names: ({ "super": "Super", meta: "Super", cmd: "Super", win: "Super", "⌘": "Super",
        ctrl: "Ctrl", control: "Ctrl", "⌃": "Ctrl", "^": "Ctrl", shift: "Shift", "⇧": "Shift", alt: "Alt", option: "Alt", "⌥": "Alt",
        esc: "Esc", escape: "Esc", "⎋": "Esc", enter: "↵", "return": "↵", "↩": "↵", tab: "Tab", "⇥": "Tab",
        backspace: "⌫", "delete": "Del", del: "Del", "⌦": "Del", up: "↑", down: "↓", left: "←", right: "→", space: "Space" })
    readonly property string glyph: names[String(text).toLowerCase()] || text
    readonly property bool word: glyph.length > 1

    height: size + 9
    width: Math.max(height, label.implicitWidth + (word ? 10 : 6))
    radius: 5
    color: Theme.wash(2)
    border.width: 1
    border.color: Theme.edge(1)

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
