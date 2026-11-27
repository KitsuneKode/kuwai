import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.config
import qs.components
import qs.components.ui as Ui
import qs.services
import "../../services/activity.mjs" as A

FocusScope {
    id: av
    property real maxHeight: 400
    readonly property real rowH: Theme.sp(Theme.rowMin)
    readonly property real cpuW: Theme.sp(48)
    readonly property real memW: Theme.sp(72)
    readonly property real headY: Theme.sp(24) + Theme.s2
    readonly property int placeholders: Math.max(2, Math.min(5, Math.floor((maxHeight - headY) / rowH)))
    readonly property real placeholderH: placeholders * rowH
    readonly property string view: Activity.view
    readonly property bool shaped: view === "list" || view === "loading"
    readonly property real topY: shaped ? headY : 0
    readonly property real listMax: Math.max(2 * rowH, maxHeight - headY)
    property bool keyboard: false
    property string selKey: ""
    property Item hoverRow: null
    readonly property int selIndex: Activity.shown.indexOf(selKey)
    property real sheen: 0

    implicitWidth: parent ? parent.width : Theme.panelM
    implicitHeight: view === "list" ? topY + list.height : topY + stage.height
    height: implicitHeight
    focus: true

    Component.onCompleted: Activity.watch()
    Component.onDestruction: Activity.unwatch()

    Binding { target: Activity; property: "hold"; value: av.hoverRow !== null || av.keyboard }

    NumberAnimation on sheen {
        running: av.view === "loading" && av.visible && !Theme.reduceMotion
        from: 0; to: 1
        duration: Theme.shimmerMs
        loops: Animation.Infinite
    }

    function nameOf(item) { return item ? item.name : ""; }

    function move(by) {
        if (Activity.count === 0) return;
        keyboard = true;
        const at = Math.max(0, Math.min(Activity.count - 1, (selIndex < 0 ? (by > 0 ? -1 : Activity.count) : selIndex) + by));
        selKey = Activity.shown[at];
        list.positionViewAtIndex(at, ListView.Contain);
    }

    function act(action) {
        const item = list.itemAtIndex(selIndex);
        if (item && !item.locked) Activity.press(item.key, action, item.name);
    }

    Keys.onPressed: e => {
        if (e.key === Qt.Key_Down) move(1);
        else if (e.key === Qt.Key_Up) move(-1);
        else if ((e.key === Qt.Key_Delete || e.key === Qt.Key_Backspace) && av.view === "list" && selIndex >= 0) act((e.modifiers & Qt.ShiftModifier) ? "force" : "stop");
        else if (e.key === Qt.Key_Escape && Activity.armedKey !== "") { Activity.armedKey = ""; Activity.armedAction = ""; }
        else return;
        e.accepted = true;
    }

    Item {
        id: head
        visible: av.shaped
        width: parent.width
        height: Theme.sp(24)
        Skeleton {
            visible: av.view === "loading"
            x: Theme.rowInset
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.sp(56); height: Theme.sp(10)
            phase: av.sheen
        }
        Label {
            visible: av.view === "list"
            x: Theme.rowInset
            anchors.verticalCenter: parent.verticalCenter
            text: Activity.count + (Activity.count === 1 ? " app" : " apps")
            size: Theme.tFootnote; weight: Theme.wSemibold; color: Theme.textTertiary
        }
        Row {
            visible: av.view === "list"
            anchors { right: parent.right; rightMargin: Theme.rowInset; verticalCenter: parent.verticalCenter }
            spacing: Theme.s2
            Label {
                width: av.cpuW; horizontalAlignment: Text.AlignRight; text: "CPU"
                size: Theme.tFootnote; weight: Theme.wSemibold; color: Theme.textTertiary
                HoverHandler { id: cpuHover }
                Tip { text: "100% is one thread fully busy · this machine has " + Activity.cpus + " threads"; shown: cpuHover.hovered; below: true }
            }
            Label { width: av.memW; horizontalAlignment: Text.AlignRight; text: "Memory"; size: Theme.tFootnote; weight: Theme.wSemibold; color: Theme.textTertiary }
        }
    }

    Column {
        id: stage
        y: av.topY
        width: parent.width
        visible: av.view !== "list"
        height: visible ? implicitHeight : 0

        Column {
            visible: av.view === "loading"
            width: parent.width
            Repeater {
                model: av.placeholders
                Item {
                    width: parent.width
                    height: av.rowH
                    Skeleton { x: Theme.rowInset; anchors.verticalCenter: parent.verticalCenter; width: Theme.rowMark; height: width; radius: Theme.r1; phase: av.sheen }
                    Column {
                        x: Theme.rowInset + Theme.rowMark + Theme.rowGap
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.s1 + 2
                        Skeleton { width: Theme.sp(150); height: Theme.sp(12); phase: av.sheen }
                        Skeleton { width: Theme.sp(86); height: Theme.sp(10); phase: av.sheen }
                    }
                    Skeleton { anchors { right: parent.right; rightMargin: Theme.rowInset; verticalCenter: parent.verticalCenter } width: av.cpuW + av.memW + Theme.s2; height: Theme.sp(12); phase: av.sheen }
                }
            }
        }

        Ui.EmptyState {
            visible: av.view === "empty"
            width: parent.width
            topPadding: Theme.s5; bottomPadding: Theme.s5
            glyph: "\u{f003b}"
            title: "No apps running"
            body: "Apps you open from the launcher or a terminal show up here, with what each one uses."
        }

        Item {
            visible: av.view === "error"
            width: parent.width
            height: errorNotice.height + Theme.s5
            Ui.Notice {
                id: errorNotice
                y: Theme.s2
                glyph: "\u{f0026}"
                title: "Can't read what's running"
                detail: "Your apps' numbers aren't available right now."
                action: "Try again"
                onActed: Activity.retry()
            }
        }
    }

    ScrollFade { flickable: list }
    ScrollHint { flickable: list; inside: true }
    ListView {
        id: list
        y: av.topY
        visible: av.view === "list"
        width: parent.width
        height: visible ? Math.min(contentHeight, av.listMax) : 0
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: Activity.rows

        FluidHighlight {
            parent: list.contentItem
            radius: Theme.r2
            target: av.keyboard ? list.itemAtIndex(av.selIndex) : av.hoverRow
            ring: av.keyboard
        }

        delegate: Item {
            id: row
            required property int index
            required property string key
            required property string appId
            required property string label
            required property int procs
            required property real cpu
            required property bool locked
            required property string tone
            required property string cpuText
            required property string memText
            required property string detail
            required property string note
            readonly property var entry: appId !== "" ? DesktopEntries.heuristicLookup(appId) : null
            readonly property string name: entry && entry.name ? entry.name : label
            readonly property string iconPath: entry && entry.icon ? NotifAdapters.iconSource(entry.icon) : ""
            readonly property bool lit: av.hoverRow === row || (av.keyboard && av.selKey === key)
            readonly property bool armed: Activity.armedKey === key && Activity.armedAction === "force"
            readonly property bool stuck: A.noteWarns(note)
            readonly property bool offered: !locked && !Activity.busy && (lit || armed || stuck)
            width: list.width
            height: av.rowH
            Accessible.role: Accessible.ListItem
            Accessible.name: name + ", " + cpuText + " CPU" + (memText !== "" ? ", " + memText : "") + ", " + detail + (locked ? ", your session needs it" : "")

            ListRow {
                anchors.fill: parent
                minHeight: av.rowH
                lead: Item {
                    id: iconBox
                    anchors.fill: parent
                    IconImage { anchors.fill: parent; visible: row.iconPath !== ""; source: row.iconPath; asynchronous: true }
                    Rectangle {
                        visible: row.iconPath === ""
                        anchors.fill: parent
                        radius: Theme.r1
                        color: Theme.pill
                        Label {
                            anchors.centerIn: parent
                            text: row.name.slice(0, 1).toUpperCase()
                            size: Theme.tBody; weight: Theme.wSemibold; color: Theme.textSecondary
                        }
                    }
                }
                title: row.name
                titleWeight: Theme.wMedium
                titleSize: Theme.tBody
                sub: row.note !== "" ? row.note : row.locked ? "Keeps your session running · " + row.detail : row.detail
                subColor: row.stuck ? Theme.orange : Theme.textTertiary
                forceStacked: false
                trail: Item {
                    width: Math.max(nums.width, acts.width)
                    height: Math.max(nums.height, acts.height)
                    Row {
                        id: nums
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.s2
                        opacity: row.offered ? 0 : 1
                        Label {
                            width: av.cpuW; horizontalAlignment: Text.AlignRight
                            text: row.cpuText
                            size: Theme.tSub; weight: Theme.wMedium; tabular: true
                            color: row.tone === "red" ? Theme.red : row.tone === "orange" ? Theme.orange : Theme.textPrimary
                        }
                        Label {
                            width: av.memW; horizontalAlignment: Text.AlignRight
                            text: row.memText !== "" ? row.memText : "–"
                            size: Theme.tSub; tabular: true; color: Theme.textSecondary
                        }
                    }
                    Row {
                        id: acts
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.s1
                        visible: row.offered
                        Ui.Button {
                            height: Theme.sp(28); size: Theme.tFootnote
                            kind: "secondary"
                            text: "Stop"
                            onClicked: Activity.press(row.key, "stop", row.name)
                        }
                        Ui.Button {
                            id: forceBtn
                            height: Theme.sp(28); size: Theme.tFootnote
                            kind: row.armed ? "danger" : "quiet"
                            text: row.armed ? "Press again to quit" : "Force quit"
                            onClicked: Activity.press(row.key, "force", row.name)
                            Tip { text: "Ends it at once; unsaved work is lost"; shown: forceBtn.hovered; below: true }
                        }
                    }
                }
            }

            HoverHandler {
                onHoveredChanged: {
                    if (hovered) { av.keyboard = false; av.selKey = row.key; av.hoverRow = row; }
                    else if (av.hoverRow === row) av.hoverRow = null;
                }
            }
        }
    }
}
