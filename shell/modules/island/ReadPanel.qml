// Read & Reply, grown out of the island: the whole message and an answer to
// it in one place. Opened by every "read this" (pull the peek down, a row in
// the bell list, Read in the center). Who sent it leads; the message reads as
// paragraphs (Notifs.readable); the composer sits under it, focused, so you
// can just start typing.
//   ⌃↵ send · ↵ a new line · Esc back
// A message whose sender can't take a reply (or is gone, after a restart)
// offers the way to it instead: Open.
// A conversation (a Gmail thread, a GitHub issue and its comments: the
// item's `thread`, from bin/rice-feeds) reads like a mail app: earlier
// messages folded to one line each (who, when, the first words), the newest
// open; click one to open or fold it. Your own say "You".
import QtQuick
import Quickshell
import qs.config
import qs.components
import qs.services

FocusScope {
    id: rp
    focus: true
    implicitWidth: convo.length ? 540 : 500
    implicitHeight: col.implicitHeight + 40

    readonly property var item: Notifs.reading
    readonly property bool canReply: Notifs.canReply(item)
    readonly property string body: item ? Notifs.fullForDisplay(item) : ""
    property bool sent: false
    // The conversation, oldest first; [] for a single message. Not while the
    // body is hidden (sharing the screen, a private chat).
    readonly property var convo: {
        if (!item || !item.thread || Notifs.bodyHidden(item, true)) return [];
        try { const t = JSON.parse(item.thread); return Array.isArray(t) && t.length > 1 ? t : []; } catch (e) { return []; }
    }
    property var opened: ({})            // index → open; the newest starts open
    onItemChanged: opened = ({})
    function isOpen(i) { return opened[i] !== undefined ? opened[i] : i === convo.length - 1; }
    function toggle(i) { const o = Object.assign({}, opened); o[i] = !isOpen(i); opened = o; }
    function when(t) {
        if (!t) return "";
        const d = new Date(t), now = new Date();
        if (d.toDateString() === now.toDateString()) return Qt.formatTime(d, Settings.clock24 ? "HH:mm" : "h:mm ap");
        return Qt.formatDate(d, now.getFullYear() === d.getFullYear() ? "d MMM" : "d MMM yyyy");
    }

    function ago(t) {
        const m = Math.max(0, Math.round((Date.now() - t) / 60000));
        return m < 1 ? "now" : m < 60 ? m + " min ago" : m < 1440 ? Math.floor(m / 60) + " h ago" : Math.floor(m / 1440) + " d ago";
    }
    function send() {
        const t = composer.text.trim();
        if (!t || !canReply || sent) return;
        const feed = !!item.feed;          // the feed says "Reply sent" itself
        Notifs.reply(item, t);
        sent = true;
        if (!feed) Moments.show({ kind: "reply", glyph: "\u{f012c}", label: "Reply sent", value: "", ring: -1, tone: Theme.green }, 1600);
        Island.close();
    }

    Column {
        id: col
        x: 20; y: 20
        width: rp.width - 40
        spacing: 14

        // ── Who: the sender leads, the app and when trail ────────────────
        Item {
            width: parent.width
            height: 40
            Rectangle {
                id: av
                width: 36; height: 36; radius: 18
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.chip
                clip: true
                Image {
                    anchors.fill: parent
                    source: rp.item && rp.item.icon ? rp.item.icon : ""
                    sourceSize: Qt.size(72, 72)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
                ImageEdge { radius: 18 }
            }
            Column {
                anchors { left: av.right; leftMargin: 12; right: openBtn.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                spacing: 2
                Label {
                    width: parent.width; elide: Text.ElideRight
                    text: rp.item ? (rp.item.title || rp.item.app || "") : ""
                    size: Theme.tCallout; weight: Theme.wSemibold
                }
                Label {
                    width: parent.width; elide: Text.ElideRight
                    text: rp.item ? (rp.item.app || "") + " · " + rp.ago(rp.item.time) : ""
                    size: Theme.tFootnote; color: Theme.textTertiary
                }
            }
            PillButton {
                id: openBtn
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: "Open"
                onClicked: { const i = rp.item; Island.close(); Notifs.openItem(i); }
            }
        }

        // A one-time code leads, with Copy.
        OtpChip { item: rp.item; width: parent.width }

        // ── The message: paragraphs, scrolls past ~16 lines ──────────────
        Item {
            width: parent.width
            height: msgFlick.height
            Flickable {
                id: msgFlick
                width: parent.width
                readonly property real natural: rp.convo.length ? convoCol.implicitHeight : msg.implicitHeight
                height: Math.min(natural, rp.convo.length ? 420 : 340)
                contentHeight: natural
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height
                // A conversation opens at its newest message.
                onNaturalChanged: if (rp.convo.length && !settled) contentY = Math.max(0, contentHeight - height)
                property bool settled: false
                onMovementStarted: settled = true
                Connections { target: rp; function onItemChanged() { msgFlick.settled = false; } }
                Label {
                    id: msg
                    visible: rp.convo.length === 0
                    width: msgFlick.width - 8
                    text: rp.body
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    size: Theme.tBody; lineHeight: 1.35
                    color: Theme.textSecondary
                }
                Column {
                    id: convoCol
                    visible: rp.convo.length > 0
                    width: msgFlick.width - 8
                    spacing: 6
                    // More came before than the reading view holds.
                    Label {
                        visible: rp.convo.length > 0 && !!rp.convo[0].skipped
                        text: rp.convo.length && rp.convo[0].skipped ? rp.convo[0].skipped + " earlier · Open to see them all" : ""
                        size: Theme.tFootnote; color: Theme.textTertiary
                        bottomPadding: 2
                    }
                    Repeater {
                        model: rp.convo
                        delegate: Rectangle {
                            id: mcard
                            required property var modelData
                            required property int index
                            readonly property bool open: rp.isOpen(index)
                            readonly property string who: modelData.me ? "You" : (modelData.who || "Someone")
                            readonly property string text: Notifs.readable(String(modelData.text || ""))
                            width: convoCol.width
                            height: mhead.height + bodyClip.height + 20
                            radius: Theme.r2
                            color: open ? Theme.card : (mArea.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : "transparent")
                            border.width: open ? 1 : 0
                            border.color: Theme.cardEdge
                            Behavior on color { ColorAnimation { duration: Theme.hoverMs } }
                            MouseArea {
                                id: mArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                // The newest stays open: it's the one you came to read.
                                onClicked: if (mcard.index !== rp.convo.length - 1) rp.toggle(mcard.index)
                            }
                            Item {
                                id: mhead
                                x: 12; y: 10
                                width: parent.width - 24
                                height: 28
                                Rectangle {
                                    id: initial
                                    width: 26; height: 26; radius: 13
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: mcard.modelData.me ? Qt.alpha(Theme.accent, 0.25) : Theme.chip
                                    Label {
                                        anchors.centerIn: parent
                                        text: mcard.who.slice(0, 1).toUpperCase()
                                        size: Theme.tFootnote; weight: Theme.wSemibold
                                        color: mcard.modelData.me ? Theme.accent : Theme.textSecondary
                                    }
                                }
                                Label {
                                    id: whoL
                                    anchors { left: initial.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
                                    text: mcard.who
                                    size: Theme.tSub; weight: Theme.wSemibold
                                    color: mcard.open ? Theme.textPrimary : Theme.textSecondary
                                }
                                // Folded: the first words, on the same line.
                                Label {
                                    anchors { left: whoL.right; leftMargin: 10; right: whenL.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                    visible: !mcard.open
                                    text: mcard.text.replace(/\s+/g, " ")
                                    elide: Text.ElideRight
                                    size: Theme.tSub; color: Theme.textTertiary
                                }
                                Label {
                                    id: whenL
                                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                    text: rp.when(mcard.modelData.when)
                                    size: Theme.tFootnote; color: Theme.textTertiary
                                    font.features: ({ "tnum": 1 })
                                }
                            }
                            // Open: the whole message. Height eases (an accordion,
                            // ease-out, enterMs); with reduced motion it just is.
                            Item {
                                id: bodyClip
                                x: 48; y: mhead.y + mhead.height + 4
                                width: parent.width - 60
                                height: mcard.open ? mbody.implicitHeight + 6 : 0
                                clip: true
                                Behavior on height { enabled: !Theme.reduceMotion; NumberAnimation { duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                                Label {
                                    id: mbody
                                    width: parent.width
                                    opacity: mcard.open ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: Theme.colorMs } }
                                    text: mcard.text
                                    textFormat: Text.PlainText
                                    wrapMode: Text.Wrap
                                    size: Theme.tBody; lineHeight: 1.35
                                    color: Theme.textSecondary
                                }
                            }
                        }
                    }
                }
            }
            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 32
                visible: msgFlick.contentY < msgFlick.contentHeight - msgFlick.height - 1
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0) }
                    GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.92) }
                }
            }
            ScrollHint { flickable: msgFlick; anchors { right: parent.right; top: parent.top; bottom: parent.bottom; rightMargin: -10 } }
        }

        // ── The composer ─────────────────────────────────────────────────
        Rectangle {
            visible: rp.canReply
            width: parent.width
            height: Math.min(Math.max(composer.implicitHeight, 22), 140) + 24 + footer.height + 8
            radius: Theme.r3
            color: Theme.card
            border.width: 1
            border.color: composer.activeFocus ? Qt.alpha(Theme.accent, 0.55) : Theme.cardEdge
            Behavior on border.color { ColorAnimation { duration: Theme.colorMs } }

            Flickable {
                id: composeFlick
                x: 14; y: 12
                width: parent.width - 28
                height: Math.min(Math.max(composer.implicitHeight, 22), 140)
                contentHeight: composer.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                TextEdit {
                    id: composer
                    width: composeFlick.width
                    focus: true
                    wrapMode: TextEdit.Wrap
                    font.family: Theme.fontText
                    font.pixelSize: Theme.tBody
                    color: Theme.textPrimary
                    selectionColor: Qt.alpha(Theme.accent, 0.45)
                    selectByMouse: true
                    cursorDelegate: SpringCaret {}
                    Keys.onPressed: e => {
                        if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && (e.modifiers & Qt.ControlModifier)) { rp.send(); e.accepted = true; }
                    }
                    onCursorRectangleChanged: {
                        // Keep the caret in view while the reply grows past the box.
                        const r = cursorRectangle;
                        if (r.y < composeFlick.contentY) composeFlick.contentY = r.y;
                        else if (r.y + r.height > composeFlick.contentY + composeFlick.height) composeFlick.contentY = r.y + r.height - composeFlick.height;
                    }
                    Label {
                        visible: composer.text === ""
                        text: "Reply to " + (rp.item ? (rp.item.title || rp.item.app || "") : "") + "…"
                        size: Theme.tBody; color: Theme.textTertiary
                        width: parent.width; elide: Text.ElideRight
                    }
                }
            }
            Item {
                id: footer
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 14; rightMargin: 8; bottomMargin: 8 }
                height: 30
                Label {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    text: "⌃↵ send · ↵ new line · Esc back"
                    size: Theme.tCaption; color: Theme.textTertiary
                }
                PillButton {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    text: "Send"
                    tint: composer.text.trim() !== "" ? Theme.accent : "transparent"
                    opacity: composer.text.trim() !== "" ? 1 : 0.45
                    Behavior on opacity { NumberAnimation { duration: Theme.colorMs } }
                    onClicked: rp.send()
                }
            }
        }

        // Can't answer here: say so, and the way to it.
        Label {
            visible: !rp.canReply && !!rp.item
            width: parent.width
            wrapMode: Text.Wrap
            text: rp.item && rp.item.notification ? "Reply in " + (rp.item.app || "the app") + " · Open takes you there"
                : "This one came before a restart, so it can't be answered here · Open takes you there"
            size: Theme.tFootnote; color: Theme.textTertiary
        }
    }
}
