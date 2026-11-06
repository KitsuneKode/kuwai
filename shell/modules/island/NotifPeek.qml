// A notification that matters, grown out of the island (Notifs.peek): icon,
// headline, a line of body, and explicit Open. Tap the text to dwell (taller
// island, more lines, Reply); Open runs the app's action; Reply hands off to
// the notification center. Swipe up (or the ×) to dismiss. Critical ones carry their colour.
import QtQuick
import Quickshell.Widgets
import qs.config
import qs.components
import qs.services

Item {
    id: peek
    required property var item
    required property var bar
    property real reveal: 1
    width: 460
    height: parent ? parent.height : 76
    opacity: reveal * swipeFade
    readonly property bool expanded: Notifs.peekExpanded
    readonly property bool redacted: !!item && Notifs.bodyRedacted(item)
    // Opened on purpose: the body shows (a chat's too), unless sharing the screen.
    readonly property bool hiddenOpen: !!item && Notifs.bodyHidden(item, true)
    readonly property bool loud: !!item && (item.severity === "critical" || item.severity === "warning")
    readonly property bool canReply: Notifs.canReply(item)
    readonly property string otp: Notifs.sharing ? "" : Notifs.otpOf(item)
    readonly property color tone: item && item.severity === "critical" ? Theme.red : Theme.orange
    readonly property color statusColor: !item ? Theme.textSecondary
        : item.statusTone === "positive" ? Theme.green : item.statusTone === "caution" ? Theme.orange
        : item.statusTone === "critical" ? Theme.red : Theme.textSecondary

    property real pop: 1
    property real swipeY: 0
    property real swipeFade: 1
    property bool swiping: false
    property bool swipingOut: false

    transform: Translate { y: swipeY }

    onItemChanged: if (item && !Theme.reduceMotion) popIn.restart()
    NumberAnimation { id: popIn; target: peek; property: "pop"; from: 0.6; to: 1; duration: 460; easing.type: Easing.OutBack; easing.overshoot: 2.2 }

    ParallelAnimation {
        id: swipeHome
        NumberAnimation { target: peek; property: "swipeY"; to: 0; duration: Theme.stackMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeCss }
        NumberAnimation { target: peek; property: "swipeFade"; to: 1; duration: Theme.stackMs }
    }
    ParallelAnimation {
        id: swipeOut
        NumberAnimation { target: peek; property: "swipeY"; to: -peek.height - 40; duration: Theme.swipeOutMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOutCss }
        NumberAnimation { target: peek; property: "swipeFade"; to: 0; duration: Theme.swipeOutMs }
        onFinished: Notifs.dismissPeekItem(peek.item)
    }

    DragHandler {
        target: null
        dragThreshold: 4
        property real swipeStart: 0
        onActiveChanged: {
            if (active) {
                swipeHome.stop();
                peek.swiping = true;
                swipeStart = Date.now();
                return;
            }
            peek.swiping = false;
            if (peek.swipeY < -Theme.swipeThreshold || (peek.swipeY < -20 && Math.abs(peek.swipeY) / Math.max(1, Date.now() - swipeStart) > Theme.swipeVelocity)) {
                peek.swipingOut = true;
                swipeOut.start();
            } else {
                // Pulled down (it rubber-bands): open it to read, the whole
                // message with Reply (iOS: pull a notification down to expand).
                if (peek.swipeY > 36 && peek.item && !Notifs.peekExpanded) Notifs.readInIsland(peek.item);
                swipeHome.start();
            }
        }
        onTranslationChanged: peek.swipeY = translation.y < 0 ? translation.y : Theme.swipeDamp(translation.y)
    }

    HoverHandler { onHoveredChanged: Notifs.peekHeld = hovered }

    function openItem() {
        const i = peek.item;
        Notifs.dropPeek();
        if (i) Notifs.activate(i);
    }

    Item {
        id: mark
        x: 16
        y: peek.expanded ? 14 : undefined
        anchors.verticalCenter: peek.expanded ? undefined : parent.verticalCenter
        width: 42; height: 42
        scale: peek.pop
        ClippingRectangle {
            anchors.fill: parent
            radius: 11
            color: "transparent"
            visible: icon.status === Image.Ready
            Image { id: icon; anchors.fill: parent; source: peek.item ? peek.item.icon || "" : ""; sourceSize: Qt.size(84, 84); fillMode: Image.PreserveAspectCrop; asynchronous: true; mipmap: true }
        }
        Rectangle {
            anchors.fill: parent
            visible: icon.status !== Image.Ready
            radius: 21
            color: peek.loud ? Qt.alpha(peek.tone, 0.22) : Theme.platter
            Text {
                anchors.centerIn: parent
                text: !peek.item ? "" : peek.item.severity === "critical" ? "\u{f0026}" : peek.item.severity === "warning" ? "\u{f0029}" : "\u{f009a}"
                font.family: Theme.fontGlyph; font.pixelSize: 20
                color: peek.loud ? peek.tone : Theme.textPrimary
            }
        }
    }

    Item {
        id: copy
        anchors {
            left: mark.right; leftMargin: 12
            right: peek.expanded ? parent.right : go.left
            rightMargin: peek.expanded ? 16 : 36
            top: peek.expanded ? mark.top : undefined
            verticalCenter: peek.expanded ? undefined : parent.verticalCenter
        }
        height: copyCol.implicitHeight   // centred on the mark, not hanging from its middle
        TapHandler {
            onTapped: {
                if (peek.expanded) return;
                Notifs.expandPeek();
            }
        }
        Column {
            id: copyCol
            width: parent.width
            spacing: peek.expanded ? 4 : 1
            Label {
                width: parent.width; elide: Text.ElideRight
                text: !peek.item ? "" : (peek.item.app || "Notification") + (peek.item.status ? "  ·  " + peek.item.status : "")
                size: 11; weight: Theme.wMedium
                color: peek.item && peek.item.status ? peek.statusColor : Theme.textTertiary
            }
            Label {
                width: parent.width; elide: Text.ElideRight
                text: peek.item ? peek.item.title || peek.item.app : ""
                size: 14; weight: Theme.wSemibold
            }
            Label {
                visible: !!peek.item && (!!peek.item.body || peek.redacted) && !peek.expanded
                width: parent.width
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
                maximumLineCount: 1
                // A one-time code takes the line: big, spaced, tabular.
                text: peek.otp !== "" ? Notifs.spacedCode(peek.otp) : Notifs.bodyForDisplay(peek.item, false)
                textFormat: Text.PlainText
                size: peek.otp !== "" ? Theme.tTitle3 : 12
                weight: peek.otp !== "" ? Theme.wSemibold : Theme.wRegular
                font.letterSpacing: peek.otp !== "" ? 1.5 : 0
                font.features: ({ "tnum": 1 })
                color: peek.otp !== "" ? Theme.textPrimary : peek.redacted ? Theme.textTertiary : Theme.textSecondary
                font.italic: peek.redacted && peek.otp === ""
            }
            Label {
                visible: !!peek.item && (!!peek.item.body || peek.redacted) && peek.expanded && !peek.hiddenOpen
                width: parent.width
                // The whole message scrolls here (240 px when the sender sent
                // it all; the short body needs 72).
                height: Math.min(bodyScroll.contentHeight, peek.item && peek.item.full ? 240 : 72)
                clip: true
                Flickable {
                    id: bodyScroll
                    width: parent.width
                    height: parent.height
                    contentHeight: bodyLong.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds
                    Label {
                        id: bodyLong
                        width: bodyScroll.width
                        wrapMode: Text.Wrap
                        text: Notifs.fullForDisplay(peek.item)
                        textFormat: Text.PlainText
                        size: 12; color: Theme.textSecondary
                    }
                }
            }
            Label {
                visible: peek.expanded && peek.hiddenOpen
                width: parent.width
                wrapMode: Text.WordWrap
                text: "Hidden while you share your screen."
                size: 12; color: Theme.textTertiary
            }
            Label {
                visible: !peek.expanded && !!peek.item
                width: parent.width
                text: peek.hiddenOpen ? "Swipe up to dismiss" : "Pull down or tap to read · swipe up to dismiss"
                size: 10
                weight: Theme.wMedium
                color: Theme.textTertiary
            }
        }
    }

    Rectangle {
        id: dismissBtn
        visible: !peek.expanded
        anchors { right: go.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
        width: 22; height: 22; radius: 11
        color: dismissArea.containsMouse ? Theme.pillHover : Qt.rgba(1, 1, 1, 0.06)
        Text { anchors.centerIn: parent; text: "\u{f0056}"; font.family: Theme.fontGlyph; font.pixelSize: 12; color: Theme.textSecondary }
        MouseArea {
            id: dismissArea
            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: Notifs.dismissPeekItem(peek.item)
        }
    }

    Rectangle {
        id: go
        visible: !peek.expanded
        anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
        height: 28; radius: 14
        width: goLabel.implicitWidth + 22
        readonly property color c: peek.loud ? peek.tone : Theme.textPrimary
        color: goArea.containsMouse ? Qt.alpha(c, 0.3) : Qt.alpha(c, 0.16)
        Behavior on color { ColorAnimation { duration: Theme.colorMs } }
        Label { id: goLabel; anchors.centerIn: parent; text: "Open"; size: 12; weight: Theme.wMedium; color: go.c }
        MouseArea {
            id: goArea
            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: peek.openItem()
        }
    }

    Row {
        visible: peek.expanded
        anchors { left: mark.left; right: parent.right; rightMargin: 16; bottom: parent.bottom; bottomMargin: 12 }
        spacing: 6
        Rectangle {
            height: 28; radius: 14
            width: openLbl.implicitWidth + 22
            color: openArea.containsMouse ? Qt.rgba(1, 1, 1, 0.92) : Qt.rgba(1, 1, 1, 0.88)
            Label { id: openLbl; anchors.centerIn: parent; text: "Open"; size: 12; weight: Theme.wMedium; color: "#111111" }
            MouseArea {
                id: openArea
                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: peek.openItem()
            }
        }
        Rectangle {
            visible: peek.otp !== ""
            height: 28; radius: 14
            width: copyLbl.implicitWidth + 22
            color: copyArea.containsMouse ? Qt.alpha(Theme.accent, 0.4) : Qt.alpha(Theme.accent, 0.25)
            Label { id: copyLbl; anchors.centerIn: parent; text: "Copy code"; size: 12; weight: Theme.wMedium }
            MouseArea {
                id: copyArea
                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: Notifs.copyCode(peek.item)
            }
        }
        Rectangle {
            visible: peek.canReply
            height: 28; radius: 14
            width: replyLbl.implicitWidth + 22
            color: replyArea.containsMouse ? Theme.pillHover : Theme.pill
            Label { id: replyLbl; anchors.centerIn: parent; text: "Reply"; size: 12; weight: Theme.wMedium }
            MouseArea {
                id: replyArea
                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: {
                    const i = peek.item;
                    if (!i) return;
                    Notifs.readInIsland(i);     // read it and answer, in the island
                }
            }
        }
    }
}
