// One row of the clipboard list: a section header, or an entry with its
// kind (thumbnail for images, swatch for colours, a glyph otherwise), the
// text with search matches marked, and what it is / when it was copied.
// Hovered: its quick actions (pin, open, delete) replace the time. Alt held:
// the first nine show the number that pastes them (⌥1…⌥9). On open, the
// first rows arrive 18ms apart (the panel's reveal clock).
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
    readonly property int rank: header ? -1 : panel.entries.indexOf(r)
    readonly property alias markItem: mark

    width: ListView.view ? ListView.view.width : 0
    height: header ? 30 : 48

    onSelectedChanged: if (selected) panel.selRow = row
    Component.onCompleted: if (selected) panel.selRow = row
    Component.onDestruction: if (panel.selRow === row) panel.selRow = null

    // Gradual reveal on open: a short drift up, a step apart.
    readonly property real shown: panel.reveal(Math.min(index, 10) * 18)
    opacity: shown
    transform: Translate { y: (1 - row.shown) * 6 }

    // ── Section header ───────────────────────────────────────────────────
    Label {
        visible: row.header
        x: 12
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 7
        text: (row.r.header || "").toUpperCase()
        size: 11
        weight: Theme.wSemibold
        extraTracking: 0.6
        color: Theme.textTertiary
    }

    // ── Entry ────────────────────────────────────────────────────────────
    Rectangle {
        visible: !row.header
        anchors.fill: parent
        anchors.topMargin: 1
        anchors.bottomMargin: 1
        radius: 12
        color: row.selected ? Qt.alpha(Theme.blue, 0.24) : hover.hovered ? Qt.rgba(1, 1, 1, 0.055) : "transparent"
        border.width: row.selected ? 1 : 0
        border.color: Qt.alpha(Theme.blue, 0.42)
        Behavior on color { ColorAnimation { duration: 80 } }
    }
    HoverHandler { id: hover; enabled: !row.header }
    TapHandler {
        enabled: !row.header
        onTapped: row.panel.select(row.r.key)
        onDoubleTapped: { row.panel.select(row.r.key); row.panel.run("paste"); }
    }

    // Kind: a thumbnail, a swatch, or a glyph on a tile.
    Item {
        id: mark
        visible: !row.header
        x: 8
        anchors.verticalCenter: parent.verticalCenter
        width: 34; height: 34

        ClippingRectangle {
            visible: row.e && row.e.kind === "image"
            anchors.fill: parent
            radius: 8
            color: Qt.rgba(1, 1, 1, 0.08)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.10)
            Image {
                id: thumb
                anchors.fill: parent
                source: row.e && row.e.kind === "image" ? Clipboard.thumb(row.e) : ""
                // Device pixels, twice over: crisp at 1.33× and on zoom.
                sourceSize: Qt.size(96, 96)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                smooth: true
                mipmap: true
                opacity: status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 120 } }
            }
            Skeleton { anchors.fill: parent; visible: thumb.status !== Image.Ready; radius: 8 }
        }
        Rectangle {
            visible: row.e && row.e.kind === "color"
            anchors.fill: parent
            radius: 9
            color: row.e && row.e.kind === "color" ? row.panel.colorOf(row.e.preview) : "transparent"
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.18)
        }
        Rectangle {
            visible: row.e && row.e.kind !== "image" && row.e.kind !== "color"
            anchors.fill: parent
            radius: 9
            color: row.e && row.e.secret ? Qt.alpha(Theme.orange, 0.16) : Qt.alpha(row.panel.toneOf(row.e), 0.14)
            Text {
                anchors.centerIn: parent
                text: row.e ? row.panel.glyphOf(row.e) : ""
                font.family: Theme.fontGlyph
                font.pixelSize: 16
                color: row.e && row.e.secret ? Theme.orange : row.panel.toneOf(row.e)
            }
        }
    }

    Label {
        id: title
        visible: !row.header
        anchors { left: mark.right; leftMargin: 11; right: trail.left; rightMargin: 8 }
        y: 7
        elide: Text.ElideRight
        textFormat: Text.StyledText
        text: !row.e ? ""
            : row.e.kind === "image" ? "Image" + (row.e.dims ? "  " + row.e.dims.replace("x", " × ") : "")
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
        y: 26
        elide: Text.ElideRight
        text: row.e ? row.panel.metaOf(row.e) : ""
        size: 11
        color: Theme.textTertiary
    }

    // Trailing: ⌥n while Alt is held, quick actions on hover, else the pin.
    Item {
        id: trail
        visible: !row.header
        anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
        width: row.panel.altHeld && row.rank >= 0 && row.rank < 9 ? 30 : hover.hovered ? quick.width : row.pinned ? 16 : 0
        height: 26

        KeyCap {
            visible: row.panel.altHeld && row.rank >= 0 && row.rank < 9
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            text: "⌥" + (row.rank + 1)
        }
        Row {
            id: quick
            visible: hover.hovered && !row.panel.altHeld
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 2
            Repeater {
                model: [
                    { a: "pin", g: "\u{f0403}", t: row.pinned ? "Unpin" : "Pin", k: ["⌃", "P"] },
                    { a: "open", g: "\u{f03cc}", t: "Open with its app", k: ["⌃", "↵"] },
                    { a: "delete", g: "\u{f0a7a}", t: "Delete", k: ["⇧", "⌦"] }
                ]
                Rectangle {
                    id: q
                    required property var modelData
                    width: 26; height: 26; radius: 8
                    color: qa.containsMouse ? (q.modelData.a === "delete" ? Qt.alpha(Theme.red, 0.25) : Qt.rgba(1, 1, 1, 0.12)) : "transparent"
                    scale: qa.pressed ? 0.92 : 1
                    Behavior on scale { NumberAnimation { duration: Theme.pressMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                    Text {
                        anchors.centerIn: parent
                        text: q.modelData.g
                        font.family: Theme.fontGlyph
                        font.pixelSize: 13
                        color: q.modelData.a === "pin" && row.pinned ? Theme.yellow : qa.containsMouse && q.modelData.a === "delete" ? Theme.red : Theme.textSecondary
                    }
                    MouseArea {
                        id: qa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onContainsMouseChanged: row.panel.tip(q, containsMouse, q.modelData.t, q.modelData.k)
                        onClicked: { row.panel.tip(q, false); row.panel.select(row.r.key); row.panel.run(q.modelData.a); }
                    }
                }
            }
        }
        Text {
            visible: row.pinned && !hover.hovered && !(row.panel.altHeld && row.rank < 9)
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            text: "\u{f0403}"
            font.family: Theme.fontGlyph
            font.pixelSize: 13
            color: Theme.yellow
        }
    }
}
