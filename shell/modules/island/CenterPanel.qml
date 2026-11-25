import QtQuick
import qs.config
import qs.services
import "../notifications"

Item {
    id: panel

    implicitWidth: Theme.panelS
    implicitHeight: Math.round(Math.min(Theme.panelMaxH, Math.max(300, content.wantH)))

    CenterHost { id: host; open: true; notch: true; ui: content }

    CenterContent {
        id: content
        anchors.fill: parent
        center: host
        hosting: true
    }

    Component.onCompleted: {
        if (Notifs.centerTab === "notifications") Qt.callLater(() => content.notifications.applyHandoff());
        if (!Notifs.centerFocusReply) Qt.callLater(() => content.search.forceActiveFocus());
    }
}
