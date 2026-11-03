// Assistant Overlay: Native Wayland AI Assistant HUD
// Physical Dynamic Island emergence (Aceternity fluid notch & Apple physics).
// Features Compact HUD mode (840x560) & Expanded Studio mode (1080x820) with shadcn ChatSidebar.
// Bound to SUPER + CTRL + SHIFT + A.
import QtQuick
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
            readonly property real targetH: root.studioMode ? studioH : compactH

            anchors.top: true
            margins.top: inIsland ? (notch ? 0 : 6) : 6

            implicitWidth: up ? Math.max(studioW, compactW) + 40 : 1
            implicitHeight: up ? Math.max(studioH, compactH) + 60 : 1
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
                tier: Theme.springModerate
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
                visible: win.up && win.m > 0.01
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

                            // ── Top Header Navigation Bar ─────────────
                            Item {
                                width: parent.width
                                height: 38

                                // Left cluster: Sidebar toggle, Assistant brand, Status
                                Row {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 10

                                    // Sidebar Toggle Button (visible in Studio mode)
                                    Rectangle {
                                        visible: root.studioMode
                                        width: 30; height: 30
                                        radius: 8
                                        color: sideToggleArea.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.05)
                                        border.width: 1
                                        border.color: Qt.rgba(1, 1, 1, 0.08)

                                        Icon {
                                            anchors.centerIn: parent
                                            name: "sidebar-simple"
                                            size: 15
                                            color: root.sidebarOpen ? Theme.accent : Theme.textSecondary
                                        }

                                        MouseArea {
                                            id: sideToggleArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.sidebarOpen = !root.sidebarOpen
                                        }
                                    }

                                    Rectangle {
                                        width: 30; height: 30
                                        radius: 9
                                        color: Qt.alpha(Theme.accent, 0.2)
                                        border.width: 1
                                        border.color: Qt.alpha(Theme.accent, 0.4)

                                        Icon {
                                            anchors.centerIn: parent
                                            name: "sparkle"
                                            size: 16
                                            color: Theme.accent
                                        }
                                    }

                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 1

                                        Row {
                                            spacing: 7
                                            Label {
                                                text: "Assistant"
                                                size: 15
                                                weight: Theme.wBold
                                                color: Theme.textPrimary
                                            }
                                            Rectangle {
                                                width: 7; height: 7
                                                radius: 3.5
                                                color: OllamaService.status === "ready" ? Theme.green : Theme.red
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                            Label {
                                                text: OllamaService.status === "ready" ? "Local AI Ready" : "Ollama Offline"
                                                size: 12
                                                weight: Theme.wMedium
                                                color: OllamaService.status === "ready" ? Theme.green : Theme.red
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }

                                        Label {
                                            text: root.studioMode ? "Studio Mode • Multi-turn Sessions" : "Island HUD • Quick Intelligence"
                                            size: 12
                                            color: Theme.textTertiary
                                        }
                                    }
                                }

                                // Right cluster: App Launcher, Shrink/Expand toggle, Clear, Close with Keyboard Badges
                                Row {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 8

                                    // App Launcher / Command Button
                                    Rectangle {
                                        height: 30
                                        width: appRow.implicitWidth + 14
                                        radius: 8
                                        color: root.appLauncherOpen ? Qt.alpha(Theme.accent, 0.2) : (appArea.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.05))
                                        border.width: 1
                                        border.color: root.appLauncherOpen ? Theme.accent : Qt.rgba(1, 1, 1, 0.08)

                                        Row {
                                            id: appRow
                                            anchors.centerIn: parent
                                            spacing: 6

                                            Icon {
                                                name: "rocket"
                                                size: 13
                                                color: Theme.accent
                                                anchors.verticalCenter: parent.verticalCenter
                                            }

                                            Label {
                                                text: "Apps"
                                                size: 12
                                                weight: Theme.wMedium
                                                color: Theme.textPrimary
                                                anchors.verticalCenter: parent.verticalCenter
                                            }

                                            Row {
                                                spacing: 2
                                                anchors.verticalCenter: parent.verticalCenter
                                                KeyCap { text: "Ctrl"; size: 9 }
                                                KeyCap { text: "O"; size: 9 }
                                            }
                                        }

                                        MouseArea {
                                            id: appArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.appLauncherOpen = !root.appLauncherOpen
                                        }
                                    }

                                    // Shrink / Expand Toggle Button
                                    Rectangle {
                                        height: 30
                                        width: shrinkRow.implicitWidth + 14
                                        radius: 8
                                        color: shrinkArea.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.05)
                                        border.width: 1
                                        border.color: Qt.rgba(1, 1, 1, 0.08)

                                        Row {
                                            id: shrinkRow
                                            anchors.centerIn: parent
                                            spacing: 6

                                            Icon {
                                                name: root.studioMode ? "arrows-in-simple" : "arrows-out-simple"
                                                size: 13
                                                color: Theme.textSecondary
                                                anchors.verticalCenter: parent.verticalCenter
                                            }

                                            Label {
                                                text: root.studioMode ? "Shrink" : "Studio"
                                                size: 12
                                                weight: Theme.wMedium
                                                color: Theme.textSecondary
                                                anchors.verticalCenter: parent.verticalCenter
                                            }

                                            Row {
                                                spacing: 2
                                                anchors.verticalCenter: parent.verticalCenter
                                                KeyCap { text: "Ctrl"; size: 9 }
                                                KeyCap { text: "M"; size: 9 }
                                            }
                                        }

                                        MouseArea {
                                            id: shrinkArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.studioMode = !root.studioMode
                                        }
                                    }

                                    // Clear conversation button
                                    Rectangle {
                                        height: 30
                                        width: clearRow.implicitWidth + 14
                                        radius: 8
                                        color: clearArea.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.05)
                                        border.width: 1
                                        border.color: Qt.rgba(1, 1, 1, 0.08)

                                        Row {
                                            id: clearRow
                                            anchors.centerIn: parent
                                            spacing: 5
                                            Icon { name: "trash"; size: 13; color: Theme.textSecondary; anchors.verticalCenter: parent.verticalCenter }
                                            Label { text: "Clear"; size: 12; color: Theme.textSecondary; anchors.verticalCenter: parent.verticalCenter }
                                            Row {
                                                spacing: 2
                                                anchors.verticalCenter: parent.verticalCenter
                                                KeyCap { text: "Ctrl"; size: 9 }
                                                KeyCap { text: "L"; size: 9 }
                                            }
                                        }

                                        MouseArea {
                                            id: clearArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: OllamaService.clear()
                                        }
                                    }

                                    // Close button
                                    Rectangle {
                                        height: 30
                                        width: closeRow.implicitWidth + 12
                                        radius: 8
                                        color: closeArea.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.05)
                                        border.width: 1
                                        border.color: Qt.rgba(1, 1, 1, 0.08)

                                        Row {
                                            id: closeRow
                                            anchors.centerIn: parent
                                            spacing: 4
                                            Icon {
                                                name: "x"
                                                size: 13
                                                color: Theme.textSecondary
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                            KeyCap {
                                                text: "Esc"
                                                size: 9
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }

                                        MouseArea {
                                            id: closeArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: Assistant.hide()
                                        }
                                    }
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

                                // Empty State (Welcome + Suggestions)
                                Item {
                                    anchors.fill: parent
                                    visible: OllamaService.messages.length === 0 && !OllamaService.streaming

                                    Column {
                                        anchors.centerIn: parent
                                        spacing: 16
                                        width: Math.min(540, parent.width * 0.9)

                                        Rectangle {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            width: 48; height: 48
                                            radius: 24
                                            color: Qt.alpha(Theme.accent, 0.15)
                                            border.width: 1
                                            border.color: Qt.alpha(Theme.accent, 0.3)

                                            Icon {
                                                anchors.centerIn: parent
                                                name: "brain"
                                                size: 24
                                                color: Theme.accent
                                            }
                                        }

                                        Column {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            spacing: 4

                                            Label {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                text: OllamaService.status === "ready" ? "Local Intelligence Ready" : "Ollama Is Not Running"
                                                size: 17
                                                weight: Theme.wBold
                                                color: Theme.textPrimary
                                            }

                                            Label {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                text: OllamaService.status === "ready"
                                                    ? "DeepSeek-R1 (reasoning), Hermes 3, and MiniCPM-V (vision) running locally."
                                                    : "Start the daemon with 'systemctl --user start ollama' or run 'ollama serve'."
                                                size: 13
                                                color: Theme.textTertiary
                                            }
                                        }

                                        // Suggestions Grid with real queries
                                        Column {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            spacing: 8
                                            width: parent.width

                                            Repeater {
                                                model: [
                                                    { title: "Analyze current screen", sub: "Snip a region with slurp to analyze visually", action: "screenshot" },
                                                    { title: "Explain Voxtype & Quickshell architecture", sub: "How speech recognition and desktop HUD integrate", action: "voxtype" },
                                                    { title: "Review live system performance", sub: "Inspect real CPU, RAM, and GPU telemetry", action: "system" }
                                                ]

                                                Rectangle {
                                                    width: parent.width
                                                    height: 48
                                                    radius: 10
                                                    color: sArea.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.04)
                                                    border.width: 1
                                                    border.color: Qt.rgba(1, 1, 1, 0.07)

                                                    Row {
                                                        anchors.left: parent.left
                                                        anchors.leftMargin: 12
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        spacing: 10

                                                        Icon {
                                                            name: modelData.action === "screenshot" ? "camera" : "sparkle"
                                                            size: 14
                                                            color: Theme.accent
                                                            anchors.verticalCenter: parent.verticalCenter
                                                        }

                                                        Column {
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            spacing: 2

                                                            Label {
                                                                text: modelData.title
                                                                size: 13
                                                                weight: Theme.wMedium
                                                                color: Theme.textPrimary
                                                            }
                                                            Label {
                                                                text: modelData.sub
                                                                size: 11
                                                                color: Theme.textTertiary
                                                            }
                                                        }
                                                    }

                                                    MouseArea {
                                                        id: sArea
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            if (modelData.action === "screenshot") {
                                                                OllamaService.takeScreenshot();
                                                            } else if (modelData.action === "voxtype") {
                                                                OllamaService.send("Explain the Voxtype and Quickshell architecture on this system, how speech tokens stream into the Dynamic Island, and how CPU/GPU loads are balanced.");
                                                            } else if (modelData.action === "system") {
                                                                // Feed live SystemStats metrics into prompt
                                                                const cpuPct = Math.round(SystemStats.cpu * 100);
                                                                const memGb = (SystemStats.memUsed / 1e9).toFixed(1);
                                                                const memTot = (SystemStats.memTotal / 1e9).toFixed(1);
                                                                let gpuInfo = "NVIDIA GPU is suspended.";
                                                                if (SystemStats.gpuState === "active") {
                                                                    gpuInfo = `RTX 4050 active at ${Math.round(SystemStats.gpu * 100)}% load, ${SystemStats.gpuMemUsed.toFixed(0)}/${SystemStats.gpuMemTotal.toFixed(0)} MiB VRAM, ${SystemStats.gpuTemp}°C.`;
                                                                }
                                                                const query = `Here are my live system metrics: CPU: ${cpuPct}% (${SystemStats.cpuTemp}°C), RAM: ${memGb}/${memTot} GB. GPU: ${gpuInfo}. How healthy is my memory and compute headroom for running local LLMs alongside Voxtype?`;
                                                                OllamaService.send(query);
                                                            }
                                                        }
                                                    }
                                                }
                                            }
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

                                    property bool userScrolledUp: false

                                    onMovementStarted: {
                                        if (scroll.contentY < scroll.contentHeight - scroll.height - 30) {
                                            userScrolledUp = true;
                                        }
                                    }

                                    onMovementEnded: {
                                        if (scroll.atYEnd || scroll.contentY >= scroll.contentHeight - scroll.height - 30) {
                                            userScrolledUp = false;
                                        }
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

                                        // Error display if any
                                        Rectangle {
                                            visible: OllamaService.errorText !== ""
                                            width: parent.width
                                            height: visible ? 40 : 0
                                            radius: 10
                                            color: Qt.alpha(Theme.red, 0.15)
                                            border.width: 1
                                            border.color: Qt.alpha(Theme.red, 0.3)

                                            Row {
                                                anchors.centerIn: parent
                                                spacing: 8
                                                Icon { name: "x"; size: 14; color: Theme.red; anchors.verticalCenter: parent.verticalCenter }
                                                Label { text: OllamaService.errorText; size: 13; color: Theme.red; anchors.verticalCenter: parent.verticalCenter }
                                            }
                                        }
                                    }
                                }
                            }

                            // ── Sticky Footer (Prompt Input) ──────────
                            PromptInput {
                                id: promptInput
                                width: parent.width
                                picker: modelPicker
                                onModelPickerRequested: modelPicker.toggle()
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

                // ── App Launcher / Command Palette Modal (Ctrl+O) ────────
                Rectangle {
                    id: appModal
                    visible: root.appLauncherOpen
                    anchors.fill: parent
                    color: Qt.rgba(0, 0, 0, 0.65)
                    radius: frame.radius
                    z: 99

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.appLauncherOpen = false
                    }

                    Rectangle {
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

                                        Icon {
                                            name: "rocket"
                                            size: 16
                                            color: appListView.currentIndex === index ? Theme.accent : Theme.textSecondary
                                            anchors.verticalCenter: parent.verticalCenter
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
