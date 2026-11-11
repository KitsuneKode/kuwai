// One notification inside the center: a lighter plate on the panel's glass.
// Click selects (read the snippet, Reply, or Open); Enter or Open runs the
// app's default action. Swipe it sideways, or the hover ×, right-click or
// Delete, and it slides out while the space it took closes (the rows below
// glide up at the same time, not after).
import QtQuick
import qs.config
import qs.components
import qs.services

Item {
    id: row

    required property var item
    // The row can outlive its notification for a frame while it collapses:
    // read through `it` so bindings see an empty object, not null.
    readonly property var it: item || ({})
    property var center                         // the NotificationsView
    property bool showTime: true
    readonly property bool selected: center && center.selected === item
    onSelectedChanged: if (selected && center) center.selectedRow = row
    Component.onDestruction: if (center && center.hoverRow === row) center.hoverRow = null

    readonly property bool critical: it.severity === "critical"
    readonly property bool warning: it.severity === "warning"
    readonly property color accent: critical ? Theme.red : warning ? Theme.orange : "transparent"
    readonly property bool unread: it.time > Notifs.lastSeen

    property real reveal: 0
    property bool removing: false
    property bool replying: false
    property bool snoozing: false
    // Live buttons: the app's actions (while it's still listening) and Reply.
    readonly property var liveActions: it.notification ? (it.actions || []).slice(0, 3) : []
    readonly property bool canReply: Notifs.canReply(item)
    readonly property bool canOpen: !!row.it.notification || !!row.it.focusClass || !!row.it.jump || /^https?:\/\//.test(row.it.url || "")
    readonly property bool previewScroll: row.selected && (row.warning || row.critical || String(row.it.body || "").length > 120 || !!row.it.full)
    // Selected with a whole message (a mail, a comment): read it all here.
    readonly property bool reading: row.selected && !!row.it.full && !Notifs.bodyHidden(row.it, true)

    function beginReply() {
        replying = true;
        Qt.callLater(() => replyField.forceActiveFocus());
    }
    function selectRow() {
        if (!center) return;
        if (!Settings.seenNotifC1Hint) Settings.set("seenNotifC1Hint", true);
        center.setExpanded(row.it.app, true);
        center.selected = row.item;
        center.keyboard = false;
    }

    width: parent ? parent.width : 0
    height: (body.implicitHeight + 24) * reveal
    opacity: reveal * swipe.fade
    transform: Translate { x: swipe.offset }
    clip: reveal < 1

    Component.onCompleted: {
        if (center && center.instant) reveal = 1;
        else grow.start();
    }
    // Reused for another notification (the top of a folded stack after its
    // first one was removed): show the new one whole.
    onItemChanged: if (removing) { shrink.stop(); removing = false; swipe.reset(); grow.start(); }
    NumberAnimation { id: grow; target: row; property: "reveal"; to: 1; duration: Theme.reduceMotion ? 0 : Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
    NumberAnimation {
        id: shrink; target: row; property: "reveal"; to: 0; duration: Theme.exitMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut
        onFinished: Notifs.discard(row.item)
    }
    // Out to the right (the way a swipe goes most), then collapse with it.
    function remove() {
        if (!swipe.gone) swipe.away(1);
        else collapse();
    }
    function collapse() {
        if (removing) return;
        removing = true;
        grow.stop();
        shrink.start();
    }
    SwipeAway {
        id: swipe
        span: row.width
        enabled: !row.replying
        onLeaving: row.collapse()
    }

    HoverHandler {
        id: hover
        onHoveredChanged: if (row.center) row.center.setHover(row, hovered)
        cursorShape: Qt.ArrowCursor
    }
    // Press feedback, kept tiny: rows are hit often.
    scale: tapH.pressed ? 0.985 : 1
    Behavior on scale { NumberAnimation { duration: Theme.pressMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
    TapHandler {
        id: tapH
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onTapped: (point, button) => {
            if (button === Qt.RightButton) row.remove();
            else row.selectRow();
        }
        onDoubleTapped: () => {
            if (!Settings.seenNotifC1Hint) Settings.set("seenNotifC1Hint", true);
            if (row.canOpen) Notifs.openItem(row.item);
        }
    }

    Rectangle {
        id: plate
        anchors.fill: parent
        radius: 18
        // Hover and the keyboard ring are the view's one gliding highlight.
        color: Qt.rgba(1, 1, 1, 0.065)
        border.width: 1
        border.color: row.selected ? Qt.rgba(1, 1, 1, row.critical || row.warning ? 0.28 : 0.18)
            : row.critical || row.warning ? Qt.alpha(row.accent, 0.35) : Qt.rgba(1, 1, 1, 0.06)

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            visible: row.critical || row.warning
            color: Qt.alpha(row.accent, row.critical ? 0.12 : 0.07)
        }
    }

    Column {
        id: body
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12; leftMargin: 14; rightMargin: 14 }
        spacing: 3

        Item {
            width: parent.width
            height: Math.max(titleText.implicitHeight, 18)

            Row {
                id: titleRow
                anchors.left: parent.left
                anchors.right: meta.left
                anchors.rightMargin: 8
                spacing: 6

                Rectangle {
                    visible: row.critical || row.warning
                    anchors.verticalCenter: titleText.verticalCenter
                    height: 16; radius: 8
                    width: chip.implicitWidth + 12
                    color: Qt.alpha(row.accent, 0.24)
                    Label {
                        id: chip
                        anchors.centerIn: parent
                        text: row.critical ? "Critical" : "Warning"
                        size: 11
                        weight: Theme.wSemibold
                        color: row.critical ? "#ff6961" : Theme.orange
                    }
                }
                Label {
                    id: titleText
                    width: titleRow.width - (row.critical || row.warning ? chip.implicitWidth + 18 : 0)
                    text: row.center ? row.center.highlight(row.it.title) : row.it.title
                    textFormat: Text.StyledText
                    // Two lines, like the toasts: the title is what tells them apart.
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    size: 14
                    weight: Theme.wSemibold
                }
            }
            Row {
                id: meta
                anchors.right: parent.right
                anchors.verticalCenter: titleRow.verticalCenter
                spacing: 6
                // Unread dot: Apple's blue, gone once the center has been seen.
                Rectangle {
                    visible: row.unread
                    anchors.verticalCenter: parent.verticalCenter
                    width: 7; height: 7; radius: 3.5
                    color: Theme.textPrimary         // unread: white, like the island's dot
                }
                Label {
                    visible: row.showTime && !hover.hovered
                    text: row.ageText
                    size: 12
                    font.features: ({ "tnum": 1 })
                    color: Theme.textTertiary
                }
                // Snooze, beside close while hovered
                Rectangle {
                    visible: hover.hovered || row.snoozing
                    width: 20; height: 20; radius: 10
                    color: snoozeArea.containsMouse || row.snoozing ? Theme.pillHover : Theme.pill
                    Accessible.role: Accessible.Button
                    Accessible.name: "Snooze"
                    Text { anchors.centerIn: parent; text: "\u{f051b}"; font.family: Theme.fontGlyph; font.pixelSize: 11; color: Theme.textPrimary }
                    MouseArea { id: snoozeArea; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { row.snoozing = !row.snoozing; row.replying = false; } }
                }
                // Close, in place of the time while hovered
                Rectangle {
                    Accessible.role: Accessible.Button
                    Accessible.name: "Dismiss"
                    visible: hover.hovered
                    width: 20; height: 20; radius: 10
                    color: closeArea.containsMouse ? Theme.pillHover : Theme.pill
                    Text {
                        anchors.centerIn: parent
                        text: "\u{f0156}"
                        font.family: Theme.fontGlyph
                        font.pixelSize: 11
                        color: Theme.textPrimary
                    }
                    MouseArea {
                        id: closeArea
                        anchors.fill: parent
                        anchors.margins: -4
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: row.remove()
                    }
                }
            }
        }

        Label {
            width: parent.width
            visible: (row.it.body !== "" || Notifs.bodyRedacted(row.it)) && !(row.selected && row.previewScroll)
            text: {
                const raw = row.it.body.replace(/<[^>]*>/g, "");
                // Selected shows a chat's body, never while sharing (bodyHidden).
                const show = Notifs.bodyHidden(row.it, row.selected) ? Notifs.bodyForDisplay(row.it, row.selected) : raw;
                return row.center && row.center.terms.length ? row.center.highlight(show) : show;
            }
            textFormat: Text.StyledText
            wrapMode: Text.Wrap
            maximumLineCount: row.selected && (row.warning || row.critical) ? 6 : 3
            elide: row.selected ? Text.ElideNone : Text.ElideRight
            size: 13
            lineHeight: 1.18
            color: Theme.textSecondary
        }
        Item {
            id: previewBox
            visible: row.previewScroll
            width: parent.width
            height: Math.min(row.reading ? 260 : 120, previewFlick.contentHeight)
            clip: true
            Flickable {
                id: previewFlick
                anchors.fill: parent
                contentHeight: previewBody.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                Label {
                    id: previewBody
                    width: previewFlick.width
                    wrapMode: Text.Wrap
                    text: row.reading ? Notifs.fullForDisplay(row.it)
                        : row.center && row.center.terms.length ? row.center.highlight(row.it.body.replace(/<[^>]*>/g, "")) : Notifs.styledSafe(row.it.body)
                    // A whole message is plain text (paragraphs kept, nothing parsed).
                    textFormat: row.reading ? Text.PlainText : Text.StyledText
                    size: 13; lineHeight: 1.18; color: Theme.textSecondary
                }
            }
        }

        Label {
            visible: row.selected && !row.canReply && !!row.it.url && (row.warning || row.critical || row.it.status !== "")
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Reply needs a live notification — use Open for the thread, or wait for the next alert from feeds."
            size: 11
            color: Theme.textTertiary
            topPadding: 2
        }

        Row {
            visible: row.it.status !== ""
            spacing: 6
            topPadding: 2
            Text {
                visible: row.it.statusGlyph !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: row.it.statusGlyph
                font.family: Theme.fontGlyph
                font.pixelSize: 13
                color: row.it.statusTone === "positive" ? Theme.positive
                     : row.it.statusTone === "caution" ? Theme.caution
                     : row.it.statusTone === "critical" ? Theme.critical
                     : Theme.textSecondary
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: row.it.status
                size: 12
                weight: Theme.wMedium
                color: Theme.textSecondary
            }
        }

        // ── Its buttons: shown once the row is selected (or while snoozing) ─
        Flow {
            visible: row.snoozing || (row.selected && (row.canOpen || row.liveActions.length > 0 || row.canReply || !!row.it.full || String(row.it.body || "").length > 0))
            width: parent.width
            spacing: 6
            topPadding: 4
            RowChip {
                visible: row.selected && row.canOpen && !row.snoozing
                text: "Open"
                filled: true
                onClicked: Notifs.openItem(row.item)
            }
            // Read it in the island: the whole message in the expanded peek,
            // Reply under it (the center closes).
            RowChip {
                visible: row.selected && !row.snoozing && (!!row.it.full || String(row.it.body || "").length > 0)
                text: "Read"
                glyph: "\u{f0208}"
                onClicked: Notifs.readInIsland(row.item)
            }
            RowChip {
                visible: row.selected && /^https?:\/\//.test(row.it.url || "")
                text: "Copy link"
                glyph: "\u{f0339}"
                onClicked: Clipboard.copyText(row.it.url)
            }
            Repeater {
                model: row.snoozing ? Notifs.snoozeChoices() : row.liveActions
                RowChip {
                    required property var modelData
                    text: row.snoozing ? modelData.label : modelData.text
                    onClicked: row.snoozing ? Notifs.snooze(row.item, modelData.until) : Notifs.invokeAction(row.item, modelData.id)
                }
            }
            RowChip {
                visible: row.canReply && !row.snoozing && !row.replying
                text: "Reply"
                glyph: "\u{f0167}"
                onClicked: row.beginReply()
            }
        }
        // Reply in place: Enter sends, Esc puts it away.
        Rectangle {
            visible: row.replying
            width: parent.width; height: 34; radius: 10
            color: Qt.rgba(1, 1, 1, 0.08)
            border.width: 1; border.color: replyField.activeFocus ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.08)
            TextInput {
                id: replyField
                anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.textPrimary
                font.family: Theme.fontText; font.pixelSize: 13
                clip: true
                Accessible.name: "Reply to " + (row.it.app || "the app")
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { Notifs.reply(row.item, text); text = ""; row.replying = false; event.accepted = true; }
                    else if (event.key === Qt.Key_Escape) { text = ""; row.replying = false; event.accepted = true; }
                }
                Label {
                    visible: replyField.text === ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: (row.it.notification && row.it.notification.inlineReplyPlaceholder) || "Reply…"
                    size: 13; color: Theme.textTertiary
                }
            }
        }
    }

    property string ageText: ""
    Timer {
        running: row.visible
        repeat: true
        triggeredOnStart: true
        interval: 30000
        onTriggered: {
            const m = Math.floor((Date.now() - row.it.time) / 60000);
            const d = Math.floor(m / 1440);
            row.ageText = m < 1 ? "now" : m < 60 ? m + "m" : m < 1440 ? Math.floor(m / 60) + "h" : d + "d";
        }
    }
}
