// Assistant Overlay: Native Wayland AI Assistant HUD
// Physical Dynamic Island emergence (Aceternity fluid notch & Apple physics).
// Features Compact HUD mode (840x560) & Expanded Studio mode (1080x820) with shadcn ChatSidebar.
// Bound to SUPER + CTRL + SHIFT + A.
import QtQuick
import QtQuick.Effects
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import qs.config
import qs.components
import qs.components.ai
import qs.services

Scope {
    id: root

    readonly property bool open: Assistant.open
    property bool studioMode: false
    property bool sidebarOpen: true
    property bool appLauncherOpen: false
    // ⌃F / "Search chats": the sidebar opens (studio) with its search focused.
    signal searchRequested()
    function searchChats() {
        root.studioMode = true;
        root.sidebarOpen = true;
        Qt.callLater(root.searchRequested);
    }
    property bool armed: false

    Timer {
        id: armTimer
        interval: 180
        onTriggered: root.armed = root.open
    }

    onOpenChanged: {
        if (open) {
            armed = false;
            armTimer.restart();
        } else {
            armTimer.stop();
            armed = false;
            // Closing doesn't decline: the request waits (it times out on its own) and you get a
            // notification to come back to it; the turn carries on in the background.
            if (OllamaService.pendingRequest) OllamaService.notifyPending();
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property ShellScreen modelData
            screen: modelData

            readonly property bool isTarget: Assistant.targetScreen === "" || Assistant.targetScreen === modelData.name || Quickshell.screens.length === 1
            readonly property bool up: root.open && isTarget

            readonly property bool inIsland: Settings.bar === "island"
            readonly property bool notch: inIsland && Settings.islandStyle !== "floating"
            readonly property real islandW: (typeof Island !== "undefined" && Island.restWidths && Island.restWidths[modelData.name]) || 220
            readonly property real pillH: inIsland ? 34 : 38

            // Dimensions: Spacious HUD matching desktop rice scale with proportional expansion
            readonly property int compactW: Math.min(920, Math.round(modelData.width * 0.52))
            readonly property int compactH: Math.min(640, Math.round(modelData.height * 0.60))
            readonly property int studioW: Math.min(1240, Math.round(modelData.width * 0.75))
            readonly property int studioH: Math.min(880, Math.round(modelData.height * 0.82))

            readonly property real targetW: root.studioMode ? studioW : compactW
            // Compact grows with the conversation (Spotlight / Raycast): a short chat
            // gets a short panel, not a tall one with dead space; it stops at compactH
            // and scrolls from there. Studio stays full height.
            readonly property real chatNeed: OllamaService.messages.length === 0 && !OllamaService.streaming
                                             ? 260 : scroll.contentHeight + 12
            readonly property real fitH: chatNeed + 38 + 1 + 12 + promptInput.implicitHeight + 12 + 32
            readonly property real targetH: root.studioMode ? studioH : Math.max(300, Math.min(compactH, fitH))

            anchors.top: true
            margins.top: inIsland ? (notch ? 0 : 6) : 6

            readonly property bool shown: up || melt.value > 0.01
            implicitWidth: shown ? Math.max(studioW, compactW) + 40 : 1
            implicitHeight: shown ? Math.max(studioH, compactH) + 60 : 1
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"

            WlrLayershell.namespace: "rice-assistant"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: (up && !Assistant.sniping) ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            mask: Region { item: win.up ? frame : null }

            HyprlandFocusGrab {
                windows: [win]
                active: win.up && root.armed && !Assistant.sniping
                onCleared: Assistant.hide()
            }

            Item {
                anchors.fill: parent
                focus: true
                Keys.onEscapePressed: {
                    if (OllamaService.pendingRequest) {
                        OllamaService.resolveRequest(OllamaService.pendingRequest.id, "decline");
                    } else if (root.appLauncherOpen) {
                        root.appLauncherOpen = false;
                    } else if (OllamaService.streaming) {
                        OllamaService.cancel();
                    } else {
                        Assistant.hide();
                    }
                }
                Keys.onPressed: event => {
                    if (event.modifiers & Qt.ControlModifier) {
                        if (event.key === Qt.Key_N) {
                            event.accepted = true;
                            OllamaService.newChat();
                        } else if (event.key === Qt.Key_O || event.key === Qt.Key_P) {
                            event.accepted = true;
                            root.appLauncherOpen = !root.appLauncherOpen;
                        } else if (event.key === Qt.Key_K) {
                            event.accepted = true;
                            modelPicker.toggle();
                        } else if (event.key === Qt.Key_F) {
                            event.accepted = true;
                            root.searchChats();
                        } else if (event.key === Qt.Key_L) {
                            event.accepted = true;
                            OllamaService.clear();
                        } else if (event.key === Qt.Key_B) {
                            event.accepted = true;
                            if (!root.studioMode) root.studioMode = true;
                            root.sidebarOpen = !root.sidebarOpen;
                        } else if (event.key === Qt.Key_M || event.key === Qt.Key_E) {
                            event.accepted = true;
                            root.studioMode = !root.studioMode;
                        }
                    }
                }
            }

            // ── Dynamic Island Emergence Springs ───────────────────────
            Spring {
                id: melt
                // Out quicker than in (an exit shouldn't linger), on the same curve back into the notch.
                tier: win.up ? Theme.springModerate : Theme.springFast
                target: win.up ? 1 : 0
                epsilon: 0.001
            }

            Spring {
                id: morphW
                tier: Theme.springSlow
                target: win.targetW
                epsilon: 0.5
            }

            Spring {
                id: morphH
                tier: Theme.springSlow
                target: win.targetH
                epsilon: 0.5
            }

            function lerp(a, b, k) { return a + (b - a) * k; }
            readonly property real m: melt.value
            readonly property real mh: Math.pow(Math.max(0, Math.min(1, m)), 0.78)

            readonly property real currentW: lerp(win.islandW, morphW.value, win.m)
            readonly property real currentH: lerp(win.pillH, morphH.value, win.mh)

            // Deep Layered Elevation
            Elevation {
                target: frame
                radius: frame.radius
                strength: Math.min(1, win.m)
            }

            // ── Main Glass Frame (Emerging from Island) ───────────────
            Rectangle {
                id: frame
                // Stays while it melts back into the notch (it vanished the moment you closed it).
                visible: win.m > 0.01
                width: Math.max(1, win.currentW)
                height: Math.max(1, win.currentH)
                x: Math.round((win.width - width) / 2)
                y: 0
                radius: win.lerp(win.notch ? 14 : win.pillH / 2, 22, win.m)
                color: "transparent"
                opacity: Math.min(1, win.m * 2.2)
                clip: true

                GlassCard {
                    anchors.fill: parent
                    radius: frame.radius
                    tint: win.inIsland ? Qt.rgba(0.05, 0.05, 0.07, 0.88) : Theme.glassTintElevated
                }

                // Inner Main Split: [Sidebar | Conversation Canvas]
                Row {
                    anchors.fill: parent

                    // ── Collapsible Chat Sidebar ──────────────────────
                    Connections {
                        target: root
                        function onSearchRequested() { if (win.up) sidebar.focusSearch(); }
                    }
                    ChatSidebar {
                        id: sidebar
                        open: root.studioMode && root.sidebarOpen
                        height: parent.height
                        onNewChatRequested: {
                            promptInput.focusInput();
                        }
                    }

                    // ── Main Conversation Canvas ──────────────────────
                    Item {
                        width: parent.width - sidebar.width
                        height: parent.height

                        Column {
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 12

                            // ── Header: the chat's title; quiet icon buttons ──────
                            // (sidebar · title … new chat · apps · studio · close).
                            // Status only speaks when something is wrong.
                            Item {
                                width: parent.width
                                height: 38

                                Row {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 8

                                    MessageAction {
                                        visible: root.studioMode
                                        width: 30; height: 30
                                        icon: "sidebar-simple"
                                        tip: "Chats · ⌃B"
                                        anchors.verticalCenter: parent.verticalCenter
                                        onClicked: root.sidebarOpen = !root.sidebarOpen
                                    }

                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 1
                                        Label {
                                            readonly property var sess: OllamaService.sessions.find(x => x.id === OllamaService.activeSessionId)
                                            text: sess && sess.title && OllamaService.messages.length > 0 ? sess.title : "New chat"
                                            size: 14
                                            weight: Theme.wSemibold
                                            color: Theme.textPrimary
                                            elide: Text.ElideRight
                                            width: Math.min(implicitWidth, 420)
                                        }
                                        Row {
                                            visible: OllamaService.status !== "ready"
                                            spacing: 6
                                            Rectangle { width: 6; height: 6; radius: 3; color: Theme.red; anchors.verticalCenter: parent.verticalCenter }
                                            Label { text: "Ollama isn't running"; size: 12; color: Theme.textTertiary }
                                        }
                                    }
                                }

                                Row {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 2

                                    MessageAction { width: 30; height: 30; icon: "note-pencil"; tip: "New chat · ⌃N"; onClicked: { OllamaService.newChat(); promptInput.focusInput(); } }
                                    MessageAction { width: 30; height: 30; icon: "squares-four"; tip: "Open an app · ⌃O"; onClicked: root.appLauncherOpen = !root.appLauncherOpen }
                                    MessageAction { width: 30; height: 30; icon: root.studioMode ? "arrows-in-simple" : "arrows-out-simple"; tip: (root.studioMode ? "Smaller" : "Bigger, with your chats") + " · ⌃M"; onClicked: root.studioMode = !root.studioMode }
                                    MessageAction { width: 30; height: 30; icon: "x"; tip: "Close · Esc"; onClicked: Assistant.hide() }
                                }
                            }

                            // ── Hairline Divider ──────────────────────
                            Rectangle {
                                width: parent.width
                                height: 1
                                color: Qt.rgba(1, 1, 1, 0.06)
                            }

                            // ── Message Scroller ──────────────────────
                            Item {
                                width: parent.width
                                height: parent.height - 38 - 1 - 12 - promptInput.implicitHeight - 12
                                clip: true

                                // Empty state: one question, and a few things it can do right now.
                                Item {
                                    anchors.fill: parent
                                    visible: OllamaService.messages.length === 0 && !OllamaService.streaming

                                    Column {
                                        anchors.centerIn: parent
                                        spacing: 18
                                        width: Math.min(560, parent.width * 0.9)

                                        Column {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            spacing: 6
                                            Label {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                text: OllamaService.status === "ready" ? "What can I help with?" : "Ollama isn't running"
                                                size: 22
                                                weight: Theme.wSemibold
                                                color: Theme.textPrimary
                                            }
                                            Label {
                                                visible: OllamaService.status !== "ready"
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                text: "Start it with systemctl --user start ollama"
                                                size: 13
                                                color: Theme.textTertiary
                                            }
                                        }

                                        Flow {
                                            visible: OllamaService.status === "ready"
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            width: Math.min(parent.width, implicitWidthGuess)
                                            readonly property real implicitWidthGuess: 520
                                            spacing: 8

                                            Suggestion { icon: "app-window"; text: "Look at this window"; onClicked: OllamaService.snapshotActiveWindow() }
                                            Suggestion { icon: "cursor-text"; text: "Explain what I've selected"; onClicked: OllamaService.send("Explain the text I have selected.") }
                                            Suggestion { icon: "clipboard-text"; text: "Summarise my clipboard"; onClicked: OllamaService.send("Summarise what's on my clipboard.") }
                                            Suggestion { icon: "cpu"; text: "What's using my GPU?"; onClicked: OllamaService.send("How busy is my GPU and memory right now?") }
                                        }
                                    }
                                }

                                // Message Scroller List
                                Flickable {
                                    id: scroll
                                    anchors.fill: parent
                                    visible: OllamaService.messages.length > 0 || OllamaService.streaming
                                    contentWidth: width
                                    contentHeight: msgCol.implicitHeight
                                    clip: true

                                    // Following the newest text (T3 Code's rule): only scrolling *up*
                                    // lets go of the bottom. Scrolling down while text streams in reads as
                                    // "not at the end" for a frame, so it mustn't count; coming back within
                                    // 40 px of the end picks the stream up again.
                                    property bool userScrolledUp: false
                                    property real lastY: 0
                                    readonly property real fromEnd: contentHeight - height - contentY
                                    onContentYChanged: {
                                        if (moving) {
                                            if (contentY < lastY - 1) userScrolledUp = true;
                                            else if (fromEnd <= 40) userScrolledUp = false;
                                        }
                                        lastY = contentY;
                                    }
                                    onMovementEnded: if (fromEnd <= 40) userScrolledUp = false

                                    // Scroll fade (AI Elements' utility): the edges fade out only when
                                    // there's more to scroll that way, so text never meets a hard cut.
                                    layer.enabled: contentHeight > height
                                    layer.effect: MultiEffect {
                                        maskEnabled: true
                                        maskSource: fadeMask
                                        maskThresholdMin: 0.0
                                        maskSpreadAtMin: 1.0
                                    }

                                    onContentHeightChanged: {
                                        // Auto-follow bottom during stream unless user manually scrolled up
                                        if (!userScrolledUp || !OllamaService.streaming) {
                                            Qt.callLater(() => {
                                                scroll.contentY = Math.max(0, scroll.contentHeight - scroll.height);
                                            });
                                        }
                                    }

                                    Column {
                                        id: msgCol
                                        width: parent.width
                                        spacing: 16

                                        // An int model: delegates stay put as messages update (a new
                                        // answer or its rendered Markdown doesn't rebuild the chat).
                                        Repeater {
                                            id: msgRepeater
                                            model: OllamaService.messages.length

                                            ChatMessage {
                                                width: msgCol.width
                                                msgIndex: index
                                                msg: OllamaService.messages[index] || ({})
                                                isLast: index === msgRepeater.count - 1 && !OllamaService.streaming
                                                // Only what you just sent animates in; history and finished answers don't.
                                                animateIn: msg.role === "user" && index === OllamaService.messages.length - 1
                                                           && Date.now() - (msg.timestamp || 0) < 1500
                                            }
                                        }

                                        // The answer in flight
                                        ChatMessage {
                                            visible: OllamaService.streaming
                                            width: msgCol.width
                                            msg: OllamaService.draft || ({ role: "assistant", parts: [] })
                                            isStreaming: true
                                        }

                                        // A failed turn: one quiet line and a way to try again.
                                        Row {
                                            visible: OllamaService.errorText !== "" && !OllamaService.streaming
                                            width: parent.width
                                            spacing: 8
                                            Icon { name: "warning-circle"; size: 15; color: Theme.red; anchors.verticalCenter: parent.verticalCenter }
                                            Label {
                                                text: OllamaService.errorText
                                                size: 13
                                                color: Theme.textSecondary
                                                wrapMode: Text.Wrap
                                                width: Math.min(implicitWidth, parent.width - 90)
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                            Label {
                                                text: "Try again"
                                                size: 13
                                                weight: Theme.wMedium
                                                color: Theme.accent
                                                anchors.verticalCenter: parent.verticalCenter
                                                MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: OllamaService.retry() }
                                            }
                                        }
                                    }
                                }

                                Item {
                                    id: fadeMask
                                    anchors.fill: scroll
                                    visible: false
                                    layer.enabled: true
                                    readonly property real fadeTop: Math.min(1, scroll.contentY / 24) * 28 / Math.max(1, height)
                                    readonly property real fadeBottom: Math.min(1, scroll.fromEnd / 24) * 28 / Math.max(1, height)
                                    Rectangle {
                                        anchors.fill: parent
                                        gradient: Gradient {
                                            GradientStop { position: 0.0; color: fadeMask.fadeTop > 0 ? "transparent" : "white" }
                                            GradientStop { position: Math.max(0.001, fadeMask.fadeTop); color: "white" }
                                            GradientStop { position: Math.min(0.999, 1 - fadeMask.fadeBottom); color: "white" }
                                            GradientStop { position: 1.0; color: fadeMask.fadeBottom > 0 ? "transparent" : "white" }
                                        }
                                    }
                                }

                                // Scrolled up: a way back to the newest message (prompt-kit's scroll button).
                                Rectangle {
                                    id: toBottom
                                    // Not while it's following the stream (a big block landing would flash it).
                                    readonly property bool show: scroll.visible && scroll.fromEnd > 120
                                                                 && (scroll.userScrolledUp || !OllamaService.streaming)
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: show || Theme.reduceMotion ? 10 : 6
                                    width: 34; height: 34
                                    radius: 17
                                    color: Qt.rgba(0.16, 0.16, 0.19, 0.96)
                                    border.width: 1
                                    border.color: Qt.rgba(1, 1, 1, 0.12)
                                    opacity: show ? 1 : 0
                                    visible: opacity > 0.01
                                    scale: tbArea.pressed ? 0.97 : 1
                                    Behavior on opacity { NumberAnimation { duration: toBottom.show ? Theme.enterMs : Theme.exitMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                                    Behavior on anchors.bottomMargin { NumberAnimation { duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                                    Behavior on scale { NumberAnimation { duration: Theme.pressMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                                    Icon { anchors.centerIn: parent; name: "arrow-down"; style: "bold"; size: 14; color: Theme.textPrimary }
                                    NumberAnimation {
                                        id: glideDown
                                        target: scroll; property: "contentY"
                                        duration: Theme.reduceMotion ? 0 : 260
                                        easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut
                                    }
                                    MouseArea {
                                        id: tbArea
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            scroll.userScrolledUp = false;
                                            glideDown.to = Math.max(0, scroll.contentHeight - scroll.height);
                                            glideDown.restart();
                                        }
                                    }
                                }
                            }

                            // ── Sticky Footer (Prompt Input) ──────────
                            PromptInput {
                                id: promptInput
                                width: parent.width
                                picker: modelPicker
                                popups: [slashMenu]
                                onModelPickerRequested: modelPicker.toggle()
                                onSlashRequested: slashMenu.open = true
                                onSearchRequested: root.searchChats()
                                onOpenAppLauncherRequested: root.appLauncherOpen = !root.appLauncherOpen
                                onToggleSidebarRequested: {
                                    if (!root.studioMode) root.studioMode = true;
                                    root.sidebarOpen = !root.sidebarOpen;
                                }
                                onToggleStudioRequested: root.studioMode = !root.studioMode
                                onEscapeRequested: {
                                    if (OllamaService.pendingRequest) {
                                        OllamaService.resolveRequest(OllamaService.pendingRequest.id, "decline");
                                    } else if (root.appLauncherOpen) {
                                        root.appLauncherOpen = false;
                                    } else if (OllamaService.streaming) {
                                        OllamaService.cancel();
                                    } else {
                                        Assistant.hide();
                                    }
                                }
                                onSubmitted: prompt => {
                                    scroll.userScrolledUp = false;
                                    Qt.callLater(() => {
                                        scroll.contentY = Math.max(0, scroll.contentHeight - scroll.height);
                                    });
                                }
                            }
                        }
                    }
                }
            }


                // ── Model picker: grows out of the model pill (⌃K) ────────
                ModelPickerMenu {
                    id: modelPicker
                    anchorItem: promptInput.modelPill
                    onClosed: promptInput.focusInput()
                }

                // ── Slash commands: "/" on an empty prompt ────────────────
                ActionMenu {
                    id: slashMenu
                    anchorItem: promptInput.slashAnchor
                    title: "Commands"
                    menuW: 300
                    items: [
                        { id: "snap", label: "Attach this window", keys: [], section: "Context" },
                        { id: "shot", label: "Attach a region of the screen", keys: [] },
                        { id: "paste", label: "Paste an image", keys: ["⌃", "V"] },
                        { id: "model", label: "Choose model", keys: ["⌃", "K"], section: "Chat" },
                        { id: "new", label: "New chat", keys: ["⌃", "N"] },
                        { id: "clear", label: "Clear this chat", keys: ["⌃", "L"] },
                        { id: "copychat", label: "Copy chat as Markdown", keys: [] },
                        { id: "compact", label: "Summarise this chat now", keys: [] },
                        { id: "fork", label: "Fork this chat", keys: [] },
                        { id: "search", label: "Search chats", keys: ["⌃", "F"] },
                        { id: "apps", label: "Open an app", keys: ["⌃", "O"] }
                    ]
                    onPicked: id => {
                        if (id === "snap") OllamaService.snapshotActiveWindow();
                        else if (id === "shot") OllamaService.takeScreenshot();
                        else if (id === "paste") OllamaService.pasteClipboardImage();
                        else if (id === "model") modelPicker.open = true;
                        else if (id === "new") OllamaService.newChat();
                        else if (id === "clear") OllamaService.clear();
                        else if (id === "copychat") OllamaService.copyChat();
                        else if (id === "compact") OllamaService.compactNext = true;
                        else if (id === "fork") OllamaService.forkAt(-1);
                        else if (id === "search") { root.searchChats(); return; }
                        else if (id === "apps") root.appLauncherOpen = true;
                        promptInput.focusInput();
                    }
                }

                // ── App Launcher / Command Palette Modal (Ctrl+O) ────────
                // A dialog: the slow spring (0.96 → 1, fading in), the backdrop
                // dimming with it; reduced motion keeps only the fades.
                Spring { id: appT; tier: Theme.springSlow; epsilon: 0.002; target: root.appLauncherOpen ? 1 : 0 }
                Rectangle {
                    id: appModal
                    visible: appT.value > 0.002 || root.appLauncherOpen
                    // Only over the panel (the layer window is bigger than the panel: filling
                    // it drew a black box around the panel).
                    x: frame.x; y: frame.y; width: frame.width; height: frame.height
                    color: Qt.rgba(0, 0, 0, 0.45 * Math.min(1, appT.value))
                    radius: frame.radius
                    z: 99

                    MouseArea {
                        anchors.fill: parent
                        enabled: root.appLauncherOpen
                        onClicked: root.appLauncherOpen = false
                    }

                    Rectangle {
                        scale: Theme.reduceMotion ? 1 : 0.96 + 0.04 * appT.value
                        opacity: Math.min(1, appT.value * 3)
                        width: Math.min(540, parent.width - 40)
                        height: Math.min(420, parent.height - 40)
                        anchors.centerIn: parent
                        radius: 16
                        color: Theme.glassTintElevated
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.12)
                        clip: true

                        Elevation {
                            strength: 1
                            radius: 16
                        }

                        Column {
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 10

                            // Search Header
                            Rectangle {
                                width: parent.width
                                height: 42
                                radius: 10
                                color: Qt.rgba(0, 0, 0, 0.35)
                                border.width: 1
                                border.color: appSearchInput.activeFocus ? Theme.accent : Qt.rgba(1, 1, 1, 0.10)

                                Row {
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 10

                                    Icon {
                                        name: "magnifying-glass"
                                        size: 15
                                        color: Theme.accent
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    TextInput {
                                        id: appSearchInput
                                        width: parent.width - 30 - escBadge.width - 20
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: Theme.textPrimary
                                        font.family: Theme.fontText
                                        font.pixelSize: 14
                                        selectByMouse: true
                                        clip: true

                                        Text {
                                            text: "Search apps to launch... (↑↓ to select, ↵ to run)"
                                            color: Theme.textDim
                                            font.pixelSize: 14
                                            visible: !appSearchInput.text && !appSearchInput.inputMethodComposing
                                        }

                                        Keys.onDownPressed: {
                                            if (appListView.count > 0) {
                                                appListView.currentIndex = (appListView.currentIndex + 1) % appListView.count;
                                            }
                                        }
                                        Keys.onUpPressed: {
                                            if (appListView.count > 0) {
                                                appListView.currentIndex = (appListView.currentIndex - 1 + appListView.count) % appListView.count;
                                            }
                                        }
                                        Keys.onReturnPressed: {
                                            if (appListView.currentItem) {
                                                appListView.currentItem.launch();
                                            }
                                        }
                                        Keys.onEscapePressed: {
                                            root.appLauncherOpen = false;
                                        }
                                    }

                                    Rectangle {
                                        id: escBadge
                                        height: 22
                                        width: escLabel.implicitWidth + 12
                                        radius: 5
                                        color: Qt.rgba(1, 1, 1, 0.08)
                                        anchors.verticalCenter: parent.verticalCenter

                                        Label {
                                            id: escLabel
                                            anchors.centerIn: parent
                                            text: "Esc"
                                            size: 10
                                            color: Theme.textTertiary
                                        }
                                    }
                                }
                            }

                            // Apps List View
                            ListView {
                                id: appListView
                                width: parent.width
                                height: parent.height - 42 - 10
                                clip: true
                                spacing: 4

                                readonly property var allApps: (typeof DesktopEntries !== "undefined" && DesktopEntries.applications) 
                                    ? DesktopEntries.applications.values.filter(e => !e.noDisplay) 
                                    : []

                                readonly property var filteredApps: {
                                    const q = appSearchInput.text.toLowerCase().trim();
                                    if (!q) return allApps;
                                    return allApps.filter(a => 
                                        (a.name && a.name.toLowerCase().indexOf(q) >= 0) ||
                                        (a.comment && a.comment.toLowerCase().indexOf(q) >= 0) ||
                                        (a.id && a.id.toLowerCase().indexOf(q) >= 0)
                                    );
                                }

                                model: filteredApps

                                delegate: Rectangle {
                                    id: appItem
                                    width: appListView.width
                                    height: 44
                                    radius: 8
                                    color: (appListView.currentIndex === index || appItemArea.containsMouse) 
                                        ? Qt.alpha(Theme.accent, 0.15) 
                                        : "transparent"
                                    border.width: appListView.currentIndex === index ? 1 : 0
                                    border.color: Qt.alpha(Theme.accent, 0.3)

                                    function launch() {
                                        modelData.execute();
                                        root.appLauncherOpen = false;
                                        OllamaService.recordToolLaunch(modelData.name);
                                    }

                                    Row {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 10

                                        // The app's own icon from the icon theme; a quiet glyph if it has none.
                                        Item {
                                            id: appIcon
                                            width: 26; height: 26
                                            anchors.verticalCenter: parent.verticalCenter
                                            readonly property string path: modelData.icon ? Quickshell.iconPath(modelData.icon, true) : ""
                                            IconImage { anchors.fill: parent; visible: appIcon.path !== ""; source: appIcon.path; asynchronous: true }
                                            Icon {
                                                visible: appIcon.path === ""
                                                anchors.centerIn: parent
                                                name: "app-window"
                                                size: 18
                                                color: Theme.textTertiary
                                            }
                                        }

                                        Column {
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 2

                                            Label {
                                                text: modelData.name || "Application"
                                                size: 13
                                                weight: Theme.wSemibold
                                                color: Theme.textPrimary
                                            }

                                            Label {
                                                text: modelData.comment || modelData.id || "Desktop Application"
                                                size: 11
                                                color: Theme.textTertiary
                                                elide: Text.ElideRight
                                                width: 380
                                            }
                                        }
                                    }

                                    KeyCap {
                                        anchors.right: parent.right
                                        anchors.rightMargin: 12
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "Enter"
                                        size: 10
                                        visible: appListView.currentIndex === index || appItemArea.containsMouse
                                    }

                                    MouseArea {
                                        id: appItemArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: appItem.launch()
                                    }
                                }
                            }
                        }
                    }
                }

            onUpChanged: {
                if (up) {
                    Qt.callLater(() => {
                        promptInput.focusInput();
                    });
                }
            }

            Connections {
                target: root
                function onAppLauncherOpenChanged() {
                    if (root.appLauncherOpen) {
                        Qt.callLater(() => appSearchInput.forceActiveFocus());
                    } else {
                        Qt.callLater(() => promptInput.focusInput());
                    }
                }
            }
        }
    }
}
