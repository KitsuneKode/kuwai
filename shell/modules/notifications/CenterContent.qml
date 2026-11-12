// What's inside the center's card: tabs, search, the four views, the key
// hints. Center owns the surface and the motion; this owns the content, and
// is built once per monitor that hosts the card (see Center's Loader).
import QtQuick
import qs.config
import qs.components
import qs.services

Item {
    id: content

    required property var center
    // Only the hosting monitor's copy polls and meters; the others sleep.
    property bool hosting: false

    // For Center: the pieces it resets, focuses and asks for keys.
    readonly property alias search: search
    readonly property alias sheet: sheet
    readonly property alias tabs: tabs
    readonly property alias notifications: notifications
    readonly property alias sound: sound
    readonly property alias display: display
    readonly property alias tips: tipLayer
    readonly property var order: ["notifications", "sound", "controls"]   // agents live in the notch (Agents panel)

    function currentView() {
        return ({ notifications: notifications, sound: sound, controls: display })[center.tab] || notifications;
    }
    // The card's height for the tab showing: the chrome above and below the
    // pages, plus what the page wants (Center clamps it to the screen).
    readonly property real wantH: searchBox.y + searchBox.height + 14 + 18 + footer.height + 12 + 8
                                  + Math.max(160, currentView().naturalHeight || 0)
    // The key hints show once you use the keyboard here (the ? stays).
    property bool usedKeys: false
    function reset() {
        usedKeys = false;
        search.text = "";
        sheet.open = false;
        notifications.reset();
        sound.reset();
        display.reset();
    }

    // ── Header: the four tabs, full width ────────────────────────────────
    Item {
        id: header
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
        height: 36
        opacity: content.center.revealAt(0)

        Segmented {
            id: tabs
            width: parent.width
            current: content.center.tab
            options: [
                { id: "notifications", label: "Notifications", badge: Notifs.inbox },
                { id: "sound", label: "Sound" },
                { id: "controls", label: "Controls" }
            ]
            onPicked: id => { Notifs.centerTab = id; search.forceActiveFocus(); }
        }
    }

    // ── Search ───────────────────────────────────────────────────────────
    Rectangle {
        id: searchBox
        anchors { left: parent.left; right: parent.right; top: header.bottom; margins: 16; topMargin: 12 }
        height: 36
        radius: 12
        opacity: content.center.revealAt(40)
        color: Qt.rgba(1, 1, 1, search.activeFocus ? 0.10 : 0.07)
        border.width: 1
        // Focused: a soft white edge, not the accent (that means "where you are").
        border.color: search.activeFocus ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.07)
        Behavior on color { ColorAnimation { duration: Theme.hoverMs } }
        Behavior on border.color { ColorAnimation { duration: Theme.hoverMs } }

        Text {
            id: searchGlyph
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: "\u{f0349}"                          // magnify
            font.family: Theme.fontGlyph
            font.pixelSize: 15
            color: Theme.textTertiary
        }

        TextInput {
            id: search
            anchors { left: searchGlyph.right; right: clearSearch.left; verticalCenter: parent.verticalCenter; leftMargin: 9; rightMargin: 6 }
            onTextChanged: {
                content.center.query = text;
                Qt.callLater(() => content.currentView().selectFirst());
            }
            color: Theme.textPrimary
            selectionColor: Qt.alpha(Theme.blue, 0.5)
            selectedTextColor: Theme.textPrimary
            font.family: Theme.fontText
            font.pixelSize: 14
            font.variableAxes: ({ "opsz": Theme.opszFor(14), "wght": Theme.wRegular })
            font.letterSpacing: Theme.tracking(14, false)
            renderType: Text.NativeRendering
            cursorDelegate: SpringCaret {}
            clip: true

            Label {
                visible: search.text === ""
                anchors.verticalCenter: parent.verticalCenter
                text: ({ notifications: "Search notifications", sound: "Search apps and devices", controls: "Search networks and devices" })[content.center.tab] || "Search"
                size: 14
                color: Theme.textTertiary
            }

            Keys.onPressed: event => {
                const k = event.key;
                if ([Qt.Key_Up, Qt.Key_Down, Qt.Key_Return, Qt.Key_Enter, Qt.Key_Tab, Qt.Key_Backtab, Qt.Key_Delete].indexOf(k) >= 0
                    || (k === Qt.Key_Backspace && search.text === ""))
                    content.usedKeys = true;
                const ctrl = event.modifiers & Qt.ControlModifier;
                const alt = event.modifiers & Qt.AltModifier;
                const shift = event.modifiers & Qt.ShiftModifier;
                const help = k === Qt.Key_F1 || (ctrl && k === Qt.Key_Slash)
                          || (k === Qt.Key_Question && search.text === "");
                if (help) {
                    sheet.open = !sheet.open;
                } else if (sheet.open && k === Qt.Key_Escape) {
                    sheet.open = false;
                } else if (ctrl && k === Qt.Key_D) {
                    Notifs.toggleUserDnd();
                } else if (ctrl && shift && (k === Qt.Key_Backspace || k === Qt.Key_Delete)) {
                    notifications.clearAll();
                } else if (k === Qt.Key_Escape) {
                    if (search.text !== "") search.text = "";
                    else if (!content.currentView().back || !content.currentView().back())
                        Notifs.setCenter(false, "key");
                } else if (ctrl && (k === Qt.Key_Tab || k === Qt.Key_Backtab)) {
                    const i = content.order.indexOf(content.center.tab);
                    Notifs.centerTab = content.order[(i + (k === Qt.Key_Backtab ? 3 : 1)) % 4];
                } else if (alt && k >= Qt.Key_1 && k <= Qt.Key_3) {
                    Notifs.centerTab = content.order[k - Qt.Key_1];
                } else if (!content.currentView().key(event, search.text === "")) {
                    return;
                }
                event.accepted = true;
            }
        }

        Rectangle {
            id: clearSearch
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: 20; height: 20; radius: 10
            opacity: search.text !== "" ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: Theme.hoverMs } }
            color: clearQueryArea.containsMouse ? Theme.pillHover : Theme.pill
            Text {
                anchors.centerIn: parent
                text: "\u{f0156}"
                font.family: Theme.fontGlyph
                font.pixelSize: 11
                color: Theme.textPrimary
            }
            MouseArea {
                id: clearQueryArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { search.text = ""; search.forceActiveFocus(); }
            }
        }
    }

    // ── The tabs' content: crossfade, a short drift toward the side the new
    // tab sits on (the motion hints where it came from) ────────────────────
    Item {
        id: pages
        anchors { left: parent.left; right: parent.right; top: searchBox.bottom; bottom: footer.top; leftMargin: 14; rightMargin: 14; topMargin: 14; bottomMargin: 18 }

        Spring { id: tabT; tier: Theme.springModerate; target: content.order.indexOf(content.center.tab); Component.onCompleted: tabT.settle() }
        // Each page: fully there at its index, fading and drifting 24px
        // toward the side it sits on as the selection moves away.
        function vis(i) { return Math.max(0, 1 - Math.abs(tabT.value - i)); }
        function drift(i) { return Theme.reduceMotion ? 0 : (i - tabT.value) * 24; }

        NotificationsView {
            hosting: content.hosting
            id: notifications
            center: content.center
            anchors.fill: parent
            visible: opacity > 0.01
            opacity: pages.vis(0)
            transform: Translate { x: pages.drift(0) }
        }
        SoundView {
            hosting: content.hosting
            id: sound
            center: content.center
            anchors.fill: parent
            visible: opacity > 0.01
            opacity: pages.vis(1)
            transform: Translate { x: pages.drift(1) }
        }
        DisplayView {
            hosting: content.hosting
            id: display
            center: content.center
            anchors.fill: parent
            visible: opacity > 0.01
            opacity: pages.vis(2)
            transform: Translate { x: pages.drift(2) }
        }
    }

    // ── Keyboard hints: the few that matter here, as keys ────────────────
    Item {
        id: footer
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 16; bottomMargin: 12 }
        height: 22
        opacity: content.center.revealAt(200)

        // Hairline above: where the list ends and the chrome begins.
        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.top; bottomMargin: 8 }
            height: 1
            color: Qt.rgba(1, 1, 1, 0.06)
        }

        Row {
            id: hints
            anchors.verticalCenter: parent.verticalCenter
            spacing: 14
            opacity: content.usedKeys || sheet.open ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
            Repeater {
                model: content.center.tab === "notifications"
                    ? [{ k: ["↑", "↓"], t: "Select" }, { k: ["↩"], t: "Open" }, { k: ["r"], t: "Reply" }, { k: ["⌫"], t: "Dismiss" }]
                    : [{ k: ["⌥", "1–3"], t: "Tabs" }, { k: ["⎋"], t: "Close" }]
                Row {
                    id: hint
                    required property var modelData
                    spacing: 5
                    Row {
                        spacing: 3
                        anchors.verticalCenter: parent.verticalCenter
                        Repeater {
                            model: hint.modelData.k
                            KeyCap { required property string modelData; text: modelData }
                        }
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: hint.modelData.t
                        size: 12
                        color: Theme.textTertiary
                    }
                }
            }
        }

        // All shortcuts. The hit area is a sibling, not a child: a child
        // sized to the Row makes the Row lay itself out forever.
        Row {
            id: helpRow
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 5
            opacity: helpArea.containsMouse ? 1 : 0.85
            KeyCap { text: "?"; anchors.verticalCenter: parent.verticalCenter }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: "Shortcuts"
                size: 12
                color: helpArea.containsMouse ? Theme.textSecondary : Theme.textTertiary
            }
        }
        MouseArea {
            id: helpArea
            anchors.fill: helpRow
            anchors.margins: -4
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { sheet.open = !sheet.open; search.forceActiveFocus(); }
        }
    }

    ShortcutSheet {
        id: sheet
        anchors.fill: parent
        z: 10
    }

    Tips { id: tipLayer }
}
