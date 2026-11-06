// Read & Reply, grown out of the island: the whole message and an answer to
// it in one place. Opened by every "read this" (pull the peek down, a row in
// the bell list, Read in the center). Who sent it leads; the message reads as
// paragraphs (Notifs.readable); the composer sits under it, focused, so you
// can just start typing.
//   ⌃↵ send · ↵ a new line · Esc back
// A message whose sender can't take a reply (or is gone, after a restart)
// offers the way to it instead: Open.
import QtQuick
import Quickshell
import qs.config
import qs.components
import qs.services

FocusScope {
    id: rp
    focus: true
    implicitWidth: 500
    implicitHeight: col.implicitHeight + 40

    readonly property var item: Notifs.reading
    readonly property bool canReply: Notifs.canReply(item)
    readonly property string body: item ? Notifs.fullForDisplay(item) : ""
    property bool sent: false

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

        // ── The message: paragraphs, scrolls past ~16 lines ──────────────
        Item {
            width: parent.width
            height: msgFlick.height
            Flickable {
                id: msgFlick
                width: parent.width
                height: Math.min(msg.implicitHeight, 340)
                contentHeight: msg.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height
                Label {
                    id: msg
                    width: msgFlick.width - 8
                    text: rp.body
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    size: Theme.tBody; lineHeight: 1.35
                    color: Theme.textSecondary
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
