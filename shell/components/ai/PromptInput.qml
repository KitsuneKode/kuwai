// Port of shadcn AI Elements: <PromptInput>
// Auto-expanding input field with attachment previews, screenshot capture,
// model selector pill, and cancel/send actions.
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.config
import qs.components
import qs.services

Rectangle {
    id: root

    property alias text: inputArea.text
    // The model picker (ModelPickerMenu) gets the keys while it's open; so do
    // the other popups listed here (the slash menu).
    property var picker: null
    property var popups: []
    readonly property alias slashAnchor: slashAnchor
    signal slashRequested()
    readonly property alias modelPill: modelPill
    signal submitted(string prompt)
    signal modelPickerRequested()
    signal openAppLauncherRequested()
    signal toggleSidebarRequested()
    signal toggleStudioRequested()
    signal escapeRequested()
    signal searchRequested()

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

    // An open popup (model picker, slash menu) takes the keys. True if it did.
    function routeToPopup(event) {
        const open = [root.picker].concat(root.popups).find(p => p && p.open);
        if (!open) return false;
        open.key(event);
        event.accepted = true;
        return true;
    }

    function firstLine(t) {
        const l = String(t || "").trim().split("\n")[0];
        return l.length > 60 ? l.slice(0, 60) + "…" : l;
    }
    readonly property var chips: {
        const out = [];
        const c = OllamaService.pendingContext || {};
        const home = Quickshell.env("HOME") || "";
        if (OllamaService.pendingImage)
            out.push({ key: "image", thumb: OllamaService.pendingImage, label: c.app ? [c.app, c.title].filter(x => !!x).join(" · ") : "Screenshot" });
        if (c.cwd)
            out.push({ key: "cwd", icon: "folder-simple", label: c.cwd.replace(home, "~") + (c.git && c.git.branch ? " · " + c.git.branch : "") });
        if (c.selection) out.push({ key: "selection", icon: "cursor-text", label: firstLine(c.selection) });
        if (c.clipboard && c.clipboard !== c.selection) out.push({ key: "clipboard", icon: "clipboard-text", label: firstLine(c.clipboard) });
        (c.files || []).forEach((f, i) => out.push({ key: "file:" + i, label: f.name,
            icon: /\.pdf$/i.test(f.name) ? "file-pdf" : /\.(md|txt|log|csv|json)$/i.test(f.name) ? "file-text" : "file-code" }));
        return out;
    }
    function removeChip(key) {
        const c = Object.assign({}, OllamaService.pendingContext || {});
        if (key === "image") {
            OllamaService.pendingImage = "";
            OllamaService.pendingAppTitle = "";
            c.app = ""; c.title = ""; c.workspace = "";
        } else if (key === "cwd") { c.cwd = ""; c.git = null; }
        else if (key.indexOf("file:") === 0) { const i = parseInt(key.slice(5)); c.files = (c.files || []).filter((_, j) => j !== i); }
        else c[key] = "";
        OllamaService.pendingContext = c;
    }

    function focusInput() {
        inputArea.forceActiveFocus();
    }

    // Drop files on the composer to attach them (text, code, PDF, images).
    DropArea {
        id: drop
        anchors.fill: parent
        keys: ["text/uri-list"]
        onDropped: drop => { (drop.urls || []).forEach(u => OllamaService.attach(decodeURIComponent(String(u)))); drop.accept(); }
    }
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: Qt.alpha(Theme.accent, 0.08)
        border.width: 1.5
        border.color: Qt.alpha(Theme.accent, 0.6)
        opacity: drop.containsDrag ? 1 : 0
        visible: opacity > 0
        z: 20
        Behavior on opacity { NumberAnimation { duration: Theme.colorMs } }
        Label { anchors.centerIn: parent; text: "Drop to attach"; size: 13; weight: Theme.wMedium; color: Theme.accent }
    }

    // ── Dictation (AI Elements speech-input) via voxtype ──────────────
    // Click the mic: voxtype records; click again: it transcribes into a file,
    // and the text lands in the composer where the cursor is. Esc cancels.
    property int editIndex: -1                  // ↑: editing that message; ↵ resends from it
    property string micState: "idle"            // idle | recording | transcribing
    property string dictPath: ""
    function toggleMic() {
        if (micState === "idle") {
            dictPath = (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/rice/ai/dictation-" + Date.now() + ".txt";
            micProc.command = ["voxtype", "record", "start", "--file=" + dictPath];
            micProc.running = true;
            micState = "recording";
        } else if (micState === "recording") {
            micProc.command = ["voxtype", "record", "stop"];
            micProc.running = true;
            micState = "transcribing";
            micTimeout.restart();
        }
    }
    function cancelMic() {
        if (micState === "idle") return false;
        micProc.command = ["voxtype", "record", "cancel"];
        micProc.running = true;
        micState = "idle";
        return true;
    }
    Process { id: micProc }
    Timer { id: micTimeout; interval: 30000; onTriggered: if (root.micState === "transcribing") root.micState = "idle" }
    FileView {
        id: dictFile
        path: root.dictPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const t = text().trim();
            if (!t || root.micState === "idle") return;
            root.micState = "idle";
            const pos = inputArea.cursorPosition;
            const before = inputArea.text.slice(0, pos);
            inputArea.insert(pos, (before && !/\s$/.test(before) ? " " : "") + t);
            inputArea.forceActiveFocus();
        }
    }

    Column {
        id: mainCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        spacing: 10

        // ── Queue: what's waiting, and steers on their way in ─────────
        // (AI Elements queue.tsx: a ring per item, actions on hover.)
        Column {
            id: queueList
            readonly property var items: OllamaService.steering.map(x => ({ id: x.id, text: x.text, steering: true }))
                .concat(OllamaService.queue.map(x => ({ id: x.id, text: x.text || "Screenshot", steering: false, image: !!x.image })))
            visible: items.length > 0
            width: parent.width
            spacing: 2

            Label {
                text: OllamaService.queue.length > 0 ? "Queued · sends when this answer is done" : "Steering"
                visible: queueList.items.length > 0
                size: 11
                weight: Theme.wMedium
                color: Theme.textTertiary
                leftPadding: 6
                bottomPadding: 2
            }

            Repeater {
                model: queueList.items
                Rectangle {
                    id: qrow
                    required property var modelData
                    width: queueList.width
                    height: 30
                    radius: 8
                    color: Qt.rgba(1, 1, 1, qArea.containsMouse ? 0.06 : 0)
                    Behavior on color { ColorAnimation { duration: Theme.colorMs } }
                    opacity: 0
                    Component.onCompleted: opacity = 1
                    Behavior on opacity { NumberAnimation { duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }

                    HoverHandler { id: qArea; readonly property bool containsMouse: hovered }

                    Item {
                        id: ring
                        x: 8
                        width: 14; height: 14
                        anchors.verticalCenter: parent.verticalCenter
                        Rectangle {
                            visible: !qrow.modelData.steering
                            anchors.centerIn: parent
                            width: 9; height: 9; radius: 4.5
                            color: "transparent"
                            border.width: 1.5
                            border.color: Theme.textTertiary
                        }
                        Icon {
                            visible: qrow.modelData.steering
                            anchors.centerIn: parent
                            name: "circle-notch"; style: "bold"; size: 12; color: Theme.accent
                            RotationAnimation on rotation { running: qrow.modelData.steering && !Theme.reduceMotion; loops: Animation.Infinite; from: 0; to: 360; duration: Theme.spinMs }
                        }
                    }
                    Label {
                        anchors { left: ring.right; leftMargin: 8; right: qActions.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
                        text: (qrow.modelData.image ? "Screenshot · " : "") + qrow.modelData.text.split("\n")[0]
                        size: 13
                        color: Theme.textSecondary
                        elide: Text.ElideRight
                    }
                    Row {
                        id: qActions
                        anchors.right: parent.right
                        anchors.rightMargin: 2
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !qrow.modelData.steering
                        opacity: qArea.containsMouse ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Theme.colorMs } }
                        spacing: 0
                        MessageAction { width: 26; height: 26; icon: "arrow-up"; onClicked: OllamaService.sendQueuedNow(qrow.modelData.id) }
                        MessageAction {
                            width: 26; height: 26; icon: "pencil-simple"
                            onClicked: { inputArea.text = OllamaService.takeQueued(qrow.modelData.id); inputArea.cursorPosition = inputArea.text.length; root.focusInput(); }
                        }
                        MessageAction { width: 26; height: 26; icon: "x"; onClicked: OllamaService.removeQueued(qrow.modelData.id) }
                    }
                }
            }
        }

        // ── Context chips: what goes with the next message ─────────────
        // The screenshot (and the window it's from), its folder and branch,
        // the selection, the clipboard. Each can go (× or ⌫ on an empty prompt).
        Flow {
            id: chipFlow
            width: parent.width
            spacing: 6
            visible: root.chips.length > 0

            Repeater {
                model: root.chips
                Rectangle {
                    id: chip
                    required property var modelData
                    height: 30
                    width: chipRow.implicitWidth + 14
                    radius: 10
                    color: Qt.rgba(1, 1, 1, 0.06)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.08)
                    opacity: 0
                    transform: Translate { id: chipLift; y: Theme.reduceMotion ? 0 : 4
                        Behavior on y { NumberAnimation { duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } } }
                    Behavior on opacity { NumberAnimation { duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                    Component.onCompleted: { opacity = 1; chipLift.y = 0; }

                    Row {
                        id: chipRow
                        anchors.left: parent.left
                        anchors.leftMargin: chip.modelData.thumb ? 4 : 9
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6

                        Rectangle {
                            visible: !!chip.modelData.thumb
                            width: 30; height: 22
                            radius: 6
                            clip: true
                            color: "black"
                            anchors.verticalCenter: parent.verticalCenter
                            Image {
                                anchors.fill: parent
                                source: chip.modelData.thumb ? "file://" + chip.modelData.thumb : ""
                                sourceSize.width: 60
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                            }
                        }
                        Icon {
                            visible: !chip.modelData.thumb
                            name: chip.modelData.icon
                            size: 13
                            color: Theme.textTertiary
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Label {
                            text: chip.modelData.label
                            size: 12
                            color: Theme.textSecondary
                            elide: Text.ElideRight
                            width: Math.min(implicitWidth, 240)
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Rectangle {
                            width: 18; height: 18
                            radius: 9
                            color: Qt.rgba(1, 1, 1, xArea.containsMouse ? 0.14 : 0)
                            anchors.verticalCenter: parent.verticalCenter
                            Behavior on color { ColorAnimation { duration: Theme.colorMs } }
                            Icon { anchors.centerIn: parent; name: "x"; style: "bold"; size: 10; color: Theme.textTertiary }
                            MouseArea { id: xArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.removeChip(chip.modelData.key) }
                        }
                    }
                }
            }
        }

        // ── Auto-Expanding Text Input ─────────────────────────────────
        Item {
            width: parent.width
            implicitHeight: Math.max(42, Math.min(160, inputArea.contentHeight + 10))

            Item { id: slashAnchor; x: 0; y: 0; width: 300; height: 1 }

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
                    text: root.micState === "recording" ? "Listening… click the mic or ⌃D to stop"
                        : root.micState === "transcribing" ? "Writing it down…"
                        : root.editIndex >= 0 ? "Edit your message"
                        : OllamaService.pendingRequest && OllamaService.pendingRequest.kind === "question"
                        ? (OllamaService.pendingRequest.options.length ? "Pick 1–" + OllamaService.pendingRequest.options.length + ", or type your answer" : "Type your answer")
                        : OllamaService.streaming ? "Enter steers this answer · Tab queues for after"
                        : OllamaService.pendingImage !== "" ? "Ask about the screenshot" : "Ask anything"
                    color: Theme.textDim
                    font.family: Theme.fontText
                    font.pixelSize: 15
                    visible: !inputArea.text && !inputArea.inputMethodComposing
                }

                // Qt calls these key-specific handlers before onPressed, so each asks the popups first.
                Keys.onReturnPressed: event => {
                    if (root.routeToPopup(event)) return;
                    const pend = OllamaService.pendingRequest;
                    if (pend && pend.kind === "question" && !(event.modifiers & Qt.ShiftModifier)) {
                        // The composer answers the question.
                        event.accepted = true;
                        const t = inputArea.text.trim();
                        if (t) { OllamaService.resolveRequest(pend.id, "accept", t); inputArea.text = ""; }
                    } else if ((event.modifiers & Qt.ControlModifier) && pend && pend.kind !== "question") {
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
                    if (root.routeToPopup(event)) return;
                    const pend = OllamaService.pendingRequest;
                    if (pend && pend.kind === "question" && inputArea.text === "" && !(event.modifiers & Qt.ControlModifier)
                            && event.key >= Qt.Key_1 && event.key <= Qt.Key_9 && event.key - Qt.Key_1 < pend.options.length) {
                        event.accepted = true;     // 1–9 picks an option
                        OllamaService.resolveRequest(pend.id, "accept", pend.options[event.key - Qt.Key_1]);
                        return;
                    }
                    if (event.key === Qt.Key_Tab && OllamaService.streaming && root.canSend) {
                        event.accepted = true;
                        OllamaService.enqueue(inputArea.text);
                        inputArea.text = "";
                        return;
                    }
                    if (inputArea.text === "" && !(event.modifiers & Qt.ControlModifier)) {
                        if (event.text === "/") { event.accepted = true; root.slashRequested(); return; }
                        if (event.key === Qt.Key_Backspace && root.chips.length > 0) {
                            event.accepted = true;
                            root.removeChip(root.chips[root.chips.length - 1].key);
                            return;
                        }
                    }
                    // ↑ in an empty composer edits your last message (Codex, ChatGPT).
                    if (event.key === Qt.Key_Up && inputArea.text === "" && !OllamaService.streaming && root.editIndex < 0) {
                        const msgs = OllamaService.messages;
                        for (let i = msgs.length - 1; i >= 0; i--) {
                            if (msgs[i].role === "user") {
                                event.accepted = true;
                                root.editIndex = i;
                                inputArea.text = msgs[i].text || "";
                                inputArea.cursorPosition = inputArea.text.length;
                                return;
                            }
                        }
                    }
                    const ctrl = (event.modifiers & Qt.ControlModifier);
                    if (ctrl && event.key === Qt.Key_D) { event.accepted = true; root.toggleMic(); return; }
                    if (ctrl && event.key === Qt.Key_F) { event.accepted = true; root.searchRequested(); return; }
                    if (ctrl && event.key === Qt.Key_Period) {
                        event.accepted = true;      // ⌃. Chat ⇄ Agent
                        OllamaService.mode = OllamaService.mode === "agent" ? "chat" : "agent";
                        OllamaService.syncCurrentSession();
                        return;
                    }
                    if (ctrl && (event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_C) {
                        event.accepted = true;      // ⌃⇧C copies the last answer
                        const msgs = OllamaService.messages;
                        for (let i = msgs.length - 1; i >= 0; i--) if (msgs[i].role === "assistant") { Clipboard.copyText(msgs[i].text || ""); break; }
                        return;
                    }
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
                        if (root.cancelMic()) return;
                        if (root.editIndex >= 0) { root.editIndex = -1; inputArea.text = ""; return; }
                        root.escapeRequested();
                    }
                }

                Keys.onUpPressed: event => {
                    if (root.routeToPopup(event)) return;
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

                MessageAction { width: 30; height: 30; radius: 15; icon: "paperclip"; tip: "Attach files · or drop them here"; onClicked: OllamaService.pickFiles() }
                // Mic: red and breathing while it listens, a spinner while voxtype writes.
                Item {
                    width: 30; height: 30
                    anchors.verticalCenter: parent.verticalCenter
                    Rectangle {
                        anchors.centerIn: parent
                        width: 30; height: 30; radius: 15
                        color: root.micState === "recording" ? Qt.alpha(Theme.red, 0.18) : Qt.rgba(1, 1, 1, micArea.containsMouse ? 0.08 : 0)
                        Behavior on color { ColorAnimation { duration: Theme.colorMs } }
                        SequentialAnimation on scale {
                            running: root.micState === "recording" && !Theme.reduceMotion
                            loops: Animation.Infinite
                            onRunningChanged: if (!running) parent.scale = 1
                            NumberAnimation { to: 1.12; duration: Theme.breatheMs; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1.0; duration: Theme.breatheMs; easing.type: Easing.InOutSine }
                        }
                    }
                    Icon {
                        anchors.centerIn: parent
                        name: root.micState === "transcribing" ? "circle-notch" : "microphone"
                        style: root.micState === "recording" ? "fill" : root.micState === "transcribing" ? "bold" : "regular"
                        size: 15
                        color: root.micState === "recording" ? Theme.red : micArea.containsMouse ? Theme.textPrimary : Theme.textTertiary
                        RotationAnimation on rotation {
                            running: root.micState === "transcribing" && !Theme.reduceMotion
                            loops: Animation.Infinite; from: 0; to: 360; duration: Theme.spinMs
                        }
                        onNameChanged: rotation = 0
                    }
                    MouseArea { id: micArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.toggleMic() }
                    MessageAction {
                        // Only for its tooltip: sits under the mic, never takes the click.
                        anchors.fill: parent
                        color: "transparent"
                        icon: ""
                        enabled: false
                        opacity: 1
                        tip: root.micState === "recording" ? "Stop and write it down · ⌃D" : root.micState === "transcribing" ? "Writing it down…" : "Dictate · ⌃D"
                        hoverSource: micArea
                    }
                }
                MessageAction { width: 30; height: 30; radius: 15; icon: "app-window"; tip: "Attach the window you were in"; onClicked: OllamaService.snapshotActiveWindow() }
                MessageAction { width: 30; height: 30; radius: 15; icon: "selection"; tip: "Attach part of the screen"; onClicked: OllamaService.takeScreenshot() }

                Item { width: 4; height: 1 }

                // Chat | Agent (⌃.): a two-part switch, the highlight slides to the one that's on.
                Rectangle {
                    id: modeSwitch
                    height: 30
                    width: chatSeg.width + agentSeg.width + 6
                    radius: 15
                    color: Qt.rgba(1, 1, 1, 0.05)
                    anchors.verticalCenter: parent.verticalCenter
                    readonly property bool agent: OllamaService.mode === "agent"
                    Rectangle {
                        x: 3 + (modeSwitch.agent ? chatSeg.width : 0)
                        y: 3
                        width: modeSwitch.agent ? agentSeg.width : chatSeg.width
                        height: 24
                        radius: 12
                        color: modeSwitch.agent ? Qt.alpha(Theme.accent, 0.22) : Qt.rgba(1, 1, 1, 0.10)
                        Behavior on x { enabled: !Theme.reduceMotion; NumberAnimation { duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                        Behavior on width { enabled: !Theme.reduceMotion; NumberAnimation { duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                        Behavior on color { ColorAnimation { duration: Theme.colorMs } }
                    }
                    Row {
                        x: 3; y: 3
                        Item {
                            id: chatSeg
                            width: chatLbl.implicitWidth + 20; height: 24
                            Label { id: chatLbl; anchors.centerIn: parent; text: "Chat"; size: 12; weight: Theme.wMedium
                                    color: !modeSwitch.agent ? Theme.textPrimary : Theme.textTertiary }
                            MouseArea { id: chatSegArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: { OllamaService.mode = "chat"; OllamaService.syncCurrentSession(); } }
                        }
                        Item {
                            id: agentSeg
                            width: agentRow.implicitWidth + 20; height: 24
                            Row {
                                id: agentRow
                                anchors.centerIn: parent
                                spacing: 5
                                Icon { anchors.verticalCenter: parent.verticalCenter; name: "lightning"; style: modeSwitch.agent ? "fill" : "regular"; size: 12
                                       color: modeSwitch.agent ? Theme.accent : Theme.textTertiary }
                                Label { anchors.verticalCenter: parent.verticalCenter; text: "Agent"; size: 12; weight: Theme.wMedium
                                        color: modeSwitch.agent ? Theme.textPrimary : Theme.textTertiary }
                            }
                            MouseArea { id: agentSegArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: { OllamaService.mode = "agent"; OllamaService.syncCurrentSession(); } }
                        }
                    }
                    MessageAction { x: 0; width: chatSeg.width; height: 30; color: "transparent"; icon: ""; enabled: false; hoverSource: chatSegArea
                                    tip: "Chat: answers, search, prices, your screen · reads, never changes · ⌃." }
                    MessageAction { x: chatSeg.width; width: agentSeg.width; height: 30; color: "transparent"; icon: ""; enabled: false; hoverSource: agentSegArea
                                    tip: "Agent: files, sandbox, plans, your machine (asks first) · ⌃." }
                }

                Item { width: 2; height: 1 }

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
                    MessageAction {
                        anchors.fill: parent
                        color: "transparent"; icon: ""; enabled: false
                        tip: "Model · ⌃K"
                        hoverSource: modelArea
                    }
                }
            }

            ContextMeter {
                anchors.right: sendBox.left
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
            }

            // Right cluster: Cancel or Send Button (Raised Button Plate)
            Item {
                id: sendBox
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 36; height: 36

                Rectangle {
                    anchors.fill: parent
                    radius: 18
                    readonly property bool stopping: OllamaService.streaming && !root.canSend
                    color: stopping
                        ? (btnArea.containsMouse ? Theme.red : Qt.alpha(Theme.red, 0.90))
                        : (root.canSend ? (btnArea.containsMouse ? Theme.accent : Qt.alpha(Theme.accent, 0.92)) : Qt.rgba(1, 1, 1, 0.08))
                    scale: btnArea.pressed ? 0.97 : 1

                    Behavior on scale { NumberAnimation { duration: Theme.pressMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                    Behavior on color { ColorAnimation { duration: Theme.colorMs } }

                    Icon {
                        anchors.centerIn: parent
                        name: parent.stopping ? "stop" : "arrow-up"
                        style: parent.stopping ? "fill" : "bold"
                        size: 16
                        color: parent.stopping || root.canSend ? Theme.onAccent : Theme.textDim
                    }

                    MouseArea {
                        id: btnArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (parent.stopping) OllamaService.cancel();
                            else if (root.canSend) root.submit();          // mid-answer this steers
                        }
                    }
                    MessageAction {
                        anchors.fill: parent
                        color: "transparent"; icon: ""; enabled: false
                        tip: parent.stopping ? "Stop · Esc" : OllamaService.streaming ? "Steer this answer · ↵" : "Send · ↵"
                        hoverSource: btnArea
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
        if (root.editIndex >= 0 && !OllamaService.streaming) {
            const i = root.editIndex;
            root.editIndex = -1;
            root.submitted(prompt);
            OllamaService.editAndResend(i, prompt);
            return;
        }
        if (OllamaService.streaming) { OllamaService.steer(prompt); return; }   // ↵ mid-answer steers it
        root.submitted(prompt);
        OllamaService.send(prompt);
    }
}
