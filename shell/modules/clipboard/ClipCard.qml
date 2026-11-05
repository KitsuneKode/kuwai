// One card on the island's shelf: the entry shown as what it is. An image
// full-bleed, a colour as a swatch with its hex, code highlighted in SF
// Mono, a link as its domain and path, text as its first lines, a secret
// masked. Under it: what it is and when it was copied. A section header
// (Pinned, Today…) is a slim vertical label between cards.
//
// Selected: a blue ring and full size; the rest sit at 97%, so the eye
// lands on one card. Hovered: pin / open / delete on the card's corner.
// Alt held: the ⌥n that pastes it. On open the first cards rise in 22ms
// apart.
import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.config
import qs.components
import qs.services

Item {
    id: card

    required property var modelData
    required property int index
    property var panel
    readonly property var r: modelData
    readonly property bool header: !!r.header
    readonly property var e: r.e || null
    readonly property bool selected: !header && panel.selKey === r.key
    readonly property bool marked: !header && !!panel.marked[r.key]
    readonly property bool pinned: e ? Clipboard.isPinned(e) : false
    readonly property bool masked: e ? e.secret && !(selected && panel.revealed) : false
    readonly property int rank: header ? -1 : panel.entries.indexOf(r)
    readonly property alias markItem: face
    // Files: what was copied, checked now (exists? moved?).
    readonly property bool isFiles: e ? (e.kind === "files" || e.kind === "path") : false
    readonly property var fileList: isFiles ? (Clipboard.fileInfo[Clipboard.ref(e)] || null) : null
    readonly property var file0: fileList && fileList.length ? fileList[0] : null
    readonly property int missing: fileList ? fileList.filter(f => !f.exists).length : 0
    function bytes(n) { return n > 1048576 ? (n / 1048576).toFixed(1) + " MB" : n > 1024 ? Math.round(n / 1024) + " KB" : (n || 0) + " B"; }

    width: header ? 30 : 184
    height: ListView.view ? ListView.view.height : 220

    onSelectedChanged: if (selected) panel.selRow = card
    Component.onCompleted: {
        if (selected) panel.selRow = card;
        if (isFiles) Clipboard.files(e);
    }
    Component.onDestruction: if (panel.selRow === card) panel.selRow = null

    // Gradual reveal: rise and settle, a step apart.
    readonly property real shown: panel.reveal(Math.min(index, 8) * 22)
    opacity: shown
    transform: Translate { y: (1 - card.shown) * 10 }

    // ── Section label, standing up between cards ──────────────────────────
    Label {
        visible: card.header
        anchors.centerIn: parent
        rotation: -90
        text: (card.r.header || "").toUpperCase()
        size: 11
        weight: Theme.wSemibold
        extraTracking: 1.2
        color: Theme.textTertiary
    }

    // ── The card ─────────────────────────────────────────────────────────
    Item {
        id: body
        visible: !card.header
        anchors.fill: parent
        anchors.topMargin: 4
        anchors.bottomMargin: 4
        scale: card.selected || Theme.reduceMotion ? 1 : (hover.hovered ? 0.985 : 0.965)
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }

        Rectangle {
            id: plate
            anchors.fill: parent
            radius: 18
            color: Qt.rgba(1, 1, 1, card.selected ? 0.10 : 0.06)
            border.width: card.selected || card.marked ? 2 : 1
            border.color: card.selected ? Qt.alpha(Theme.blue, 0.85) : card.marked ? Qt.alpha(Theme.accent, 0.7) : Qt.rgba(1, 1, 1, 0.08)
            Behavior on color { ColorAnimation { duration: Theme.colorMs } }
        }
        HoverHandler { id: hover }
        TapHandler {
            acceptedModifiers: Qt.NoModifier
            onTapped: { card.panel.clearMarks(); card.panel.select(card.r.key); }
            onDoubleTapped: { card.panel.select(card.r.key); card.panel.run("paste"); }
        }
        TapHandler {
            acceptedModifiers: Qt.ControlModifier
            onTapped: { card.panel.mark(card.r.key); card.panel.select(card.r.key); }
        }
        TapHandler {
            acceptedModifiers: Qt.ShiftModifier
            onTapped: { card.panel.mark(card.panel.selKey, true); card.panel.markRange(card.r.key); card.panel.focusSearch(); }
        }
        // Marked: a check in the theme's colour, top left.
        Rectangle {
            z: 5
            visible: card.marked
            x: 12; y: 12
            width: 20; height: 20; radius: 10
            color: Theme.accent
            border.width: 2; border.color: Qt.rgba(0, 0, 0, 0.5)
            scale: card.marked ? 1 : 0.6
            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
            Text { anchors.centerIn: parent; text: "\u{f012c}"; font.family: Theme.fontGlyph; font.pixelSize: 12; color: Theme.onAccent }
        }

        // Face: the entry itself.
        ClippingRectangle {
            id: face
            x: 6; y: 6
            width: parent.width - 12
            height: parent.height - 66
            radius: 13
            color: card.e && card.e.kind === "color" ? card.panel.colorOf(card.e.preview)
                 : card.e && card.e.kind === "image" ? Qt.rgba(0, 0, 0, 0.25)
                 : card.e && card.e.secret ? Qt.alpha(Theme.orange, 0.10)
                 : Qt.rgba(0, 0, 0, 0.18)

            Image {
                id: img
                visible: card.e && card.e.kind === "image"
                anchors.fill: parent
                source: visible ? Clipboard.thumb(card.e) : ""
                sourceSize: Qt.size(Math.round(face.width * 2), Math.round(face.height * 2))
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                smooth: true
                mipmap: true
                opacity: status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 140 } }
            }
            Skeleton { anchors.fill: parent; radius: 13; visible: card.e && card.e.kind === "image" && img.status !== Image.Ready }

            // Files: a PDF's first page or the image itself; else its kind.
            Image {
                visible: card.isFiles && !!(card.file0 && card.file0.preview)
                anchors.fill: parent
                source: visible ? "file://" + card.file0.preview : ""
                sourceSize: Qt.size(Math.round(face.width * 2), Math.round(face.height * 2))
                fillMode: Image.PreserveAspectCrop
                verticalAlignment: Image.AlignTop
                asynchronous: true
                smooth: true
                mipmap: true
                opacity: card.missing && card.missing === (card.fileList || []).length ? 0.35 : 1
            }
            Column {
                visible: card.isFiles && !(card.file0 && card.file0.preview)
                anchors.centerIn: parent
                spacing: 6
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: card.file0 && card.file0.dir ? "\u{f024b}" : "\u{f0214}"
                    font.family: Theme.fontGlyph
                    font.pixelSize: 34
                    color: card.file0 && card.file0.dir ? Theme.cyan : Theme.textSecondary
                }
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: card.file0 ? (card.file0.name.split(".").length > 1 && !card.file0.dir ? card.file0.name.split(".").pop().toUpperCase() : card.file0.dir ? "Folder" : "File") : ""
                    size: 11
                    weight: Theme.wSemibold
                    color: Theme.textTertiary
                }
            }
            // How many, and whether they're all still there.
            Rectangle {
                visible: card.isFiles && card.fileList !== null && (card.fileList.length > 1 || card.missing > 0)
                anchors { left: parent.left; bottom: parent.bottom; margins: 8 }
                height: 20; radius: 10
                width: fcount.implicitWidth + 14
                color: card.missing ? Qt.alpha(Theme.red, 0.9) : Qt.rgba(0.08, 0.08, 0.1, 0.9)
                Label {
                    id: fcount
                    anchors.centerIn: parent
                    text: !card.fileList ? "" : card.missing ? (card.missing === card.fileList.length ? "Missing" : card.missing + " missing") : card.fileList.length + " files"
                    size: 11
                    weight: Theme.wSemibold
                    color: "white"
                }
            }

            // Colour: its value on the swatch, in whichever ink reads on it.
            Label {
                visible: card.e && card.e.kind === "color"
                anchors { left: parent.left; bottom: parent.bottom; margins: 10 }
                readonly property color c: card.e && card.e.kind === "color" ? card.panel.colorOf(card.e.preview) : "black"
                text: card.e ? card.e.preview.trim() : ""
                size: 13
                weight: Theme.wSemibold
                font.family: Theme.fontMono
                color: (0.299 * c.r + 0.587 * c.g + 0.114 * c.b) > 0.6 ? "#111114" : "white"
            }

            // Link: domain big, path small.
            Column {
                visible: card.e && card.e.kind === "link" && !card.masked
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 12 }
                spacing: 4
                readonly property var u: card.e && card.e.kind === "link" ? card.e.preview.trim().replace(/^\w+:\/\//, "") : ""
                Text { text: "\u{f0339}"; font.family: Theme.fontGlyph; font.pixelSize: 20; color: Theme.blue }
                Label { width: parent.width; elide: Text.ElideRight; text: parent.u ? parent.u.split("/")[0] : ""; size: 15; weight: Theme.wSemibold }
                Label { width: parent.width; elide: Text.ElideMiddle; text: parent.u ? "/" + parent.u.split("/").slice(1).join("/") : ""; size: 11; color: Theme.textTertiary; visible: text.length > 1 }
            }

            // Code: highlighted (rendered once, cached); text: its first lines.
            TextEdit {
                id: snippet
                visible: card.e && !card.masked && ["code", "text", "email"].includes(card.e.kind)
                anchors { fill: parent; margins: 10 }
                readOnly: true
                activeFocusOnPress: false
                selectByMouse: false
                clip: true
                wrapMode: TextEdit.Wrap
                textFormat: card.rendered ? TextEdit.RichText : TextEdit.PlainText
                text: card.rendered ? card.rendered : (card.e ? card.e.preview.slice(0, 400) : "")
                color: Theme.textPrimary
                font.family: card.e && card.e.kind === "code" ? Theme.fontMono : Theme.fontText
                font.pixelSize: card.e && card.e.kind === "code" ? 10 : 12
                renderType: Text.NativeRendering
            }
            Column {
                visible: card.masked
                anchors.centerIn: parent
                spacing: 6
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "\u{f0306}"; font.family: Theme.fontGlyph; font.pixelSize: 26; color: Theme.orange }
                Label { anchors.horizontalCenter: parent.horizontalCenter; text: "Looks like a secret"; size: 11; color: Theme.orange }
            }
            Text {
                visible: card.e && card.e.kind === "file"
                anchors.centerIn: parent
                text: "\u{f0214}"
                font.family: Theme.fontGlyph
                font.pixelSize: 30
                color: Theme.textTertiary
            }

            // Quick actions on hover, Alt numbers while ⌥ is held.
            Row {
                visible: hover.hovered && !card.panel.altHeld
                anchors { right: parent.right; top: parent.top; margins: 6 }
                spacing: 3
                Repeater {
                    model: [
                        { a: "pin", g: "\u{f0403}", t: card.pinned ? "Unpin" : "Pin", k: ["⌃", "P"] },
                        { a: "open", g: "\u{f03cc}", t: "Open with its app", k: ["⌃", "↵"] },
                        { a: "delete", g: "\u{f0a7a}", t: "Delete", k: ["⇧", "⌦"] }
                    ]
                    Rectangle {
                        id: q
                        required property var modelData
                        width: 26; height: 26; radius: 9
                        color: qa.containsMouse ? (q.modelData.a === "delete" ? Qt.alpha(Theme.red, 0.9) : Qt.rgba(0.25, 0.25, 0.28, 0.98)) : Qt.rgba(0.12, 0.12, 0.14, 0.92)
                        scale: qa.pressed ? 0.92 : 1
                        Behavior on scale { NumberAnimation { duration: Theme.pressMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                        Text {
                            anchors.centerIn: parent
                            text: q.modelData.g
                            font.family: Theme.fontGlyph
                            font.pixelSize: 13
                            color: q.modelData.a === "pin" && card.pinned ? Theme.yellow : Theme.textPrimary
                        }
                        MouseArea {
                            id: qa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onContainsMouseChanged: card.panel.tip(q, containsMouse, q.modelData.t, q.modelData.k)
                            onClicked: { card.panel.tip(q, false); card.panel.select(card.r.key); card.panel.run(q.modelData.a); }
                        }
                    }
                }
            }
            KeyCap {
                visible: card.panel.altHeld && card.rank >= 0 && card.rank < 9
                anchors { right: parent.right; top: parent.top; margins: 8 }
                text: "⌥" + (card.rank + 1)
            }
            Text {
                visible: card.pinned && !hover.hovered
                anchors { right: parent.right; top: parent.top; margins: 8 }
                text: "\u{f0403}"
                font.family: Theme.fontGlyph
                font.pixelSize: 13
                color: Theme.yellow
            }
        }

        // What it is, when it was copied.
        Label {
            id: title
            anchors { left: parent.left; right: parent.right; leftMargin: 12; rightMargin: 12 }
            y: parent.height - 54
            elide: Text.ElideRight
            textFormat: Text.StyledText
            text: !card.e ? ""
                : card.e.kind === "image" ? "Image" + (card.e.dims ? "  " + card.e.dims.replace("x", " × ") : "")
                : card.isFiles && card.file0 ? card.file0.name + (card.fileList.length > 1 ? "  +" + (card.fileList.length - 1) : "")
                : card.masked ? "•••••••••"
                : Clipboard.marked(card.e.preview.replace(/\s+/g, " ").slice(0, 120), card.r.m ? card.r.m.pos : [], Theme.yellow)
            size: 12
            weight: card.selected ? Theme.wSemibold : Theme.wMedium
        }
        Label {
            anchors { left: title.left; right: title.right }
            y: parent.height - 34
            elide: Text.ElideRight
            text: !card.e ? ""
                : card.isFiles && card.file0 ? (card.missing === card.fileList.length ? "Moved or deleted"
                    : [card.file0.dir ? "Folder" : card.file0.type === "application/pdf" ? "PDF" : (card.file0.type.split("/")[1] || "File").toUpperCase(),
                       card.file0.dir ? "" : card.bytes(card.file0.size),
                       card.file0.pages ? card.file0.pages + (card.file0.pages === 1 ? " page" : " pages") : ""].filter(x => x).join("  ·  "))
                : card.panel.metaOf(card.e)
            size: 11
            color: Theme.textTertiary
        }
    }

    // Code gets highlighted once it's on screen (cached per entry).
    property string rendered: ""
    Timer {
        running: !card.header && card.e && card.e.kind === "code" && !card.e.secret && card.rendered === ""
        interval: 80 + card.index * 30
        onTriggered: Clipboard.render(card.e, d => { if (d.kind === "code" || d.kind === "markdown") card.rendered = d.html; })
    }
}
