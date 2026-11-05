// Tabs & agents, drawn in real pixels beside a focused kitty. Kitty's own bar
// is cells wide (a 19-cell strip on this machine is about 200 logical px) and
// Hyprland only publishes the window's goal rectangle, refreshed late, while
// the move spring is still running (~200 ms). A layer glued to that rectangle
// cannot stay aligned. This is the other placement: a column on the left edge
// of the monitor that has the focused kitty, with an exclusive zone so the
// tiled window sits beside it. It slides away on the moderate spring when
// focus leaves kitty.
//
// Off until Settings.kittyTabs (`rice set kittyTabs true`). It never takes
// the keyboard. A click runs `kittymux act` for that row.
//
// RICE_KITTY_TABS_PREVIEW=1 draws it on the first screen with no kitty in
// front, for an off-screen render. Nothing sets that in normal use.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.config
import qs.components
import qs.components.ui
import qs.services

Scope {
    id: root

    property string hostName: "this machine"
    readonly property bool preview: Quickshell.env("RICE_KITTY_TABS_PREVIEW") === "1"

    FileView {
        path: "/etc/hostname"
        printErrors: false
        onLoaded: {
            const n = text().trim();
            if (n) root.hostName = n;
        }
    }

    function resetText(epoch) {
        if (!epoch) return "Limit";
        const mins = Math.max(0, Math.round((epoch - Date.now() / 1000) / 60));
        const h = Math.floor(mins / 60), m = mins % 60;
        if (h <= 0 && m <= 0) return "soon";
        return h ? (h + "h" + (m ? " " + m + "m" : "")) : (m + "m");
    }
    function kindOf(t) {
        if (!t) return "idle";
        if (t.needsYou || t.state === "waiting") return "needs";
        if (t.state === "error") return "error";
        if (t.state === "limited") return "limit";
        if (t.state === "working") return "working";
        if (t.state === "done") return "done";
        return "idle";
    }
    function stateLine(t) {
        const k = kindOf(t);
        if (k === "needs") return "Needs you";
        if (k === "error") return "Error";
        if (k === "limit") return "Hit a limit";
        if (k === "working") return "Working";
        if (k === "done") return "Done";
        return "Idle";
    }
    function inkOn(hex) {
        const c = Qt.color(hex);
        const l = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
        return l > 0.55 ? "#16161d" : "#ffffff";
    }

    Variants {
        model: Settings.kittyTabs ? Quickshell.screens : []

        PanelWindow {
            id: win
            required property ShellScreen modelData
            screen: modelData

            readonly property var top: Hyprland.activeToplevel
            readonly property var info: top && top.lastIpcObject ? top.lastIpcObject : ({})
            readonly property string winClass: String(info.class || "").toLowerCase()
            readonly property bool kittyClass: winClass === "kitty" || winClass.startsWith("kitty-")
            readonly property bool fullscreen: info.fullscreen === 1 || info.fullscreen === 2 || info.fullscreen === true
            readonly property var monitor: Hyprland.monitorFor(modelData)
            readonly property bool onScreen: !!(top && monitor && top.monitor === monitor)
            readonly property bool previewHere: root.preview && (Quickshell.screens.length < 2 || modelData === Quickshell.screens[0])
            readonly property bool want: Settings.kittyTabs && (previewHere || (kittyClass && onScreen && !fullscreen))

            // The focused kitty's own tabs. Without tabs.json, every running
            // agent, so a kitty that is not in the file still has a column.
            readonly property var oswin: {
                const wins = Kittymux.tabs || [];
                if (!wins.length) return null;
                const pid = Number(info.pid) || 0;
                if (!Kittymux.tabsLive) {
                    if (pid) {
                        const mine = wins.find(w => Number(w.kittyPid) === pid);
                        if (mine) return mine;
                    }
                    const tabs = [];
                    let session = "";
                    wins.forEach(w => {
                        if (w.session && !session) session = w.session;
                        (w.tabs || []).forEach(t => tabs.push(t));
                    });
                    return { kittyPid: pid, session: session, focused: true, tabs: tabs };
                }
                if (pid) {
                    const same = wins.filter(w => Number(w.kittyPid) === pid);
                    if (same.length) return same.find(w => w.focused) || same[0];
                }
                if (previewHere) return wins.find(w => w.focused) || wins[0];
                return null;
            }
            readonly property int tabCount: oswin && oswin.tabs ? oswin.tabs.length : 0
            readonly property int columnW: Math.round(Math.max(220, Math.min(280, (modelData.width || 1280) * 0.34)))

            property int tick: 0
            Timer { interval: 30000; repeat: true; running: win.want; onTriggered: win.tick++ }

            // Slide in from the edge the column lives on. Retargeting keeps
            // the velocity, so focus that returns mid-exit turns around.
            Spring { id: slide; tier: Theme.springModerate }
            function applySlide() {
                if (Theme.reduceMotion) slide.snap(want ? 1 : 0);
                else slide.target = want ? 1 : 0;
            }
            onWantChanged: applySlide()
            Component.onCompleted: applySlide()

            property Item hoverItem: null
            property var hoverTab: null
            property bool peekOn: false
            function setHover(item, tab) {
                hoverItem = item;
                hoverTab = tab;
                peekOn = false;
                if (tab && peekWorthy(tab)) peekArm.restart();
                else peekArm.stop();
            }
            function peekWorthy(t) {
                if (!t) return false;
                if (t.question) return true;
                return (t.place || "").length > 28;
            }
            Timer { id: peekArm; interval: Theme.tipMs; onTriggered: if (win.hoverTab && win.peekWorthy(win.hoverTab)) win.peekOn = true }

            anchors { left: true; top: true; bottom: true }
            implicitWidth: columnW + 268
            exclusiveZone: want ? columnW : 0
            color: "transparent"
            visible: want || slide.value > 0.01
            WlrLayershell.namespace: "rice-kitty-tabs"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            mask: Region {
                item: slide.value > 0.04 ? shell : null
                Region { item: peekCard.opacity > 0.2 ? peekCard : null }
            }

            Item {
                id: shell
                width: win.columnW
                height: parent.height
                x: Math.round((slide.value - 1) * width)
                opacity: slide.value

                GlassCard {
                    anchors.fill: parent
                    radius: 0
                    tint: Theme.glassTintThick
                }
                Rectangle {
                    anchors.right: parent.right
                    width: 1
                    height: parent.height
                    color: Qt.rgba(1, 1, 1, 0.08)
                }

                Column {
                    id: head
                    x: 14
                    y: 16
                    width: parent.width - 28
                    spacing: 0

                    Item {
                        width: parent.width
                        height: 32
                        Rectangle {
                            width: 32
                            height: 32
                            radius: 9
                            color: Qt.rgba(1, 1, 1, 0.08)
                            Image {
                                anchors.centerIn: parent
                                width: 18
                                height: 18
                                source: Kittymux.brand("kittymux")
                                fillMode: Image.PreserveAspectFit
                                sourceSize: Qt.size(36, 36)
                                smooth: true
                            }
                        }
                        Column {
                            x: 42
                            width: parent.width - 42
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1
                            Label {
                                width: parent.width
                                elide: Text.ElideRight
                                text: (win.oswin && win.oswin.session) ? win.oswin.session : "kitty"
                                size: 14
                                weight: Theme.wSemibold
                            }
                            Label {
                                width: parent.width
                                elide: Text.ElideRight
                                text: root.hostName + "  ·  " + win.tabCount + (win.tabCount === 1 ? " tab" : " tabs")
                                size: 11
                                color: Theme.textTertiary
                                font.features: ({ "tnum": 1 })
                            }
                        }
                    }
                    Item { width: 1; height: 14 }
                    Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.08) }
                }

                Flickable {
                    id: flick
                    x: 8
                    y: head.y + head.height + 8
                    width: parent.width - 16
                    height: Math.max(0, parent.height - y - 12)
                    contentHeight: list.height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Item {
                        id: list
                        width: flick.width
                        height: rows.implicitHeight

                        // Not a child of the column: a column would stack it
                        // as a row and fight the glide.
                        FluidHighlight { id: lit; target: win.hoverItem; radius: 10; z: 0 }

                        Column {
                        id: rows
                        width: parent.width
                        spacing: 2

                        Label {
                            visible: win.tabCount === 0
                            x: 6
                            width: parent.width - 12
                            text: Kittymux.available
                                  ? (Kittymux.tabsLive ? "No tabs in this window" : "No agents running")
                                  : "kittymux isn't installed"
                            size: 12
                            color: Theme.textTertiary
                            wrapMode: Text.WordWrap
                        }

                        Repeater {
                            model: win.oswin && win.oswin.tabs ? win.oswin.tabs : []
                            delegate: Item {
                                id: row
                                required property var modelData
                                required property int index
                                width: list.width
                                height: 48
                                z: 1
                                scale: down ? 0.985 : 1
                                transformOrigin: Item.Center
                                Behavior on scale {
                                    NumberAnimation { duration: Theme.pressMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
                                }
                                property bool down: false
                                readonly property string kind: root.kindOf(modelData)
                                readonly property string mark: Kittymux.brand(modelData.brand || modelData.agent)
                                readonly property bool active: !!modelData.active
                                readonly property color spinColor: active ? Theme.accent : Theme.textSecondary

                                Rectangle {
                                    visible: row.active
                                    anchors.fill: parent
                                    radius: 10
                                    color: Qt.rgba(1, 1, 1, 0.07)
                                    border.width: 1
                                    border.color: Qt.rgba(1, 1, 1, 0.12)
                                }
                                Rectangle {
                                    visible: row.active
                                    anchors.fill: parent
                                    anchors.margins: 1
                                    radius: 9
                                    gradient: Gradient {
                                        GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.10) }
                                        GradientStop { position: 0.42; color: Qt.rgba(1, 1, 1, 0.0) }
                                        GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.14) }
                                    }
                                }
                                Rectangle {
                                    visible: row.active
                                    x: 7
                                    width: 3
                                    height: 14
                                    radius: 1.5
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: Theme.accent
                                }

                                Item {
                                    id: icon
                                    x: 16
                                    width: 16
                                    height: 16
                                    anchors.verticalCenter: parent.verticalCenter
                                    Image {
                                        anchors.fill: parent
                                        visible: row.mark !== ""
                                        source: row.mark
                                        fillMode: Image.PreserveAspectFit
                                        sourceSize: Qt.size(32, 32)
                                        smooth: true
                                        mipmap: true
                                    }
                                    Rectangle {
                                        anchors.fill: parent
                                        visible: row.mark === "" && modelData.hue !== ""
                                        radius: 5
                                        color: modelData.hue
                                        Label {
                                            anchors.centerIn: parent
                                            text: (modelData.title || "?").charAt(0).toUpperCase()
                                            size: 10
                                            weight: Theme.wBold
                                            color: root.inkOn(modelData.hue)
                                        }
                                    }
                                    Rectangle {
                                        anchors.fill: parent
                                        visible: row.mark === "" && modelData.hue === ""
                                        radius: 4
                                        color: Qt.rgba(1, 1, 1, 0.08)
                                        border.width: 1
                                        border.color: Qt.rgba(1, 1, 1, 0.12)
                                        Label {
                                            anchors.centerIn: parent
                                            text: ">"
                                            size: 10
                                            weight: Theme.wSemibold
                                            color: Theme.textSecondary
                                        }
                                    }
                                }

                                Column {
                                    id: words
                                    x: 40
                                    width: Math.max(0, parent.width - x - cluster.width - 14)
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 1
                                    Label {
                                        width: parent.width
                                        elide: Text.ElideRight
                                        text: modelData.title || "Terminal"
                                        size: 13
                                        weight: row.active ? Theme.wSemibold : Theme.wMedium
                                        color: row.kind === "idle" ? Theme.textSecondary : Theme.textPrimary
                                    }
                                    Label {
                                        visible: modelData.place !== ""
                                        width: parent.width
                                        elide: Text.ElideRight
                                        text: modelData.place
                                        size: 11
                                        color: Theme.textTertiary
                                    }
                                }

                                Row {
                                    id: cluster
                                    spacing: 6
                                    anchors.right: parent.right
                                    anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    Label {
                                        visible: modelData.age !== "" && row.kind !== "limit"
                                        text: modelData.age
                                        size: 11
                                        rounded: true
                                        color: Theme.textTertiary
                                        font.features: ({ "tnum": 1 })
                                        height: 22
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    Chip {
                                        visible: row.kind === "needs"
                                        text: "Needs you"
                                        tone: Theme.orange
                                    }
                                    Chip {
                                        visible: row.kind === "error"
                                        text: "Error"
                                        tone: Theme.red
                                    }
                                    Chip {
                                        visible: row.kind === "limit"
                                        text: win.tick >= 0 ? root.resetText(modelData.limitReset) : ""
                                        tone: Theme.orange
                                    }
                                    Item {
                                        visible: row.kind === "working"
                                        width: 12
                                        height: 22
                                        Item {
                                            width: 12
                                            height: 12
                                            anchors.centerIn: parent
                                            Rectangle {
                                                anchors.fill: parent
                                                radius: 6
                                                color: "transparent"
                                                border.width: 1.5
                                                border.color: Qt.alpha(row.spinColor, 0.28)
                                            }
                                            Item {
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                anchors.top: parent.top
                                                height: parent.height / 2
                                                clip: true
                                                Rectangle {
                                                    width: 12
                                                    height: 12
                                                    radius: 6
                                                    color: "transparent"
                                                    border.width: 1.5
                                                    border.color: row.spinColor
                                                }
                                            }
                                            RotationAnimation on rotation {
                                                running: row.kind === "working" && win.want && !Theme.reduceMotion
                                                loops: Animation.Infinite
                                                from: 0
                                                to: 360
                                                duration: 900
                                            }
                                        }
                                    }
                                    Item {
                                        visible: row.kind === "done"
                                        width: 7
                                        height: 22
                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: 7
                                            height: 7
                                            radius: 4
                                            color: Theme.green
                                        }
                                    }
                                    Item {
                                        visible: row.kind === "idle"
                                        width: 7
                                        height: 22
                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: 7
                                            height: 7
                                            radius: 4
                                            color: "transparent"
                                            border.width: 1.3
                                            border.color: Theme.textTertiary
                                        }
                                    }
                                }

                                Rectangle {
                                    visible: typeof modelData.progress === "number"
                                    x: 40
                                    y: parent.height - 5
                                    width: Math.max(0, parent.width - 52)
                                    height: 2
                                    radius: 1
                                    color: Qt.rgba(1, 1, 1, 0.10)
                                    Rectangle {
                                        width: parent.width * Math.max(0, Math.min(100, modelData.progress)) / 100
                                        height: parent.height
                                        radius: 1
                                        color: row.active ? Theme.accent : Qt.rgba(1, 1, 1, 0.55)
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: modelData.action ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onContainsMouseChanged: {
                                        if (containsMouse) win.setHover(row, modelData);
                                        else if (win.hoverItem === row) win.setHover(null, null);
                                    }
                                    onPressed: row.down = true
                                    onReleased: row.down = false
                                    onCanceled: row.down = false
                                    onClicked: if (modelData.action) Kittymux.act(modelData.action)
                                    Accessible.role: Accessible.Button
                                    Accessible.name: (modelData.title || "Tab") + ", " + root.stateLine(modelData)
                                }
                            }
                        }
                        }
                    }
                }
            }

            Item {
                id: peekCard
                x: win.columnW + 8
                y: {
                    if (!win.hoverItem) return 16;
                    const p = win.hoverItem.mapToItem(win.contentItem, 0, 0);
                    return Math.max(12, Math.min(win.height - height - 12, p.y - 6));
                }
                width: 248
                height: peekCol.implicitHeight + 20
                opacity: (win.peekOn && win.want && slide.value > 0.92 && win.hoverTab) ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: Theme.reduceMotion ? 1 : 120; easing.type: Easing.OutCubic } }

                GlassCard { anchors.fill: parent; radius: 14; tint: Theme.glassTintElevated }

                Column {
                    id: peekCol
                    x: 12
                    y: 10
                    width: parent.width - 24
                    spacing: 3
                    Label {
                        width: parent.width
                        elide: Text.ElideRight
                        text: win.hoverTab ? win.hoverTab.title : ""
                        size: 13
                        weight: Theme.wSemibold
                    }
                    Label {
                        visible: win.hoverTab && win.hoverTab.place !== ""
                        width: parent.width
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        text: win.hoverTab ? win.hoverTab.place : ""
                        size: 11
                        color: Theme.textTertiary
                    }
                    Label {
                        width: parent.width
                        text: win.hoverTab ? (root.stateLine(win.hoverTab) + (win.hoverTab.age ? "  ·  " + win.hoverTab.age : "")) : ""
                        size: 11
                        color: Theme.textSecondary
                    }
                    Label {
                        visible: win.hoverTab && win.hoverTab.question !== ""
                        width: parent.width
                        wrapMode: Text.WordWrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                        text: win.hoverTab ? win.hoverTab.question : ""
                        size: 12
                        color: Theme.textPrimary
                    }
                }
            }
        }
    }
}
