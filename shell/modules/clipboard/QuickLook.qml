// Quick Look (Space): the selected entry grows out of its row into the whole
// panel, the way Aceternity's expandable card grows out of the list (shared
// element: one rectangle morphing from the row's mark to the view), over a
// backdrop that steps the list back. Images at full resolution, sized to
// their own aspect; text set large for reading. Space or Esc folds it back
// into its row; ↑↓ keep browsing inside it.
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
    property rect from: Qt.rect(width / 2, height / 2, 32, 32)
    property string full: ""

    anchors.fill: parent
    visible: t.value > 0.002 || open
    z: 25

    Spring { id: t; tier: Theme.springModerate; epsilon: 0.001 }
    onOpenChanged: { t.target = open ? 1 : 0; if (Theme.reduceMotion) t.settle(); }
    function lerp(a, b, k) { return a + (b - a) * k; }

    readonly property bool isImage: entry && entry.kind === "image"
    readonly property var dims: {
        const m = entry && entry.dims ? entry.dims.match(/(\d+)x(\d+)/) : null;
        return m ? { w: +m[1], h: +m[2] } : { w: 4, h: 3 };
    }
    // The view: an image keeps its aspect inside the panel; text gets it all.
    readonly property real pad: 28
    readonly property rect to: {
        const W = width - pad * 2, H = height - pad * 2 - 30;
        if (!isImage) return Qt.rect(pad, pad, W, H);
        const s = Math.min(W / dims.w, H / dims.h, 1.5);
        const w = Math.round(dims.w * s), h = Math.round(dims.h * s);
        return Qt.rect(Math.round((width - w) / 2), Math.round(pad + (H - h) / 2), w, h);
    }

    onEntryChanged: { full = ""; if (entry && !isImage) Clipboard.fetchText(entry); }
    Connections {
        target: Clipboard
        function onTextReady(ref, text) { if (ql.entry && ref === Clipboard.ref(ql.entry)) ql.full = text; }
    }

    // Backdrop: the list steps back.
    Rectangle {
        anchors.fill: parent
        radius: 22
        color: Qt.rgba(0.05, 0.05, 0.07, 0.72 * Math.min(1, t.value))
        MouseArea { anchors.fill: parent; enabled: ql.open; onClicked: ql.open = false }
    }

    ClippingRectangle {
        id: frame
        x: ql.lerp(ql.from.x, ql.to.x, t.value)
        y: ql.lerp(ql.from.y, ql.to.y, t.value)
        width: Math.max(1, ql.lerp(ql.from.width, ql.to.width, t.value))
        height: Math.max(1, ql.lerp(ql.from.height, ql.to.height, t.value))
        radius: ql.lerp(8, ql.isImage ? 14 : 18, Math.min(1, t.value))
        color: ql.isImage ? Qt.rgba(0, 0, 0, 0.3) : Qt.rgba(0.13, 0.13, 0.16, 0.96)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.10 * Math.min(1, t.value))

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
        Flickable {
            visible: !ql.isImage
            anchors.fill: parent
            anchors.margins: 22
            clip: true
            contentHeight: reader.implicitHeight
            opacity: Math.max(0, Math.min(1, (t.value - 0.5) / 0.4))
            TextEdit {
                id: reader
                width: parent.width
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.Wrap
                text: ql.entry && ql.entry.secret && !ql.panel.revealed ? "•".repeat(32) : (ql.full || (ql.entry ? ql.entry.preview : ""))
                color: Theme.textPrimary
                selectionColor: Qt.alpha(Theme.blue, 0.5)
                font.family: ql.entry && ql.entry.kind === "code" ? Theme.fontMono : Theme.fontText
                font.pixelSize: ql.entry && ql.entry.kind === "code" ? 14 : 17
                font.variableAxes: ql.entry && ql.entry.kind === "code" ? ({}) : ({ "opsz": Theme.opszFor(17), "wght": Theme.wRegular })
                renderType: Text.NativeRendering
            }
        }
    }

    Label {
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 16 }
        opacity: Math.max(0, Math.min(1, (t.value - 0.6) / 0.4))
        text: ql.entry ? ql.panel.detailOf(ql.entry, ql.full) + "      Space or Esc to close" : ""
        size: 11
        color: Theme.textTertiary
    }
}
