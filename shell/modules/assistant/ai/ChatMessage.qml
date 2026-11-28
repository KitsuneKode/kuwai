import QtQuick
import qs.config
import qs.components
import qs.services
import "../../../services/ai/turn.mjs" as Turn

Item {
    id: root

    property var msg: ({})
    property int msgIndex: -1
    property bool isStreaming: false
    property bool isLast: false
    property bool animateIn: false
    property bool editing: false

    readonly property bool isUser: msg.role === "user"
    readonly property var parts: msg.parts || []
    readonly property string plainText: isUser ? (msg.text || "")
        : parts.filter(p => p.kind === "text").map(p => p.text).join("\n\n")
    readonly property int lastTextIndex: {
        for (let i = parts.length - 1; i >= 0; i--) if (parts[i].kind === "text") return i;
        return -1;
    }

    readonly property var blocks: {
        const out = [];
        let plan = null;
        for (let i = 0; i < parts.length; i++) {
            const p = parts[i];
            const last = out.length ? out[out.length - 1] : null;
            if (p.kind === "plan") {
                if (plan) plan.part = p;
                else { plan = { type: "plan", part: p }; out.push(plan); }
                continue;
            }
            if (p.kind === "tool") {
                if (last && last.type === "tools") last.parts.push(p);
                else out.push({ type: "tools", parts: [p] });
            } else {
                out.push({ type: p.kind, part: p, isLastText: i === lastTextIndex });
            }
        }
        return out;
    }

    implicitWidth: parent ? parent.width : 600
    implicitHeight: col.implicitHeight

    HoverHandler { id: hover }

    opacity: animateIn ? 0 : 1
    transform: Translate {
        id: lift
        y: root.animateIn && !Theme.reduceMotion ? 6 : 0
        Behavior on y { NumberAnimation { duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
    }
    Component.onCompleted: if (animateIn) { opacity = 1; lift.y = 0; }
    Behavior on opacity { NumberAnimation { duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }

    function copyText() {
        Clipboard.copyText(root.plainText);
        copied = true;
        copiedTimer.restart();
    }
    property bool copied: false
    Timer { id: copiedTimer; interval: 1500; onTriggered: root.copied = false }

    Column {
        id: col
        width: parent.width
        spacing: 8

        Row {
            visible: root.isUser && !!root.msg.context && (root.msg.context.files || []).length > 0
            anchors.right: parent.right
            spacing: 6
            Repeater {
                model: root.isUser && root.msg.context ? (root.msg.context.files || []) : []
                Rectangle {
                    required property var modelData
                    height: 26
                    width: fRow.implicitWidth + 16
                    radius: Theme.r1
                    color: Theme.wash(1)
                    Row {
                        id: fRow
                        anchors.centerIn: parent
                        spacing: 6
                        Icon { name: /\.pdf$/i.test(parent.parent.modelData.name) ? "file-pdf" : "file-text"; size: 13; color: Theme.textTertiary; anchors.verticalCenter: parent.verticalCenter }
                        Label { text: parent.parent.modelData.name; size: Theme.tSub; color: Theme.textSecondary; anchors.verticalCenter: parent.verticalCenter }
                    }
                }
            }
        }

        Row {
            visible: root.isUser && !!root.msg.context && !!root.msg.context.app
            anchors.right: parent.right
            spacing: 6
            Icon { name: "app-window"; size: 12; color: Theme.textTertiary; anchors.verticalCenter: parent.verticalCenter }
            Label {
                text: root.msg.context ? [root.msg.context.app, root.msg.context.title].filter(s => !!s).join(" · ") : ""
                size: Theme.tSub
                color: Theme.textTertiary
                elide: Text.ElideRight
                width: Math.min(implicitWidth, col.width * 0.7)
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Rectangle {
            visible: root.isUser && !!root.msg.image
            anchors.right: parent.right
            width: 220; height: 132
            radius: Theme.r2
            color: Qt.rgba(0, 0, 0, 0.35)
            border.width: 1
            border.color: Theme.edge(1)
            clip: true
            Image {
                anchors.fill: parent
                source: root.msg.image ? "file://" + root.msg.image : ""
                sourceSize.width: 440
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
        }

        Rectangle {
            id: bubble
            visible: root.isUser
            anchors.right: parent.right
            width: root.editing ? col.width * 0.85 : Math.min(col.width * 0.8, userText.implicitWidth + 30)
            implicitHeight: (root.editing ? editor.implicitHeight : userText.implicitHeight) + 22
            radius: 18
            color: Theme.wash(2)
            border.width: 1
            border.color: root.editing ? Qt.alpha(Theme.accent, 0.6) : Theme.edge(0)
            Behavior on border.color { ColorAnimation { duration: Theme.colorMs } }

            TextEdit {
                id: userText
                visible: !root.editing
                x: 15; y: 11
                width: Math.min(implicitWidth, col.width * 0.8 - 30)
                text: root.msg.text || ""
                readOnly: true
                selectByMouse: true
                selectionColor: Qt.alpha(Theme.accent, 0.5)
                wrapMode: TextEdit.Wrap
                color: Theme.textPrimary
                font.family: Theme.fontText
                font.pixelSize: 15
                font.variableAxes: Theme.axesFor(15)
            }

            TextEdit {
                id: editor
                visible: root.editing
                x: 15; y: 11
                width: parent.width - 30
                wrapMode: TextEdit.Wrap
                selectByMouse: true
                selectionColor: Qt.alpha(Theme.accent, 0.5)
                color: Theme.textPrimary
                font.family: Theme.fontText
                font.pixelSize: 15
                font.variableAxes: Theme.axesFor(15)
                Keys.onReturnPressed: event => {
                    if (event.modifiers & Qt.ShiftModifier) { event.accepted = false; return; }
                    event.accepted = true;
                    const t = editor.text.trim();
                    root.editing = false;
                    if (t !== "" && t !== root.msg.text) OllamaService.editAndResend(root.msgIndex, t);
                }
                Keys.onEscapePressed: event => { event.accepted = true; root.editing = false; }
            }
        }

        Row {
            visible: root.isUser && !root.editing
            anchors.right: parent.right
            spacing: 2
            opacity: hover.hovered ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.colorMs } }
            MessageAction { icon: root.copied ? "check" : "copy"; tip: root.copied ? "Copied" : "Copy"; onClicked: root.copyText() }
            MessageAction { icon: "git-branch"; tip: "Fork from here"; visible: !OllamaService.busyHere; onClicked: OllamaService.forkAt(root.msgIndex) }
            MessageAction {
                icon: "pencil-simple"
                tip: "Edit"
                visible: !OllamaService.busyHere
                onClicked: { editor.text = root.msg.text || ""; root.editing = true; editor.forceActiveFocus(); editor.cursorPosition = editor.text.length; }
            }
        }

        Item {
            id: waiting
            visible: !root.isUser && root.isStreaming && (root.parts.length === 0 || root.parts[root.parts.length - 1].kind === "steer")
            width: parent.width
            height: 22
            property int secs: 0
            Timer {
                running: waiting.visible
                interval: 1000
                repeat: true
                onRunningChanged: if (running) waiting.secs = 0
                onTriggered: waiting.secs++
            }
            readonly property bool loading: root.msg.phase === "loading" && root.parts.length === 0
            Row {
                spacing: 8
                anchors.verticalCenter: parent.verticalCenter
                Shimmer {
                    text: waiting.loading ? "Loading " + OllamaService.modelLabel(root.msg.model) + " into memory" : "Thinking"
                    size: Theme.tCallout
                    anchors.verticalCenter: parent.verticalCenter
                }
                Label {
                    visible: waiting.secs >= 2
                    text: waiting.secs + "s"
                    size: Theme.tSub
                    color: Theme.textDim
                    font.features: { "tnum": 1 }
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        Repeater {
            model: root.isUser ? 0 : root.blocks.length

            Loader {
                id: blockLoader
                required property int index
                readonly property var block: root.blocks[index] || ({ type: "" })
                width: col.width
                sourceComponent: block.type === "reasoning" ? reasoningBlock
                    : block.type === "tools" ? toolsBlock
                    : block.type === "text" ? textBlock
                    : block.type === "steer" ? steerBlock
                    : block.type === "plan" ? planBlock : null

                Component {
                    id: planBlock
                    PlanCard {
                        width: blockLoader.width
                        steps: blockLoader.block.part && blockLoader.block.part.input ? (blockLoader.block.part.input.steps || []) : []
                        live: root.isStreaming
                    }
                }

                Component {
                    id: reasoningBlock
                    ReasoningBlock {
                        width: blockLoader.width
                        text: blockLoader.block.part ? blockLoader.block.part.text : ""
                        isThinking: !!blockLoader.block.part && blockLoader.block.part.status === "running"
                        startedAt: blockLoader.block.part ? (blockLoader.block.part.startedAt || 0) : 0
                        endedAt: blockLoader.block.part ? (blockLoader.block.part.endedAt || 0) : 0
                    }
                }
                Component {
                    id: toolsBlock
                    ToolGroup {
                        width: blockLoader.width
                        parts: blockLoader.block.parts || []
                        live: root.isStreaming
                    }
                }
                Component {
                    id: steerBlock
                    Item {
                        width: blockLoader.width
                        implicitHeight: steerBubble.height + 8
                        Rectangle {
                            id: steerBubble
                            anchors.right: parent.right
                            y: 4
                            width: Math.min(parent.width * 0.8, steerText.implicitWidth + 30)
                            height: steerText.implicitHeight + 20
                            radius: Theme.r3
                            color: Theme.wash(2)
                            Text {
                                textFormat: Text.PlainText
                                id: steerText
                                x: 15; y: 10
                                width: Math.min(implicitWidth, blockLoader.width * 0.8 - 30)
                                text: blockLoader.block.part ? blockLoader.block.part.text : ""
                                wrapMode: Text.Wrap
                                color: Theme.textPrimary
                                font.family: Theme.fontText
                                font.pixelSize: 14
                            }
                        }
                    }
                }
                Component {
                    id: textBlock
                    Column {
                        id: tcol
                        width: blockLoader.width
                        spacing: 12
                        readonly property string raw: blockLoader.block.part ? blockLoader.block.part.text : ""
                        readonly property var blocks: Turn.splitBlocks(raw)
                        readonly property bool live: root.isStreaming && !!blockLoader.block.isLastText

                        Repeater {
                            model: tcol.blocks.length
                            Loader {
                                id: seg
                                required property int index
                                property string text: (tcol.blocks[index] || {}).text || ""
                                property string kind: (tcol.blocks[index] || {}).kind || "md"
                                property string lang: (tcol.blocks[index] || {}).lang || ""
                                property bool open: !!(tcol.blocks[index] || {}).open
                                readonly property bool tail: tcol.live && index === tcol.blocks.length - 1
                                readonly property string html: {
                                    OllamaService.renderTick;
                                    if (kind === "code" && open) return "";
                                    return OllamaService.blockHtml({ kind: kind, lang: lang, text: text, live: tail && kind === "md" });
                                }
                                property string shown: ""
                                onHtmlChanged: if (html) shown = html
                                onOpenChanged: if (open) shown = ""

                                width: tcol.width
                                sourceComponent: kind === "code" ? codeSeg : mdSeg

                                NumberAnimation on opacity {
                                    id: fadeIn
                                    running: false
                                    from: 0; to: 1
                                    duration: Theme.enterMs
                                    easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut
                                }
                                Component.onCompleted: { if (html) shown = html; if (root.isStreaming && !Theme.reduceMotion) fadeIn.start(); }

                                Component {
                                    id: mdSeg
                                    TextEdit {
                                        width: seg.width
                                        textFormat: seg.shown ? TextEdit.RichText : TextEdit.MarkdownText
                                        text: seg.shown ? seg.shown : Turn.liveMarkdown(seg.text)
                                        topPadding: /^#{1,3}\s/.test(seg.text) && seg.index > 0 ? 6 : 0
                                        readOnly: true
                                        selectByMouse: true
                                        selectionColor: Qt.alpha(Theme.accent, 0.5)
                                        wrapMode: TextEdit.Wrap
                                        color: Theme.textPrimary
                                        font.family: Theme.fontText
                                        font.pixelSize: 15
                                        font.variableAxes: Theme.axesFor(15)
                                        onLinkActivated: link => { if (Turn.safeLink(link)) Apps.open(link); }
                                        HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.IBeamCursor }
                                    }
                                }
                                Component {
                                    id: codeSeg
                                    Rectangle {
                                        id: codeBox
                                        width: seg.width
                                        height: codeHead.height + codeFlick.height + 12
                                        radius: 10
                                        color: Qt.rgba(0, 0, 0, 0.30)
                                        border.width: 1
                                        border.color: Theme.edge(0)
                                        property bool copied: false
                                        Timer { id: codeCopied; interval: 1500; onTriggered: codeBox.copied = false }

                                        Item {
                                            id: codeHead
                                            width: parent.width
                                            height: 30
                                            Label {
                                                x: 12
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: seg.lang || "code"
                                                size: Theme.tFootnote
                                                weight: Theme.wMedium
                                                color: Theme.textTertiary
                                            }
                                            Row {
                                                anchors.right: parent.right
                                                anchors.rightMargin: 10
                                                anchors.verticalCenter: parent.verticalCenter
                                                spacing: 5
                                                Icon { name: codeBox.copied ? "check" : "copy"; size: 12; color: codeBox.copied ? Theme.green : Theme.textTertiary; anchors.verticalCenter: parent.verticalCenter }
                                                Label { text: codeBox.copied ? "Copied" : "Copy"; size: Theme.tFootnote; color: codeBox.copied ? Theme.green : Theme.textTertiary; anchors.verticalCenter: parent.verticalCenter }
                                            }
                                            MouseArea {
                                                anchors.right: parent.right
                                                width: 80; height: parent.height
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: { Clipboard.copyText(seg.text); codeBox.copied = true; codeCopied.restart(); }
                                                activeFocusOnTab: true
                                                Accessible.role: Accessible.Button
                                                Accessible.name: codeBox.copied ? "Copied" : "Copy " + (seg.lang || "code")
                                                Accessible.onPressAction: { Clipboard.copyText(seg.text); codeBox.copied = true; codeCopied.restart(); }
                                                Keys.onPressed: e => { if (e.key === Qt.Key_Space || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { Clipboard.copyText(seg.text); codeBox.copied = true; codeCopied.restart(); e.accepted = true; } }
                                                FocusRing { cornerRadius: Theme.r1 }
                                            }
                                            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.wash(1) }
                                        }

                                        Flickable {
                                            id: codeFlick
                                            anchors.top: codeHead.bottom
                                            anchors.topMargin: 8
                                            x: 12
                                            width: parent.width - 24
                                            height: codeText.implicitHeight
                                            contentWidth: codeText.implicitWidth
                                            contentHeight: codeText.implicitHeight
                                            interactive: contentWidth > width
                                            boundsBehavior: Flickable.StopAtBounds
                                            flickableDirection: Flickable.HorizontalFlick
                                            clip: true
                                            TextEdit {
                                                id: codeText
                                                textFormat: seg.shown ? TextEdit.RichText : TextEdit.PlainText
                                                text: seg.shown ? seg.shown : seg.text
                                                readOnly: true
                                                selectByMouse: true
                                                selectionColor: Qt.alpha(Theme.accent, 0.5)
                                                wrapMode: TextEdit.NoWrap
                                                color: Theme.textPrimary
                                                font.family: Theme.fontMono
                                                font.pixelSize: 12
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Flow {
            readonly property var files: {
                if (root.isUser || root.isStreaming || !root.msg.parts) return [];
                const seen = [];
                root.msg.parts.forEach(p => {
                    if (p.itemType === "file_change" && p.status === "completed" && p.input && p.input.path
                        && seen.indexOf(p.input.path) < 0) seen.push(p.input.path);
                });
                return seen;
            }
            visible: files.length > 0
            width: parent.width
            spacing: 6
            Repeater {
                model: parent.files
                Rectangle {
                    id: fileChip
                    required property string modelData
                    height: 28
                    width: fileRow.implicitWidth + 18
                    radius: Theme.r1
                    color: Qt.rgba(1, 1, 1, fileArea.containsMouse ? 0.09 : 0.05)
                    Behavior on color { ColorAnimation { duration: Theme.colorMs } }
                    Row {
                        id: fileRow
                        anchors.centerIn: parent
                        spacing: 6
                        Icon { name: "file-code"; size: 13; color: Theme.textTertiary; anchors.verticalCenter: parent.verticalCenter }
                        Label { text: fileChip.modelData; size: Theme.tSub; color: Theme.textSecondary; anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideMiddle; width: Math.min(implicitWidth, Math.max(80, col.width - 64)) }
                    }
                    MouseArea {
                        id: fileArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Apps.open("file://" + OllamaService.sandboxDir() + "/" + fileChip.modelData.replace(/^\/?(work\/[^\/]+\/)?/, ""))
                    }
                    activeFocusOnTab: true
                    Accessible.role: Accessible.Link
                    Accessible.name: "Open " + fileChip.modelData
                    Accessible.onPressAction: Apps.open("file://" + OllamaService.sandboxDir() + "/" + fileChip.modelData.replace(/^\/?(work\/[^\/]+\/)?/, ""))
                    Keys.onPressed: e => { if (e.key === Qt.Key_Space || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { Apps.open("file://" + OllamaService.sandboxDir() + "/" + fileChip.modelData.replace(/^\/?(work\/[^\/]+\/)?/, "")); e.accepted = true; } }
                    FocusRing {}
                }
            }
            Rectangle {
                height: 28
                width: folderRow.implicitWidth + 18
                radius: Theme.r1
                color: Qt.rgba(1, 1, 1, folderArea.containsMouse ? 0.09 : 0)
                Behavior on color { ColorAnimation { duration: Theme.colorMs } }
                Row {
                    id: folderRow
                    anchors.centerIn: parent
                    spacing: 6
                    Icon { name: "folder-open"; size: 13; color: Theme.textTertiary; anchors.verticalCenter: parent.verticalCenter }
                    Label { text: "Sandbox folder"; size: Theme.tSub; color: Theme.textTertiary; anchors.verticalCenter: parent.verticalCenter }
                }
                MouseArea { id: folderArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Apps.open("file://" + OllamaService.sandboxDir()) }
                activeFocusOnTab: true
                Accessible.role: Accessible.Link
                Accessible.name: "Open the sandbox folder"
                Accessible.onPressAction: Apps.open("file://" + OllamaService.sandboxDir())
                Keys.onPressed: e => { if (e.key === Qt.Key_Space || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { Apps.open("file://" + OllamaService.sandboxDir()); e.accepted = true; } }
                FocusRing {}
            }
        }

        Flow {
            readonly property var sources: root.isUser || root.isStreaming ? [] : Turn.sourcesOf(root.msg)
            visible: sources.length > 0
            width: parent.width
            spacing: 6
            Repeater {
                model: parent.sources
                Rectangle {
                    id: src
                    required property var modelData
                    height: 26
                    width: srcRow.implicitWidth + 16
                    radius: Theme.r1
                    color: Qt.rgba(1, 1, 1, srcArea.containsMouse ? 0.09 : 0.05)
                    scale: srcArea.pressed ? 0.97 : 1
                    Behavior on color { ColorAnimation { duration: Theme.colorMs } }
                    Behavior on scale { NumberAnimation { duration: Theme.pressMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                    Row {
                        id: srcRow
                        anchors.centerIn: parent
                        spacing: 6
                        Icon { name: src.modelData.read ? "file-text" : "globe-simple"; size: 12; color: Theme.textTertiary; anchors.verticalCenter: parent.verticalCenter }
                        Label {
                            text: src.modelData.domain
                            size: Theme.tSub
                            color: srcArea.containsMouse ? Theme.textPrimary : Theme.textSecondary
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    MouseArea { id: srcArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { if (Turn.safeLink(src.modelData.url)) Apps.open(src.modelData.url); } }
                    activeFocusOnTab: true
                    Accessible.role: Accessible.Link
                    Accessible.name: src.modelData.domain
                    Accessible.description: src.modelData.read ? "A page it read" : "A search result it saw"
                    Accessible.onPressAction: { if (Turn.safeLink(src.modelData.url)) Apps.open(src.modelData.url); }
                    Keys.onPressed: e => { if (e.key === Qt.Key_Space || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { if (Turn.safeLink(src.modelData.url)) Apps.open(src.modelData.url); e.accepted = true; } }
                    FocusRing {}
                }
            }
        }

        Row {
            visible: !root.isUser && !root.isStreaming && (root.plainText !== "" || root.msg.status === "interrupted")
            spacing: 2
            opacity: root.isLast || hover.hovered ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.colorMs } }

            MessageAction { icon: root.copied ? "check" : "copy"; tip: root.copied ? "Copied" : "Copy"; visible: root.plainText !== ""; onClicked: root.copyText() }
            MessageAction { icon: "arrow-clockwise"; tip: "Retry"; visible: !OllamaService.busyHere; onClicked: OllamaService.regenerate(root.msgIndex) }
            MessageAction { icon: "git-branch"; tip: "Fork from here"; visible: !OllamaService.busyHere && root.msgIndex >= 0; onClicked: OllamaService.forkAt(root.msgIndex) }
            Label {
                text: [OllamaService.modelLabel(root.msg.model),
                       root.msg.startedAt && root.msg.endedAt > root.msg.startedAt
                           ? ((root.msg.endedAt - root.msg.startedAt) / 1000).toFixed(1) + "s" : "",
                       root.msg.stats && root.msg.stats.tokensPerSec ? root.msg.stats.tokensPerSec + " tok/s" : "",
                       root.msg.time || "",
                       root.msg.status === "interrupted" ? "Stopped" : root.msg.status === "max_tool_rounds" ? "Stopped after 6 tool rounds"
                       : root.msg.status === "repeating" ? "Stopped: it was repeating itself" : ""]
                      .filter(s => !!s).join(" · ")
                size: Theme.tSub
                color: Theme.textTertiary
                leftPadding: 6
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
}
