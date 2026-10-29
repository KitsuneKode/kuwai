// One app's notifications in the center.
//
//   [icon] T3 Code  3                         Show less  ✕
//   ┌───────────────────────────────────────────────┐
//   │ newest notification                            │
//   └───────────────────────────────────────────────┘
//     └─────────────────────────────────────────┘      ← collapsed: the rest
//        └───────────────────────────────────┘           peek out underneath
//
// Collapsed, a group is a stack like the toasts': the newest on top, up to
// two plates peeking out below it (8px apart, 5% narrower each). Clicking
// the stack fans it out; "Show less" folds it back. ✕ clears the app.
import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.config
import qs.components
import qs.services

Item {
    id: group

    required property var modelData                 // { key, app, icon, items }
    required property int index
    property var center                             // the NotificationsView
    property bool expanded: false
    property bool canFold: true                     // not while searching/filtering
    signal toggled()

    readonly property var items: modelData.items
    readonly property int count: items.length
    readonly property bool stacked: !expanded && count > 1
    readonly property int peeks: stacked ? Math.min(2, count - 1) : 0

    width: ListView.view ? ListView.view.width : 0
    height: header.height + 8 + (expanded ? list.height : first.height + peeks * 8)
    Behavior on height { enabled: !(group.center && group.center.instant); NumberAnimation { duration: Theme.reflowMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }

    // Header
    Item {
        id: header
        width: parent.width
        height: 26

        HoverHandler { id: headerHover }

        Row {
            anchors.left: parent.left
            anchors.leftMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            ClippingRectangle {
                width: 18; height: 18; radius: 5
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.platter
                Image {
                    anchors.fill: parent
                    source: group.modelData.icon || NotifAdapters.iconForApp(group.modelData.app)
                    sourceSize: Qt.size(36, 36)
                    asynchronous: true
                    smooth: true
                    mipmap: true
                }
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: group.modelData.app
                size: 13
                weight: Theme.wSemibold
                color: Theme.textSecondary
            }
            Rectangle {
                visible: group.count > 1
                anchors.verticalCenter: parent.verticalCenter
                height: 16; radius: 8
                width: countLabel.implicitWidth + 10
                color: Theme.pill
                Label {
                    id: countLabel
                    rounded: true
                    anchors.centerIn: parent
                    text: group.count
                    size: 10
                    weight: Theme.wSemibold
                    font.features: ({ "tnum": 1 })
                    color: Theme.textSecondary
                }
            }
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            opacity: headerHover.hovered || group.expanded ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.colorMs } }

            Rectangle {
                visible: group.expanded && group.canFold
                height: 22; radius: 11
                width: lessLabel.implicitWidth + 18
                color: lessArea.containsMouse ? Theme.pillHover : Theme.pill
                Label {
                    id: lessLabel
                    anchors.centerIn: parent
                    text: "Show less"
                    size: 11
                    weight: Theme.wSemibold
                }
                MouseArea {
                    id: lessArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: group.toggled()
                }
            }
            Rectangle {
                width: 22; height: 22; radius: 11
                color: clearArea.containsMouse ? Theme.pillHover : Theme.pill
                Text {
                    anchors.centerIn: parent
                    text: "\u{f0156}"
                    font.family: Theme.fontGlyph
                    font.pixelSize: 11
                    color: Theme.textPrimary
                }
                MouseArea {
                    id: clearArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Notifs.removeApp(group.modelData.app)
                }
            }
        }
    }

    // Collapsed: newest on top, the rest peeking out beneath it.
    Item {
        id: stackView
        visible: !group.expanded
        anchors.top: header.bottom
        anchors.topMargin: 8
        width: parent.width
        height: first.height + group.peeks * 8

        Repeater {
            model: group.peeks
            // Only the sliver below the layer in front is drawn: the plates
            // are translucent, so overlapping ones would smear through.
            Item {
                required property int index
                readonly property int depth: index + 1
                width: stackView.width * (1 - 0.05 * depth)
                x: (stackView.width - width) / 2
                y: first.height + 8 * (depth - 1)
                height: 8
                clip: true
                Rectangle {
                    width: parent.width
                    height: 36
                    y: parent.height - height
                    radius: 14
                    color: Qt.rgba(1, 1, 1, 0.075 - 0.025 * parent.depth)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.05)
                }
            }
        }

        CenterRow {
            id: first
            item: group.items[0]
            center: group.center
        }

        // Tapping a folded stack opens it rather than the top notification.
        MouseArea {
            visible: group.stacked
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: group.toggled()
        }
    }

    // Expanded: every notification, newest first.
    Column {
        id: list
        visible: group.expanded
        anchors.top: header.bottom
        anchors.topMargin: 8
        width: parent.width
        spacing: 8
        // No move transition: rows grow/shrink their own height, and the
        // column follows that directly (a lagging move would overlap them).

        Repeater {
            model: ScriptModel { values: group.expanded ? group.items : [] }
            CenterRow {
                required property var modelData
                item: modelData
                center: group.center
            }
        }
    }
}
