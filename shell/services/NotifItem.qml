// One notification as the rice sees it: the adapted text (see NotifAdapters)
// plus popup state. Live items hold the D-Bus Notification so actions can be
// invoked; items restored from history have none.
import QtQuick
import Quickshell.Services.Notifications

QtObject {
    id: item

    property Notification notification
    property int nid: -1              // D-Bus id, to reattach after a reload
    property real time: Date.now()

    property string app
    property string title
    property string body
    property string status
    property string statusGlyph
    property string statusTone
    property string icon
    property string savedIcon            // what history keeps (see NotifAdapters.lastingIcon)
    property string groupKey
    property string focusClass
    property int urgency: NotificationUrgency.Normal
    property string severity: "normal"   // critical | warning | normal | low
    property var actions: []          // [{ id, text }] besides the default one
    property bool hasDefault: false
    property int count: 1             // times this card was replaced in place
    property int bumps: 0             // ticks when replaced, the card pulses

    // ── Popup state ──────────────────────────────────────────────────────
    property bool popup: false        // on screen (including while leaving)
    property bool leaving: false      // exit animation requested
    property bool discard: false      // drop from history once it has left
    property bool hovered: false
    property int expireMs: 5000
    property int remaining: 5000      // counts down; pauses, never restarts (Sonner)
    property real cardHeight: 0       // the toast's natural height, for the stack

    // All toasts count down together and all pause while the stack is
    // expanded or being touched, then resume where they left off.
    readonly property Timer expiry: Timer {
        interval: 100
        repeat: true
        running: item.popup && !item.leaving && item.expireMs > 0 && !Notifs.held
        onTriggered: {
            item.remaining -= interval;
            if (item.remaining <= 0) item.leaving = true;
        }
    }

    readonly property Connections live: Connections {
        target: item.notification
        function onSummaryChanged() { item.refresh(); }
        function onBodyChanged() { item.refresh(); }
        function onImageChanged() { item.refresh(); }
        function onActionsChanged() { item.refresh(); }
        function onClosed(reason) {
            item.notification = null;
            // The app took it back (e.g. it replaced or withdrew it).
            if (reason === NotificationCloseReason.CloseRequested) item.leaving = true;
        }
    }

    function apply(n, a) {
        nid = n.id;
        app = a.app;
        title = a.title;
        body = a.body;
        status = a.status;
        statusGlyph = a.statusGlyph;
        statusTone = a.statusTone;
        icon = a.icon;
        savedIcon = NotifAdapters.lastingIcon(n, a.icon);
        groupKey = a.groupKey;
        focusClass = a.focusClass;
        urgency = n.urgency;
        severity = a.severity;
        hasDefault = n.actions.some(x => x.identifier === "default");
        actions = n.actions.filter(x => x.identifier !== "default" && x.text)
                           .map(x => ({ id: x.identifier, text: x.text }));
        // Critical stays until dealt with; warnings get time to be read;
        // low-priority ones get out of the way sooner.
        expireMs = severity === "critical" ? 0
                 : n.expireTimeout > 0 ? Math.max(3000, n.expireTimeout)
                 : severity === "warning" ? 9000
                 : severity === "low" ? 3500 : 5500;
        remaining = expireMs;
    }

    function refresh() {
        if (notification) apply(notification, NotifAdapters.adapt(notification));
    }

    // A newer notification with the same group key: take its content, keep
    // this card where it is, and restart its clock.
    function absorb(n, a) {
        const old = notification;
        notification = n;
        apply(n, a);
        time = Date.now();
        count += 1;
        bumps += 1;
        if (old && old !== n) old.dismiss();
    }

    function toJson() {
        return { nid, time, app, title, body, status, statusGlyph, statusTone, icon: savedIcon || icon, groupKey, focusClass, urgency, severity, count };
    }
}
