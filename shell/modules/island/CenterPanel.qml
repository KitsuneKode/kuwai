import QtQuick
import qs.config
import qs.services
import "../notifications"

Item {
    id: panel

    property string query: ""

    implicitWidth: Theme.panelS
    implicitHeight: Math.round(Math.min(Theme.panelMaxH, Math.max(300, content.wantH)))

    CenterHost { id: host; open: true; inIsland: true; ui: content }

    CenterContent {
        id: content
        anchors.fill: parent
        center: host
        hosting: true
    }

    Component.onCompleted: {
        if (Notifs.centerTab === "notifications") Qt.callLater(() => content.notifications.applyHandoff());
        if (panel.query !== "") content.search.text = panel.query;
        if (!Notifs.centerFocusReply) Qt.callLater(() => content.search.forceActiveFocus());
    }
}
