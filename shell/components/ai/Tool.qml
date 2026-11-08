// One tool call in a turn, from a Part (services/ai/turn.mjs): a quiet row
// (icon, what it did, a status only when it didn't simply work) that opens to
// show what went in and what came out. A pending approval shows its card
// under the row. Refs: AI Elements tool.tsx, T3 Code TimelineAssistantRows /
// TimelineToolActivityIcon, Codex exec_cell.
import QtQuick
import qs.config
import qs.components
import qs.components.ai
import qs.services

Item {
    id: root

    property var part: ({})
    property bool expanded: false
    property bool showAll: false

    readonly property string status: part.status || "running"
    readonly property bool running: status === "running"
    readonly property var request: part.request || null
    readonly property bool pending: !!request && request.state === "pending"
    readonly property string itemType: part.itemType || "dynamic_tool_call"

    readonly property bool question: itemType === "user_input"
    readonly property string t: part.title || ""
    readonly property string icon: itemType === "command_execution" ? "terminal-window"
        : /^Reading (http|https):/.test(t) ? "globe"
        : /^Reading /.test(t) ? "file-text"
        : /^(Finding|Listing) /.test(t) ? "folder-open"
        : /^Searching for /.test(t) ? "magnifying-glass"
        : /^Remembering/.test(t) ? "lightbulb"
        : /^Editing /.test(t) ? "pencil-simple-line"
        : itemType === "file_change" ? "file-code"
        : itemType === "user_input" ? "question"
        : itemType === "web_search" ? "globe-simple"
        : itemType === "image_view" ? "image"
        : itemType === "context_compaction" ? "stack"
        : "wrench"

    readonly property string statusText: status === "failed" ? "Failed"
        : status === "declined" ? (part.output === "Timed out" ? "Timed out" : part.output === "Stopped" ? "Stopped"
            : part.output === "Skipped" ? "Skipped" : "Declined")
        : ""

    function inputText() {
        const i = part.input || {};
        if (itemType === "command_execution") return "$ " + (i.command || "");
        if (itemType === "file_change") return i.content || "";
        if (itemType === "user_input") return "";
        const keys = Object.keys(i);
        if (keys.length === 0) return "";
        if (keys.length === 1 && typeof i[keys[0]] === "string") return i[keys[0]];
        return JSON.stringify(i, null, 2);
    }
    readonly property string bodyText: {
        const a = inputText(), b = part.output || "";
        if (itemType === "web_search") return b;
        return a && b ? a + "\n\n" + b : (a || b);
    }
    readonly property bool hasBody: bodyText !== "" && !pending && !question
    // A command's exit code (the output ends "(exit N)"): a chip on the row, red when it failed.
    readonly property int exitCode: {
        if (itemType !== "command_execution" || status !== "completed") return -1;
        const m = /\(exit (\d+)\)\s*$/.exec(part.output || "");
        return m ? parseInt(m[1]) : -1;
    }

    implicitWidth: parent ? parent.width : 500
    implicitHeight: col.implicitHeight

    Column {
        id: col
        width: parent.width
        spacing: 6

        Item {
            id: row
            width: parent.width
            height: 28

            Rectangle {
                anchors.fill: parent
                radius: 8
                color: Qt.rgba(1, 1, 1, area.containsMouse && root.hasBody ? 0.05 : 0)
                Behavior on color { ColorAnimation { duration: Theme.colorMs } }
            }

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                Item {
                    width: 16; height: 16
                    anchors.verticalCenter: parent.verticalCenter
                    Icon {
                        anchors.centerIn: parent
                        name: root.running && !root.pending ? "circle-notch" : root.icon
                        style: root.running && !root.pending ? "bold" : "duotone"
                        size: 14
                        color: root.status === "failed" ? Theme.red : root.running ? Theme.accent : Theme.textTertiary
                        RotationAnimation on rotation {
                            running: root.running && !root.pending && !Theme.reduceMotion
                            loops: Animation.Infinite
                            from: 0; to: 360
                            duration: Theme.spinMs
                        }
                        onNameChanged: rotation = 0
                    }
                }

                Label {
                    text: root.part.title || "Tool"
                    size: 13
                    weight: root.running ? Theme.wMedium : Theme.wRegular
                    color: root.running ? Theme.textPrimary : Theme.textSecondary
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth, row.width - 120)
                    anchors.verticalCenter: parent.verticalCenter
                    Behavior on color { ColorAnimation { duration: Theme.colorMs } }
                }
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                // A question answered: the answer, where a duration would be.
                Label {
                    visible: root.question && root.status === "completed"
                    text: root.part.output || ""
                    size: 12
                    weight: Theme.wMedium
                    color: Theme.textSecondary
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth, row.width * 0.4)
                    anchors.verticalCenter: parent.verticalCenter
                }
                Rectangle {
                    visible: root.exitCode > 0
                    width: exitLabel.implicitWidth + 12
                    height: 18
                    radius: 9
                    color: Qt.alpha(Theme.red, 0.16)
                    anchors.verticalCenter: parent.verticalCenter
                    Label {
                        id: exitLabel
                        anchors.centerIn: parent
                        text: "exit " + root.exitCode
                        size: 11
                        weight: Theme.wMedium
                        color: Theme.red
                        font.features: { "tnum": 1 }
                    }
                }
                Label {
                    visible: root.part.where === "sandbox" && !root.running
                    text: "Sandbox"
                    size: 11
                    color: Theme.textTertiary
                    anchors.verticalCenter: parent.verticalCenter
                }
                Label {
                    readonly property real ms: root.part.endedAt > root.part.startedAt && root.part.startedAt > 0 ? root.part.endedAt - root.part.startedAt : 0
                    visible: root.statusText === "" && !root.running && ms > 0 && !root.question
                    text: ms < 1000 ? Math.round(ms) + " ms" : (ms / 1000).toFixed(1) + "s"
                    size: 12
                    color: Theme.textTertiary
                    font.features: { "tnum": 1 }
                    anchors.verticalCenter: parent.verticalCenter
                }
                Label {
                    visible: root.statusText !== ""
                    text: root.statusText
                    size: 12
                    color: root.status === "failed" ? Theme.red : Theme.textTertiary
                    anchors.verticalCenter: parent.verticalCenter
                }
                Icon {
                    visible: root.hasBody
                    opacity: area.containsMouse || root.expanded ? 1 : 0
                    name: "caret-right"
                    style: "bold"
                    size: 11
                    color: Theme.textTertiary
                    rotation: root.expanded ? 90 : 0
                    anchors.verticalCenter: parent.verticalCenter
                    Behavior on opacity { NumberAnimation { duration: Theme.colorMs } }
                    Behavior on rotation {
                        enabled: !Theme.reduceMotion
                        NumberAnimation { duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
                    }
                }
            }

            MouseArea {
                id: area
                anchors.fill: parent
                hoverEnabled: true
                enabled: root.hasBody
                cursorShape: Qt.PointingHandCursor
                onClicked: root.expanded = !root.expanded
            }
        }

        QuestionCard {
            visible: root.pending && root.request.kind === "question"
            width: parent.width
            request: root.request || ({})
            onAnswered: text => OllamaService.resolveRequest(root.request.id, "accept", text)
            onSkipped: OllamaService.resolveRequest(root.request.id, "decline", "")
        }

        ApprovalCard {
            visible: root.pending && root.request.kind !== "question"
            width: parent.width
            request: root.request || ({})
            onDecided: d => OllamaService.resolveRequest(root.request.id, d, "")
        }

        Item {
            width: parent.width
            height: root.expanded && root.hasBody ? body.implicitHeight : 0
            visible: height > 0
            clip: true
            Behavior on height {
                enabled: !Theme.reduceMotion
                NumberAnimation { duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
            }

            Rectangle {
                id: body
                width: parent.width
                implicitHeight: bodyCol.implicitHeight + 20
                radius: 10
                color: Qt.rgba(0, 0, 0, 0.28)

                Column {
                    id: bodyCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 10
                    spacing: 6

                    Text {
                        id: bodyLabel
                        width: parent.width
                        text: root.bodyText
                        color: Theme.textSecondary
                        font.family: Theme.fontMono
                        font.pixelSize: 12
                        wrapMode: Text.WrapAnywhere
                        maximumLineCount: root.showAll ? 100000 : 8
                        elide: Text.ElideRight
                    }

                    Row {
                        spacing: 14
                        Label {
                            visible: bodyLabel.truncated || root.showAll
                            text: root.showAll ? "Show less" : "Show all"
                            size: 12
                            weight: Theme.wMedium
                            color: Theme.accent
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.showAll = !root.showAll
                            }
                        }
                        Label {
                            id: copyLabel
                            property bool copied: false
                            text: copied ? "Copied" : "Copy"
                            size: 12
                            weight: Theme.wMedium
                            color: copied ? Theme.green : Theme.textTertiary
                            Timer { id: copiedTimer; interval: 1500; onTriggered: copyLabel.copied = false }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { Clipboard.copyText(root.bodyText); copyLabel.copied = true; copiedTimer.restart(); }
                            }
                        }
                    }
                }
            }
        }
    }
}
