// Quick Look (Space): the selected card grows into the whole island, the
// way Aceternity's expandable card grows out of its list (shared element:
// one rectangle morphing from the card's face to the view) over a backdrop
// that steps the shelf back. Space or Esc folds it back into its card;
// ←→ keep browsing inside it.
//
// What it shows: an image at full resolution, sized to its own aspect; text
// as what it is (bin/rice-render: Markdown rendered with highlighted code
// blocks, code highlighted, a Mermaid diagram drawn), ⌃R for the raw text;
// a colour with its hex, rgb and hsl. ⌃E edits the text in place, ⌃↵ pastes
// the edit, Esc drops it.
import QtQuick
import Quickshell.Widgets
import qs.config
import qs.components
import qs.services

Item {
    id: ql

    property var panel
    property var entry: null
    property bool open: false
    property bool editing: false
    property bool raw: false
    property rect from: Qt.rect(width / 2, height / 2, 32, 32)
    property string full: ""
    property var rendered: ({ kind: "text" })

    anchors.fill: parent
    visible: t.value > 0.002 || open
    z: 25

    Spring { id: t; tier: Theme.springModerate; epsilon: 0.001 }
    onOpenChanged: {
        if (!open) editing = false;
        t.target = open ? 1 : 0;
        if (Theme.reduceMotion) t.settle();
    }
    onEditingChanged: if (editing) { editor.forceActiveFocus(); editor.cursorPosition = editor.length; }
    function lerp(a, b, k) { return a + (b - a) * k; }

    readonly property bool isImage: entry && entry.kind === "image"
    readonly property bool isColor: entry && entry.kind === "color"
    readonly property bool masked: entry && entry.secret && !panel.revealed
    readonly property bool rich: !raw && !editing && !masked && ["markdown", "code", "mermaid"].includes(rendered.kind)
    readonly property var dims: {
        const m = entry && entry.dims ? entry.dims.match(/(\d+)x(\d+)/) : null;
        return m ? { w: +m[1], h: +m[2] } : { w: 4, h: 3 };
    }
    // The view: an image keeps its aspect; everything else gets the room.
    readonly property real pad: 22
    readonly property rect to: {
        const W = width - pad * 2, H = height - pad * 2 - 26;
        if (!isImage) return Qt.rect(pad, pad, W, H);
        const s = Math.min(W / dims.w, H / dims.h, 1.5);
        const w = Math.round(dims.w * s), h = Math.round(dims.h * s);
        return Qt.rect(Math.round((width - w) / 2), Math.round(pad + (H - h) / 2), w, h);
    }

    onEntryChanged: {
        full = "";
        raw = false;
        editing = false;
        rendered = { kind: "text" };
        if (!entry || isImage || entry.kind === "file") return;
        const r = Clipboard.ref(entry);
        Clipboard.fetchText(entry);
        if (!entry.secret) Clipboard.render(entry, d => { if (ql.entry && Clipboard.ref(ql.entry) === r) ql.rendered = d; });
    }
    Connections {
        target: Clipboard
        function onTextReady(ref, text) { if (ql.entry && ref === Clipboard.ref(ql.entry)) ql.full = text; }
    }

    // Backdrop: the shelf steps back.
    Rectangle {
        anchors.fill: parent
        radius: 24
        color: Qt.rgba(0.05, 0.05, 0.07, 0.78 * Math.min(1, t.value))
        MouseArea { anchors.fill: parent; enabled: ql.open; onClicked: ql.open = false }
    }

    ClippingRectangle {
        id: frame
        x: ql.lerp(ql.from.x, ql.to.x, t.value)
        y: ql.lerp(ql.from.y, ql.to.y, t.value)
        width: Math.max(1, ql.lerp(ql.from.width, ql.to.width, t.value))
        height: Math.max(1, ql.lerp(ql.from.height, ql.to.height, t.value))
        radius: ql.lerp(13, ql.isImage ? 14 : 18, Math.min(1, t.value))
        color: ql.isColor && ql.entry ? ql.panel.colorOf(ql.entry.preview)
             : ql.isImage ? Qt.rgba(0, 0, 0, 0.3) : Qt.rgba(0.13, 0.13, 0.16, 0.97)
        border.width: 1
        border.color: ql.editing ? Qt.alpha(Theme.blue, 0.6) : Qt.rgba(1, 1, 1, 0.10 * Math.min(1, t.value))

        Image {
            visible: ql.isImage
            anchors.fill: parent
            source: ql.isImage ? Clipboard.thumb(ql.entry) : ""
            // Decoded at the pixels it lands on, not stretched from a thumbnail.
            sourceSize: Qt.size(Math.round(ql.to.width * 2), Math.round(ql.to.height * 2))
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            smooth: true
            mipmap: true
            retainWhileLoading: true
        }

        // Colour: its values, large, in whichever ink reads on it.
        Column {
            visible: ql.isColor
            anchors.centerIn: parent
            spacing: 6
            opacity: Math.max(0, Math.min(1, (t.value - 0.5) / 0.4))
            readonly property color c: ql.isColor && ql.entry ? ql.panel.colorOf(ql.entry.preview) : "black"
            readonly property color ink: (0.299 * c.r + 0.587 * c.g + 0.114 * c.b) > 0.6 ? "#111114" : "white"
            Repeater {
                model: ql.isColor ? ql.panel.colorValues(parent.c) : []
                Label {
                    required property string modelData
                    required property int index
                    anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined
                    text: modelData
                    size: index === 0 ? 28 : 15
                    weight: index === 0 ? Theme.wBold : Theme.wMedium
                    font.family: Theme.fontMono
                    color: parent ? parent.ink : "white"
                }
            }
        }

        // Rendered: Markdown, highlighted code; or a diagram.
        Flickable {
            visible: ql.rich && !(ql.rendered.kind === "mermaid" && ql.rendered.image)
            anchors.fill: parent
            anchors.margins: 22
            clip: true
            contentHeight: richText.implicitHeight
            opacity: Math.max(0, Math.min(1, (t.value - 0.5) / 0.4))
            TextEdit {
                id: richText
                width: parent.width
                readOnly: true
                selectByMouse: true
                textFormat: TextEdit.RichText
                wrapMode: TextEdit.Wrap
                text: ql.rich ? (ql.rendered.html || "") : ""
                color: Theme.textPrimary
                selectionColor: Qt.alpha(Theme.blue, 0.5)
                font.family: Theme.fontText
                font.pixelSize: 15
                onLinkActivated: link => Qt.openUrlExternally(link)
            }
        }
        Image {
            visible: ql.rich && ql.rendered.kind === "mermaid" && !!ql.rendered.image
            anchors.fill: parent
            anchors.margins: 22
            source: ql.rendered.image ? "file://" + ql.rendered.image : ""
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
            mipmap: true
        }

        // Raw text, readable, or being edited.
        Flickable {
            visible: !ql.isImage && !ql.isColor && !ql.rich
            anchors.fill: parent
            anchors.margins: 22
            clip: true
            contentHeight: editor.implicitHeight
            opacity: Math.max(0, Math.min(1, (t.value - 0.5) / 0.4))
            TextEdit {
                id: editor
                width: parent.width
                readOnly: !ql.editing
                selectByMouse: true
                wrapMode: TextEdit.Wrap
                text: ql.masked ? "•".repeat(32) : (ql.full || (ql.entry ? ql.entry.preview : ""))
                color: ql.masked ? Theme.textTertiary : Theme.textPrimary
                selectionColor: Qt.alpha(Theme.blue, 0.5)
                font.family: ql.entry && (ql.entry.kind === "code" || ql.rendered.kind === "code") ? Theme.fontMono : Theme.fontText
                font.pixelSize: ql.entry && (ql.entry.kind === "code" || ql.rendered.kind === "code") ? 14 : 17
                renderType: Text.NativeRendering
                cursorDelegate: SpringCaret {}
                Keys.onPressed: event => {
                    if (!ql.editing) return;
                    if (event.key === Qt.Key_Escape) { ql.editing = false; ql.panel.focusSearch(); event.accepted = true; }
                    else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ControlModifier)) {
                        Clipboard.pasteText(editor.text);
                        event.accepted = true;
                    }
                }
            }
        }
    }

    Label {
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 12 }
        opacity: Math.max(0, Math.min(1, (t.value - 0.6) / 0.4))
        text: !ql.entry ? ""
            : ql.editing ? "Editing  ·  ⌃↵ paste this  ·  Esc cancel"
            : [({ markdown: "Markdown", code: "Code", mermaid: "Mermaid diagram" })[ql.rendered.kind] || "",
               ql.rendered.kind === "code" ? ql.rendered.lang : "",
               ql.panel.detailOf(ql.entry, ql.full),
               ql.rendered.kind !== "text" ? (ql.raw ? "⌃R rendered" : "⌃R raw") : "",
               "⌃E edit", "Space close"].filter(x => x).join("    ")
        size: 11
        color: Theme.textTertiary
    }
}
