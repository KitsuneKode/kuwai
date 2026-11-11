// The bell's list, as the island itself (right-click or hold the bell): what
// needs you first, then unread chats and mail, then the newest. The island
// grows into it like the T3 panel (one black glass, one morph), so it's
// attached by construction; it used to be a separate popup below the island,
// styled apart. A row reads it in the island (the whole message, Reply).
// Swipe a row sideways (or its ×, or Delete) and it's gone; the rows below
// close up as it slides.
//   ↑ ↓ choose · ↵ read · ⌫ / Delete dismiss · Esc back
import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.config
import qs.components
import qs.services

FocusScope {
    id: np
    focus: true
    implicitWidth: 420
    implicitHeight: col.implicitHeight + 36

    readonly property var quick: Notifs.bellQuickList(10)
    property int sel: 0
    property bool keyboard: false            // the ring shows for keys, not the pointer
    onQuickChanged: sel = Math.min(sel, Math.max(0, quick.length - 1))
    function ago(t) {
        const m = Math.max(0, Math.round((Date.now() - t) / 60000));
        return m < 1 ? "now" : m < 60 ? m + "m" : m < 1440 ? Math.floor(m / 60) + "h" : Math.floor(m / 1440) + "d";
    }
    function read(item) { if (!item) return; Island.close(); Notifs.readInIsland(item); }
    function dismissAt(i) {
        const r = list.itemAtIndex(i);
        if (r) r.swipe.away(1);
        else if (quick[i]) Notifs.discard(quick[i]);
    }

    Keys.onPressed: e => {
        keyboard = true;
        if (e.key === Qt.Key_Down) sel = Math.min(quick.length - 1, sel + 1);
        else if (e.key === Qt.Key_Up) sel = Math.max(0, sel - 1);
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) read(quick[sel]);
        else if (e.key === Qt.Key_Delete || e.key === Qt.Key_Backspace) dismissAt(sel);
        else return;
        list.positionViewAtIndex(sel, ListView.Contain);
        e.accepted = true;
    }

    Column {
        id: col
        x: 18; y: 18
        width: np.width - 36
        spacing: 10

        Item {
            width: parent.width
            height: 22
            Label {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                text: Notifs.missed.length ? "Need you" : Notifs.unread ? "Unread" : "Recent"
                size: Theme.tTitle3; weight: Theme.wSemibold
            }
            Label {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: ""      // the count is on the button below (it said the same thing twice)
                size: Theme.tFootnote; color: Theme.textTertiary
                font.features: ({ "tnum": 1 })
            }
        }

        // Loading: the history isn't read yet (the first second after a
        // restart). Two rows in the rows' own shape.
        Column {
            visible: !Notifs.loaded
            width: parent.width
            spacing: 12
            topPadding: 4; bottomPadding: 4
            Repeater {
                model: 2
                Row {
                    spacing: 12
                    leftPadding: 10
                    Skeleton { width: 32; height: 32; radius: 9 }
                    Column {
                        spacing: 6
                        Skeleton { width: 90; height: 10 }
                        Skeleton { width: col.width - 76; height: 12 }
                    }
                }
            }
        }

        // Empty: say so, and what happens next.
        Column {
            visible: Notifs.loaded && np.quick.length === 0
            width: parent.width
            topPadding: 10; bottomPadding: 10
            spacing: 6
            Icon { anchors.horizontalCenter: parent.horizontalCenter; name: "bell"; size: 22; color: Theme.textTertiary }
            Label { anchors.horizontalCenter: parent.horizontalCenter; text: "You’re all caught up"; size: Theme.tSub; color: Theme.textSecondary }
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Notifs.dnd ? "Focus is on: new ones wait here quietly." : "New ones land here first."
                size: Theme.tFootnote; color: Theme.textTertiary
            }
        }

        ListView {
            id: list
            visible: Notifs.loaded && np.quick.length > 0
            width: parent.width
            height: Math.min(contentHeight, 360)
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            model: ScriptModel { values: np.quick; comparisonMode: ObjectComparison.Identity }
            // A swiped row stays while its spring carries it out; the rows
            // below move up at the same time (one move, no stagger).
            remove: Transition { PauseAnimation { duration: Theme.reduceMotion ? 0 : Theme.swipeOutMs } }
            displaced: Transition {
                NumberAnimation { property: "y"; duration: Theme.reduceMotion ? 0 : Theme.reflowMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeInOut }
            }
            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index
                readonly property bool fresh: modelData.time > Notifs.lastSeen && !modelData.discard
                readonly property bool hot: modelData.severity === "critical" || modelData.severity === "warning"
                readonly property color dot: modelData.severity === "critical" ? Theme.red : hot ? Theme.orange : Theme.accent
                // Waiting on your input (an agent's question): said, and its question gets room.
                readonly property bool asks: modelData.statusTone === "caution" || /needs you|waiting|permission/i.test(String(modelData.status || ""))
                readonly property alias swipe: swipe
                readonly property bool shown: rowHover.hovered || (np.keyboard && np.sel === index)
                width: list.width
                height: Math.max(inner.implicitHeight, 34) + 20
                radius: Theme.r2
                color: rowHover.hovered || np.sel === index ? Qt.rgba(1, 1, 1, 0.07) : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.hoverMs } }
                opacity: swipe.fade
                transform: Translate { x: swipe.offset }
                // Screen readers: who, what, and whether it waits on you; the
                // body as the panel shows it (private ones stay private).
                Accessible.role: Accessible.ListItem
                Accessible.name: (modelData.app || "Notification") + ": " + (modelData.title || "") + (asks ? ", needs you" : "")
                Accessible.description: Notifs.readable(Notifs.bodyForDisplay(modelData, true))
                Accessible.selected: np.sel === index
                // The keyboard's place: the shared ring look, keys only.
                Rectangle {
                    visible: np.keyboard && np.sel === row.index
                    anchors.fill: parent
                    anchors.margins: -2
                    radius: parent.radius + 2
                    color: "transparent"
                    border.width: 2
                    border.color: Qt.rgba(1, 1, 1, 0.6)
                    z: 100
                }
                SwipeAway {
                    id: swipe
                    span: row.width
                    onLeaving: Notifs.discard(row.modelData)
                }
                // Who it's from, at a glance: the app's mark or the sender's picture
                // (a glyph when there's none); the unread dot sits on its corner.
                Item {
                    x: 10; y: 12
                    width: 32; height: 32
                    ClippingRectangle {
                        anchors.fill: parent
                        radius: 9
                        color: Qt.rgba(1, 1, 1, 0.06)
                        Image {
                            id: rowIcon
                            anchors.fill: parent
                            // The notification's own image, else the app's launcher icon
                            // (ZapZap and others send none).
                            readonly property var entry: row.modelData.icon ? null : DesktopEntries.heuristicLookup(String(row.modelData.app || ""))
                            source: row.modelData.icon || (entry && entry.icon ? Quickshell.iconPath(entry.icon, true) : "")
                            sourceSize: Qt.size(64, 64)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true; smooth: true; mipmap: true
                        }
                        Text {
                            visible: rowIcon.status !== Image.Ready
                            anchors.centerIn: parent
                            text: "\u{f009a}"      // a bell: no mark from the app
                            font.family: Theme.fontGlyph; font.pixelSize: 15
                            color: Theme.textSecondary
                        }
                    }
                    ImageEdge { radius: 9 }
                    Rectangle {
                        visible: row.fresh || row.hot || row.asks
                        x: parent.width - 7; y: -2
                        width: 9; height: 9; radius: 4.5
                        color: row.asks ? Theme.orange : row.dot
                        border.width: 2; border.color: "#000000"
                    }
                }
                Column {
                    id: inner
                    x: 54; y: 10
                    width: parent.width - 66
                    spacing: 3
                    Row {
                        width: parent.width - 24       // room for the × (kept, so nothing shifts on hover)
                        spacing: 6
                        Label {
                            width: Math.min(implicitWidth, parent.width - stamp.width - 6)
                            elide: Text.ElideRight
                            text: row.modelData.app || ""
                            size: Theme.tFootnote; weight: Theme.wMedium
                            color: row.hot ? row.dot : Theme.textTertiary
                        }
                        Label { id: stamp; text: "· " + np.ago(row.modelData.time); size: Theme.tFootnote; color: Theme.textTertiary }
                        Label { visible: row.asks; text: "· Needs you"; size: Theme.tFootnote; weight: Theme.wSemibold; color: Theme.orange }
                    }
                    Label {
                        width: parent.width
                        visible: text !== ""
                        elide: Text.ElideRight
                        text: row.modelData.title || ""
                        size: Theme.tBody; weight: Theme.wSemibold
                    }
                    Label {
                        width: parent.width
                        visible: text !== ""
                        wrapMode: Text.Wrap; maximumLineCount: row.asks ? 3 : 2; elide: Text.ElideRight
                        text: Notifs.readable(Notifs.bodyForDisplay(row.modelData, true))
                        size: Theme.tSub; lineHeight: 1.3; color: Theme.textSecondary
                    }
                }
                HoverHandler {
                    id: rowHover
                    cursorShape: Qt.PointingHandCursor
                    onHoveredChanged: if (hovered) { np.keyboard = false; np.sel = row.index; }
                }
                TapHandler {
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onTapped: (point, button) => button === Qt.RightButton ? row.swipe.away(1) : np.read(row.modelData)
                }
                // Dismiss, for the pointer: on hover (and for the keyboard's row).
                Rectangle {
                    visible: row.shown
                    x: parent.width - width - 8; y: 10
                    width: 20; height: 20; radius: 10
                    color: closeHover.hovered ? Theme.pillHover : Theme.pill
                    Accessible.role: Accessible.Button
                    Accessible.name: "Dismiss"
                    Text { anchors.centerIn: parent; text: "\u{f0156}"; font.family: Theme.fontGlyph; font.pixelSize: 11; color: Theme.textPrimary }
                    HoverHandler { id: closeHover; margin: 10; cursorShape: Qt.PointingHandCursor }
                    TapHandler { margin: 10; gesturePolicy: TapHandler.ReleaseWithinBounds; onTapped: row.swipe.away(1) }
                }
            }
        }

        PillButton {
            width: parent.width
            text: "Open notification center" + (Notifs.inbox > 0 ? " · " + (Notifs.inbox > 9 ? "9+" : String(Notifs.inbox)) : "")
            onClicked: { Island.close(); Notifs.toggleCenter("notifications", "pointer", Island.screen); }
        }
    }
}
