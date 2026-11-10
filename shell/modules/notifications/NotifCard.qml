// One notification toast on glass.
//
//   ┌────────────────────────────────────────────┐
//   │ [icon]  [CRITICAL] HyDE Power   ×2     now │  header
//   │    (!)  Battery low                        │  title
//   │         12% remaining, plug in soon        │  body (≤3 lines)
//   │         ✓ Thread completed                 │  status (adapter)
//   │         ( Reply ) ( Mark read )            │  extra actions
//   └────────────────────────────────────────────┘
//
// Motion and gestures follow Sonner (emilkowalski/sonner, read from
// refs/emilkowalski_sonner/src): Popups decides where each toast sits in
// the stack; the card animates there over 400ms with CSS `ease`, starting
// from wherever it is now.
//   enter     drops in from one card-height above (out from under the bar)
//   leave     the front one goes back up; one behind, while the stack is
//             fanned out, goes up from its own slot; one behind in the
//             collapsed stack sinks 40%; all unmount after 200ms
//   swipe     axis locks on the first pixel; right and up follow the pointer
//             1:1, left and down are damped (1 / (1.5 + |d|/20)); release
//             past 45px or faster than 0.11px/ms (averaged over the whole
//             gesture) throws it out over 200ms ease-out, else it eases home
//
// Severity sets the material, not just a colour on one word:
//   critical  red wash and edge, "CRITICAL" chip, icon badge, one glow ring
//             on arrival plus the warning sound; stays until dismissed,
//             rides at the front, ignores do-not-disturb
//   warning   orange wash and edge, "WARNING" chip, icon badge, 9s
//   normal    plain glass, 5.5s
//   low       lighter glass, one line of body, 3.5s
//
// Click the card to engage (Open / actions); right click or the hover
// close button dismisses. Engaged: explicit Open, then activate.
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import qs.config
import qs.components
import qs.services

