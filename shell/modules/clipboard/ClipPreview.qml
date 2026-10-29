// The selected entry in full: images at size, colours as a swatch with their
// values, text in full (monospace when it's code), secrets masked until ⌃H.
// Text arrives from cliphist after selection; until then a skeleton holds
// its shape.
import QtQuick
import Quickshell
import qs.config
import qs.components
import qs.services

Item {
    id: pv

    property var panel
    property var entry: null
    property bool revealed: false

    readonly property string ref: entry ? Clipboard.ref(entry) : ""
    property string full: ""
    property bool loading: false
    readonly property bool textual: entry && entry.kind !== "image" && entry.kind !== "file"
    readonly property bool masked: entry && entry.secret && !revealed

    onRefChanged: {
        full = "";
        loading = textual;
        if (textual) fetch.restart();
    }
    // Arrowing fast through the list shouldn't decode every row it passes.
    Timer { id: fetch; interval: 60; onTriggered: if (pv.entry) Clipboard.fetchText(pv.entry) }
    Connections {
        target: Clipboard
        function onTextReady(ref, text) {
            if (ref !== pv.ref) return;
            pv.full = text;
            pv.loading = false;
        }
    }

    // ── Empty ────────────────────────────────────────────────────────────
    Label {
        visible: !pv.entry
        anchors.centerIn: parent
        text: "Nothing selected"
        size: 13
        color: Theme.textTertiary
    }

    // ── Image ────────────────────────────────────────────────────────────
    Item {
        visible: pv.entry && pv.entry.kind === "image"
        anchors { left: parent.left; right: parent.right; top: parent.top; bottom: info.top; bottomMargin: 10 }
        Rectangle {
            anchors.fill: parent
            radius: 14
            color: Qt.rgba(0, 0, 0, 0.25)
        }
        Image {
            id: big
            anchors.fill: parent
            anchors.margins: 10
            source: pv.entry && pv.entry.kind === "image" ? Clipboard.thumb(pv.entry) : ""
            sourceSize: Qt.size(1200, 1200)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
            mipmap: true
            opacity: status === Image.Ready ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
        }
        Skeleton {
            visible: big.status !== Image.Ready
            anchors.centerIn: parent
            width: parent.width * 0.7
            height: parent.height * 0.6
            radius: 12
        }
    }

    // ── Colour ───────────────────────────────────────────────────────────
    Column {
        visible: pv.entry && pv.entry.kind === "color"
        anchors.centerIn: parent
        spacing: 14
        readonly property color c: pv.entry && pv.entry.kind === "color" ? pv.panel.colorOf(pv.entry.preview) : "transparent"
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 140; height: 140; radius: 32
            color: parent.c
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.2)
        }
        Repeater {
            model: pv.entry && pv.entry.kind === "color" ? pv.panel.colorValues(parent.c) : []
            Label {
                required property string modelData
                anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined
                text: modelData
                size: 13
                font.family: Theme.fontMono
                color: Theme.textSecondary
            }
        }
    }

    // ── Text, code, links, paths ─────────────────────────────────────────
    Flickable {
        id: textFlick
        visible: pv.textual && pv.entry.kind !== "color"
        anchors { left: parent.left; right: parent.right; top: parent.top; bottom: info.top; bottomMargin: 10 }
        clip: true
        contentHeight: body.implicitHeight + 8
        boundsBehavior: Flickable.StopAtBounds

        TextEdit {
            id: body
            width: textFlick.width - 8
            readOnly: true
            selectByMouse: true
            wrapMode: TextEdit.WrapAnywhere
            visible: !pv.loading
            text: pv.masked ? "•".repeat(Math.min(48, (pv.full || pv.entry.preview).length)) : pv.full
            color: pv.masked ? Theme.textTertiary : Theme.textPrimary
            selectionColor: Qt.alpha(Theme.blue, 0.5)
            font.family: pv.entry && (pv.entry.kind === "code" || pv.entry.secret) ? Theme.fontMono : Theme.fontText
            font.pixelSize: pv.entry && pv.entry.kind === "link" ? 15 : 13
            renderType: Text.NativeRendering
        }
        Column {
            visible: pv.loading
            width: textFlick.width - 8
            spacing: 10
            Repeater {
                model: [0.92, 0.78, 0.86, 0.55]
                Skeleton { required property real modelData; width: textFlick.width * modelData; height: 12 }
            }
        }
    }
    Rectangle {
        visible: pv.masked
        anchors.centerIn: textFlick
        width: hide.implicitWidth + 28
        height: 30
        radius: 15
        color: Qt.alpha(Theme.orange, 0.18)
        border.width: 1
        border.color: Qt.alpha(Theme.orange, 0.4)
        Label {
            id: hide
            anchors.centerIn: parent
            text: "Looks like a secret · ⌃H to show"
            size: 12
            weight: Theme.wMedium
            color: Theme.orange
        }
    }

    // ── What it is ───────────────────────────────────────────────────────
    Label {
        id: info
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        elide: Text.ElideRight
        text: pv.entry ? pv.panel.detailOf(pv.entry, pv.full) : ""
        size: 11
        color: Theme.textTertiary
    }
}
