// The Controls tab's Wi‑Fi picker, opened from the Wi‑Fi tile's chevron:
// what's around, strongest first (the network you're on, then saved ones).
//
//   ▂▄▆ Home            🔒  Connected      (hover: Disconnect)
//   ▂▄_ Office          🔒  Saved          click: join; hover: Forget
//   ▂__ Café                               click: join
//   ▂▄▆ Neighbour       🔒                 click: asks for the password inline
//
// Scans only while open. NetworkManager does the joining (Quickshell's
// Networking); a failure shows why under the row. Esc closes the password
// field first, then the list.
import QtQuick
import Quickshell
import Quickshell.Networking
import qs.config
import qs.components

Column {
    id: wifi

    required property var center
    property var device: null
    property bool open: false

    width: parent ? parent.width : 0
    spacing: 2

    property var asking: null                  // the network whose password is being typed
    property var failed: ({})                  // network name → why it didn't join
    function back() {
        if (asking) { asking = null; return true; }
        return false;
    }
    onOpenChanged: { if (!open) { asking = null; failed = {}; } scanStale = false; }

    // States: off · scanning · none found (after 8 s, with a rescan) · no
    // match for the search · the list. "Scanning…" used to stay forever.
    readonly property int found: device ? device.networks.values.filter(n => n.name).length : 0
    property bool scanStale: false
    onFoundChanged: if (found > 0) scanStale = false
    Timer { interval: 8000; running: wifi.open && Networking.wifiEnabled && wifi.found === 0 && !wifi.scanStale; onTriggered: wifi.scanStale = true }
    function rescan() {
        if (!device) return;
        scanStale = false;
        device.scannerEnabled = false;
        Qt.callLater(() => { if (wifi.device) wifi.device.scannerEnabled = true; });
    }
    readonly property string status: !Networking.wifiEnabled ? "Wi‑Fi is off"
        : !device ? "No Wi‑Fi adapter"
        : found === 0 ? (scanStale ? "None found" : "Scanning…")
        : networks.length === 0 ? "No match" : ""

    Binding { target: wifi.device; property: "scannerEnabled"; value: true; when: wifi.device !== null && wifi.open }

    readonly property var networks: (device ? device.networks.values : [])
        .filter(n => n.name && center.matchesText(n.name))
        .sort((a, b) => (b.connected - a.connected) || (b.known - a.known) || (b.signalStrength - a.signalStrength))
    function secured(n) { return n.security !== WifiSecurityType.Open && n.security !== WifiSecurityType.Owe; }
    function bars(s) { return s > 0.75 ? "\u{f0928}" : s > 0.5 ? "\u{f0925}" : s > 0.25 ? "\u{f0922}" : "\u{f091f}"; }
    function join(n) {
        failed = Object.assign({}, failed, { [n.name]: "" });
        if (n.known || !secured(n)) { asking = null; n.connect(); }
        else asking = n;
    }

    Item {
        width: wifi.width
        height: 26
        Label { x: 4; anchors.verticalCenter: parent.verticalCenter; text: "Networks"; size: 13; weight: Theme.wSemibold; color: Theme.textSecondary }
        Row {
            anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
            spacing: 8
            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: wifi.status
                size: Theme.tFootnote
                color: Theme.textTertiary
            }
            Label {
                visible: wifi.status === "None found"
                anchors.verticalCenter: parent.verticalCenter
                text: "Rescan"
                size: Theme.tFootnote; weight: Theme.wSemibold
                color: rescanArea.containsMouse ? Theme.textPrimary : Theme.accent
                MouseArea { id: rescanArea; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: wifi.rescan() }
            }
        }
    }

    Repeater {
        model: Networking.wifiEnabled ? wifi.networks.slice(0, 12) : []

        Item {
            id: row
            required property var modelData
            readonly property var net: modelData
            readonly property bool busy: net.stateChanging || net.state === ConnectionState.Connecting
            readonly property bool asking: wifi.asking === net
            readonly property string why: wifi.failed[net.name] || ""
            width: wifi.width
            height: 38 + (asking ? 44 : 0) + (why ? 18 : 0)
            Behavior on height { enabled: !Theme.reduceMotion; NumberAnimation { duration: Theme.reflowMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
            clip: true

            Connections {
                target: row.net
                function onConnectionFailed(reason) {
                    wifi.failed = Object.assign({}, wifi.failed, { [row.net.name]: ConnectionFailReason.toString(reason) });
                    if (reason === ConnectionFailReason.NoSecrets) wifi.asking = row.net;
                }
                function onConnectedChanged() { if (row.net.connected && wifi.asking === row.net) wifi.asking = null; }
            }

            Rectangle {
                width: parent.width
                height: 38
                radius: 12
                color: row.net.connected ? Qt.alpha(Theme.blue, 0.16) : hover.hovered ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.colorMs } }
            }
            HoverHandler { id: hover; cursorShape: row.net.connected ? Qt.ArrowCursor : Qt.PointingHandCursor }
            TapHandler { enabled: !row.net.connected; onTapped: wifi.join(row.net) }

            Text {
                id: strength
                x: 10; y: 9
                text: wifi.bars(row.net.signalStrength)
                font.family: Theme.fontGlyph
                font.pixelSize: 17
                color: row.net.connected ? Theme.blue : Theme.textSecondary
            }
            Label {
                anchors { left: strength.right; leftMargin: 10; right: trail.left; rightMargin: 8 }
                y: 10
                elide: Text.ElideRight
                text: wifi.center.highlight(row.net.name)
                textFormat: Text.StyledText
                size: 13
                weight: row.net.connected ? Theme.wSemibold : Theme.wRegular
            }
            Row {
                id: trail
                anchors.right: parent.right
                anchors.rightMargin: 10
                y: 9
                spacing: 8
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.busy ? "Joining…"
                        : row.net.connected ? (hover.hovered ? "" : "Connected")
                        : row.net.known && !hover.hovered ? "Saved" : ""
                    visible: text !== ""
                    size: 11
                    color: Theme.textTertiary
                }
                // Hover actions: leave the one you're on; forget a saved one.
                Rectangle {
                    visible: hover.hovered && !row.busy && (row.net.connected || row.net.known)
                    anchors.verticalCenter: parent.verticalCenter
                    height: 20; radius: 10
                    width: actLabel.implicitWidth + 14
                    color: actArea.containsMouse ? Theme.pillHover : Theme.pill
                    Label { id: actLabel; anchors.centerIn: parent; text: row.net.connected ? "Disconnect" : "Forget"; size: 11; weight: Theme.wMedium }
                    MouseArea {
                        id: actArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: row.net.connected ? row.net.disconnect() : row.net.forget()
                    }
                }
                Text {
                    visible: wifi.secured(row.net)
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u{f033e}"                                  // lock
                    font.family: Theme.fontGlyph
                    font.pixelSize: 12
                    color: Theme.textTertiary
                }
            }

            Label {
                visible: row.why !== ""
                x: 37; y: 36
                text: "Couldn't join: " + row.why
                size: 11
                color: Theme.red
            }

            // Password, inline under the network it's for.
            Rectangle {
                visible: row.asking
                x: 37
                y: 38 + (row.why ? 18 : 0) + 4
                width: parent.width - 37 - 4
                height: 34
                radius: 10
                color: Qt.rgba(1, 1, 1, 0.08)
                border.width: 1
                border.color: psk.activeFocus ? Qt.alpha(Theme.blue, 0.6) : Qt.rgba(1, 1, 1, 0.08)
                TextInput {
                    id: psk
                    anchors { left: parent.left; right: joinBtn.left; leftMargin: 10; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    echoMode: TextInput.Password
                    color: Theme.textPrimary
                    font.family: Theme.fontText
                    font.pixelSize: 13
                    renderType: Text.NativeRendering
                    clip: true
                    onVisibleChanged: if (visible) { text = ""; forceActiveFocus(); }
                    Label { visible: psk.text === ""; anchors.verticalCenter: parent.verticalCenter; text: "Password"; size: 13; color: Theme.textTertiary }
                    Keys.onReturnPressed: joinBtn.join()
                    Keys.onEnterPressed: joinBtn.join()
                    Keys.onEscapePressed: { wifi.asking = null; wifi.center.ui.search.forceActiveFocus(); }
                }
                Rectangle {
                    id: joinBtn
                    anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                    height: 26; radius: 8
                    width: joinLabel.implicitWidth + 20
                    color: psk.text.length >= 8 ? Theme.blue : Theme.pill
                    function join() {
                        if (psk.text.length < 8) return;
                        row.net.connectWithPsk(psk.text);
                        wifi.asking = null;
                        wifi.center.ui.search.forceActiveFocus();
                    }
                    Label { id: joinLabel; anchors.centerIn: parent; text: "Join"; size: 12; weight: Theme.wSemibold }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: joinBtn.join() }
                }
            }
        }
    }
}
