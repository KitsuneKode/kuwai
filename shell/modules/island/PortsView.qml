import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.config
import qs.components
import qs.components.ui as Ui
import qs.services
import "../../services/ports.mjs" as P

FocusScope {
    id: pv
    property real maxHeight: 400
    readonly property bool stackMetrics: Theme.textScale >= 1.5
    readonly property real rowH: Theme.sp(Theme.rowMin) + (stackMetrics ? Theme.sp(28) + Theme.s2 : 0)
    readonly property real portW: Theme.sp(56)
    readonly property real cpuW: Theme.sp(48)
    readonly property real memW: Theme.sp(72)
    readonly property real scopeW: cpuW
    readonly property real openW: portW
    readonly property real stopW: Theme.sp(64)
    readonly property real trailW: portW + scopeW + cpuW + memW + Theme.s2 * 3
    readonly property real headY: Theme.sp(24) + Theme.s2
    readonly property int placeholders: Math.max(2, Math.min(5, Math.floor((maxHeight - headY) / rowH)))
    readonly property real placeholderH: placeholders * rowH
    readonly property string phase: Ports.phase
    readonly property bool shaped: phase === "ready" || phase === "loading"
    readonly property real topY: shaped ? headY : 0
    readonly property real listMax: Math.max(2 * rowH, maxHeight - headY)
    property bool keyboard: false
    property string selKey: ""
    property Item hoverRow: null
    readonly property int selIndex: Ports.shown.indexOf(selKey)
    property real sheen: 0

    implicitWidth: parent ? parent.width : Theme.panelM
    implicitHeight: phase === "ready" ? topY + list.height : topY + stage.height
    height: implicitHeight
    focus: true

    Component.onCompleted: Ports.watch()
    Component.onDestruction: Ports.unwatch()
    Binding { target: Ports; property: "hold"; value: pv.hoverRow !== null || pv.keyboard }

    NumberAnimation on sheen {
        running: pv.phase === "loading" && pv.visible && !Theme.reduceMotion
        from: 0; to: 1
        duration: Theme.shimmerMs
        loops: Animation.Infinite
    }

    function move(by) {
        if (Ports.count === 0) return;
        keyboard = true;
        const at = Math.max(0, Math.min(Ports.count - 1, (selIndex < 0 ? (by > 0 ? -1 : Ports.count) : selIndex) + by));
        selKey = Ports.shown[at];
        list.positionViewAtIndex(at, ListView.Contain);
    }

    function act(action) {
        const item = list.itemAtIndex(selIndex);
        if (item) Ports.press(item.key, action, item.title);
    }

    function openSel() {
        const item = list.itemAtIndex(selIndex);
        if (item && item.openable) Ports.openUrl(item.port);
    }

    Keys.onPressed: e => {
        if (e.key === Qt.Key_Down) move(1);
        else if (e.key === Qt.Key_Up) move(-1);
        else if ((e.key === Qt.Key_Delete || e.key === Qt.Key_Backspace) && pv.phase === "ready" && selIndex >= 0) act((e.modifiers & Qt.ShiftModifier) ? "force" : "stop");
        else if (e.key === Qt.Key_O && (e.modifiers & Qt.ControlModifier)) openSel();
        else if (e.key === Qt.Key_Escape && Ports.armedKey !== "") { Ports.armedKey = ""; Ports.armedAction = ""; }
        else return;
        e.accepted = true;
    }

    Item {
        id: head
        visible: pv.shaped
        width: parent.width
        height: Theme.sp(24)
        Skeleton {
            visible: pv.phase === "loading"
            x: Theme.rowInset
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.sp(72); height: Theme.sp(10)
            phase: pv.sheen
        }
        Label {
            visible: pv.phase === "ready"
            x: Theme.rowInset
            anchors.verticalCenter: parent.verticalCenter
            text: Ports.count + (Ports.count === 1 ? " port" : " ports")
            size: Theme.tFootnote; weight: Theme.wSemibold; color: Theme.textTertiary
        }
        Row {
            visible: pv.phase === "ready"
            height: parent.height
            anchors { right: parent.right; rightMargin: Theme.rowInset; verticalCenter: parent.verticalCenter }
            spacing: Theme.s2
            Item {
                width: pv.portW; height: parent.height
                Label {
                    anchors.centerIn: parent
                    text: "Port" + (Ports.sortKey === "port" ? (Ports.sortDir < 0 ? " ↓" : " ↑") : "")
                    size: Theme.tFootnote; weight: Theme.wSemibold; color: Theme.textTertiary
                }
                Accessible.role: Accessible.Button
                Accessible.name: "Sort by port"
                Accessible.onPressAction: Ports.chooseSort("port")
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Ports.chooseSort("port") }
            }
            Item { width: pv.scopeW; height: parent.height }
            Item {
                width: pv.cpuW; height: parent.height
                Label {
                    anchors.centerIn: parent
                    text: "CPU" + (Ports.sortKey === "cpu" ? (Ports.sortDir < 0 ? " ↓" : " ↑") : "")
                    size: Theme.tFootnote; weight: Theme.wSemibold; color: Theme.textTertiary
                }
                Accessible.role: Accessible.Button
                Accessible.name: "Sort by CPU"
                Accessible.onPressAction: Ports.chooseSort("cpu")
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Ports.chooseSort("cpu") }
            }
            Item {
                width: pv.memW; height: parent.height
                Label {
                    anchors.centerIn: parent
                    text: "Memory" + (Ports.sortKey === "memory" ? (Ports.sortDir < 0 ? " ↓" : " ↑") : "")
                    size: Theme.tFootnote; weight: Theme.wSemibold; color: Theme.textTertiary
                }
                Accessible.role: Accessible.Button
                Accessible.name: "Sort by memory"
                Accessible.onPressAction: Ports.chooseSort("memory")
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Ports.chooseSort("memory") }
            }
        }
    }

    Column {
        id: stage
        y: pv.topY
        width: parent.width
        visible: pv.phase !== "ready"
        height: visible ? implicitHeight : 0

        Column {
            visible: pv.phase === "loading"
            width: parent.width
            Repeater {
                model: pv.placeholders
                Item {
                    width: parent.width
                    height: pv.rowH
                    Skeleton { x: Theme.rowInset; anchors.verticalCenter: parent.verticalCenter; width: Theme.rowMark; height: width; radius: Theme.r1; phase: pv.sheen }
                    Column {
                        x: Theme.rowInset + Theme.rowMark + Theme.rowGap
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.s1 + 2
                        Skeleton { width: Theme.sp(150); height: Theme.sp(12); phase: pv.sheen }
                        Skeleton { width: Theme.sp(110); height: Theme.sp(10); phase: pv.sheen }
                    }
                    Skeleton { anchors { right: parent.right; rightMargin: Theme.rowInset; verticalCenter: parent.verticalCenter } width: pv.trailW; height: Theme.sp(12); phase: pv.sheen }
                }
            }
        }

        Ui.EmptyState {
            visible: pv.phase === "empty"
            width: parent.width
            topPadding: Theme.s5; bottomPadding: Theme.s5
            glyph: "\u{f048d}"
            title: "No local servers"
            body: "Development servers and daemons listening on this machine show up here."
        }

        Item {
            visible: pv.phase === "error"
            width: parent.width
            height: errorNotice.height + Theme.s5
            Ui.Notice {
                id: errorNotice
                y: Theme.s2
                glyph: "\u{f0026}"
                title: "Can't read listening ports"
                detail: "The port list isn't available right now."
                action: "Try again"
                onActed: Ports.retry()
            }
        }
    }

    ScrollFade { flickable: list }
    ScrollHint { flickable: list; inside: true }
    ListView {
        id: list
        y: pv.topY
        visible: pv.phase === "ready"
        width: parent.width
        height: visible ? Math.min(contentHeight, pv.listMax) : 0
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: Ports.rows

        FluidHighlight {
            parent: list.contentItem
            radius: Theme.r2
            target: pv.keyboard ? list.itemAtIndex(pv.selIndex) : pv.hoverRow
            ring: pv.keyboard
        }

        delegate: Item {
            id: row
            required property int index
            required property string key
            required property int port
            required property string host
            required property string proc
            required property string title
            required property int pid
            required property int start
            required property string agent
            required property string parentApp
            required property real cpu
            required property string memText
            required property string monogram
            required property string scope
            required property string sub
            required property bool openable
            required property string note
            readonly property var entry: DesktopEntries.heuristicLookup(proc) || (parentApp !== "" ? DesktopEntries.heuristicLookup(parentApp) : null)
            readonly property string iconPath: entry && entry.icon ? NotifAdapters.iconSource(entry.icon) : ""
            readonly property bool lit: pv.hoverRow === row || (pv.keyboard && pv.selKey === key)
            readonly property bool armed: Ports.armedKey === key
            readonly property bool stuck: P.noteWarns(note)
            readonly property bool offered: !Ports.busy && (lit || armed || stuck)
            width: list.width
            height: pv.rowH
            clip: true
            Accessible.role: Accessible.ListItem
            Accessible.name: title + ", port " + port + ", " + Math.round(cpu) + "% CPU, " + memText + (scope === "lan" ? ", on this network" : ", local")

            ListRow {
                anchors.fill: parent
                minHeight: pv.rowH
                lead: Item {
                    anchors.fill: parent
                    IconImage { anchors.fill: parent; visible: row.iconPath !== ""; source: row.iconPath; asynchronous: true }
                    Rectangle {
                        visible: row.iconPath === ""
                        anchors.fill: parent
                        radius: Theme.r1
                        color: Theme.pill
                        Label { anchors.centerIn: parent; text: row.monogram; size: Theme.tFootnote; weight: Theme.wBold; color: Theme.textSecondary }
                    }
                }
                title: row.title
                titleWeight: Theme.wMedium
                titleSize: Theme.tBody
                sub: row.note !== "" ? row.note : row.sub
                subColor: row.stuck ? Theme.orange : Theme.textTertiary
                forceStacked: false
                trail: Loader {
                    visible: !pv.stackMetrics
                    active: visible
                    sourceComponent: portTrail
                    width: visible ? pv.trailW : 0
                    height: Theme.sp(28)
                }
                Loader {
                    visible: pv.stackMetrics
                    active: visible
                    sourceComponent: portTrail
                    width: pv.width - Theme.rowInset * 2 - Theme.rowMark - Theme.rowGap
                    height: visible ? Theme.sp(28) : 0
                }
            }


            Component {
                id: portTrail
                Item {
                    width: parent ? parent.width : pv.trailW
                    height: parent ? parent.height : Theme.sp(28)
                    Row {
                        id: nums
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.s2
                        opacity: row.offered ? 0 : 1
                        Rectangle {
                            width: pv.portW; height: Theme.sp(22)
                            radius: Theme.r1
                            color: Theme.pill
                            Label { anchors.centerIn: parent; text: ":" + row.port; size: Theme.tFootnote; weight: Theme.wMedium; tabular: true; color: Theme.textSecondary }
                        }
                        Item {
                            width: pv.scopeW; height: Theme.sp(22)
                            Rectangle {
                                anchors.centerIn: parent
                                width: lanText.implicitWidth + Theme.s3; height: Theme.sp(20)
                                radius: Theme.r1
                                color: row.scope === "lan" ? Qt.alpha(Theme.orange, Theme.tintNotice) : "transparent"
                                Label {
                                    id: lanText
                                    anchors.centerIn: parent
                                    text: row.scope === "lan" ? "LAN" : "local"
                                    size: Theme.tFootnote; weight: Theme.wMedium; color: row.scope === "lan" ? Theme.orange : Theme.textTertiary
                                }
                            }
                        }
                        Label {
                            width: pv.cpuW; horizontalAlignment: Text.AlignRight
                            text: Math.round(row.cpu) + "%"
                            size: Theme.tSub; weight: Theme.wMedium; tabular: true; color: Theme.textPrimary
                        }
                        Label {
                            width: pv.memW; horizontalAlignment: Text.AlignRight
                            text: row.memText
                            size: Theme.tSub; tabular: true; color: Theme.textSecondary
                        }
                    }
                    Row {
                        id: acts
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.s2
                        visible: row.offered
                        Rectangle {
                            width: pv.portW; height: Theme.sp(22)
                            radius: Theme.r1
                            color: Theme.pill
                            Label { anchors.centerIn: parent; text: ":" + row.port; size: Theme.tFootnote; weight: Theme.wMedium; tabular: true; color: Theme.textSecondary }
                        }
                        Item {
                            width: pv.scopeW; height: Theme.sp(28)
                            Rectangle {
                                anchors.centerIn: parent
                                width: actLanText.implicitWidth + Theme.s3; height: Theme.sp(20)
                                radius: Theme.r1
                                color: row.scope === "lan" ? Qt.alpha(Theme.orange, Theme.tintNotice) : "transparent"
                                Label {
                                    id: actLanText
                                    anchors.centerIn: parent
                                    text: row.scope === "lan" ? "LAN" : "local"
                                    size: Theme.tFootnote; weight: Theme.wMedium; color: row.scope === "lan" ? Theme.orange : Theme.textTertiary
                                }
                            }
                        }
                        Item {
                            width: pv.openW; height: Theme.sp(28)
                            Ui.Button {
                                anchors.fill: parent
                                visible: row.openable
                                size: Theme.tFootnote
                                kind: "quiet"
                                text: "Open"
                                onClicked: Ports.openUrl(row.port)
                            }
                        }
                        Item {
                            width: pv.stopW; height: Theme.sp(28)
                            Ui.Button {
                                anchors.fill: parent
                                size: Theme.tFootnote
                                kind: row.armed ? "danger" : "secondary"
                                text: row.armed ? "Confirm" : "Stop"
                                onClicked: Ports.press(row.key, "stop", row.title)
                            }
                        }
                    }
                }
            }

            HoverHandler {
                onHoveredChanged: {
                    if (hovered) { pv.keyboard = false; pv.selKey = row.key; pv.hoverRow = row; }
                    else if (pv.hoverRow === row) pv.hoverRow = null;
                }
            }
        }
    }
}
