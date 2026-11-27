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
import "ai"
import qs.services
import qs.components.ui as Ui
import "../../services/surfaceState.mjs" as Surface

Scope {
    id: root

    readonly property bool open: Assistant.open
    readonly property bool needsOptIn: !Settings.assistantOptIn
    property bool studioMode: false
    // Almost the whole screen (⌃⇧M, the corners button): for long work, a
    // big diff, a wide table. Your chats beside it, like studio.
    property bool fullMode: false
    onFullModeChanged: if (fullMode) studioMode = true
    onStudioModeChanged: if (!studioMode) fullMode = false
    property bool sidebarOpen: true
    property bool appLauncherOpen: false
    // ⌃F / "Search chats": the sidebar opens (studio) with its search focused.
    signal searchRequested()
    function searchChats() {
        root.studioMode = true;
        root.sidebarOpen = true;
        Qt.callLater(root.searchRequested);
    }
    property var surface: Surface.createSurfaceState()
    readonly property var surfaceOut: Surface.surfaceOutputs(surface)
    readonly property bool armed: surfaceOut.armed
    // Built only while used: open, and 10 s after (the close animation, and a
    // quick reopen stays instant). It used to be mapped for good on every
    // screen as a 1×1 surface with the whole chat UI inside.
    property bool alive: open
    Timer { id: linger; interval: 10000; onTriggered: { root.alive = root.open; if (!root.open) root.surface = Surface.stepSurface(root.surface, { type: "foldDone", seq: root.surface.seq }).state; } }

    Timer {
        id: armTimer
        property int seq: 0
        interval: 180
        onTriggered: root.surface = Surface.stepSurface(root.surface, { type: "armed", seq: seq }).state
    }

    onOpenChanged: {
        if (open) {
            linger.stop();
            alive = true;
            surface = Surface.stepSurface(surface, { type: "open" }).state;
            surface = Surface.stepSurface(surface, { type: "surfaceMapped", seq: surface.seq }).state;
            armTimer.seq = surface.seq;
            armTimer.restart();
        } else {
            armTimer.stop();
            surface = Surface.stepSurface(surface, { type: "close" }).state;
            linger.restart();
            // Closing doesn't decline: the request waits (it times out on its own) and you get a
            // notification to come back to it; the turn carries on in the background.
            if (OllamaService.pendingRequest) OllamaService.notifyPending();
        }
    }

    Variants {
        model: Quickshell.screens

        LazyLoader {
            id: slot
            required property ShellScreen modelData
            active: root.alive && (Quickshell.screens.length === 1 || Assistant.targetScreen === "" || Assistant.targetScreen === modelData.name)
        PanelWindow {
            id: win
            readonly property ShellScreen modelData: slot.modelData
            screen: modelData

            readonly property bool isTarget: Assistant.targetScreen === "" || Assistant.targetScreen === modelData.name || Quickshell.screens.length === 1
            readonly property bool up: root.open && isTarget

            readonly property bool inIsland: Settings.bar === "island"
            readonly property bool notch: inIsland && Settings.islandStyle !== "floating"
            readonly property real islandW: (typeof Island !== "undefined" && Island.restWidths && Island.restWidths[modelData.name]) || 220
            readonly property real pillH: inIsland ? 34 : 38

            // Dimensions: Spacious HUD matching desktop kuwai scale with proportional expansion
            readonly property real scrW: Theme.screenSize(modelData, "width", 1920)
            readonly property real scrH: Theme.screenSize(modelData, "height", 1080)
            readonly property int compactW: Math.min(920, Math.round(scrW * 0.52))
            readonly property int compactH: Math.min(640, Math.round(scrH * 0.60))
            readonly property int studioW: Math.min(1240, Math.round(scrW * 0.75))
            readonly property int studioH: Math.min(880, Math.round(scrH * 0.82))

            readonly property int fullW: scrW - 48
            readonly property int fullH: scrH - 36
            readonly property real targetW: root.fullMode ? fullW : root.studioMode ? studioW : compactW
            // Compact grows with the conversation (Spotlight / Raycast): a short chat
            // gets a short panel, not a tall one with dead space; it stops at compactH
            // and scrolls from there. Studio stays full height.
            readonly property real chatNeed: OllamaService.messages.length === 0 && !OllamaService.busyHere
                                             ? 260 : scroll.contentHeight + 12
            readonly property real fitH: chatNeed + 38 + 1 + 12 + promptInput.implicitHeight + 12 + 32
            readonly property real targetH: root.fullMode ? fullH : root.studioMode ? studioH : Math.max(300, Math.min(compactH, fitH))

            anchors.top: true
            margins.top: inIsland ? (notch ? 0 : 6) : 6

            readonly property bool shown: up || melt.value > 0.01
            implicitWidth: shown ? Math.max(studioW, compactW, root.fullMode ? fullW : 0) + 40 : 1
            implicitHeight: shown ? Math.max(studioH, compactH, root.fullMode ? fullH : 0) + 36 : 1
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"

            WlrLayershell.namespace: "kuwai-assistant"
            WlrLayershell.layer: WlrLayer.Overlay
            // Yielded (a window opened over it): on demand, so a click in the
            // assistant takes the keyboard back.
            WlrLayershell.keyboardFocus: !up || Assistant.sniping ? WlrKeyboardFocus.None
                : Assistant.yielded ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive

            mask: Region { item: win.up ? frame : null }

            HyprlandFocusGrab {
                windows: [win]
                active: win.up && root.armed && !Assistant.sniping && !Assistant.yielded
                onCleared: Assistant.hide()
            }

            Item {
                anchors.fill: parent
                // A click in it after a window took the keyboard: it's yours again.
                PointHandler { onActiveChanged: if (active && Assistant.yielded) Assistant.yielded = false }
                focus: true
                Keys.onEscapePressed: {
                    if (OllamaService.pendingHere) {
                        OllamaService.resolveRequest(OllamaService.pendingHere.id, "decline");
                    } else if (root.appLauncherOpen) {
                        root.appLauncherOpen = false;
                    } else if (OllamaService.busyHere) {
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
                            OllamaService.requestClear();
                        } else if (event.key === Qt.Key_B) {
                            event.accepted = true;
                            if (!root.studioMode) root.studioMode = true;
                            root.sidebarOpen = !root.sidebarOpen;
                        } else if (event.key === Qt.Key_M && (event.modifiers & Qt.ShiftModifier)) {
                            event.accepted = true;
                            root.fullMode = !root.fullMode;
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

            // ── The notch, grown: in notch style the assistant IS the notch
            // (square into the screen edge, the same ears, its rim), not a
            // rounded card hanging under it. Drawn outside the frame (its ears
            // reach past it); the frame clips only the content.
            NotchShape {
                visible: win.notch && frame.visible
                x: frame.x - ear; y: 0
                w: frame.width; h: frame.height
                ear: 9
                radius: frame.radius
                fill: Qt.rgba(0.02, 0.02, 0.03, 0.96)
                opacity: frame.opacity
            }
            LiquidRim {
                visible: win.notch && frame.visible
                x: frame.x - 9; y: 0
                width: frame.width + 18; height: frame.height
                ear: 9
                radius: frame.radius * 1.2
                strength: Math.min(1, win.m) * 0.8
                light: Qt.point(width * 0.22, height + 90)
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
                    visible: !win.notch
                    anchors.fill: parent
                    radius: frame.radius
                    tint: win.inIsland ? Qt.rgba(0.05, 0.05, 0.07, 0.88) : Theme.glassTintElevated
                }

                Column {
                    anchors.centerIn: parent
                    width: Math.min(320, parent.width - 48)
                    visible: root.needsOptIn && win.m > 0.4
                    spacing: 14
                    Label { width: parent.width; wrapMode: Text.WordWrap; text: "Local assistant"; size: Theme.tTitle2; weight: Theme.wSemibold; horizontalAlignment: Text.AlignHCenter }
                    Label {
                        width: parent.width; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter
                        text: "Chat with Ollama on this machine. Off until you opt in — like Omarchy Quattro, nothing runs in the background without your choice."
                        size: Theme.tBody; color: Theme.textSecondary
                    }
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 10
                        Ui.Button {
                            height: Theme.sp(30); size: Theme.tSub
                            text: "Not now"
                            onClicked: Assistant.hide()
                        }
                        Ui.Button {
                            primary: true
                            text: "Turn on"
                            onClicked: {
                                Settings.set("assistantOptIn", true);
                                Settings.set("seenAssistantPrompt", true);
                            }
                        }
                    }
                }

                // Inner Main Split: [Sidebar | Conversation Canvas]
                Row {
                    anchors.fill: parent
                    visible: !root.needsOptIn

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
                                        tip: "Chats · Ctrl+B"
                                        anchors.verticalCenter: parent.verticalCenter
                                        onClicked: root.sidebarOpen = !root.sidebarOpen
                                    }

                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 1
                                        Label {
                                            readonly property var sess: OllamaService.sessions.find(x => x.id === OllamaService.activeSessionId)
                                            text: sess && sess.title && OllamaService.messages.length > 0 ? sess.title : "New chat"
                                            size: Theme.tCallout
                                            weight: Theme.wSemibold
                                            color: Theme.textPrimary
                                            elide: Text.ElideRight
                                            width: Math.min(implicitWidth, Math.max(120, parent.parent.parent.width - 240))   // the header, not the Row (that would loop)
                                        }
                                        Row {
                                            visible: OllamaService.status !== "ready"
                                            spacing: 6
                                            Rectangle { width: 6; height: 6; radius: 3; color: Theme.red; anchors.verticalCenter: parent.verticalCenter }
                                            Label { text: "Ollama isn't running"; size: Theme.tSub; color: Theme.textTertiary }
                                        }
                                    }
                                }

                                Row {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 2

                                    MessageAction { width: 30; height: 30; icon: "note-pencil"; tip: "New chat · Ctrl+N"; onClicked: { OllamaService.newChat(); promptInput.focusInput(); } }
                                    MessageAction { width: 30; height: 30; icon: "squares-four"; tip: "Open an app · Ctrl+O"; onClicked: root.appLauncherOpen = !root.appLauncherOpen }
                                    MessageAction { width: 30; height: 30; icon: root.studioMode ? "arrows-in-simple" : "arrows-out-simple"; tip: (root.studioMode ? "Smaller" : "Bigger, with your chats") + " · Ctrl+M"; onClicked: root.studioMode = !root.studioMode }
                                    MessageAction { width: 30; height: 30; icon: root.fullMode ? "corners-in" : "corners-out"; tip: (root.fullMode ? "Back to studio" : "Almost full screen") + " · Ctrl+Shift+M"; onClicked: root.fullMode = !root.fullMode }
                                    MessageAction { width: 30; height: 30; icon: "x"; tip: "Close · Esc"; tipAlign: 1; onClicked: Assistant.hide() }
                                }
                            }

                            // ── Hairline Divider ──────────────────────
                            Rectangle {
                                width: parent.width
                                height: 1
                                color: Theme.wash(1)
                            }

                            // ── Message Scroller ──────────────────────
                            Item {
                                width: parent.width
                                height: parent.height - 38 - 1 - 12 - promptInput.implicitHeight - 12
                                clip: true

                                // Empty state: one question, and a few things it can do right now.
                                Item {
                                    anchors.fill: parent
                                    visible: OllamaService.messages.length === 0 && !OllamaService.busyHere

                                    Column {
                                        anchors.centerIn: parent
                                        spacing: 18
                                        width: Math.min(560, parent.width * 0.9)

                                        Column {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            spacing: 6
                                            Label {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                text: OllamaService.status === "ready" ? "What can I help with?" : OllamaService.status === "loading" ? "Starting up" : "Ollama isn't running"
                                                size: Theme.tTitle1
                                                weight: Theme.wSemibold
                                                color: Theme.textPrimary
                                            }
                                            Label {
                                                visible: OllamaService.status !== "ready"
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                text: OllamaService.status === "loading" ? "Waking the model…" : "It runs as a system service: sudo systemctl start ollama"
                                                size: Theme.tBody
                                                color: Theme.textTertiary
                                            }
                                            Ui.Button {
                                                height: Theme.sp(30); size: Theme.tSub
                                                visible: OllamaService.status === "offline"
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                text: "Check again"
                                                onClicked: OllamaService.probe()
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
                                    visible: OllamaService.messages.length > 0 || OllamaService.busyHere
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

                                    onContentHeightChanged: {
                                        // Auto-follow bottom during stream unless user manually scrolled up
                                        if (!userScrolledUp || !OllamaService.busyHere) {
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
                                                isLast: index === msgRepeater.count - 1 && !OllamaService.busyHere
                                                // Only what you just sent animates in; history and finished answers don't.
                                                animateIn: msg.role === "user" && index === OllamaService.messages.length - 1
                                                           && Date.now() - (msg.timestamp || 0) < 1500
                                            }
                                        }

                                        // The answer in flight
                                        ChatMessage {
                                            visible: OllamaService.busyHere
                                            width: msgCol.width
                                            msg: OllamaService.draftHere || ({ role: "assistant", parts: [] })
                                            isStreaming: true
                                        }

                                        // A failed turn: one quiet line and a way to try again.
                                        Row {
                                            visible: OllamaService.errorText !== "" && !OllamaService.busyHere
                                            width: parent.width
                                            spacing: 8
                                            Icon { name: "warning-circle"; size: 15; color: Theme.red; anchors.verticalCenter: parent.verticalCenter }
                                            Label {
                                                text: OllamaService.errorText
                                                size: Theme.tBody
                                                color: Theme.textSecondary
                                                wrapMode: Text.Wrap
                                                width: Math.min(implicitWidth, parent.width - 90)
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                            Label {
                                                text: "Try again"
                                                size: Theme.tBody
                                                weight: Theme.wMedium
                                                color: Theme.accent
                                                anchors.verticalCenter: parent.verticalCenter
                                                MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: OllamaService.retry() }
                                                activeFocusOnTab: true
                                                Accessible.role: Accessible.Button
                                                Accessible.name: "Try again"
                                                Accessible.onPressAction: OllamaService.retry()
                                                Keys.onPressed: e => { if (e.key === Qt.Key_Space || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { OllamaService.retry(); e.accepted = true; } }
                                                FocusRing { cornerRadius: Theme.r1 }
                                            }
                                        }
                                    }
                                }

                                // Scroll fade (AI Elements' utility): the edges fade out only when
                                // there's more to scroll that way, so text never meets a hard cut.
                                ScrollFade { flickable: scroll; reach: Theme.sp(28) }
                                ScrollHint { flickable: scroll; inside: true }

                                // Scrolled up: a way back to the newest message (prompt-kit's scroll button).
                                Rectangle {
                                    id: toBottom
                                    // Not while it's following the stream (a big block landing would flash it).
                                    readonly property bool show: scroll.visible && scroll.fromEnd > 120
                                                                 && (scroll.userScrolledUp || !OllamaService.busyHere)
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: show || Theme.reduceMotion ? 10 : 6
                                    width: 34; height: 34
                                    radius: 17
                                    color: Qt.rgba(0.16, 0.16, 0.19, 0.96)
                                    border.width: 1
                                    border.color: Theme.edge(1)
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
                                    Accessible.role: Accessible.Button
                                    Accessible.name: "Scroll to the newest"
                                    Accessible.onPressAction: { scroll.userScrolledUp = false; glideDown.to = Math.max(0, scroll.contentHeight - scroll.height); glideDown.restart(); }
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
                                    if (OllamaService.pendingHere) {
                                        OllamaService.resolveRequest(OllamaService.pendingHere.id, "decline");
                                    } else if (root.appLauncherOpen) {
                                        root.appLauncherOpen = false;
                                    } else if (OllamaService.busyHere) {
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
                        { id: "paste", label: "Paste an image", keys: ["Ctrl", "V"] },
                        { id: "model", label: "Choose model", keys: ["Ctrl", "K"], section: "Chat" },
                        { id: "new", label: "New chat", keys: ["Ctrl", "N"] },
                        { id: "clear", label: "Clear this chat", keys: ["Ctrl", "L"] },
                        { id: "copychat", label: "Copy chat as Markdown", keys: [] },
                        { id: "compact", label: "Summarise this chat now", keys: [] },
                        { id: "fork", label: "Fork this chat", keys: [] },
                        { id: "search", label: "Search chats", keys: ["Ctrl", "F"] },
                        { id: "apps", label: "Open an app", keys: ["Ctrl", "O"] }
                    ]
                    onPicked: id => {
                        if (id === "snap") OllamaService.snapshotActiveWindow();
                        else if (id === "shot") OllamaService.takeScreenshot();
                        else if (id === "paste") OllamaService.pasteClipboardImage();
                        else if (id === "model") modelPicker.open = true;
                        else if (id === "new") OllamaService.newChat();
                        else if (id === "clear") OllamaService.requestClear();
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
                    // The app picker; a click on the dim outside it closes it (Esc too).
                    Accessible.role: Accessible.Dialog
                    Accessible.name: "Open an app"

                    Rectangle {
                        scale: Theme.reduceMotion ? 1 : 0.96 + 0.04 * appT.value
                        opacity: Math.min(1, appT.value * 3)
                        width: Math.min(540, parent.width - 40)
                        height: Math.min(420, parent.height - 40)
                        anchors.centerIn: parent
                        radius: Theme.r3
                        color: Theme.glassTintElevated
                        border.width: 1
                        border.color: Theme.edge(1)
                        clip: true

                        Elevation {
                            strength: 1
                            radius: Theme.r3
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
                                border.color: appSearchInput.activeFocus ? Theme.accent : Theme.edge(1)

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
                                            text: "Search apps to launch… (↑↓ to select, ↵ to run)"
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
                                        color: Theme.wash(2)
                                        anchors.verticalCenter: parent.verticalCenter

                                        Label {
                                            id: escLabel
                                            anchors.centerIn: parent
                                            text: "Esc"
                                            size: Theme.tCaption
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
                                    radius: Theme.r1
                                    color: (appListView.currentIndex === index || appItemArea.containsMouse) 
                                        ? Qt.alpha(Theme.accent, 0.15) 
                                        : "transparent"
                                    border.width: appListView.currentIndex === index ? 1 : 0
                                    border.color: Qt.alpha(Theme.accent, 0.3)

                                    function launch() {
                                        Apps.launch(modelData);
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
                                            readonly property string path: modelData.icon ? NotifAdapters.iconSource(modelData.icon) : ""
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
                                                size: Theme.tBody
                                                weight: Theme.wSemibold
                                                color: Theme.textPrimary
                                            }

                                            Label {
                                                text: modelData.comment || modelData.id || "Desktop Application"
                                                size: Theme.tFootnote
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
                                        size: Theme.tCaption
                                        visible: appListView.currentIndex === index || appItemArea.containsMouse
                                    }

                                    MouseArea {
                                        id: appItemArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: appItem.launch()
                                    }
                                    Accessible.role: Accessible.ListItem
                                    Accessible.name: modelData.name || "Application"
                                    Accessible.description: modelData.comment || ""
                                    Accessible.selected: appListView.currentIndex === index
                                    Accessible.onPressAction: appItem.launch()
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

            Dialog {
                id: clearDialog
                parent: frame
                anchors.centerIn: parent
                modal: true
                focus: true
                title: "Clear this chat?"
                standardButtons: Dialog.Cancel | Dialog.Ok
                contentItem: Label { text: "Remove this chat's messages and queued work? Other chats keep running."; wrapMode: Text.WordWrap; width: 300 }
                onOpened: standardButton(Dialog.Cancel).forceActiveFocus()
                onAccepted: OllamaService.confirmClear()
                onRejected: OllamaService.cancelClear()
                Keys.onPressed: e => { if (e.isAutoRepeat && (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space)) e.accepted = true; }
            }
            Connections {
                target: OllamaService
                function onClearPendingSessionChanged() {
                    if (OllamaService.clearPendingSession && win.visible) clearDialog.open();
                    else clearDialog.close();
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
}
