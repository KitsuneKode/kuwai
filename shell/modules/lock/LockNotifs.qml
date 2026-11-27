// The notifications that matter, on the lock screen, under what's playing:
// what the island's missed dot counts (Notifs.missed's rule: critical or
// warning, or something you can act on), since you last looked, newest
// first. As on an iPhone, a preview: the app, when, the headline and one
// line of it, and the app's own status where its adapter gives one
// ("✓ Completed", "Usage limit reached"). One card per conversation or
// thread (the adapter's group), with a count and a card peeking out behind
// it; three at most and "N more". A code (a verification or sign-in
// message) never shows: "Code hidden · unlock to see". A new one springs in
// at the top and the rest make room. A click asks for the password and
// opens that notification once you're in (`tapped(item)`).
import QtQuick
import Quickshell.Services.Notifications
import Quickshell.Widgets
import qs.config
import qs.components
import qs.services

Column {
    id: stack
    signal tapped(var item)
    property real plate: 0
    spacing: 8
    width: Theme.sp(430)
    readonly property real move: Theme.reduceMotion ? 0 : 1

    function notable(i) {
        return !i.discard && i.time > Notifs.lastSeen
            && (i.severity === "critical" || i.severity === "warning" || i.urgency === NotificationUrgency.Critical || i.hasDefault || (i.actions && i.actions.length));
    }
    function key(i) { return i.groupKey || (i.nid + ":" + i.time); }
    // Newest first, one entry per group: { k, item (the newest), count }.
    readonly property var groups: {
        const out = [], at = {};
        for (const i of Notifs.items.filter(notable).sort((a, b) => b.time - a.time)) {
            const k = key(i);
            if (at[k] === undefined) { at[k] = out.length; out.push({ k: k, item: i, count: 1 }); }
            else out[at[k]].count++;
        }
        return out;
    }
    property real room: Infinity
    function fits(total, room, each, gap, note) {
        let n = Math.min(3, total);
        while (n > 0 && n * each + (n - 1) * gap + (n < total ? gap + note : 0) > room) n--;
        return n;
    }
    readonly property var shownGroups: groups.slice(0, fits(groups.length, room, Theme.sp(90), spacing, Theme.sp(18)))
    readonly property var byKey: { const m = {}; for (const g of groups) m[g.k] = g; return m; }

    // A code can sit in the title as well as the body ("123456 is your
    // code"), and the title is drawn on its own line: both are checked, both hidden.
    // At least as careful as the rest of the shell (review 2026-11-10, finding
    // 06): anything Notifs.otpOf calls a code (grouped "123 456", a Security
    // PIN) is one here too, and so is a text that talks about a code and has
    // a number that could be one (Notifs.otpLikely). Not a link, a date or a
    // branch name: "Code hidden" on every GitHub notification taught nothing.
    function isCode(i) { return Notifs.otpOf(i) !== "" || Notifs.otpLikely(i); }
    function heading(i) {
        if (isCode(i) && Notifs.codeShaped(i.title || "")) return (i.app || "Verification") + " · code";
        if (Notifs.lockHidden(i)) return i.app || "Message";
        return i.title || i.app || "";
    }
    function preview(i) {
        if (isCode(i)) return "Code hidden · unlock to see or clear";
        if (Notifs.lockHidden(i)) return "Message hidden · unlock to read or clear";
        return String(i.body || "").replace(/\s+/g, " ").trim();
    }

    function guarded(list) { return list.some(i => Notifs.lockHidden(i) || isCode(i)); }
    function members(k) { return Notifs.items.filter(i => key(i) === k); }
    function clear(k) {
        const all = members(k);
        if (guarded(all)) return false;
        for (const i of all) Notifs.remove(i);
        return true;
    }

    property real now: Date.now()
    Timer { interval: 30000; running: stack.groups.length > 0; repeat: true; onTriggered: stack.now = Date.now() }
    function ago(t) {
        const m = Math.floor((now - t) / 60000);
        return m < 1 ? "now" : m < 60 ? m + "m ago" : Math.floor(m / 60) + "h ago";
    }

    // Kept as a model of keys, so only what changed animates (a fresh array
    // would replay every card).
    ListModel { id: model }
    onShownGroupsChanged: {
        const want = shownGroups.map(g => g.k);
        for (let i = model.count - 1; i >= 0; i--)
            if (want.indexOf(model.get(i).k) < 0) model.remove(i);
        want.forEach((k, i) => {
            let at = -1;
            for (let j = 0; j < model.count; j++) if (model.get(j).k === k) at = j;
            if (at < 0) model.insert(i, { k: k });
            else if (at !== i) model.move(at, i, 1);
        });
    }

    ListView {
        id: list
        width: parent.width
        height: contentHeight
        interactive: false
        spacing: 8
        model: model
        // One moment, one timing family: the arriving card (the lead) and the
        // cards it pushes down move together, same curve, same length. No
        // overshoot: a notification arriving isn't a flick or a plug-in
        // (STATES.md), and the lock screen should read calm.
        add: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
                NumberAnimation { property: "scale"; from: 1 - 0.04 * stack.move; to: 1; duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
            }
        }
        displaced: Transition {
            enabled: !Theme.reduceMotion
            NumberAnimation { property: "y"; duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
        }
        remove: Transition {
            NumberAnimation { property: "opacity"; to: 0; duration: Theme.microMs }
        }
        delegate: Item {
            id: card
            required property string k
            readonly property var group: stack.byKey[k] || ({ item: ({}), count: 0 })
            readonly property var item: group.item
            readonly property bool loud: item.severity === "critical" || item.severity === "warning"
            readonly property color tone: item.severity === "critical" ? Theme.red : Theme.orange
            readonly property color statusColor: item.statusTone === "positive" ? Theme.green : item.statusTone === "caution" ? Theme.orange
                : item.statusTone === "critical" ? Theme.red : Qt.rgba(1, 1, 1, 0.7)
            readonly property string line: stack.preview(item)
            readonly property bool stacked: group.count > 1
            readonly property bool guarded: stack.guarded(stack.members(k))
            readonly property bool guardNote: guarded && !stack.isCode(item) && !Notifs.lockHidden(item)
            width: list.width
            height: face.height + (stacked ? 8 : 0)

            // More from the same conversation: a card peeking out below.
            Item {
                visible: card.stacked
                anchors { left: parent.left; right: parent.right; top: face.bottom; bottom: parent.bottom }
                clip: true
                Rectangle {
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
                    width: parent.width - 24; height: 30
                    radius: Theme.r3
                    color: Qt.alpha(Theme.glassBlack, stack.plate)
                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        color: Theme.wash(2)
                        border.width: 1
                        border.color: Theme.edge(1)
                    }
                }
            }
            Item {
                id: face
                width: parent.width
                height: Math.max(64, words.implicitHeight + 27)

                Rectangle {
                    anchors.fill: parent
                    radius: faceBg.radius
                    visible: stack.plate > 0.005
                    color: Qt.alpha(Theme.glassBlack, stack.plate)
                }
                Rectangle {
                    id: faceBg
                    anchors.fill: parent
                    radius: 20
                    color: Qt.rgba(1, 1, 1, over.hovered ? 0.2 : 0.15)
                    border.width: 1
                    border.color: card.loud ? Qt.alpha(card.tone, 0.55) : Theme.edge(3)
                    Behavior on color { ColorAnimation { duration: Theme.colorMs } }
                }
                Item {
                    id: iconBox
                    x: 14; y: 14
                    width: 38; height: 38
                    ClippingRectangle {
                        anchors.fill: parent
                        radius: 10
                        color: "transparent"
                        visible: icon.status === Image.Ready
                        Image { id: icon; anchors.fill: parent; source: Notifs.lockHidden(card.item) ? NotifAdapters.iconForApp(card.item.app || "") : NotifAdapters.resolveIcon(card.item); sourceSize: Qt.size(76, 76); fillMode: Image.PreserveAspectCrop; asynchronous: true; mipmap: true }
                    }
                    Rectangle {
                        anchors.fill: parent
                        visible: icon.status !== Image.Ready
                        radius: 19
                        color: card.loud ? Qt.alpha(card.tone, 0.25) : Theme.wash(3)
                        Text {
                            textFormat: Text.PlainText
                            anchors.centerIn: parent
                            text: card.item.severity === "critical" ? "\u{f0026}" : card.item.severity === "warning" ? "\u{f0029}" : "\u{f009a}"
                            font.family: Theme.fontGlyph; font.pixelSize: 18
                            color: card.loud ? card.tone : "white"
                        }
                    }
                    // How many in this conversation.
                    Rectangle {
                        visible: card.stacked
                        anchors { right: parent.right; top: parent.top; rightMargin: -6; topMargin: -6 }
                        width: Math.max(18, countLabel.implicitWidth + 10); height: 18; radius: 9
                        color: "white"
                        Label { id: countLabel; anchors.centerIn: parent; text: card.group.count; size: Theme.tFootnote; weight: Theme.wBold; rounded: true; color: Theme.inkOnLight }
                    }
                }
                Column {
                    id: words
                    anchors { left: iconBox.right; leftMargin: 12; right: parent.right; rightMargin: 16; top: parent.top; topMargin: 13 }
                    spacing: 2
                    Item {
                        width: parent.width; height: appLabel.height
                        Label {
                            id: appLabel
                            anchors.left: parent.left
                            width: parent.width - when.width - 8
                            elide: Text.ElideRight
                            text: card.item.app || "Notification"
                            size: Theme.tSub; weight: Theme.wMedium
                            color: Qt.rgba(1, 1, 1, 0.62)
                        }
                        Label {
                            id: when
                            anchors.right: parent.right
                            text: stack.ago(card.item.time)
                            size: Theme.tSub
                            color: Qt.rgba(1, 1, 1, 0.5)
                        }
                    }
                    Label {
                        width: parent.width
                        elide: Text.ElideRight
                        text: stack.heading(card.item)
                        textFormat: Text.PlainText
                        size: Theme.tCallout; weight: Theme.wSemibold
                        color: "white"
                    }
                    Label {
                        id: lineLabel
                        visible: card.line !== ""
                        width: parent.width
                        maximumLineCount: 1
                        elide: Text.ElideRight
                        text: card.line
                        textFormat: Text.PlainText
                        size: Theme.tBody
                        font.italic: stack.isCode(card.item)
                        color: Qt.rgba(1, 1, 1, stack.isCode(card.item) ? 0.55 : 0.78)
                    }
                    Row {
                        id: statusRow
                        visible: !!card.item.status && !Notifs.lockHidden(card.item)
                        topPadding: 2
                        spacing: 5
                        Text {
                            textFormat: Text.PlainText
                            visible: !!card.item.statusGlyph
                            anchors.verticalCenter: parent.verticalCenter
                            text: card.item.statusGlyph || ""
                            font.family: Theme.fontGlyph; font.pixelSize: 13
                            color: card.statusColor
                        }
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            text: card.item.status || ""
                            size: Theme.tSub; weight: Theme.wMedium
                            color: card.statusColor
                        }
                    }
                    Label {
                        visible: card.guardNote
                        topPadding: 2
                        text: "Unlock to clear"
                        size: Theme.tSub; weight: Theme.wMedium
                        color: Qt.rgba(1, 1, 1, 0.62)
                    }
                }
                HoverHandler { id: over; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: stack.tapped(card.item) }
                // The keyboard's way to the same two things: Enter asks to open it,
                // Delete clears the conversation (as a swipe does).
                activeFocusOnTab: true
                Keys.onPressed: e => {
                    if (e.key === Qt.Key_Space || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { stack.tapped(card.item); e.accepted = true; }
                    else if (e.key === Qt.Key_Delete) {
                        stack.clear(card.k);
                        e.accepted = true;
                    }
                }
                FocusRing { cornerRadius: faceBg.radius }
                // Only what the lock screen already shows (its heading and line, never more).
                Accessible.role: Accessible.Button
                Accessible.name: (card.item.app || "Notification") + ": " + stack.heading(card.item)
                Accessible.description: card.line + (statusRow.visible ? ". " + card.item.status : "") + (card.guardNote ? ". Unlock to clear" : "")
                Accessible.onPressAction: stack.tapped(card.item)
                // Swipe it away, either way: the shell's one swipe (components/
                // SwipeAway), as in the notch's list and the center. It follows the
                // pointer 1:1 and fades with the distance; past 40 % of its width or
                // on a flick it leaves at the pointer's speed, otherwise it comes home,
                // and it can be caught on the way. The conversation clears as it
                // leaves (it only clears; nothing opens while locked). This used to be
                // its own drag: a fixed 100 px line, a fixed-length ease whatever the
                // speed, and no fade until it was already going.
                SwipeAway {
                    id: swipe
                    span: card.width
                    held: card.guarded
                    onLeaving: stack.clear(card.k)
                }
                transform: Translate { x: swipe.offset }
                opacity: swipe.fade
            }
        }
    }
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: stack.groups.length > stack.shownGroups.length
        width: more.width + Theme.s5; height: more.height + Theme.s2
        radius: height / 2
        color: Qt.alpha(Theme.glassBlack, stack.plate)
        Rectangle { anchors.fill: parent; radius: parent.radius; color: Theme.platter }
        Label {
            id: more
            anchors.centerIn: parent
            text: stack.shownGroups.length ? (stack.groups.length - stack.shownGroups.length) + " more"
                : stack.groups.length === 1 ? "1 notification" : stack.groups.length + " notifications"
            size: Theme.tBody; weight: Theme.wMedium
            color: Qt.rgba(1, 1, 1, 0.72)
        }
    }
}