Item {
    id: card

    required property var modelData
    required property var stack                 // the Popups scope
    readonly property var item: modelData

    readonly property string severity: item.severity
    readonly property bool critical: severity === "critical"
    readonly property bool warning: severity === "warning"
    readonly property bool low: severity === "low"
    readonly property color accent: critical ? Theme.red : warning ? Theme.orange : "transparent"

    // ── Place in the stack ───────────────────────────────────────────────
    readonly property int index: stack.live.indexOf(item)
    readonly property bool front: index === 0
    readonly property bool removed: item.leaving
    readonly property real naturalHeight: content.implicitHeight + 30
    readonly property real offset: index > 0 ? stack.offsetOf(index) : 0

    // Remembered while live, used for the exit path once it's removed.
    property int lastIndex: 0
    property real lastOffset: 0
    property bool lastExpanded: false
    onIndexChanged: if (index >= 0) { lastIndex = index; lastOffset = offset; }
    onOffsetChanged: if (index >= 0) lastOffset = offset
    readonly property bool stackExpanded: stack.expanded
    onStackExpandedChanged: if (!removed) lastExpanded = stackExpanded

    property bool mounted: false
    readonly property bool engaged: stack.engaged === item
    readonly property bool canOpen: item.hasDefault || !!item.focusClass || !!item.jump || /^https?:\/\//.test(item.url || "")
    readonly property bool canReply: Notifs.canReply(item)
    property bool replying: false

    readonly property bool behind: !front && !stack.expanded && !removed

    // Island mode: enter from the island, the front one leaves into it.
    property real islandW: 260
    readonly property bool fromIsland: !!stack.fromIsland && !Theme.reduceMotion
    readonly property real islandY: -(stack.islandGap + stack.islandH)
    readonly property bool inIsland: fromIsland && (!mounted || (removed && lastIndex === 0))
    property real em: inIsland ? 0 : 1
    Behavior on em { enabled: !Theme.reduceMotion; NumberAnimation { duration: Theme.stackMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }

    readonly property real targetY: {
        if (!mounted) return fromIsland ? islandY : -naturalHeight;
        if (removed) {
            if (lastIndex === 0) return fromIsland ? islandY : -height;
            if (lastExpanded) return lastOffset - height;
            return height * 0.4;
        }
        if (stack.expanded) return offset;
        if (front) return 0;
        return Theme.stackGap * index;
    }
    readonly property real targetScale: behind && mounted ? 1 - Theme.stackScaleStep * index : 1
    readonly property real targetOpacity: !mounted || removed || index >= Theme.stackVisible ? 0 : 1

    // Collapsed toasts behind the front one take its height (so their edges
    // peek out evenly) and hide their content.
    width: Theme.toastWidth
    height: behind ? stack.frontHeight : naturalHeight
    // Keeps its layer while leaving (the front one exits over the others).
    z: removed ? stack.live.length + 1 - lastIndex : stack.live.length - index
    y: targetY
    scale: targetScale
    opacity: targetOpacity * swipeFade
    transformOrigin: Item.Center

    // A non-front toast leaving a collapsed stack takes longer to sink and
    // fades faster, as in Sonner.
    readonly property bool sinking: removed && lastIndex > 0 && !lastExpanded
    // Reduced motion: toasts fade in place; the stack doesn't travel or scale.
    Behavior on y { enabled: !card.swiping && !Theme.reduceMotion; NumberAnimation { duration: card.sinking ? 500 : Theme.stackMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeCss } }
    Behavior on scale { enabled: !Theme.reduceMotion; NumberAnimation { duration: card.sinking ? 500 : Theme.stackMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeCss } }
    Behavior on opacity { enabled: !card.swipingOut; NumberAnimation { duration: card.sinking ? 200 : Theme.stackMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeCss } }
    Behavior on height { NumberAnimation { duration: Theme.stackMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeCss } }

    onNaturalHeightChanged: item.cardHeight = naturalHeight
    Component.onCompleted: {
        item.cardHeight = naturalHeight;
        lastExpanded = stack.expanded;
        if (item.leaving) { Notifs.left(item); return; }
        // Mount on the next frame so the drop-in is animated.
        Qt.callLater(() => { card.mounted = true; });
        if (critical) arrival.start();
    }

    // Removed: let the exit path play, unmount after 200ms (Sonner's timing).
    onRemovedChanged: if (removed) unmount.start()
    Timer { id: unmount; interval: Theme.unmountMs; onTriggered: Notifs.left(card.item) }

    Connections {
        target: card.item
        function onBumpsChanged() { bump.restart(); }
    }
    SequentialAnimation {
        id: bump
        NumberAnimation { target: pulse; properties: "xScale,yScale"; to: 1.02; duration: 110; easing.type: Easing.OutQuad }
        NumberAnimation { target: pulse; properties: "xScale,yScale"; to: 1.0; duration: 300; easing.type: Easing.OutCubic }
    }

    // ── Swipe ────────────────────────────────────────────────────────────
    // While the pointer is down the card is the pointer (each move snaps the
    // springs: no easing, no lag). Let go and a spring finishes it, seeded
    // with the pointer's speed (Fling), home or out; grabbing it again
    // mid-flight catches it where it is. The fade is the way out itself, so
    // a caught exit is never left half-faded.
    Spring { id: sx; tier: Theme.springModerate; epsilon: 0.5; onSettledChanged: card.swipeLanded() }
    Spring { id: sy; tier: Theme.springModerate; epsilon: 0.5; onSettledChanged: card.swipeLanded() }
    Fling { id: fling }
    readonly property real swipeX: sx.value
    readonly property real swipeY: sy.value
    property bool swiping: false
    property bool swipingOut: false
    property string swipeAxis: ""
    property real grabX: 0
    property real grabY: 0
    property real outFrom: 0
    property real outTo: 0
    readonly property real swipeFade: !swipingOut ? 1
        : Math.max(0, Math.min(1, 1 - Math.abs((swipeAxis === "x" ? swipeX : swipeY) - outFrom) / Math.max(1, Math.abs(outTo - outFrom))))
    function swipeLanded() {
        if (swipingOut && sx.settled && sy.settled) Notifs.drop(card.item);
    }

    transform: [
        Translate { x: card.swipeX; y: card.swipeY },
        Scale { id: pulse; origin.x: card.width / 2; origin.y: card.height / 2 },
        // Out of / back into the island: the island's width and a sliver of
        // height at em = 0, the full card at em = 1 (top edge stays put).
        Scale {
            origin.x: card.width / 2; origin.y: 0
            xScale: card.fromIsland ? (card.islandW / card.width) + (1 - card.islandW / card.width) * card.em : 1
            yScale: card.fromIsland ? 0.25 + 0.75 * card.em : 1
        }
    ]

    DragHandler {
        id: drag
        target: null
        dragThreshold: 2
        onActiveChanged: {
            if (active) {
                // Caught mid-flight (going home, or on its way out): it stays
                // where it is and follows the pointer from there.
                card.swipingOut = false;
                card.grabX = sx.value; card.grabY = sy.value;
                sx.snap(sx.value); sy.snap(sy.value);
                fling.reset();
                card.swiping = true;
                card.swipeAxis = card.grabX !== 0 ? "x" : card.grabY !== 0 ? "y" : "";
                card.stack.interacting = true;
                return;
            }
            card.stack.interacting = false;
            card.swiping = false;
            const x = card.swipeAxis === "x";
            const s = x ? sx : sy;
            const away = x ? 1 : -1;                         // right, up: away from the corner
            const amount = s.value * away;                   // how far out
            const flick = (x ? fling.vx() : fling.vy()) * away;   // px/ms, + is outward
            // Out past the distance, or flicked outward; a flick back home
            // keeps it even past the distance (it changed its mind).
            if (card.swipeAxis && amount > 0 && flick > -Theme.swipeFlick && (amount >= Theme.swipeThreshold || flick > Theme.swipeFlick)) {
                card.swipingOut = true;
                card.outFrom = s.value;
                card.outTo = s.value + away * (x ? card.width : card.height);
                s.velocity = Math.max(0, flick) * away * 1000;
                s.target = card.outTo;
            } else {
                s.velocity = amount > 0 ? flick * away * 1000 : 0;   // the damped side gets no throw
                s.target = 0;
            }
            card.swipeLanded();                              // reduced motion: already there
        }
        onTranslationChanged: {
            const dx = translation.x, dy = translation.y;
            fling.add(dx, dy);
            if (!card.swipeAxis && (Math.abs(dx) > 1 || Math.abs(dy) > 1))
                card.swipeAxis = Math.abs(dx) > Math.abs(dy) ? "x" : "y";
            if (card.swipeAxis === "x") { const v = card.grabX + dx; sx.snap(v > 0 ? v : Theme.swipeDamp(v)); }
            else if (card.swipeAxis === "y") { const v = card.grabY + dy; sy.snap(v < 0 ? v : Theme.swipeDamp(v)); }
        }
    }

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onTapped: (point, button) => {
            if (button === Qt.RightButton) { card.stack.engaged = null; Notifs.dismiss(card.item); }
            else if (Settings.notifToastInstantOpen) Notifs.activate(card.item);
            else if (card.stack.engaged !== card.item) {
                card.stack.engaged = card.item;
                card.stack.interacting = true;
                if (Settings.notifEngageReply && card.canReply)
                    Qt.callLater(() => { card.replying = true; });
            }
        }
    }

    // ── Material ─────────────────────────────────────────────────────────
    RectangularShadow {
        anchors.fill: glass
        radius: glass.radius
        offset.y: 6
        blur: 22
        spread: -2
        color: Qt.rgba(0, 0, 0, 0.26)
    }

    GlassCard {
        id: glass
        anchors.fill: parent
        radius: 22
        tint: card.low ? Theme.glassTint : Theme.glassIsland
    }

    // Severity wash: colour soaks into the glass from the top-left, where
    // the icon and chip are, and fades out across the card.
    Rectangle {
        anchors.fill: parent
        radius: glass.radius
        visible: card.critical || card.warning
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Qt.alpha(card.accent, card.critical ? 0.26 : 0.15) }
            GradientStop { position: 0.55; color: Qt.alpha(card.accent, card.critical ? 0.10 : 0.05) }
            GradientStop { position: 1.0; color: Qt.alpha(card.accent, card.critical ? 0.05 : 0.02) }
        }
        border.width: 1
        border.color: Qt.alpha(card.accent, card.critical ? 0.55 : 0.32)
    }

    Rectangle {
        anchors.fill: parent
        radius: glass.radius
        visible: card.engaged && !card.critical && !card.warning
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.22)
    }

    // Critical arrival: one ring of light leaves the card. Once, not a loop.
    Rectangle {
        id: ring
        anchors.fill: parent
        radius: glass.radius
        color: "transparent"
        border.width: 2
        border.color: Theme.red
        opacity: 0
        transform: Scale { id: ringScale; origin.x: ring.width / 2; origin.y: ring.height / 2 }
    }
    ParallelAnimation {
        id: arrival
        NumberAnimation { target: ring; property: "opacity"; from: 0.9; to: 0; duration: 900; easing.type: Easing.OutCubic }
        NumberAnimation { target: ringScale; properties: "xScale,yScale"; from: 1; to: 1.07; duration: 900; easing.type: Easing.OutCubic }
    }

    // ── Content ──────────────────────────────────────────────────────────
    Row {
        id: content
        // Hidden on toasts behind the front one (Sonner fades children 400ms)
        opacity: card.behind ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: Theme.stackMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeCss } }
        anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 15; leftMargin: 15; rightMargin: 17 }
        spacing: 13

        // App icon, or a glyph platter when the app gave us nothing to draw;
        // warning/critical put a badge on it so severity reads at a glance.
        Item {
            width: 42; height: 42

            ClippingRectangle {
                anchors.fill: parent
                radius: 11
                color: "transparent"
                visible: icon.status === Image.Ready
                Image {
                    id: icon
                    anchors.fill: parent
                    source: card.item.icon
                    sourceSize: Qt.size(84, 84)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    smooth: true
                    mipmap: true
                }
            }
            Rectangle {
                anchors.fill: parent
                visible: icon.status !== Image.Ready
                radius: 21
                color: card.critical || card.warning ? Qt.alpha(card.accent, 0.22) : Theme.platter
                Text {
                    anchors.centerIn: parent
                    text: card.critical ? "\u{f0026}" : card.warning ? "\u{f0029}" : "\u{f009a}"   // alert / alert-outline / bell
                    font.family: Theme.fontGlyph
                    font.pixelSize: 20
                    color: card.critical || card.warning ? card.accent : Theme.textPrimary
                }
            }
            Rectangle {
                visible: (card.critical || card.warning) && icon.status === Image.Ready
                width: 18; height: 18; radius: 9
                x: parent.width - 13; y: parent.height - 13
                color: card.accent
                border.width: 2
                border.color: Qt.rgba(0.08, 0.08, 0.10, 1)
                Label {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: 0.5
                    text: "!"
                    size: 11
                    weight: Theme.wBold
                    color: card.critical ? "white" : Qt.rgba(0.12, 0.08, 0, 1)
                }
            }
        }

        Column {
            width: content.width - 42 - content.spacing
            spacing: 3

            // Header: [severity chip] app ×count ··· age
            Item {
                width: parent.width
                height: 17

                Row {
                    anchors.left: parent.left
                    anchors.right: age.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    Rectangle {
                        visible: card.critical || card.warning
                        anchors.verticalCenter: parent.verticalCenter
                        height: 16
                        width: chipLabel.implicitWidth + 12
                        radius: 8
                        color: Qt.alpha(card.accent, 0.24)
                        Label {
                            id: chipLabel
                            anchors.centerIn: parent
                            text: card.critical ? "Critical" : "Warning"
                            size: 11
                            weight: Theme.wSemibold
                            color: card.critical ? "#ff6961" : Theme.orange
                        }
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, parent.width - x)
                        text: card.item.app
                        size: 12
                        weight: Theme.wMedium
                        elide: Text.ElideRight
                        color: Theme.textTertiary
                    }
                    Rectangle {
                        visible: card.item.count > 1 || card.item.burst > 0
                        anchors.verticalCenter: parent.verticalCenter
                        height: 16
                        width: countLabel.implicitWidth + 10
                        radius: 8
                        color: Theme.pill
                        Label {
                            id: countLabel
                            rounded: true
                            anchors.centerIn: parent
                            // Replaced in place: ×3; a burst it stands for: +13.
                            text: card.item.burst > 0 ? "+" + card.item.burst : card.item.count
                            size: 10
                            weight: Theme.wSemibold
                            font.features: ({ "tnum": 1 })
                            color: Theme.textSecondary
                        }
                    }
                }
                Label {
                    id: age
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: card.ageText
                    size: 12
                    font.features: ({ "tnum": 1 })
                    color: Theme.textTertiary
                }
            }

            Label {
                width: parent.width
                topPadding: 1
                text: card.item.title
                visible: text !== ""
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                size: 15
                weight: Theme.wSemibold
                lineHeight: 1.1
                color: Theme.textPrimary
            }

            Label {
                width: parent.width
                // Opened (engaged) shows a chat's body, never while sharing (bodyHidden).
                text: Notifs.bodyHidden(card.item, card.engaged) ? Notifs.bodyForDisplay(card.item, card.engaged) : Notifs.styledSafe(card.item.body)
                visible: text !== "" || Notifs.bodyRedacted(card.item)
                textFormat: Text.StyledText
                wrapMode: Text.Wrap
                maximumLineCount: card.low ? 1 : 3
                elide: Text.ElideRight
                size: 13
                lineHeight: 1.18
                color: Theme.textSecondary
                font.italic: Notifs.bodyRedacted(card.item) && !card.engaged
            }
            // A one-time code: the hero, with Copy.
            OtpChip { item: card.item; width: parent.width }

            Row {
                visible: card.item.status !== ""
                spacing: 6
                topPadding: 3
                Text {
                    visible: card.item.statusGlyph !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: card.item.statusGlyph
                    font.family: Theme.fontGlyph
                    font.pixelSize: 14
                    color: card.item.statusTone === "positive" ? Theme.positive
                         : card.item.statusTone === "caution" ? Theme.caution
                         : card.item.statusTone === "critical" ? Theme.critical
                         : Theme.textSecondary
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: card.item.status
                    size: 12
                    weight: Theme.wMedium
                    color: Theme.textSecondary
                }
            }

            Flow {
                width: parent.width
                visible: card.engaged && (card.canOpen || card.canReply || card.item.actions.length > 0)
                spacing: 6
                topPadding: 8
                Rectangle {
                    visible: card.canOpen
                    height: 28; radius: 14
                    width: openAct.implicitWidth + 26
                    color: openArea.containsMouse ? Qt.rgba(1, 1, 1, 0.92) : Qt.rgba(1, 1, 1, 0.88)
                    Label { id: openAct; anchors.centerIn: parent; text: "Open"; size: 12; weight: Theme.wSemibold; color: "#111111" }
                    MouseArea {
                        id: openArea
                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { card.stack.engaged = null; Notifs.activate(card.item) }
                    }
                }
                Rectangle {
                    visible: card.canReply && !card.replying
                    height: 28; radius: 14
                    width: replyChip.implicitWidth + 26
                    color: replyBtn.containsMouse ? Theme.pillHover : Theme.pill
                    Label { id: replyChip; anchors.centerIn: parent; text: "Reply"; size: 12; weight: Theme.wSemibold }
                    MouseArea {
                        id: replyBtn
                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { card.replying = true; card.stack.interacting = true; }
                    }
                }
                Repeater {
                    model: card.item.actions
                    delegate: Rectangle {
                        id: pillRect
                        required property var modelData
                        required property int index
                        // Critical: the first action is the way out, so it carries the colour.
                        readonly property bool primary: card.critical && index === 0
                        height: 28
                        width: actionLabel.implicitWidth + 26
                        radius: 14
                        color: primary ? Qt.alpha(Theme.red, actionArea.containsMouse ? 0.85 : 0.7)
                             : actionArea.containsMouse ? Theme.pillHover : Theme.pill
                        scale: actionArea.pressed ? 0.97 : 1
                        Behavior on color { ColorAnimation { duration: Theme.colorMs } }
                        Behavior on scale { enabled: !Theme.reduceMotion; NumberAnimation { duration: Theme.pressMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                        Label {
                            id: actionLabel
                            anchors.centerIn: parent
                            text: pillRect.modelData.text
                            size: 12
                            weight: Theme.wSemibold
                            color: Theme.textPrimary
                        }
                        MouseArea {
                            id: actionArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Notifs.invokeAction(card.item, pillRect.modelData.id)
                        }
                    }
                }
            }

            Rectangle {
                visible: card.engaged && card.canReply && card.replying
                width: parent.width
                height: 34
                radius: 10
                color: Qt.rgba(1, 1, 1, 0.08)
                border.width: 1
                border.color: toastReply.activeFocus ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.08)
                TextInput {
                    id: toastReply
                    anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.textPrimary
                    font.family: Theme.fontText
                    font.pixelSize: 13
                    clip: true
                    Component.onCompleted: if (card.replying) forceActiveFocus()
                    onVisibleChanged: if (visible) Qt.callLater(() => forceActiveFocus())
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            Notifs.reply(card.item, text);
                            text = "";
                            card.replying = false;
                            card.stack.engaged = null;
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Escape) {
                            text = "";
                            card.replying = false;
                            event.accepted = true;
                        }
                    }
                    Label {
                        visible: toastReply.text === ""
                        anchors.verticalCenter: parent.verticalCenter
                        text: (card.item.notification && card.item.notification.inlineReplyPlaceholder) || "Reply…"
                        size: 13
                        color: Theme.textTertiary
                    }
                }
            }
        }
    }


    // Close button: macOS-style, on the top-left corner, while hovered.
    Rectangle {
        width: 22; height: 22; radius: 11
        x: -6; y: -6
        opacity: hover.hovered && !card.behind ? 1 : 0
        visible: opacity > 0
        scale: closeArea.pressed ? 0.94 : 1
        Behavior on opacity { NumberAnimation { duration: 100 } }
        Behavior on scale { enabled: !Theme.reduceMotion; NumberAnimation { duration: Theme.pressMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
        color: closeArea.containsMouse ? Qt.rgba(0.30, 0.30, 0.33, 0.97) : Qt.rgba(0.18, 0.18, 0.20, 0.95)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.18)
        Text {
            anchors.centerIn: parent
            text: "\u{f0156}"                   // close
            font.family: Theme.fontGlyph
            font.pixelSize: 12
            color: Theme.textPrimary
        }
        MouseArea {
            id: closeArea
            anchors.fill: parent
            anchors.margins: -4
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { card.stack.engaged = null; Notifs.dismiss(card.item) }
        }
    }

    // "now", "3m", "2h": refreshed while on screen.
    property string ageText: "now"
    Timer {
        running: card.visible
        repeat: true
        triggeredOnStart: true
        interval: 20000
        onTriggered: {
            const m = Math.floor((Date.now() - card.item.time) / 60000);
            card.ageText = m < 1 ? "now" : m < 60 ? m + "m" : Math.floor(m / 60) + "h";
        }
    }
}
