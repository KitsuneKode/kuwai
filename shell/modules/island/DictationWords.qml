import QtQuick
import qs.config
import qs.components
import qs.services

Item {
    id: words

    readonly property var shown: Dictation.shown
    property var kept: ({ mode: "", text: "" })
    onShownChanged: if (shown.mode !== "") kept = shown
    Component.onCompleted: if (shown.mode !== "") kept = shown
    readonly property var cur: shown.mode !== "" ? shown : kept
    readonly property bool flowing: cur.mode === "live"
    readonly property int rows: cur.mode === "note" ? 1 : 2

    implicitWidth: Theme.cardW - Theme.s4 * 2
    implicitHeight: view.height + Theme.s3
    Accessible.role: Accessible.StaticText
    Accessible.name: cur.mode === "live" ? "What you said so far" : cur.text

    Flickable {
        id: view
        width: parent.width
        interactive: false
        clip: true
        readonly property real lineH: lines.lineCount > 0 ? lines.contentHeight / lines.lineCount : lines.font.pixelSize
        height: Math.max(lineH, Math.min(lines.contentHeight, lineH * words.rows))
        contentWidth: width
        contentHeight: lines.contentHeight
        readonly property real end: Math.max(0, contentHeight - height)
        contentY: slide.value
        Spring { id: slide; tier: Theme.springModerate; epsilon: 0.3; target: view.end; Component.onCompleted: settle() }
        Label {
            id: lines
            width: view.width
            wrapMode: words.cur.mode === "note" ? Text.NoWrap : Text.WordWrap
            maximumLineCount: words.flowing ? 200 : words.rows
            elide: words.flowing ? Text.ElideNone : Text.ElideRight
            text: words.cur.text
            size: words.flowing ? Theme.tCallout : Theme.tSub
            weight: words.flowing ? Theme.wMedium : Theme.wRegular
            color: words.flowing ? Theme.textPrimary : Theme.textSecondary
        }
    }
    Rectangle {
        width: view.width
        height: view.lineH * 0.6
        visible: words.flowing && view.contentY > 1
        gradient: Gradient {
            GradientStop { position: 0; color: Theme.cutout }
            GradientStop { position: 1; color: Qt.alpha(Theme.cutout, 0) }
        }
    }
}
