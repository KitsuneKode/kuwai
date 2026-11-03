// Port of shadcn AI Elements: <PromptInput>
// Auto-expanding input field with attachment previews, screenshot capture,
// model selector pill, and cancel/send actions.
import QtQuick
import QtQuick.Controls
import qs.config
import qs.components
import qs.services

Rectangle {
    id: root

    property alias text: inputArea.text
    // The model picker (ModelPickerMenu) gets the keys while it's open.
    property var picker: null
    readonly property alias modelPill: modelPill
    signal submitted(string prompt)
    signal modelPickerRequested()
    signal openAppLauncherRequested()
    signal toggleSidebarRequested()
    signal toggleStudioRequested()
    signal escapeRequested()

    implicitHeight: mainCol.implicitHeight + 24
    radius: 18
    color: Qt.rgba(0.08, 0.08, 0.10, 0.85)
    border.width: 1
    border.color: inputArea.activeFocus ? Theme.accent : Qt.rgba(1, 1, 1, 0.12)

    Behavior on border.color { ColorAnimation { duration: Theme.colorMs } }
    Behavior on implicitHeight {
        NumberAnimation {
            duration: Theme.reflowMs
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.easeOut
        }
    }

    function focusInput() {
        inputArea.forceActiveFocus();
    }

    Column {
        id: mainCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        spacing: 10

        // ── Attachment Preview (if screenshot pending) ────────────────
        Rectangle {
            id: attachBox
            visible: height > 0
            width: parent.width
            height: OllamaService.pendingImage !== "" ? 52 : 0
            opacity: OllamaService.pendingImage !== "" ? 1 : 0
            clip: true
            radius: 10
            color: Qt.rgba(1, 1, 1, 0.06)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.10)

            Behavior on height {
                NumberAnimation {
                    duration: Theme.reflowMs
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.easeOut
                }
            }
            Behavior on opacity {
                NumberAnimation { duration: Theme.colorMs }
            }

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10

                Rectangle {
                    width: 52
                    height: 38
                    radius: 6
                    clip: true
                    color: "black"

                    Image {
                        anchors.fill: parent
                        source: OllamaService.pendingImage !== "" ? "file://" + OllamaService.pendingImage : ""
                        fillMode: Image.PreserveAspectCrop
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Label {
                        text: OllamaService.pendingAppTitle !== "" ? OllamaService.pendingAppTitle : "Snapshot attached"
                        size: 13
                        weight: Theme.wSemibold
                        color: Theme.textPrimary
                        elide: Text.ElideRight
                        width: 320
                    }
                    Label {
                        text: "Vision analysis active via " + (OllamaService.model.indexOf("minicpm") >= 0 ? "MiniCPM-V" : OllamaService.model)
                        size: 11
                        color: Theme.textTertiary
                    }
                }
            }

            // Remove Attachment Button
            Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: 26; height: 26
                radius: 13
                color: removeArea.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.08)

                Icon {
                    anchors.centerIn: parent
                    name: "x"
                    size: 13
                    color: Theme.textSecondary
                }

                MouseArea {
                    id: removeArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: OllamaService.pendingImage = ""
                }
            }
        }

        // ── Auto-Expanding Text Input ─────────────────────────────────
        Item {
            width: parent.width
            implicitHeight: Math.max(42, Math.min(160, inputArea.contentHeight + 10))

            TextEdit {
                id: inputArea
                anchors.fill: parent
                anchors.leftMargin: 6
                anchors.rightMargin: 6
                anchors.topMargin: 4
                color: Theme.textPrimary
                font.family: Theme.fontText
                font.pixelSize: 15
                wrapMode: TextEdit.Wrap
                selectByMouse: true
                selectionColor: Theme.accent
                selectedTextColor: Theme.onAccent

                // Placeholder Text
                Text {
                    anchors.fill: parent
                    text: OllamaService.pendingImage !== "" ? "Ask about the screenshot" : "Ask anything"
                    color: Theme.textDim
                    font.family: Theme.fontText
                    font.pixelSize: 15
                    visible: !inputArea.text && !inputArea.inputMethodComposing
                }

                Keys.onReturnPressed: event => {
                    if ((event.modifiers & Qt.ControlModifier) && OllamaService.pendingRequest) {
                        event.accepted = true;
                        OllamaService.resolveRequest(OllamaService.pendingRequest.id, "accept");
                    } else if (event.modifiers & Qt.ShiftModifier) {
                        event.accepted = false; // allow newline
                    } else {
                        event.accepted = true;
                        root.submit();
                    }
                }

                Keys.onPressed: event => {
                    if (root.picker && root.picker.open) {
                        root.picker.key(event);
                        event.accepted = true;
                        return;
                    }
                    const ctrl = (event.modifiers & Qt.ControlModifier);
                    if (ctrl) {
                        if (event.key === Qt.Key_V) {
                            event.accepted = true;
                            OllamaService.pasteClipboardImage();
                        } else if (event.key === Qt.Key_N) {
                            event.accepted = true;
                            inputArea.text = "";
                            OllamaService.newChat();
                        } else if (event.key === Qt.Key_O || event.key === Qt.Key_P) {
                            event.accepted = true;
                            root.openAppLauncherRequested();
                        } else if (event.key === Qt.Key_K) {
                            event.accepted = true;
                            root.modelPickerRequested();
                        } else if (event.key === Qt.Key_L) {
                            event.accepted = true;
                            inputArea.text = "";
                            OllamaService.clear();
                        } else if (event.key === Qt.Key_B) {
                            event.accepted = true;
                            root.toggleSidebarRequested();
                        } else if (event.key === Qt.Key_M || event.key === Qt.Key_E) {
                            event.accepted = true;
                            root.toggleStudioRequested();
                        }
                    } else if (event.key === Qt.Key_Escape) {
                        event.accepted = true;
                        root.escapeRequested();
                    }
                }

                Keys.onUpPressed: event => {
                    if (inputArea.text === "" && OllamaService.messages.length > 0) {
                        for (let i = OllamaService.messages.length - 1; i >= 0; i--) {
                            if (OllamaService.messages[i].role === "user") {
                                inputArea.text = OllamaService.messages[i].text;
                                inputArea.cursorPosition = inputArea.text.length;
                                event.accepted = true;
                                return;
                            }
                        }
                    }
                }
            }
        }

        // ── Action Bar (Attachments, Model Selector, Send Button) ─────
        Item {
            width: parent.width
            height: 36

            // Left: attach the focused window, or a region; then the model.
            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                MessageAction { width: 30; height: 30; radius: 15; icon: "app-window"; onClicked: OllamaService.snapshotActiveWindow() }
                MessageAction { width: 30; height: 30; radius: 15; icon: "selection"; onClicked: OllamaService.takeScreenshot() }

                Item { width: 4; height: 1 }

                Rectangle {
                    id: modelPill
                    height: 30
                    width: modelRow.implicitWidth + 22
                    radius: 15
                    anchors.verticalCenter: parent.verticalCenter
                    color: Qt.rgba(1, 1, 1, modelArea.containsMouse || (root.picker && root.picker.open) ? 0.10 : 0.05)
                    scale: modelArea.pressed ? 0.97 : 1
                    Behavior on color { ColorAnimation { duration: Theme.colorMs } }
                    Behavior on scale { NumberAnimation { duration: Theme.pressMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }

                    Row {
                        id: modelRow
                        anchors.centerIn: parent
                        spacing: 6

                        Label {
                            text: OllamaService.modelLabel(OllamaService.model)
                            size: 13
                            weight: Theme.wMedium
                            color: Theme.textPrimary
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Icon {
                            name: "caret-down"
                            style: "bold"
                            size: 10
                            color: Theme.textTertiary
                            rotation: root.picker && root.picker.open ? 180 : 0
                            anchors.verticalCenter: parent.verticalCenter
                            Behavior on rotation {
                                enabled: !Theme.reduceMotion
                                NumberAnimation { duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
                            }
                        }
                    }

                    MouseArea {
                        id: modelArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.modelPickerRequested()
                    }
                }
            }

            // Right cluster: Cancel or Send Button (Raised Button Plate)
            Item {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 36; height: 36

                Rectangle {
                    anchors.fill: parent
                    radius: 18
                    color: OllamaService.streaming
                        ? (btnArea.containsMouse ? Theme.red : Qt.alpha(Theme.red, 0.90))
                        : (root.canSend ? (btnArea.containsMouse ? Theme.accent : Qt.alpha(Theme.accent, 0.92)) : Qt.rgba(1, 1, 1, 0.08))
                    scale: btnArea.pressed ? 0.97 : 1

                    Behavior on scale { NumberAnimation { duration: Theme.pressMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                    Behavior on color { ColorAnimation { duration: Theme.colorMs } }

                    Icon {
                        anchors.centerIn: parent
                        name: OllamaService.streaming ? "stop" : "arrow-up"
                        style: OllamaService.streaming ? "fill" : "bold"
                        size: 16
                        color: OllamaService.streaming || root.canSend ? Theme.onAccent : Theme.textDim
                    }

                    MouseArea {
                        id: btnArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (OllamaService.streaming) {
                                OllamaService.cancel();
                            } else if (root.canSend) {
                                root.submit();
                            }
                        }
                    }
                }
            }
        }

    }

    readonly property bool canSend: (inputArea.text.trim().length > 0) || (OllamaService.pendingImage !== "")

    function submit() {
        const val = inputArea.text.trim();
        const prompt = val !== "" ? val : (OllamaService.pendingImage !== "" ? "Analyze this screenshot in detail." : "");
        if (prompt === "") return;

        inputArea.text = "";
        root.submitted(prompt);
        OllamaService.send(prompt);
    }
}
