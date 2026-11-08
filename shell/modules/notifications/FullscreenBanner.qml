// Fullscreen banner: what can't wait, over a game or a film.
//
//            ╭───────────────────────────────────────╮
//            │ ▣  Signal · Alex             Reply  ✕ │      top centre, overlay layer
//            ╰───────────────────────────────────────╯
//
// A fullscreen window covers the island and the toasts (Hyprland draws it
// over the top layer), so Notifs routes what matters here instead
// (Notifs.bannerFor: critical always; warnings and people you can reply to
// unless Focus or sharing holds them). One line, no body: the app and who or
// what, so nothing is read over your film. Critical: a red edge and 8 s; the
// rest 4 s, held while the pointer is on it.
//
// Click: what a toast click does (the app's action, then its window: you
// leave fullscreen because you chose to). ✕ or a flick up: gone, it waits
// in the center. It never takes the keyboard; only the pill takes the pointer.
//
// Motion: drops 10px and fades in (enterMs, ease-out), leaves faster
// (exitMs) straight up; reduce motion: fades only.
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.config
import qs.components
import qs.services

Scope {
    id: root
    // Kept after Notifs.banner clears, so the exit can play with its content.
    property var shown: null
    readonly property bool live: Notifs.banner !== null
    Connections { target: Notifs; function onBannerChanged() { if (Notifs.banner) root.shown = Notifs.banner; } }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: win
            required property ShellScreen modelData
            screen: modelData
            // Only on the screen you're looking at (the fullscreen one).
            readonly property bool here: modelData && modelData.name === Screens.focusedName
            visible: here && (root.live || pill.opacity > 0.01)

            anchors.top: true
            implicitWidth: 520
            implicitHeight: 88
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.namespace: "rice-banner"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            mask: Region { item: pill }

            readonly property var item: root.shown || ({})
            readonly property bool critical: !!root.shown && Notifs.rank(root.shown) === 0
            readonly property bool privateNow: Notifs.sharing

            Rectangle {
                id: pill
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(parent.width - 24, Math.max(280, line.implicitWidth + 112))
                height: 46
                radius: height / 2
                color: Qt.rgba(0.07, 0.07, 0.08, 0.94)
                border.width: 1
                border.color: win.critical ? Qt.alpha(Theme.red, 0.75) : Qt.rgba(1, 1, 1, 0.09)

                // In: 10px drop + fade; out: quicker, straight up. Interruptible
                // (Behaviors retarget from wherever they are).
                y: root.live ? 14 : 4
                opacity: root.live ? 1 : 0
                Behavior on y { enabled: !Theme.reduceMotion; NumberAnimation { duration: root.live ? Theme.enterMs : Theme.exitMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                Behavior on opacity { NumberAnimation { duration: root.live ? Theme.enterMs : Theme.exitMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }

                HoverHandler { onHoveredChanged: Notifs.holdBanner(hovered) }

                Row {
                    id: row
                    anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                    spacing: 10
                    Item {
                        width: 28; height: 28
                        anchors.verticalCenter: parent.verticalCenter
                        Image {
                            id: icon
                            anchors.fill: parent
                            source: win.item.icon || ""
                            sourceSize: Qt.size(56, 56)
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            smooth: true
                            mipmap: true
                            visible: status === Image.Ready
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: 8
                            visible: icon.status !== Image.Ready
                            color: win.critical ? Qt.alpha(Theme.red, 0.25) : Qt.rgba(1, 1, 1, 0.1)
                            Text {
                                anchors.centerIn: parent
                                text: win.critical ? "\u{f0026}" : "\u{f009a}"     // alert / bell
                                font.family: Theme.fontGlyph
                                font.pixelSize: 15
                                color: win.critical ? Theme.red : Theme.textPrimary
                            }
                        }
                    }
                    Label {
                        id: line
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, pill.width - 112)
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        size: 13
                        weight: Theme.wMedium
                        // Sharing: the app only (titles can be private too).
                        text: win.privateNow || !win.item.title ? (win.item.app || "Notification")
                            : (win.item.app || "") + (win.item.app ? "  ·  " : "") + win.item.title
                    }
                }

                // ✕: gone from the screen; it stays in the center.
                Rectangle {
                    id: close
                    anchors { right: parent.right; rightMargin: 9; verticalCenter: parent.verticalCenter }
                    width: 28; height: 28; radius: 14
                    color: closeArea.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.hoverMs } }
                    Text {
                        anchors.centerIn: parent
                        text: "\u{f0156}"
                        font.family: Theme.fontGlyph
                        font.pixelSize: 14
                        color: Theme.textSecondary
                    }
                    MouseArea { id: closeArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Notifs.dropBanner() }
                }

                // The pill itself: act like a toast click; a flick up dismisses.
                MouseArea {
                    anchors { left: parent.left; right: close.left; top: parent.top; bottom: parent.bottom }
                    cursorShape: Qt.PointingHandCursor
                    property real startY: 0
                    onPressed: mouse => startY = mouse.y
                    onReleased: mouse => {
                        if (startY - mouse.y > 12) { Notifs.dropBanner(); return; }
                        const it = root.shown;
                        Notifs.dropBanner();
                        if (it) Notifs.activate(it);
                    }
                }
            }
        }
    }
}
