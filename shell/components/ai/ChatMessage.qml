// One turn of the conversation.
//   You: a bubble on the right, with the screenshot and the window it came
//        from above it; hover for Copy and Edit (edit resends from here).
//   Assistant: no card, the text sits on the glass (as in ChatGPT/Claude).
//        Its parts render in order: reasoning, tool rows (grouped), text.
//        Below: Copy, Retry and the model/speed/time, shown on hover and
//        always on the last answer.
// `msg` is a message from OllamaService (user, or Turn's Msg with parts).
import QtQuick
import qs.config
import qs.components
import qs.services

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

    // Parts → blocks; consecutive tool parts become one group.
    readonly property var blocks: {
        const out = [];
        for (let i = 0; i < parts.length; i++) {
            const p = parts[i];
            const last = out.length ? out[out.length - 1] : null;
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

    // New messages you send arrive from just below (opacity + 6 px); answers
    // arrive with the streaming message, so the finished one doesn't animate again.
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

        // ── You ────────────────────────────────────────────────────────
        Row {
            visible: root.isUser && !!root.msg.context && !!root.msg.context.app
            anchors.right: parent.right
            spacing: 6
            Icon { name: "app-window"; size: 12; color: Theme.textTertiary; anchors.verticalCenter: parent.verticalCenter }
            Label {
                text: root.msg.context ? [root.msg.context.app, root.msg.context.title].filter(s => !!s).join(" · ") : ""
                size: 12
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
            radius: 12
            color: Qt.rgba(0, 0, 0, 0.35)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.12)
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
            color: Qt.rgba(1, 1, 1, 0.09)
            border.width: 1
            border.color: root.editing ? Qt.alpha(Theme.accent, 0.6) : Qt.rgba(1, 1, 1, 0.06)
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
            MessageAction { icon: root.copied ? "check" : "copy"; onClicked: root.copyText() }
            MessageAction {
                icon: "pencil-simple"
                visible: !OllamaService.streaming
                onClicked: { editor.text = root.msg.text || ""; root.editing = true; editor.forceActiveFocus(); editor.cursorPosition = editor.text.length; }
            }
        }

        // ── Assistant ──────────────────────────────────────────────────
        // Before the first word: loading the model into memory (cold, ~10 s) or
        // thinking; a seconds counter once it's been a moment.
        Label {
            id: waiting
            visible: !root.isUser && root.isStreaming && root.parts.length === 0
            property int secs: 0
            Timer {
                running: waiting.visible
                interval: 1000
                repeat: true
                onRunningChanged: if (running) waiting.secs = 0
                onTriggered: waiting.secs++
            }
            text: (root.msg.phase === "loading" ? "Loading " + OllamaService.modelLabel(root.msg.model) + "…" : "Thinking")
                  + (secs >= 2 ? "  " + secs + "s" : "")
            size: 14
            color: Theme.textTertiary
            SequentialAnimation on opacity {
                running: waiting.visible && !Theme.reduceMotion
                loops: Animation.Infinite
                NumberAnimation { from: 1; to: 0.45; duration: 700; easing.type: Easing.InOutSine }
                NumberAnimation { from: 0.45; to: 1; duration: 700; easing.type: Easing.InOutSine }
            }
        }

        // An int model keeps each block (open tool rows, text selection) while parts stream.
        Repeater {
            model: root.isUser ? 0 : root.blocks.length

            Loader {
                id: blockLoader
                required property int index
                readonly property var block: root.blocks[index] || ({ type: "" })
                width: col.width
                sourceComponent: block.type === "reasoning" ? reasoningBlock
                    : block.type === "tools" ? toolsBlock
                    : block.type === "text" ? textBlock : null

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
                    id: textBlock
                    TextEdit {
                        readonly property bool rich: !root.isStreaming && blockLoader.block.isLastText && !!root.msg.html
                        width: blockLoader.width
                        textFormat: rich ? TextEdit.RichText : TextEdit.PlainText
                        text: rich ? root.msg.html : (blockLoader.block.part ? blockLoader.block.part.text : "")
                        readOnly: true
                        selectByMouse: true
                        selectionColor: Qt.alpha(Theme.accent, 0.5)
                        wrapMode: TextEdit.Wrap
                        color: Theme.textPrimary
                        font.family: Theme.fontText
                        font.pixelSize: 15
                        onLinkActivated: link => Qt.openUrlExternally(link)
                    }
                }
            }
        }

        Row {
            visible: !root.isUser && !root.isStreaming && (root.plainText !== "" || root.msg.status === "interrupted")
            spacing: 2
            opacity: root.isLast || hover.hovered ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.colorMs } }

            MessageAction { icon: root.copied ? "check" : "copy"; visible: root.plainText !== ""; onClicked: root.copyText() }
            MessageAction { icon: "arrow-clockwise"; visible: !OllamaService.streaming; onClicked: OllamaService.regenerate(root.msgIndex) }
            Label {
                text: [OllamaService.modelLabel(root.msg.model),
                       root.msg.startedAt && root.msg.endedAt > root.msg.startedAt
                           ? ((root.msg.endedAt - root.msg.startedAt) / 1000).toFixed(1) + "s" : "",
                       root.msg.stats && root.msg.stats.tokensPerSec ? root.msg.stats.tokensPerSec + " tok/s" : "",
                       root.msg.time || "",
                       root.msg.status === "interrupted" ? "Stopped" : root.msg.status === "max_tool_rounds" ? "Stopped after 6 tool rounds"
                       : root.msg.status === "repeating" ? "Stopped: it was repeating itself" : ""]
                      .filter(s => !!s).join(" · ")
                size: 12
                color: Theme.textTertiary
                leftPadding: 6
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
}
