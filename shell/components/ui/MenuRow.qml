import QtQuick
import Quickshell.Widgets
import qs.config
import qs.components

Item {
    id: row

    property string kind: "item"
    property bool checked: false
    property string glyph: ""
    property string icon: ""
    property string text: ""
    property string shortcut: ""
    property var keys: []
    property bool submenu: false
    property bool danger: false
    property bool can: true
    property bool lead: true
    property bool selected: false
    signal activated()
    signal pointed(bool on)

    readonly property bool sep: kind === "separator"
    readonly property bool heading: kind === "label"
    readonly property real indent: lead ? Theme.sp(28) : Theme.s2
    readonly property real natural: sep ? 0
        : indent + words.implicitWidth + Theme.s2
          + (shortcutLabel.visible ? Theme.s4 + shortcutLabel.implicitWidth : 0)
          + (caps.visible ? Theme.s4 + caps.implicitWidth : 0)
          + (chev.visible ? Theme.s3 + chev.implicitWidth : 0)

    implicitHeight: sep ? Theme.s2 + 1 : heading ? Theme.sp(26) : Theme.sp(30)
    height: implicitHeight

    Rectangle {
        visible: row.sep
        anchors.verticalCenter: parent.verticalCenter
        x: Theme.s1; width: parent.width - 2 * Theme.s1; height: 1
        color: Theme.menuEdge
    }
    Item {
        visible: !row.sep
        anchors.fill: parent
        readonly property string markGlyph: row.kind === "check" ? (row.checked ? "\u{f012c}" : "")
            : row.kind === "radio" ? (row.checked ? "\u{f0765}" : "\u{f0766}") : ""
        Text {
            id: leadGlyph
            textFormat: Text.PlainText
            visible: row.lead && (parent.markGlyph !== "" || (row.glyph !== "" && row.kind === "item"))
            width: row.indent; horizontalAlignment: Text.AlignHCenter
            anchors.verticalCenter: parent.verticalCenter
            text: parent.markGlyph !== "" ? parent.markGlyph : row.glyph
            font.family: Theme.fontGlyph; font.pixelSize: Theme.sp(Theme.glyphS)
            color: !row.can ? Theme.textTertiary : row.danger ? Theme.red : parent.markGlyph !== "" ? Theme.textPrimary : Theme.textSecondary
        }
        IconImage {
            visible: row.lead && !leadGlyph.visible && row.icon !== "" && row.kind === "item"
            opacity: row.can ? 1 : 0.5
            x: (row.indent - implicitSize) / 2
            anchors.verticalCenter: parent.verticalCenter
            implicitSize: Theme.sp(16)
            source: row.icon
            asynchronous: true
        }
        Label {
            id: words
            anchors {
                left: parent.left; leftMargin: row.indent
                right: shortcutLabel.visible ? shortcutLabel.left : caps.visible ? caps.left : chev.visible ? chev.left : parent.right
                rightMargin: shortcutLabel.visible || caps.visible ? Theme.s4 : chev.visible ? Theme.s3 : Theme.s2
                verticalCenter: parent.verticalCenter
            }
            elide: Text.ElideRight
            text: row.text
            size: row.heading ? Theme.tFootnote : Theme.tBody
            weight: row.heading ? Theme.wSemibold : Theme.wRegular
            color: row.heading || !row.can ? Theme.textTertiary : row.danger ? Theme.redText : Theme.textPrimary
        }
        Label {
            id: shortcutLabel
            visible: row.shortcut !== "" && !row.heading
            anchors { right: parent.right; rightMargin: Theme.s2; verticalCenter: parent.verticalCenter }
            text: row.shortcut
            size: Theme.tFootnote
            color: Theme.textTertiary
        }
        Row {
            id: caps
            visible: (row.keys || []).length > 0 && !row.heading
            anchors { right: parent.right; rightMargin: Theme.s2; verticalCenter: parent.verticalCenter }
            spacing: 3
            Repeater { model: row.keys || []; KeyCap { required property string modelData; text: modelData } }
        }
        Text {
            id: chev
            textFormat: Text.PlainText
            visible: row.submenu
            anchors { right: parent.right; rightMargin: Theme.s2; verticalCenter: parent.verticalCenter }
            text: "\u{f0142}"
            font.family: Theme.fontGlyph; font.pixelSize: Theme.sp(Theme.glyphS)
            color: Theme.textTertiary
        }
    }
    MouseArea {
        id: area
        anchors.fill: parent
        enabled: row.can && !row.sep && !row.heading
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onContainsMouseChanged: row.pointed(containsMouse)
        onClicked: row.activated()
    }
    readonly property bool pressed: area.pressed

    Accessible.role: sep ? Accessible.Separator : heading ? Accessible.StaticText : Accessible.MenuItem
    Accessible.name: text + (submenu ? ", submenu" : "")
    Accessible.description: shortcut || (keys || []).join("+")
    Accessible.checkable: kind === "check" || kind === "radio"
    Accessible.checked: checked
    Accessible.selected: selected
    Accessible.ignored: sep
    Accessible.onPressAction: if (can && !sep && !heading) activated()
}
