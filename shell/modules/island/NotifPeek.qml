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
    // Expanded, its own height (IslandBar.peekH): padding, the header, the
    // body (scrolling past maxBody), a gap, the buttons, padding. A fixed 340
    // let a long message run under Open and Reply.
    readonly property int pad: 16
    readonly property real maxBody: peek.item && peek.item.full ? 260 : 96
    readonly property real wantH: pad + copyCol.implicitHeight + 12 + 28 + pad
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
    // The pointer drives it 1:1 while down (snap per move); on release a
    // spring seeded with the pointer's speed (Fling) takes it home or up and
    // out, and can be caught again mid-flight. The fade is the way out.
    Spring { id: sy; tier: Theme.springModerate; epsilon: 0.5; onSettledChanged: peek.landed() }
    Fling { id: fling }
    readonly property real swipeY: sy.value
    property bool swiping: false
    property bool swipingOut: false
    property real outFrom: 0
    readonly property real outTo: -height - 40
    readonly property real swipeFade: !swipingOut ? 1 : Math.max(0, Math.min(1, 1 - (outFrom - swipeY) / Math.max(1, outFrom - outTo)))
    function landed() { if (swipingOut && sy.settled) Notifs.dismissPeekItem(peek.item); }

    transform: Translate { y: swipeY }

    onItemChanged: if (item && !Theme.reduceMotion) popIn.restart()
    // Arrives tens of times a day: quick and settled, no bounce (a 460 ms
    // overshoot from 0.6 read as slow and toy-like; the notch's own spring
    // already carries the arrival). Ease-out, from 0.94.
    NumberAnimation { id: popIn; target: peek; property: "pop"; from: 0.94; to: 1; duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }

    DragHandler {
        target: null
        dragThreshold: 4
        property real grab: 0
        onActiveChanged: {
            if (active) {
                peek.swipingOut = false;        // caught on its way out: it stays
                grab = sy.value;
                sy.snap(sy.value);
                fling.reset();
                peek.swiping = true;
                return;
            }
            peek.swiping = false;
            const up = -fling.vy();             // px/ms, + is up (out)
            if (peek.swipeY < 0 && up > -Theme.swipeFlick && (peek.swipeY < -Theme.swipeThreshold || up > Theme.swipeFlick)) {
                peek.swipingOut = true;
                peek.outFrom = sy.value;
                sy.velocity = -Math.max(0, up) * 1000;
                sy.target = peek.outTo;
                peek.landed();                  // reduced motion: already there
            } else {
                // Pulled down (it rubber-bands), in two steps like iOS: the
                // first opens the preview (more of it, Reply); pulled again,
                // or one long pull, it's the reader (the whole message, the
                // conversation).
                // (By the finger's real travel: the shown pull is damped and
                // never passed ~20 px, so a 36 px check never fired.)
                if (rawDown > 40 && peek.item) {
                    if (Notifs.peekExpanded || rawDown > 140) Notifs.readInIsland(peek.item);
                    else Notifs.expandPeek();
                }
                sy.velocity = peek.swipeY < 0 ? fling.vy() * 1000 : 0;   // keeps the pointer's speed; the damped pull gets no throw
                sy.target = 0;
            }
        }
        property real rawDown: 0
        onTranslationChanged: {
            fling.add(translation.x, translation.y);
            const v = grab + translation.y;
            rawDown = Math.max(0, translation.y);
            sy.snap(v < 0 ? v : Theme.swipeDamp(v));
        }
    }

    HoverHandler { onHoveredChanged: Notifs.peekHeld = hovered }

    function openItem() {
        const i = peek.item;
        Notifs.dropPeek();
        if (i) Notifs.activate(i);
    }

    Item {
        id: mark
        x: peek.pad
        y: peek.expanded ? peek.pad : undefined
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
            rightMargin: peek.expanded ? peek.pad : 36
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
            Item {
                visible: !!peek.item && (!!peek.item.body || peek.redacted) && peek.expanded && !peek.hiddenOpen
                width: parent.width
                // The whole message scrolls here past maxBody; a fade at the
                // bottom says there's more (and goes once you've reached the end).
                height: Math.min(bodyScroll.contentHeight, peek.maxBody)
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
                        size: Theme.tBody; color: Theme.textSecondary
                        lineHeight: 1.12
                    }
                }
                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: 28
                    visible: bodyScroll.contentY + bodyScroll.height < bodyScroll.contentHeight - 2
                    gradient: Gradient {
                        GradientStop { position: 0; color: "transparent" }
                        GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.94) }
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
        anchors { left: copy.left; right: parent.right; rightMargin: peek.pad; bottom: parent.bottom; bottomMargin: peek.pad }
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
