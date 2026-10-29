// One row of the clipboard list: a section header, or an entry with its
// kind (thumbnail for images, swatch for colours, a glyph otherwise), the
// text with search matches marked, and what it is / when it was copied.
import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.config
import qs.components
import qs.services

Item {
    id: row

    required property var modelData
    required property int index
    property var panel
    readonly property var r: modelData
    readonly property bool header: !!r.header
    readonly property var e: r.e || null
    readonly property bool selected: !header && panel.selKey === r.key
    readonly property bool pinned: e ? Clipboard.isPinned(e) : false
    readonly property bool masked: e ? e.secret && !(selected && panel.revealed) : false

    width: ListView.view ? ListView.view.width : 0
    height: header ? 30 : 46

    // ── Section header ───────────────────────────────────────────────────
    Label {
        visible: row.header
        x: 10
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 6
        text: row.r.header || ""
        size: 11
        weight: Theme.wSemibold
        color: Theme.textTertiary
    }

    // ── Entry ────────────────────────────────────────────────────────────
    Rectangle {
        visible: !row.header
        anchors.fill: parent
        anchors.topMargin: 1
        anchors.bottomMargin: 1
        radius: 12
        color: row.selected ? Qt.alpha(Theme.blue, 0.26) : hover.hovered ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
        border.width: row.selected ? 1 : 0
        border.color: Qt.alpha(Theme.blue, 0.45)
    }
    HoverHandler { id: hover; enabled: !row.header }
    TapHandler {
        enabled: !row.header
        onTapped: row.panel.select(row.r.key)
        onDoubleTapped: { row.panel.select(row.r.key); row.panel.act("paste"); }
    }

    // Kind: a thumbnail, a swatch, or a glyph on a tile.
    Item {
        id: mark
        visible: !row.header
        x: 8
        anchors.verticalCenter: parent.verticalCenter
        width: 32; height: 32

        ClippingRectangle {
            visible: row.e && row.e.kind === "image"
            anchors.fill: parent
            radius: 8
            color: Qt.rgba(1, 1, 1, 0.08)
            Image {
                anchors.fill: parent
                source: row.e && row.e.kind === "image" ? Clipboard.thumb(row.e) : ""
                sourceSize: Qt.size(64, 64)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
            }
        }
        Rectangle {
            visible: row.e && row.e.kind === "color"
            anchors.fill: parent
            radius: 8
            color: row.e && row.e.kind === "color" ? row.panel.colorOf(row.e.preview) : "transparent"
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.18)
        }
        Rectangle {
            visible: row.e && row.e.kind !== "image" && row.e.kind !== "color"
            anchors.fill: parent
            radius: 8
            color: row.e && row.e.secret ? Qt.alpha(Theme.orange, 0.18) : Qt.rgba(1, 1, 1, 0.08)
            Text {
                anchors.centerIn: parent
                text: row.e ? row.panel.glyphOf(row.e) : ""
                font.family: Theme.fontGlyph
                font.pixelSize: 15
                color: row.e && row.e.secret ? Theme.orange : Theme.textSecondary
            }
        }
    }

    Label {
        id: title
        visible: !row.header
        anchors { left: mark.right; leftMargin: 10; right: pin.left; rightMargin: 6 }
        y: 6
        elide: Text.ElideRight
        textFormat: Text.StyledText
        text: !row.e ? ""
            : row.e.kind === "image" ? "Image"
            : row.masked ? "•••••••••••• (looks like a secret)"
            : Clipboard.marked(row.e.preview.replace(/\s+/g, " ").slice(0, 160), row.r.m ? row.r.m.pos : [], Theme.yellow)
        size: 13
        weight: row.selected ? Theme.wMedium : Theme.wRegular
        color: Theme.textPrimary
        font.family: row.e && row.e.kind === "code" && !row.masked ? Theme.fontMono : Theme.fontText
    }
    Label {
        visible: !row.header
        anchors { left: title.left; right: title.right }
        y: 25
        elide: Text.ElideRight
        text: row.e ? row.panel.metaOf(row.e) : ""
        size: 11
        color: Theme.textTertiary
    }
    Text {
        id: pin
        visible: !row.header
        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
        width: row.pinned ? implicitWidth : 0
        text: row.pinned ? "\u{f0403}" : ""                // pin
        font.family: Theme.fontGlyph
        font.pixelSize: 13
        color: Theme.yellow
    }
}
